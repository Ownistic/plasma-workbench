# SPDX-FileCopyrightText: 2026 OwnisticApps
# SPDX-License-Identifier: LGPL-3.0-or-later
# pyright: reportMissingImports=false

"""Black-box Appium coverage for the Workbench plasmoid."""

from __future__ import annotations

import json
import os
import shlex
import sqlite3
import unittest
from datetime import UTC, date, datetime, time, timedelta
from io import BytesIO
from pathlib import Path
from threading import Thread
from time import sleep
from typing import cast
from zoneinfo import ZoneInfo

from appium import webdriver
from appium.options.common.base import AppiumOptions
from appium.webdriver.common.appiumby import AppiumBy
from PIL import Image
from selenium.common.exceptions import WebDriverException
from selenium.webdriver.common.action_chains import ActionChains
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.remote.webelement import WebElement
from selenium.webdriver.support import expected_conditions as conditions
from selenium.webdriver.support.ui import WebDriverWait

APPIUM_SERVER_URL = "http://127.0.0.1:4723"
CATEGORY_NAME = "Launch preparation"
DRAG_SOURCE_CATEGORY = "Ghost source"
DRAG_TARGET_CATEGORY = "Ghost destination"
DRAG_TASK_TITLE = "Verify translucent placeholder"
DRAG_TARGET_TASK_TITLE = "Target drop group"
MAX_RSS_KIB = 768 * 1024
MAX_RSS_GROWTH_KIB = 96 * 1024
NAVIGATION_ITERATIONS = 10
README_SCREENSHOT_FIXTURE = os.environ.get("WORKBENCH_README_SCREENSHOTS") == "1"
README_HEATMAP_SESSION_OFFSETS = (3, 7, 12, 18, 26, 31, 39, 45, 52, 58, 64, 71, 78, 85, 88)


def plasmawindowed_rss_kib(package_dir: Path) -> int:
    """Return RSS for the plasmawindowed instance hosting this source package."""
    package_bytes = os.fsencode(str(package_dir))
    matches: list[int] = []
    for process_dir in Path("/proc").glob("[0-9]*"):
        try:
            command_line = (process_dir / "cmdline").read_bytes()
            if b"plasmawindowed" not in command_line or package_bytes not in command_line:
                continue
            for line in (process_dir / "status").read_text(encoding="utf-8").splitlines():
                if line.startswith("VmRSS:"):
                    matches.append(int(line.split()[1]))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    if len(matches) != 1:
        raise AssertionError(f"Expected one Workbench plasmawindowed process, found {len(matches)}")
    return matches[0]


class WorkbenchEndToEndTest(unittest.TestCase):
    """Exercise Workbench through the same accessibility API used by Plasma."""

    driver: webdriver.Remote
    wait: WebDriverWait
    package_dir: Path
    variant: str

    @classmethod
    def setUpClass(cls) -> None:
        package_value = os.environ.get("WORKBENCH_PACKAGE_DIR")
        if not package_value:
            raise RuntimeError("WORKBENCH_PACKAGE_DIR must point at the built plasmoid package")
        cls.package_dir = Path(package_value).resolve()
        cls.variant = os.environ.get("WORKBENCH_VISUAL_VARIANT", "compact")
        if not (cls.package_dir / "metadata.json").is_file():
            raise RuntimeError(f"Invalid plasmoid package directory: {cls.package_dir}")

        options = AppiumOptions()
        command = "plasmawindowed -p org.kde.plasma.nano " + shlex.quote(str(cls.package_dir))
        options.set_capability("app", command)
        options.set_capability("timeouts", {"implicit": 10000})
        options.set_capability(
            "environ",
            {
                "LC_ALL": "en_US.UTF-8",
                "QT_LINUX_ACCESSIBILITY_ALWAYS_ON": "1",
                "QT_LOGGING_RULES": "qt.accessibility.atspi.warning=false",
                "QT_SCALE_FACTOR": os.environ.get("WORKBENCH_SCALE_FACTOR", "1"),
            },
        )
        cls.driver = webdriver.Remote(command_executor=APPIUM_SERVER_URL, options=options)
        cls.wait = WebDriverWait(cls.driver, 20)

    @classmethod
    def tearDownClass(cls) -> None:
        if hasattr(cls, "driver"):
            cls.driver.quit()

    def tearDown(self) -> None:
        outcome = getattr(self, "_outcome", None)
        result = getattr(outcome, "result", None)
        if result is not None and result.wasSuccessful():
            return
        artifact_dir = Path(os.environ.get("APPIUM_ARTIFACT_OUTPUT_PATH", "."))
        artifact_dir.mkdir(parents=True, exist_ok=True)
        test_name = self.id().rsplit(".", maxsplit=1)[-1]
        try:
            self.driver.get_screenshot_as_file(
                str(artifact_dir / f"workbench-e2e-{test_name}-failure.png")
            )
        except WebDriverException as error:
            print(f"Could not capture failure screenshot: {error}")

    def element(self, name: str) -> WebElement:
        return self.wait.until(
            conditions.presence_of_element_located((AppiumBy.NAME, name))
        )

    def capture_screenshot(self, state: str) -> None:
        artifact_dir = Path(os.environ.get("APPIUM_ARTIFACT_OUTPUT_PATH", "."))
        artifact_dir.mkdir(parents=True, exist_ok=True)
        screenshot_path = artifact_dir / f"daily-editor-{self.variant}-{state}.png"
        self.assertTrue(self.driver.get_screenshot_as_file(str(screenshot_path)))

    def assert_contained(self, parent: WebElement, child: WebElement) -> None:
        parent_rect = parent.rect
        child_rect = child.rect
        self.assertGreaterEqual(child_rect["x"], parent_rect["x"] - 1)
        self.assertGreaterEqual(child_rect["y"], parent_rect["y"] - 1)
        self.assertLessEqual(child_rect["x"] + child_rect["width"],
                             parent_rect["x"] + parent_rect["width"] + 1)
        self.assertLessEqual(child_rect["y"] + child_rect["height"],
                             parent_rect["y"] + parent_rect["height"] + 1)

    def create_category(self, name: str = CATEGORY_NAME) -> None:
        self.element("Create category").click()
        name_field = self.wait.until(
            conditions.presence_of_element_located(
                (AppiumBy.ACCESSIBILITY_ID, "create-category-name")
            )
        )
        name_field.send_keys(name)
        self.wait.until(
            conditions.element_to_be_clickable(
                (AppiumBy.ACCESSIBILITY_ID, "create-category-save")
            )
        ).click()

    def create_task(self, title: str = "Polish daily timeline",
                    category_name: str = CATEGORY_NAME, category_index: int = 0) -> None:
        self.element("Create task").click()
        title_field = self.wait.until(
            conditions.presence_of_element_located(
                (AppiumBy.ACCESSIBILITY_ID, "create-task-title")
            )
        )
        title_field.send_keys(title)
        category_field = self.wait.until(
            conditions.element_to_be_clickable(
                (AppiumBy.ACCESSIBILITY_ID, "create-task-category")
            )
        )
        category_field.send_keys(Keys.HOME)
        for _ in range(category_index):
            category_field.send_keys(Keys.ARROW_DOWN)
        self.wait.until(
            conditions.element_to_be_clickable(
                (AppiumBy.ACCESSIBILITY_ID, "create-task-save")
            )
        ).click()
        self.element(f"Category: {category_name}")

    def card_accent_pixel(self, card: WebElement) -> tuple[int, int, int]:
        """Sample the category-color accent, where compositing is visually unambiguous."""
        screenshot = Image.open(BytesIO(self.driver.get_screenshot_as_png())).convert("RGB")
        rect = card.rect
        content_x, content_y, scale = self.compositor_content_origin(screenshot)
        sample_x = round(content_x + (rect["x"] + 1) * scale)
        sample_y = round(content_y + (rect["y"] + rect["height"] / 2) * scale)
        pixels: list[tuple[int, int, int]] = [
            cast(tuple[int, int, int], screenshot.getpixel((sample_x + offset_x, sample_y + offset_y)))
            for offset_x in range(-1, 2)
            for offset_y in range(-2, 3)
        ]
        return (
            sum(pixel[0] for pixel in pixels) // len(pixels),
            sum(pixel[1] for pixel in pixels) // len(pixels),
            sum(pixel[2] for pixel in pixels) // len(pixels),
        )

    def compositor_content_origin(self, screenshot: Image.Image) -> tuple[float, float, float]:
        """Map client-relative AT-SPI rectangles to KWin's compositor coordinates."""
        bounds = screenshot.getbbox()
        if bounds is None:
            raise AssertionError("Expected the Workbench window in the compositor screenshot")
        left, top, _, _ = bounds
        scale = float(os.environ.get("WORKBENCH_SCALE_FACTOR", "1"))
        return left + 8 * scale, top + 36 * scale, scale

    def visible_task_card(self, title: str) -> WebElement | bool:
        """Return the live task card, ignoring stale preview accessibility nodes."""
        for card in self.driver.find_elements(AppiumBy.NAME, f"Open task {title}"):
            try:
                if card.rect["width"] > 0:
                    return card
            except WebDriverException:
                continue
        return False

    def aligned_element(self, name: str, x: float) -> WebElement:
        """Find the lowest visible element aligned with the destination column."""
        candidates: list[tuple[float, WebElement]] = []
        for element in self.driver.find_elements(AppiumBy.NAME, name):
            try:
                rect = element.rect
                if rect["width"] > 0 and rect["height"] > 0 and abs(rect["x"] - x) <= 1:
                    candidates.append((rect["y"], element))
            except WebDriverException:
                continue
        if not candidates:
            raise AssertionError(f"Expected {name!r} aligned at x={x}")
        return max(candidates, key=lambda candidate: candidate[0])[1]

    def open_daily_report(self) -> WebElement:
        self.element(f"Open daily timeline for {CATEGORY_NAME}").click()
        reports_page = self.wait.until(
            conditions.presence_of_element_located(
                (AppiumBy.ACCESSIBILITY_ID, "reports-page")
            )
        )
        reports_page.find_element(AppiumBy.NAME, "Back to tasks")
        return reports_page

    def close_report(self, reports_page: WebElement) -> None:
        reports_page.find_element(AppiumBy.NAME, "Back to tasks").click()
        self.element(f"Open daily timeline for {CATEGORY_NAME}")

    def add_report_session(self, reports_page: WebElement, start_date: str, start_time: str,
                           end_time: str, visible_session_count: int | None = None,
                           capture_state: str = "") -> None:
        add_button = reports_page.find_element(AppiumBy.ACCESSIBILITY_ID, "report-add-session")
        add_button.click()
        editor = self.wait.until(
            conditions.presence_of_element_located(
                (AppiumBy.ACCESSIBILITY_ID, "daily-session-editor")
            )
        )
        fields = {
            "daily-session-start-date": start_date,
            "daily-session-start": start_time,
            "daily-session-end-date": start_date,
            "daily-session-end": end_time,
        }
        for field_id, value in fields.items():
            field = editor.find_element(AppiumBy.ACCESSIBILITY_ID, field_id)
            self.assert_contained(editor, field)
            field.clear()
            field.send_keys(value)
        if capture_state:
            self.capture_screenshot(capture_state)
        editor.find_element(AppiumBy.ACCESSIBILITY_ID, "daily-session-save").click()
        self.wait.until(
            conditions.invisibility_of_element_located(
                (AppiumBy.ACCESSIBILITY_ID, "daily-session-editor")
            )
        )
        if visible_session_count is not None:
            self.wait.until(
                lambda driver: len(driver.find_elements(
                    AppiumBy.XPATH, "//*[contains(@accessibility-id, 'timeline-session-')]"
                )) >= visible_session_count
            )
        add_button = reports_page.find_element(AppiumBy.ACCESSIBILITY_ID, "report-add-session")
        self.wait.until(lambda _driver, button=add_button: button.is_selected())

    def seed_readme_heatmap_sessions(self, today: date) -> None:
        """Populate the isolated Qt LocalStorage database without slow editor interactions."""
        data_home = Path(os.environ["XDG_DATA_HOME"])
        database_paths = list(data_home.glob("**/QML/OfflineStorage/Databases/*.sqlite"))
        self.assertEqual(len(database_paths), 1, f"Expected one Qt LocalStorage database in {data_home}")

        with sqlite3.connect(database_paths[0], timeout=10) as database:
            task = database.execute(
                "SELECT id FROM tasks WHERE title = ?", ("Polish daily timeline",)
            ).fetchone()
            timezone = database.execute(
                "SELECT timezone_id FROM work_sessions ORDER BY started_at_utc LIMIT 1"
            ).fetchone()
            self.assertIsNotNone(task)
            self.assertIsNotNone(timezone)
            timezone_id = str(timezone[0])
            zone = ZoneInfo(timezone_id)
            created_at = datetime.now(UTC).isoformat(timespec="milliseconds").replace("+00:00", "Z")
            sessions: list[tuple[str, str, str, str, str, int]] = []

            for index, day_offset in enumerate(README_HEATMAP_SESSION_OFFSETS):
                session_date = today - timedelta(days=day_offset)
                start_hour = 9 + index % 3
                end_hour = start_hour + 1 + index % 3
                started_at = datetime.combine(session_date, time(start_hour), zone)
                ended_at = datetime.combine(session_date, time(end_hour, 30 if index % 2 else 0), zone)
                started_at_utc = started_at.astimezone(UTC).isoformat(timespec="milliseconds").replace("+00:00", "Z")
                ended_at_utc = ended_at.astimezone(UTC).isoformat(timespec="milliseconds").replace("+00:00", "Z")
                duration = int((ended_at - started_at).total_seconds())
                sessions.append((
                    f"readme-heatmap-{session_date.isoformat()}",
                    str(task[0]),
                    started_at_utc,
                    ended_at_utc,
                    timezone_id,
                    duration,
                ))

            database.executemany(
                "INSERT INTO work_sessions "
                "(id, task_id, started_at_utc, ended_at_utc, timezone_id, manually_edited, note, created_at_utc, updated_at_utc) "
                "VALUES (?, ?, ?, ?, ?, 1, '', ?, ?)",
                [session[:5] + (created_at, created_at) for session in sessions],
            )
            database.execute(
                "UPDATE tasks SET tracked_seconds = tracked_seconds + ? WHERE id = ?",
                (sum(session[5] for session in sessions), str(task[0])),
            )

    def seed_plane_owner_fixture(self, task_title: str) -> None:
        """Create a cached Plane link and members without any network request."""
        data_home = Path(os.environ["XDG_DATA_HOME"])
        database_paths = list(data_home.glob("**/QML/OfflineStorage/Databases/*.sqlite"))
        self.assertEqual(len(database_paths), 1, f"Expected one Qt LocalStorage database in {data_home}")

        timestamp = datetime.now(UTC).isoformat(timespec="milliseconds").replace("+00:00", "Z")
        with sqlite3.connect(database_paths[0], timeout=10) as database:
            task = database.execute(
                "SELECT tasks.id, categories.id, categories.workspace_id FROM tasks "
                "JOIN categories ON categories.id = tasks.category_id WHERE tasks.title = ?",
                (task_title,),
            ).fetchone()
            self.assertIsNotNone(task)
            task_id, category_id, workspace_id = (str(value) for value in task)
            project_id = "plane-readme-project"

            database.execute(
                "INSERT INTO workspace_providers "
                "(workspace_id, provider, connection_id, config_json, created_at_utc, updated_at_utc) "
                "VALUES (?, 'plane', 'readme-plane', ?, ?, ?) "
                "ON CONFLICT(workspace_id) DO UPDATE SET provider = excluded.provider, "
                "connection_id = excluded.connection_id, config_json = excluded.config_json, "
                "updated_at_utc = excluded.updated_at_utc",
                (workspace_id, json.dumps({"baseUrl": "https://api.plane.so", "workspace": "4leaf-labs"}), timestamp, timestamp),
            )
            database.execute(
                "INSERT INTO provider_project_mappings "
                "(category_id, workspace_id, provider, remote_project_id, remote_project_name, created_at_utc, updated_at_utc) "
                "VALUES (?, ?, 'plane', ?, '4leaflabs', ?, ?) "
                "ON CONFLICT(category_id) DO UPDATE SET workspace_id = excluded.workspace_id, provider = excluded.provider, "
                "remote_project_id = excluded.remote_project_id, remote_project_name = excluded.remote_project_name, "
                "updated_at_utc = excluded.updated_at_utc",
                (category_id, workspace_id, project_id, timestamp, timestamp),
            )
            database.execute(
                "DELETE FROM provider_members WHERE workspace_id = ? AND provider = 'plane' AND project_id = ?",
                (workspace_id, project_id),
            )
            members = [
                ("member-ari", "Ari Vega", "ari@example.test"),
                ("member-mila", "Mila Chen", "mila@example.test"),
                ("member-sam", "Sam Patel", "sam@example.test"),
            ]
            database.executemany(
                "INSERT INTO provider_members "
                "(workspace_id, provider, project_id, member_id, member_name, member_email, member_payload_json, updated_at_utc) "
                "VALUES (?, 'plane', ?, ?, ?, ?, '{}', ?)",
                [(workspace_id, project_id, member_id, name, email, timestamp) for member_id, name, email in members],
            )
            database.execute(
                "INSERT INTO provider_task_links "
                "(task_id, provider, remote_id, remote_key, remote_url, project_id, remote_updated_at, remote_revision, "
                "last_local_updated_at, last_synced_at, sync_state, sync_error, assignee_ids_json, managed_baseline_json, "
                "remote_payload_json, created_at_utc, updated_at_utc) "
                "VALUES (?, 'plane', 'plane-readme-task', '4LEAF-42', 'https://app.plane.so/4leaf-labs/browse/4LEAF-42', "
                "?, ?, 'readme-revision', ?, ?, 'in_sync', NULL, ?, '{}', '{}', ?, ?) "
                "ON CONFLICT(task_id) DO UPDATE SET provider = excluded.provider, remote_id = excluded.remote_id, "
                "remote_key = excluded.remote_key, remote_url = excluded.remote_url, project_id = excluded.project_id, "
                "remote_updated_at = excluded.remote_updated_at, remote_revision = excluded.remote_revision, "
                "last_synced_at = excluded.last_synced_at, sync_state = excluded.sync_state, sync_error = excluded.sync_error, "
                "assignee_ids_json = excluded.assignee_ids_json, updated_at_utc = excluded.updated_at_utc",
                (task_id, project_id, timestamp, timestamp, timestamp, json.dumps(["member-ari"]), timestamp, timestamp),
            )

    def test_z_plane_owner_picker_uses_cached_project_members(self) -> None:
        category_name = "Plane launch"
        task_title = "Coordinate Plane launch"
        self.create_category(category_name)
        self.create_task(task_title, category_name, category_index=2)
        self.seed_plane_owner_fixture(task_title)

        task_card = self.wait.until(lambda _driver: self.visible_task_card(task_title))
        assert isinstance(task_card, WebElement)
        task_card.send_keys(Keys.ENTER)
        owner_picker = self.element("Plane owner: Ari Vega")
        owner_picker.click()
        self.element("Search Plane members")
        self.element("Assign Plane task to Mila Chen")
        self.capture_screenshot("plane-owner-picker")

    def test_report_navigation_remains_bounded(self) -> None:
        self.create_category()
        self.create_task(category_index=2)
        self.create_task("Plan the release", category_index=2)
        self.create_task("Review activity report", category_index=2)
        self.capture_screenshot("board")
        rss_samples: list[int] = []

        reports_page = self.open_daily_report()
        reports_page.find_element(
            AppiumBy.ACCESSIBILITY_ID, "reports-year-tab"
        ).send_keys(Keys.SPACE)
        self.wait.until(
            conditions.presence_of_element_located(
                (AppiumBy.XPATH, "//*[contains(@name, 'Daily tracked-time heatmap ending')]")
            )
        )
        reports_page.find_element(
            AppiumBy.ACCESSIBILITY_ID, "reports-day-tab"
        ).send_keys(Keys.SPACE)
        self.wait.until(
            conditions.presence_of_element_located(
                (AppiumBy.XPATH, "//*[contains(@name, '15-minute work-session timeline for')]")
            )
        )

        anchor_hour = max(3, min(20, datetime.now(UTC).astimezone().hour))
        session_times = [
            (f"{anchor_hour - 3:02d}:00:00", f"{anchor_hour - 2:02d}:30:00"),
            (f"{anchor_hour - 1:02d}:00:00", f"{anchor_hour:02d}:00:00"),
            (f"{anchor_hour + 1:02d}:00:00", f"{anchor_hour + 2:02d}:30:00"),
        ]

        today = datetime.now(UTC).astimezone().date()
        for index, (start_time, end_time) in enumerate(session_times):
            self.add_report_session(
                reports_page,
                today.isoformat(),
                start_time,
                end_time,
                index + 1,
                "editing" if index == len(session_times) - 1 else "",
            )

        if README_SCREENSHOT_FIXTURE:
            self.seed_readme_heatmap_sessions(today)

        self.wait.until(
            conditions.presence_of_element_located(
                (AppiumBy.XPATH, "//*[starts-with(@name, 'Total:') and not(contains(@name, '00:00:00'))]")
            )
        )
        self.capture_screenshot("populated")

        reports_page.find_element(
            AppiumBy.ACCESSIBILITY_ID, "reports-year-tab"
        ).send_keys(Keys.SPACE)
        tracked_day = self.wait.until(
            conditions.presence_of_element_located(
                (AppiumBy.XPATH,
                 f"//*[starts-with(@name, 'Tracked time on {today.isoformat()}:') "
                 "and not(contains(@name, '00:00:00'))]"),
            )
        )
        heatmap_days = self.driver.find_elements(
            AppiumBy.XPATH, "//*[starts-with(@name, 'Tracked time on ')]"
        )
        rightmost_day_x = max(day.rect["x"] for day in heatmap_days if day.rect["width"] > 0)
        self.assertAlmostEqual(
            tracked_day.rect["x"],
            rightmost_day_x,
            delta=1,
            msg="The selected day must be in the final heatmap column",
        )
        self.capture_screenshot("year-populated")

        self.close_report(reports_page)
        baseline_rss = plasmawindowed_rss_kib(self.package_dir)

        for _ in range(NAVIGATION_ITERATIONS):
            reports_page = self.open_daily_report()
            self.close_report(reports_page)
            rss_samples.append(plasmawindowed_rss_kib(self.package_dir))

        self.assertLess(max(rss_samples), MAX_RSS_KIB)
        self.assertLess(max(rss_samples) - baseline_rss, MAX_RSS_GROWTH_KIB)

    def test_category_drag_insertion_ghost_matches_task_behavior(self) -> None:
        self.create_category(DRAG_SOURCE_CATEGORY)
        self.create_task(DRAG_TASK_TITLE, DRAG_SOURCE_CATEGORY)
        self.create_category(DRAG_TARGET_CATEGORY)
        self.create_task(DRAG_TARGET_TASK_TITLE, DRAG_TARGET_CATEGORY, category_index=1)

        source_handle = self.element(f"Drag category {DRAG_SOURCE_CATEGORY} to reorder it")
        target_header = self.element(f"Category: {DRAG_TARGET_CATEGORY}")
        target_card = self.wait.until(lambda _driver: self.visible_task_card(DRAG_TARGET_TASK_TITLE))
        source_rect = source_handle.rect
        target_rect = target_header.rect
        target_card_rect = target_card.rect
        initial_screenshot = Image.open(BytesIO(self.driver.get_screenshot_as_png())).convert("RGB")
        content_x, content_y, scale = self.compositor_content_origin(initial_screenshot)
        source_x = content_x + source_rect["x"] * scale
        source_y = content_y + source_rect["y"] * scale
        target_x = content_x + (target_rect["x"] + target_rect["width"] / 2) * scale
        target_y = content_y + (target_rect["y"] + target_rect["height"] * 3 / 4) * scale
        drag_actions = ActionChains(self.driver, duration=500).move_by_offset(source_x, source_y).click_and_hold().pause(0.2).move_by_offset(
            target_x - source_x, target_y - source_y).pause(5).release()
        drag_thread = Thread(target=drag_actions.perform)
        drag_thread.start()
        try:
            sleep(2)
            self.capture_screenshot("category-drag-placeholder")
            insertion_previews = self.driver.find_elements(AppiumBy.NAME, "Category drag insertion preview")
            self.assertEqual(
                len(insertion_previews),
                1,
                "A category drag must render exactly one destination ghost",
            )
            preview_header = self.aligned_element(f"Category: {DRAG_SOURCE_CATEGORY}", target_rect["x"])
            preview_card = self.aligned_element(f"Open task {DRAG_TASK_TITLE}", target_card_rect["x"])
            current_target_header = self.element(f"Category: {DRAG_TARGET_CATEGORY}")
            self.assertGreater(preview_header.rect["y"], current_target_header.rect["y"])
            ghost_rect = preview_card.rect
            ghost_pixel = self.card_accent_pixel(preview_card)
        finally:
            drag_thread.join()

        solid_card = self.wait.until(lambda _driver: self.visible_task_card(DRAG_TASK_TITLE))
        solid_pixel = self.card_accent_pixel(solid_card)
        color_distance = sum(abs(ghost_pixel[channel] - solid_pixel[channel]) for channel in range(3))
        self.assertGreater(
            color_distance,
            10,
            f"Expected translucent insertion pixels to differ from the solid card: {ghost_pixel} vs {solid_pixel}; ghost={ghost_rect}",
        )


if __name__ == "__main__":
    unittest.main()
