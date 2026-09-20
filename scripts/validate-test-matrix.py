#!/usr/bin/env python3
"""Fail when the test matrix no longer covers the declared product surface."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


PRD_ROW = re.compile(r"^\|\s*([A-Z]+-\d+)\s*\|\s*(P[012])\s*\|")
MATRIX_ROW = re.compile(r"^\|\s*([A-Z]+-\d+)\s*\|\s*(P[0-9]|N/A)\s*\|\s*(.+?)\s*\|\s*(.+?)\s*\|\s*(fast|release)\s*\|\s*(.+?)\s*\|\s*(Partial|Planned)\s*\|\s*$")
TEST_REFERENCE = re.compile(r"^(?:Partial): `([^`]+)::([A-Za-z_][A-Za-z0-9_]*)`$")
PLANE_CAPABILITIES = {
    "PLANE-001", "PLANE-002", "PLANE-003", "PLANE-004", "PLANE-005",
    "PLANE-006", "PLANE-007", "PLANE-008", "PLANE-009", "PLANE-010",
    "PLANE-011", "PLANE-012", "PLANE-013", "PLANE-014", "PLANE-015",
}


def declared_requirements(prd: Path) -> dict[str, str]:
    requirements: dict[str, str] = {}
    for line in prd.read_text(encoding="utf-8").splitlines():
        match = PRD_ROW.match(line)
        if match and match.group(2) in {"P0", "P1"}:
            requirement, priority = match.groups()
            requirements[requirement] = priority
    return requirements


def known_test_functions(test_root: Path) -> set[tuple[str, str]]:
    functions: set[tuple[str, str]] = set()
    for source in test_root.rglob("*"):
        if source.suffix not in {".cpp", ".py", ".qml"}:
            continue
        text = source.read_text(encoding="utf-8")
        for match in re.finditer(r"(?:function|void|def)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", text):
            functions.add((source.name, match.group(1)))
    return functions


def matrix_rows(matrix: Path, test_root: Path) -> dict[str, tuple[str, str, str, str, str]]:
    rows: dict[str, tuple[str, str, str, str, str]] = {}
    errors: list[str] = []
    known_functions = known_test_functions(test_root)
    for number, line in enumerate(matrix.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.startswith("|") or line.startswith("| Requirement") or line.startswith("| ---"):
            continue
        match = MATRIX_ROW.match(line)
        if not match:
            errors.append(f"{matrix}:{number}: invalid matrix row")
            continue
        requirement, priority, tests, tier, gate, negative, status = match.groups()
        if requirement in rows:
            errors.append(f"{matrix}:{number}: duplicate requirement {requirement}")
        if not negative.strip():
            errors.append(f"{matrix}:{number}: missing negative-path assertion")
        if status == "Partial":
            reference = TEST_REFERENCE.match(tests)
            if not reference:
                errors.append(f"{matrix}:{number}: Partial coverage requires a backticked file::function reference")
            elif reference.groups() not in known_functions:
                errors.append(f"{matrix}:{number}: stale test reference {reference.group(1)}::{reference.group(2)}")
        if status == "Planned" and not tests.startswith("Planned:"):
            errors.append(f"{matrix}:{number}: Planned coverage must name a Planned test")
        rows[requirement] = (priority, tests, tier, gate, negative)
    if errors:
        raise ValueError("\n".join(errors))
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--prd", type=Path, required=True)
    parser.add_argument("--matrix", type=Path, required=True)
    arguments = parser.parse_args()

    expected = declared_requirements(arguments.prd)
    try:
        rows = matrix_rows(arguments.matrix, arguments.prd.parent / "tests")
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1

    errors: list[str] = []
    missing = sorted(set(expected) - set(rows))
    if missing:
        errors.append("missing P0/P1 requirements: " + ", ".join(missing))
    missing_plane = sorted(PLANE_CAPABILITIES - set(rows))
    if missing_plane:
        errors.append("missing Plane capabilities: " + ", ".join(missing_plane))
    unknown = sorted(set(rows) - set(expected) - PLANE_CAPABILITIES)
    if unknown:
        errors.append("unknown matrix requirements: " + ", ".join(unknown))
    for requirement, priority in expected.items():
        if requirement in rows and rows[requirement][0] != priority:
            errors.append(f"{requirement}: matrix priority {rows[requirement][0]} does not match PRD {priority}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Validated {len(expected)} P0/P1 requirements and {len(PLANE_CAPABILITIES)} Plane capabilities.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
