# Test coverage matrix

This matrix is the release-coverage inventory, not a statement that planned
tests pass. `Partial` names an implemented test that covers only part of the
requirement; `Planned` names the test to add in the owning phase. Neither is
accepted as complete coverage. The validator requires every P0/P1 PRD
requirement and every current Plane capability to have exactly one row, a
negative-path assertion, and a live source reference for each partial test.

| Requirement | Priority | Test IDs / planned coverage | Tier | Gate | Negative-path assertion | Status |
| --- | --- | --- | --- | --- | --- | --- |
| TASK-001 | P0 | Partial: `tst_database.qml::test_taskCreationAndFiltering` | QML repository | fast | rejected invalid field or destructive-action cancellation | Partial |
| TASK-002 | P0 | Planned: task details field edit contract | QML interaction | fast | rejected invalid field or destructive-action cancellation | Planned |
| TASK-003 | P0 | Planned: card-to-details navigation contract | QML interaction | fast | rejected invalid field or destructive-action cancellation | Planned |
| TASK-004 | P0 | Planned: task archive retains history | QML repository | fast | rejected invalid field or destructive-action cancellation | Planned |
| TASK-005 | P1 | Planned: delete confirmation and cascade contract | QML interaction | fast | rejected invalid field or destructive-action cancellation | Planned |
| TASK-006 | P1 | Planned: archived-task visibility preference | QML repository | fast | rejected invalid field or destructive-action cancellation | Planned |
| TASK-007 | P1 | Partial: `tst_database.qml::test_titleLimitCountsUnicodeCodePoints` | QML repository | fast | rejected invalid field or destructive-action cancellation | Partial |
| TASK-008 | P1 | Planned: 20,000-character description round trip | QML repository | fast | rejected invalid field or destructive-action cancellation | Planned |
| CAT-001 | P0 | Partial: `tst_category_drag.qml::test_emptyCategoryActionsMenuDeletesToTrash` | QML interaction | fast | rejected invalid move or constrained deletion | Partial |
| CAT-002 | P0 | Partial: `tst_category_drag.qml::test_categoryDragShowsFullFidelityGroupGhost` | QML interaction | fast | rejected invalid move or constrained deletion | Partial |
| CAT-003 | P0 | Partial: `tst_database.qml::test_filteredMoveUsesStableTaskIds` | QML repository | fast | rejected invalid move or constrained deletion | Partial |
| CAT-004 | P0 | Partial: `tst_database.qml::test_moveTaskCanPlaceTaskAtEndOfAnotherCategory` | QML repository | fast | rejected invalid move or constrained deletion | Partial |
| CAT-005 | P0 | Partial: `tst_database.qml::test_rebalanceKeepsUniqueOrderAfterExhaustingGaps` | QML repository | fast | rejected invalid move or constrained deletion | Partial |
| CAT-006 | P1 | Planned: collapse state persistence contract | QML interaction | fast | rejected invalid move or constrained deletion | Planned |
| CAT-007 | P1 | Partial: `tst_category_drag.qml::test_emptyCategoryActionsMenuDeletesToTrash` | QML interaction | fast | rejected invalid move or constrained deletion | Partial |
| STATUS-001 | P0 | Partial: `tst_database.qml::test_workbenchWorkflowStatusesAreScopedAndTerminal` | QML repository | fast | rejected invalid filter or historical correction | Partial |
| STATUS-002 | P0 | Partial: `tst_database.qml::test_statusHistoryReconcilesAfterCorrection` | QML repository | fast | rejected invalid filter or historical correction | Partial |
| STATUS-003 | P0 | Partial: `tst_database.qml::test_taskCreationAndFiltering` | QML repository | fast | rejected invalid filter or historical correction | Partial |
| STATUS-004 | P0 | Planned: clear-all status filters contract | QML interaction | fast | rejected invalid filter or historical correction | Planned |
| STATUS-005 | P1 | Partial: `tst_database.qml::test_statusChangeRejectsHistoricalTimestampAndCorrectionStopsTimer` | QML repository | fast | rejected invalid filter or historical correction | Partial |
| STATUS-006 | P1 | Planned: manual-status indicator contract | QML interaction | fast | rejected invalid filter or historical correction | Planned |
| STATUS-007 | P1 | Partial: `tst_database.qml::test_statusHistoryReconcilesAfterCorrection` | QML repository | fast | rejected invalid filter or historical correction | Partial |
| TIME-001 | P0 | Partial: `tst_database.qml::test_timerSwitchAndCompletionAreAtomic` | QML repository | fast | rejected invalid session or atomic transition failure | Partial |
| TIME-002 | P0 | Partial: `tst_database.qml::test_singleTimerModeStopsConcurrentTimersAndStopExceptIsAtomic` | QML repository | fast | rejected invalid session or atomic transition failure | Partial |
| TIME-003 | P0 | Partial: `tst_database.qml::test_singleTimerModeStopsConcurrentTimersAndStopExceptIsAtomic` | QML repository | fast | rejected invalid session or atomic transition failure | Partial |
| TIME-004 | P0 | Partial: `tst_database.qml::test_timerSwitchAndCompletionAreAtomic` | QML repository | fast | rejected invalid session or atomic transition failure | Partial |
| TIME-005 | P0 | Planned: visible elapsed-time refresh contract | QML interaction | fast | rejected invalid session or atomic transition failure | Planned |
| TIME-006 | P0 | Planned: elapsed time uses persisted timestamps | QML interaction | fast | rejected invalid session or atomic transition failure | Planned |
| TIME-007 | P0 | Planned: hosted-plasmoid timer restart workflow | Appium | release | rejected invalid session or atomic transition failure | Planned |
| TIME-008 | P1 | Partial: `tst_category_drag.qml::test_dailyReportAddsAndSelectsExactSession` | QML interaction | fast | rejected invalid session or atomic transition failure | Partial |
| TIME-009 | P1 | Partial: `tst_category_drag.qml::test_dailyReportExposesDiscoverableEditorControls` | QML interaction | fast | rejected invalid session or atomic transition failure | Partial |
| TIME-010 | P1 | Partial: `tst_database.qml::test_invalidInstantsAndTimeZonesAreRejectedWithoutWrites` | QML repository | fast | rejected invalid session or atomic transition failure | Partial |
| TIME-011 | P1 | Partial: `tst_category_drag.qml::test_dailyReportConfirmsUnusuallyLongSession` | QML interaction | fast | rejected invalid session or atomic transition failure | Partial |
| REPORT-001 | P0 | Partial: `tst_database.qml::test_weeklyReportSplitsAtLocalMidnight` | QML repository | fast | empty, boundary, or invalid-timezone result | Partial |
| REPORT-002 | P0 | Planned: monthly report aggregation fixture | QML repository | fast | empty, boundary, or invalid-timezone result | Planned |
| REPORT-003 | P0 | Partial: `tst_database.qml::test_categoryTrashRetainsReportHistory` | QML repository | fast | empty, boundary, or invalid-timezone result | Partial |
| REPORT-004 | P0 | Partial: `tst_timemath.cpp::splitsCrossMidnight` | native unit | fast | empty, boundary, or invalid-timezone result | Partial |
| REPORT-005 | P0 | Planned: week and month boundary aggregation fixture | QML repository | fast | empty, boundary, or invalid-timezone result | Planned |
| REPORT-006 | P0 | Partial: `tst_timemath.cpp::splitsDstTransition` | native unit | fast | empty, boundary, or invalid-timezone result | Partial |
| REPORT-007 | P1 | Partial: `tst_database.qml::test_categoryTimeMergesOverlappingTaskSessions` | QML repository | fast | empty, boundary, or invalid-timezone result | Partial |
| REPORT-008 | P1 | Planned: manual correction included in report fixture | QML repository | fast | empty, boundary, or invalid-timezone result | Planned |
| REPORT-010 | P1 | Partial: `tst_category_drag.qml::test_dailyTimelineStacksConcurrentTimersAndSupportsZoom` | QML interaction | fast | empty, boundary, or invalid-timezone result | Partial |
| REPORT-011 | P1 | Partial: `tst_category_drag.qml::test_dailyReportExposesDiscoverableEditorControls` | QML interaction | fast | empty, boundary, or invalid-timezone result | Partial |
| REPORT-012 | P1 | Partial: `tst_category_drag.qml::test_dailyEditorRequiresExplicitDstOffset` | QML interaction | fast | empty, boundary, or invalid-timezone result | Partial |
| REPORT-013 | P1 | Planned: year heatmap contribution contract | QML interaction | fast | empty, boundary, or invalid-timezone result | Planned |
| REPORT-014 | P1 | Partial: `tst_category_drag.qml::test_reportTabsPreserveDailyCategoryScope` | QML interaction | fast | empty, boundary, or invalid-timezone result | Partial |
| PREF-001 | P1 | Planned: first-day-of-week preference report fixture | QML interaction | fast | malformed preference falls back to a documented default | Planned |
| PREF-002 | P1 | Planned: report-timezone preference persistence | QML interaction | fast | malformed preference falls back to a documented default | Planned |
| PREF-003 | P1 | Planned: default status-filter persistence | QML interaction | fast | malformed preference falls back to a documented default | Planned |
| PREF-004 | P1 | Planned: archived-task preference persistence | QML interaction | fast | malformed preference falls back to a documented default | Planned |
| PREF-005 | P1 | Planned: 12/24-hour format preference contract | QML interaction | fast | malformed preference falls back to a documented default | Planned |
| PREF-006 | P1 | Planned: Plasma configuration reload contract | QML interaction | fast | malformed preference falls back to a documented default | Planned |
| PLANE-001 | N/A | Planned: test-only credential adapter rejects production use | native integration | fast | rejected request, remote failure, or secret-redaction path | Planned |
| PLANE-002 | N/A | Partial: `tst_planesync.cpp::rejectsInvalidBaseUrl` | native unit | fast | rejected request, remote failure, or secret-redaction path | Partial |
| PLANE-003 | N/A | Planned: fake-Plane project discovery | native integration | fast | rejected request, remote failure, or secret-redaction path | Planned |
| PLANE-004 | N/A | Planned: fake-Plane state discovery and mapping | QML integration | fast | rejected request, remote failure, or secret-redaction path | Planned |
| PLANE-005 | N/A | Partial: `test_workbench.py::test_z_plane_owner_picker_uses_cached_project_members` | Appium | release | rejected request, remote failure, or secret-redaction path | Partial |
| PLANE-006 | N/A | Partial: `tst_database.qml::test_providerBindingMappingsAndMemberCacheRemainOptional` | QML repository | fast | rejected request, remote failure, or secret-redaction path | Partial |
| PLANE-007 | N/A | Partial: `tst_database.qml::test_workbenchWorkflowStatusesAreScopedAndTerminal` | QML repository | fast | rejected request, remote failure, or secret-redaction path | Partial |
| PLANE-008 | N/A | Planned: fake-Plane outbound work-item creation | QML integration | fast | rejected request, remote failure, or secret-redaction path | Planned |
| PLANE-009 | N/A | Planned: fake-Plane fetch-before-push conflict | QML integration | fast | rejected request, remote failure, or secret-redaction path | Planned |
| PLANE-010 | N/A | Planned: fake-Plane outbound update | QML integration | fast | rejected request, remote failure, or secret-redaction path | Planned |
| PLANE-011 | N/A | Planned: fake-Plane pull creates and updates local tasks | QML integration | fast | rejected request, remote failure, or secret-redaction path | Planned |
| PLANE-012 | N/A | Planned: fake-Plane pull pagination policy | QML integration | fast | rejected request, remote failure, or secret-redaction path | Planned |
| PLANE-013 | N/A | Partial: `tst_database.qml::test_providerTaskLinksSupportPendingCreationConflictAndLegacyFields` | QML repository | fast | rejected request, remote failure, or secret-redaction path | Partial |
| PLANE-014 | N/A | Planned: HTTP failure and secret-redaction fixture | native integration | fast | rejected request, remote failure, or secret-redaction path | Planned |
| PLANE-015 | N/A | Planned: disconnect clears local binding and test credential | QML integration | fast | rejected request, remote failure, or secret-redaction path | Planned |
