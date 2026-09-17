# SPDX-FileCopyrightText: 2026 OwnisticApps
# SPDX-License-Identifier: LGPL-3.0-or-later
# pyright: reportMissingImports=false

"""Black-box Appium coverage for the Workbench plasmoid."""

from __future__ import annotations

import os
import shlex
import unittest
from pathlib import Path

from appium import webdriver
from appium.options.common.base import AppiumOptions
from appium.webdriver.common.appiumby import AppiumBy
from selenium.common.exceptions import WebDriverException
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.remote.webelement import WebElement
from selenium.webdriver.support import expected_conditions as conditions
from selenium.webdriver.support.ui import WebDriverWait

APPIUM_SERVER_URL = "http://127.0.0.1:4723"
CATEGORY_NAME = "Appium category"
MAX_RSS_KIB = 768 * 1024
MAX_RSS_GROWTH_KIB = 96 * 1024
NAVIGATION_ITERATIONS = 10


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

    def create_category(self) -> None:
        self.element("Create category").click()
        name_field = self.wait.until(
            conditions.presence_of_element_located(
                (AppiumBy.ACCESSIBILITY_ID, "create-category-name")
            )
        )
        name_field.send_keys(CATEGORY_NAME)
        self.wait.until(
            conditions.element_to_be_clickable(
                (AppiumBy.ACCESSIBILITY_ID, "create-category-save")
            )
        ).click()

    def create_task(self) -> None:
        self.element("Create task").click()
        title_field = self.wait.until(
            conditions.presence_of_element_located(
                (AppiumBy.ACCESSIBILITY_ID, "create-task-title")
            )
        )
        title_field.send_keys("Appium task")
        self.wait.until(
            conditions.element_to_be_clickable(
                (AppiumBy.ACCESSIBILITY_ID, "create-task-save")
            )
        ).click()
        self.element(f"Category: {CATEGORY_NAME}")

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

    def test_report_navigation_remains_bounded(self) -> None:
        self.create_category()
        self.create_task()
        rss_samples: list[int] = []

        reports_page = self.open_daily_report()
        reports_page.find_element(
            AppiumBy.ACCESSIBILITY_ID, "reports-year-tab"
        ).send_keys(Keys.SPACE)
        self.wait.until(
            conditions.presence_of_element_located(
                (AppiumBy.XPATH, "//*[contains(@name, 'Daily tracked-time heatmap for')]")
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

        add_button = reports_page.find_element(AppiumBy.ACCESSIBILITY_ID, "report-add-session")
        add_button.click()
        editor = self.wait.until(
            conditions.presence_of_element_located(
                (AppiumBy.ACCESSIBILITY_ID, "daily-session-editor")
            )
        )
        start_field = editor.find_element(AppiumBy.ACCESSIBILITY_ID, "daily-session-start")
        editor.find_element(AppiumBy.ACCESSIBILITY_ID, "daily-session-end")
        for field_id in ("daily-session-start-date", "daily-session-start",
                         "daily-session-end-date", "daily-session-end"):
            self.assert_contained(
                editor,
                editor.find_element(AppiumBy.ACCESSIBILITY_ID, field_id),
            )
        self.wait.until(lambda _driver: start_field.is_selected())
        self.capture_screenshot("editing")
        editor.find_element(AppiumBy.ACCESSIBILITY_ID, "daily-session-save").click()
        self.wait.until(
            conditions.presence_of_element_located(
                (AppiumBy.XPATH, "//*[contains(@accessibility-id, 'timeline-session-')]")
            )
        )
        self.wait.until(
            conditions.presence_of_element_located(
                (AppiumBy.XPATH, "//*[starts-with(@name, 'Total:') and not(contains(@name, '00:00:00'))]")
            )
        )
        add_button = reports_page.find_element(AppiumBy.ACCESSIBILITY_ID, "report-add-session")
        self.wait.until(lambda _driver: add_button.is_selected())
        self.capture_screenshot("populated")

        self.close_report(reports_page)
        baseline_rss = plasmawindowed_rss_kib(self.package_dir)

        for _ in range(NAVIGATION_ITERATIONS):
            reports_page = self.open_daily_report()
            self.close_report(reports_page)
            rss_samples.append(plasmawindowed_rss_kib(self.package_dir))

        self.assertLess(max(rss_samples), MAX_RSS_KIB)
        self.assertLess(max(rss_samples) - baseline_rss, MAX_RSS_GROWTH_KIB)


if __name__ == "__main__":
    unittest.main()
