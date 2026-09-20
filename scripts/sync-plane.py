#!/usr/bin/env python3
"""Preview or apply a read-only Plane snapshot to the Workbench database.

The input is a JSON array of normalized assigned work items. This tool never
writes to Plane. It updates only Workbench's SQLite database when --apply is
given and keeps existing work sessions intact.
"""

from __future__ import annotations

import argparse
import configparser
import datetime as dt
import json
import os
import pathlib
import sqlite3
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid


DEFAULT_DATABASE_DIR = pathlib.Path.home() / ".local/share/plasmashell/QML/OfflineStorage/Databases"
DATABASE_NAME = "io.github.ownisticapps.worktodo"
VALID_STATUSES = {"backlog", "ready", "in_progress", "blocked", "completed"}
PLANE_STATUS_MAP = {
    "backlog": "backlog",
    "unstarted": "ready",
    "started": "in_progress",
    "completed": "completed",
    "cancelled": "completed",
}


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def new_id() -> str:
    return f"plane-{uuid.uuid4()}"


def find_database(database_dir: pathlib.Path) -> pathlib.Path:
    for ini_path in sorted(database_dir.glob("*.ini")):
        config = configparser.ConfigParser()
        config.read(ini_path)
        if config.get("General", "Name", fallback="") == DATABASE_NAME:
            database_path = ini_path.with_suffix(".sqlite")
            if database_path.exists():
                return database_path
    raise RuntimeError(f"Could not find the {DATABASE_NAME} database in {database_dir}")


def validate_item(item: dict) -> dict:
    required = ("id", "key", "title", "status", "url")
    missing = [field for field in required if not str(item.get(field, "")).strip()]
    if missing:
        raise ValueError(f"Plane item is missing: {', '.join(missing)}")
    status = str(item["status"])
    if status not in VALID_STATUSES:
        raise ValueError(f"Unsupported Workbench status {status!r} for {item['key']}")
    return {
        "id": str(item["id"]).strip(),
        "key": str(item["key"]).strip(),
        "title": str(item["title"]).strip(),
        "details": str(item.get("details", "")),
        "status": status,
        "url": str(item["url"]).strip(),
        "project_id": str(item.get("project_id", "")).strip() or None,
        "category": str(item.get("category", "")).strip(),
        "updated_at": str(item.get("updated_at", "")).strip() or None,
        "payload": json.dumps(item, ensure_ascii=False, separators=(",", ":")),
    }


def api_get(base_url: str, api_key: str, path: str, query: dict | None = None) -> object:
    url = base_url.rstrip("/") + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    request = urllib.request.Request(url, headers={"X-API-Key": api_key, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Plane API returned HTTP {error.code}: {body[:500]}") from error
    except urllib.error.URLError as error:
        raise RuntimeError(f"Could not reach Plane API: {error.reason}") from error


def response_results(payload: object) -> list[dict]:
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict) and isinstance(payload.get("results"), list):
        return payload["results"]
    raise RuntimeError("Plane API returned an unexpected response shape")


def fetch_plane_items(base_url: str, api_key: str, workspace: str, assignee: str) -> list[dict]:
    workspace_path = f"/api/v1/workspaces/{urllib.parse.quote(workspace, safe='') }"
    projects = response_results(api_get(base_url, api_key, workspace_path + "/projects/"))
    normalized = []
    for project in projects:
        if project.get("is_member") is False:
            continue
        project_id = str(project["id"])
        project_path = workspace_path + f"/projects/{urllib.parse.quote(project_id, safe='')}"
        states = response_results(api_get(base_url, api_key, project_path + "/states/"))
        states_by_id = {str(state["id"]): state for state in states}
        cursor = ""
        seen_cursors = set()
        while True:
            query = {"assignee": assignee, "expand": "state", "per_page": 100}
            if cursor:
                query["cursor"] = cursor
            payload = api_get(base_url, api_key, project_path + "/work-items/", query)
            for item in response_results(payload):
                state = item.get("state")
                if not isinstance(state, dict):
                    state = states_by_id.get(str(state), {})
                group = str(state.get("group", "backlog")).lower()
                status = "blocked" if "block" in str(state.get("name", "")).lower() else PLANE_STATUS_MAP.get(group, "backlog")
                key = f"{project['identifier']}-{item['sequence_id']}"
                url = f"https://app.plane.so/{workspace}/browse/{key}/"
                description = str(item.get("description_stripped") or "").strip()
                normalized.append({
                    "id": str(item["id"]),
                    "key": key,
                    "title": str(item["name"]),
                    "details": description,
                    "status": status,
                    "url": url,
                    "project_id": project_id,
                    "category": str(project["name"]),
                    "updated_at": item.get("updated_at"),
                })
            if not isinstance(payload, dict) or not payload.get("next_page_results"):
                break
            cursor = str(payload.get("next_cursor") or "")
            if not cursor or cursor in seen_cursors:
                raise RuntimeError("Plane API pagination did not advance")
            seen_cursors.add(cursor)
    return normalized


def category_id(connection: sqlite3.Connection, workspace_name: str, name: str) -> str:
    row = connection.execute(
        "SELECT categories.id FROM categories JOIN workspaces ON workspaces.id = categories.workspace_id "
        "WHERE workspaces.name = ? AND categories.name = ? AND categories.trashed_at_utc IS NULL "
        "ORDER BY categories.position LIMIT 1",
        (workspace_name, name),
    ).fetchone()
    if not row:
        raise RuntimeError(f"Workbench category {workspace_name!r} / {name!r} does not exist")
    return str(row[0])


def next_position(connection: sqlite3.Connection, category: str) -> int:
    row = connection.execute(
        "SELECT COALESCE(MAX(position), 0) + 1024 FROM tasks WHERE category_id = ?", (category,)
    ).fetchone()
    return int(row[0])


def link_table(connection: sqlite3.Connection) -> str:
    """Use the provider-neutral links after the in-plasmoid migration.

    Older installed databases retain external_tasks until Workbench opens them,
    so the CLI remains backwards compatible without maintaining two sources of
    truth in upgraded databases.
    """
    row = connection.execute(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'provider_task_links'"
    ).fetchone()
    return "provider_task_links" if row else "external_tasks"


def plan_item(connection: sqlite3.Connection, category: str, item: dict) -> tuple[str, sqlite3.Row | None, sqlite3.Row | None]:
    links = link_table(connection)
    link = connection.execute(
        f"SELECT * FROM {links} WHERE provider = 'plane' AND remote_id = ?", (item["id"],)
    ).fetchone()
    if not link:
        return "create", None, None
    task = connection.execute("SELECT * FROM tasks WHERE id = ?", (link["task_id"],)).fetchone()
    if not task:
        raise RuntimeError(f"Plane link {item['key']} points to a missing Workbench task")
    local_changed = task["updated_at_utc"] != link["last_local_updated_at"]
    remote_changed = item["updated_at"] != link["remote_updated_at"]
    if local_changed and remote_changed:
        return "conflict", link, task
    if local_changed:
        return "pending_push", link, task
    if remote_changed or any((
        task["title"] != item["title"],
        task["details"] != item["details"],
        task["status"] != item["status"],
        task["category_id"] != category,
    )):
        return "update", link, task
    return "unchanged", link, task


def insert_status_event(connection: sqlite3.Connection, task_id: str, previous: str | None, status: str, timestamp: str) -> None:
    sequence = connection.execute(
        "SELECT COALESCE(MAX(sequence), 0) + 1 FROM status_events WHERE task_id = ?", (task_id,)
    ).fetchone()[0]
    connection.execute(
        "INSERT INTO status_events (id, task_id, previous_status, status, occurred_at_utc, sequence, "
        "manually_edited, created_at_utc, updated_at_utc) VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)",
        (new_id(), task_id, previous, status, timestamp, sequence, timestamp, timestamp),
    )


def apply_item(connection: sqlite3.Connection, category: str, item: dict, action: str, link: sqlite3.Row | None, task: sqlite3.Row | None) -> None:
    timestamp = utc_now()
    links = link_table(connection)
    if action == "create":
        task_id = new_id()
        connection.execute(
            "INSERT INTO tasks (id, category_id, title, details, status, position, archived_at_utc, "
            "completed_at_utc, created_at_utc, updated_at_utc, tracked_seconds) "
            "VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, 0)",
            (task_id, category, item["title"], item["details"], item["status"],
             next_position(connection, category), timestamp if item["status"] == "completed" else None,
             timestamp, timestamp),
        )
        insert_status_event(connection, task_id, None, item["status"], timestamp)
        if links == "provider_task_links":
            connection.execute(
                "INSERT INTO provider_task_links (task_id, provider, remote_id, remote_key, remote_url, project_id, "
                "remote_updated_at, last_local_updated_at, last_synced_at, sync_state, remote_payload_json, created_at_utc, updated_at_utc) "
                "VALUES (?, 'plane', ?, ?, ?, ?, ?, ?, ?, 'in_sync', ?, ?, ?)",
                (task_id, item["id"], item["key"], item["url"], item["project_id"], item["updated_at"],
                 timestamp, timestamp, item["payload"], timestamp, timestamp),
            )
        else:
            connection.execute(
                "INSERT INTO external_tasks (provider, remote_id, task_id, remote_key, remote_url, project_id, "
                "remote_updated_at, last_local_updated_at, last_synced_at, sync_state, remote_payload_json) "
                "VALUES ('plane', ?, ?, ?, ?, ?, ?, ?, ?, 'in_sync', ?)",
                (item["id"], task_id, item["key"], item["url"], item["project_id"], item["updated_at"],
                 timestamp, timestamp, item["payload"]),
            )
        return

    assert link is not None and task is not None
    if action == "update":
        if task["status"] != item["status"]:
            insert_status_event(connection, task["id"], task["status"], item["status"], timestamp)
            if item["status"] == "completed":
                connection.execute(
                    "UPDATE work_sessions SET ended_at_utc = CASE WHEN started_at_utc > ? THEN started_at_utc ELSE ? END, "
                    "updated_at_utc = ? WHERE task_id = ? AND ended_at_utc IS NULL",
                    (timestamp, timestamp, timestamp, task["id"]),
                )
                connection.execute(
                    "UPDATE tasks SET tracked_seconds = COALESCE((SELECT SUM(strftime('%s', ended_at_utc) - "
                    "strftime('%s', started_at_utc)) FROM work_sessions WHERE task_id = ? AND ended_at_utc IS NOT NULL), 0) "
                    "WHERE id = ?",
                    (task["id"], task["id"]),
                )
        completed_at = (task["completed_at"] or timestamp) if item["status"] == "completed" else None
        connection.execute(
            "UPDATE tasks SET category_id = ?, title = ?, details = ?, status = ?, completed_at_utc = ?, "
            "updated_at_utc = ? WHERE id = ?",
            (category, item["title"], item["details"], item["status"], completed_at, timestamp, task["id"]),
        )
        last_local_updated_at = timestamp
        recorded_remote_updated_at = item["updated_at"]
        sync_state = "in_sync"
    elif action == "conflict":
        last_local_updated_at = link["last_local_updated_at"]
        recorded_remote_updated_at = link["remote_updated_at"]
        sync_state = "conflict"
    elif action == "pending_push":
        last_local_updated_at = link["last_local_updated_at"]
        recorded_remote_updated_at = link["remote_updated_at"]
        sync_state = "pending_push"
    else:
        last_local_updated_at = link["last_local_updated_at"]
        recorded_remote_updated_at = item["updated_at"]
        sync_state = "in_sync"

    connection.execute(
        f"UPDATE {links} SET remote_key = ?, remote_url = ?, project_id = ?, remote_updated_at = ?, "
        "last_local_updated_at = ?, last_synced_at = ?, sync_state = ?, remote_payload_json = ? "
        f"WHERE provider = 'plane' AND remote_id = ?",
        (item["key"], item["url"], item["project_id"], recorded_remote_updated_at, last_local_updated_at,
         timestamp, sync_state, item["payload"], item["id"]),
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("snapshot", nargs="?", type=pathlib.Path, help="Normalized Plane work-item JSON snapshot")
    parser.add_argument("--category", default="4leaflabs", help="Workbench category receiving new tasks")
    parser.add_argument("--workbench-workspace", default="4leaflabs", help="Workbench workspace receiving Plane tasks")
    parser.add_argument("--database", type=pathlib.Path, help="Workbench SQLite database path")
    parser.add_argument("--apply", action="store_true", help="Apply the previewed local changes")
    parser.add_argument("--workspace", default="4leaf-labs", help="Plane workspace slug for live API pull")
    parser.add_argument("--assignee", help="Plane user UUID for live API pull")
    parser.add_argument("--api-key-env", default="PLANE_API_KEY", help="Environment variable containing a Plane API key")
    parser.add_argument("--api-base-url", default="https://api.plane.so", help="Plane API base URL")
    args = parser.parse_args()

    database = args.database or find_database(DEFAULT_DATABASE_DIR)
    if args.snapshot:
        raw_items = json.loads(args.snapshot.read_text(encoding="utf-8"))
    else:
        api_key = os.environ.get(args.api_key_env, "")
        if not api_key or not args.assignee:
            parser.error(f"live pull requires --assignee and the {args.api_key_env} environment variable")
        raw_items = fetch_plane_items(args.api_base_url, api_key, args.workspace, args.assignee)
    items = [validate_item(item) for item in raw_items]
    connection = sqlite3.connect(database)
    connection.row_factory = sqlite3.Row
    try:
        categories = {}
        for item in items:
            name = item["category"] or args.category
            if name not in categories:
                categories[name] = category_id(connection, args.workbench_workspace, name)
        plan = [(item, categories[item["category"] or args.category],
                 *plan_item(connection, categories[item["category"] or args.category], item)) for item in items]
        for item, _, action, _, _ in plan:
            print(f"{action:12} {item['key']:14} {item['title']}")
        counts = {action: sum(1 for _, _, planned, _, _ in plan if planned == action)
                  for action in ("create", "update", "unchanged", "pending_push", "conflict")}
        print("Summary: " + ", ".join(f"{count} {action}" for action, count in counts.items() if count))
        if not args.apply:
            print("Dry run only; pass --apply to update Workbench. Plane is never modified by this tool.")
            return 0
        with connection:
            for item, category, action, link, task in plan:
                apply_item(connection, category, item, action, link, task)
        print(f"Applied local Workbench sync to {database}")
        return 0
    finally:
        connection.close()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, sqlite3.Error, json.JSONDecodeError) as error:
        print(f"sync-plane: {error}", file=sys.stderr)
        raise SystemExit(1)
