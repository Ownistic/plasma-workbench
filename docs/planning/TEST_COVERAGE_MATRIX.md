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
| TASK-002 | P0 | Partial: `test_workbench.py::test_task_details_edits_persist_to_the_board` | Appium | release | rejected invalid field or destructive-action cancellation | Partial |
| TASK-003 | P0 | Partial: `test_workbench.py::test_task_details_edits_persist_to_the_board` | Appium | release | rejected invalid field or destructive-action cancellation | Partial |
| TASK-004 | P0 | Partial: `tst_database.qml::test_archivingHidesTaskButRetainsSessionsAndHistory` | QML repository | fast | rejected invalid field or destructive-action cancellation | Partial |
| TASK-005 | P1 | Partial: `tst_database.qml::test_deletingTaskCascadesSessionsAndStatusHistory` | QML repository | fast | rejected invalid field or destructive-action cancellation | Partial |
| TASK-006 | P1 | Partial: `tst_database.qml::test_archivingHidesTaskButRetainsSessionsAndHistory` | QML repository | fast | rejected invalid field or destructive-action cancellation | Partial |
| TASK-007 | P1 | Partial: `tst_database.qml::test_titleLimitCountsUnicodeCodePoints` | QML repository | fast | rejected invalid field or destructive-action cancellation | Partial |
| TASK-008 | P1 | Partial: `tst_database.qml::test_descriptionAcceptsLimitAndRejectsOneExtraCodePoint` | QML repository | fast | rejected invalid field or destructive-action cancellation | Partial |
| CAT-001 | P0 | Partial: `tst_category_drag.qml::test_emptyCategoryActionsMenuDeletesToTrash` | QML interaction | fast | rejected invalid move or constrained deletion | Partial |
| CAT-002 | P0 | Partial: `tst_category_drag.qml::test_categoryDragShowsFullFidelityGroupGhost` | QML interaction | fast | rejected invalid move or constrained deletion | Partial |
| CAT-003 | P0 | Partial: `tst_database.qml::test_filteredMoveUsesStableTaskIds` | QML repository | fast | rejected invalid move or constrained deletion | Partial |
| CAT-004 | P0 | Partial: `tst_database.qml::test_moveTaskCanPlaceTaskAtEndOfAnotherCategory` | QML repository | fast | rejected invalid move or constrained deletion | Partial |
| CAT-005 | P0 | Partial: `tst_database.qml::test_rebalanceKeepsUniqueOrderAfterExhaustingGaps` | QML repository | fast | rejected invalid move or constrained deletion | Partial |
| CAT-006 | P1 | Partial: `tst_database.qml::test_categoryCollapseStatePersistsAcrossRepositoryReinitialization` | QML repository | fast | rejected invalid move or constrained deletion | Partial |
| CAT-007 | P1 | Partial: `tst_category_drag.qml::test_emptyCategoryActionsMenuDeletesToTrash` | QML interaction | fast | rejected invalid move or constrained deletion | Partial |
| STATUS-001 | P0 | Partial: `tst_database.qml::test_workbenchWorkflowStatusesAreScopedAndTerminal` | QML repository | fast | rejected invalid filter or historical correction | Partial |
| STATUS-002 | P0 | Partial: `tst_database.qml::test_statusHistoryReconcilesAfterCorrection` | QML repository | fast | rejected invalid filter or historical correction | Partial |
| STATUS-003 | P0 | Partial: `tst_database.qml::test_taskCreationAndFiltering` | QML repository | fast | rejected invalid filter or historical correction | Partial |
| STATUS-004 | P0 | Partial: `test_workbench.py::test_clear_status_filters_restores_hidden_task` | Appium | release | rejected invalid filter or historical correction | Partial |
| STATUS-005 | P1 | Partial: `tst_database.qml::test_statusChangeRejectsHistoricalTimestampAndCorrectionStopsTimer` | QML repository | fast | rejected invalid filter or historical correction | Partial |
| STATUS-006 | P1 | Planned: manual-status indicator contract | QML interaction | fast | rejected invalid filter or historical correction | Planned |
| STATUS-007 | P1 | Partial: `tst_database.qml::test_statusHistoryReconcilesAfterCorrection` | QML repository | fast | rejected invalid filter or historical correction | Partial |
| TIME-001 | P0 | Partial: `tst_database.qml::test_timerSwitchAndCompletionAreAtomic` | QML repository | fast | rejected invalid session or atomic transition failure | Partial |
| TIME-002 | P0 | Partial: `tst_database.qml::test_singleTimerModeStopsConcurrentTimersAndStopExceptIsAtomic` | QML repository | fast | rejected invalid session or atomic transition failure | Partial |
| TIME-003 | P0 | Partial: `tst_database.qml::test_singleTimerModeStopsConcurrentTimersAndStopExceptIsAtomic` | QML repository | fast | rejected invalid session or atomic transition failure | Partial |
| TIME-004 | P0 | Partial: `tst_database.qml::test_timerSwitchAndCompletionAreAtomic` | QML repository | fast | rejected invalid session or atomic transition failure | Partial |
| TIME-005 | P0 | Partial: `test_workbench.py::test_active_timer_elapsed_text_refreshes_and_pauses` | Appium | release | rejected invalid session or atomic transition failure | Partial |
| TIME-006 | P0 | Partial: `test_workbench.py::test_active_timer_elapsed_text_refreshes_and_pauses` | Appium | release | rejected invalid session or atomic transition failure | Partial |
| TIME-007 | P0 | Partial: `tst_database.qml::test_activeTimerSurvivesRepositoryReinitialization` | QML repository | fast | rejected invalid session or atomic transition failure | Partial |
| TIME-008 | P1 | Partial: `tst_category_drag.qml::test_dailyReportAddsAndSelectsExactSession` | QML interaction | fast | rejected invalid session or atomic transition failure | Partial |
| TIME-009 | P1 | Partial: `tst_category_drag.qml::test_dailyReportExposesDiscoverableEditorControls` | QML interaction | fast | rejected invalid session or atomic transition failure | Partial |
| TIME-010 | P1 | Partial: `tst_database.qml::test_invalidInstantsAndTimeZonesAreRejectedWithoutWrites` | QML repository | fast | rejected invalid session or atomic transition failure | Partial |
| TIME-011 | P1 | Partial: `tst_category_drag.qml::test_dailyReportConfirmsUnusuallyLongSession` | QML interaction | fast | rejected invalid session or atomic transition failure | Partial |
| REPORT-001 | P0 | Partial: `tst_database.qml::test_weeklyReportSplitsAtLocalMidnight` | QML repository | fast | empty, boundary, or invalid-timezone result | Partial |
| REPORT-002 | P0 | Partial: `tst_database.qml::test_monthlyReportAggregatesPersistedSessions` | QML repository | fast | empty, boundary, or invalid-timezone result | Partial |
| REPORT-003 | P0 | Partial: `tst_database.qml::test_categoryTrashRetainsReportHistory` | QML repository | fast | empty, boundary, or invalid-timezone result | Partial |
| REPORT-004 | P0 | Partial: `tst_timemath.cpp::splitsCrossMidnight` | native unit | fast | empty, boundary, or invalid-timezone result | Partial |
| REPORT-005 | P0 | Partial: `tst_database.qml::test_weekAndMonthReportsClipAtCalendarBoundaries` | QML repository | fast | empty, boundary, or invalid-timezone result | Partial |
| REPORT-006 | P0 | Partial: `tst_timemath.cpp::splitsDstTransition` | native unit | fast | empty, boundary, or invalid-timezone result | Partial |
| REPORT-007 | P1 | Partial: `tst_database.qml::test_categoryTimeMergesOverlappingTaskSessions` | QML repository | fast | empty, boundary, or invalid-timezone result | Partial |
| REPORT-008 | P1 | Partial: `tst_database.qml::test_manualCorrectionContributesToReports` | QML repository | fast | empty, boundary, or invalid-timezone result | Partial |
| REPORT-010 | P1 | Partial: `tst_category_drag.qml::test_dailyTimelineStacksConcurrentTimersAndSupportsZoom` | QML interaction | fast | empty, boundary, or invalid-timezone result | Partial |
| REPORT-011 | P1 | Partial: `tst_category_drag.qml::test_dailyReportExposesDiscoverableEditorControls` | QML interaction | fast | empty, boundary, or invalid-timezone result | Partial |
| REPORT-012 | P1 | Partial: `tst_category_drag.qml::test_dailyEditorRequiresExplicitDstOffset` | QML interaction | fast | empty, boundary, or invalid-timezone result | Partial |
| REPORT-013 | P1 | Partial: `tst_category_drag.qml::test_categoryDailyReportUsesBoundedLazyPage` | QML interaction | fast | empty, boundary, or invalid-timezone result | Partial |
| REPORT-014 | P1 | Partial: `tst_category_drag.qml::test_reportTabsPreserveDailyCategoryScope` | QML interaction | fast | empty, boundary, or invalid-timezone result | Partial |
| PREF-001 | P1 | Planned: first-day-of-week preference report fixture | QML interaction | fast | malformed preference falls back to a documented default | Planned |
| PREF-002 | P1 | Planned: report-timezone preference persistence | QML interaction | fast | malformed preference falls back to a documented default | Planned |
| PREF-003 | P1 | Planned: default status-filter persistence | QML interaction | fast | malformed preference falls back to a documented default | Planned |
| PREF-004 | P1 | Planned: archived-task preference persistence | QML interaction | fast | malformed preference falls back to a documented default | Planned |
| PREF-005 | P1 | Planned: 12/24-hour format preference contract | QML interaction | fast | malformed preference falls back to a documented default | Planned |
| PREF-006 | P1 | Planned: Plasma configuration reload contract | QML interaction | fast | malformed preference falls back to a documented default | Planned |
| PLANE-001 | N/A | Planned: test-only credential adapter rejects production use | native integration | fast | rejected request, remote failure, or secret-redaction path | Planned |
| PLANE-002 | N/A | Partial: `tst_planesync.cpp::rejectsInvalidBaseUrl` | native unit | fast | rejected request, remote failure, or secret-redaction path | Partial |
| PLANE-003 | N/A | Partial: `tst_planesync.cpp::deterministicTransportCoversRequestMethods` | native integration | fast | rejected request, remote failure, or secret-redaction path | Partial |
| PLANE-004 | N/A | Planned: fake-Plane state discovery and mapping | QML integration | fast | rejected request, remote failure, or secret-redaction path | Planned |
| PLANE-005 | N/A | Partial: `test_workbench.py::test_z_plane_owner_picker_uses_cached_project_members` | Appium | release | rejected request, remote failure, or secret-redaction path | Partial |
| PLANE-006 | N/A | Partial: `tst_database.qml::test_providerBindingMappingsAndMemberCacheRemainOptional` | QML repository | fast | rejected request, remote failure, or secret-redaction path | Partial |
| PLANE-007 | N/A | Partial: `tst_database.qml::test_workbenchWorkflowStatusesAreScopedAndTerminal` | QML repository | fast | rejected request, remote failure, or secret-redaction path | Partial |
| PLANE-008 | N/A | Partial: `tst_plane_integration.qml::test_queueCreatesAndLinksRemoteWorkItem` | QML integration | fast | rejected request, remote failure, or secret-redaction path | Partial |
| PLANE-009 | N/A | Partial: `tst_plane_integration.qml::test_queueMarksConflictWhenRemoteChangedSinceBaseline` | QML integration | fast | rejected request, remote failure, or secret-redaction path | Partial |
| PLANE-010 | N/A | Partial: `tst_plane_integration.qml::test_forcePushUpdatesExistingRemoteWorkItem` | QML integration | fast | rejected request, remote failure, or secret-redaction path | Partial |
| PLANE-011 | N/A | Partial: `tst_plane_integration.qml::test_workspacePullCreatesMappedRemoteWorkItem` | QML integration | fast | rejected request, remote failure, or secret-redaction path | Partial |
| PLANE-012 | N/A | Partial: `tst_plane_integration.qml::test_workspacePullFollowsCursorUntilAllPagesAreImported` | QML integration | fast | rejected request, remote failure, or secret-redaction path | Partial |
| PLANE-013 | N/A | Partial: `tst_database.qml::test_providerTaskLinksSupportPendingCreationConflictAndLegacyFields` | QML repository | fast | rejected request, remote failure, or secret-redaction path | Partial |
| PLANE-014 | N/A | Partial: `tst_planesync.cpp::decodesFailuresWithoutLeakingLargePayloads` | native unit | fast | rejected request, remote failure, or secret-redaction path | Partial |
| PLANE-015 | N/A | Planned: disconnect clears local binding and test credential | QML integration | fast | rejected request, remote failure, or secret-redaction path | Planned |
