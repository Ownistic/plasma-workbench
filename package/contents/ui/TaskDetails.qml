import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

import "../code/Database.js" as Database
import "../code/Markdown.js" as Markdown
import "../code/Reports.js" as Reports
import "time" as WorkbenchTime

FocusScope {
    id: root

    required property var board
    property string taskId: ""
    property var task: null
    property string loadedTitle: ""
    property string loadedDescription: ""
    property string loadedCategoryId: ""
    property string loadedStatus: ""
    property bool showDescriptionPreview: false
    property bool manualSessionOpen: false
    property bool manualSessionLongConfirmed: false
    property var dailyTimelineReport: null
    property string dailyTimelineDate: ""
    property var planeLink: null
    property var planeAssigneeIds: []
    property string planeSyncMessage: ""
    readonly property bool hasUnsavedChanges: root.task && (
        titleField.text !== root.loadedTitle
        || descriptionField.text !== root.loadedDescription
        || root.selectedCategoryId() !== root.loadedCategoryId
        || statusField.currentValue !== root.loadedStatus
        || JSON.stringify(root.planeAssigneeIds) !== JSON.stringify(root.planeLink ? root.planeLink.assigneeIds : [])
    )
    readonly property bool hasManualCorrections: root.task && (
        root.task.workSessions.some(function(session) { return session.manually_edited })
        || root.task.statusEvents.some(function(event) { return event.manually_edited })
    )
    signal closeRequested()
    anchors.fill: parent
    visible: false
    focus: visible

    function selectedCategoryId() {
        return categoryField.currentIndex >= 0 && categoryField.currentIndex < root.board.categories.count
            ? root.board.categories.get(categoryField.currentIndex).id : ""
    }

    function loadTask(id) {
        root.taskId = id
        root.task = Database.getTask(id)
        root.planeLink = root.task ? Database.getTaskExternalLink(id) : null
        root.planeAssigneeIds = root.planeLink ? root.planeLink.assigneeIds.slice() : []
        if (!root.task) {
            root.visible = false
            return
        }
        titleField.text = root.task.title
        descriptionField.text = root.task.details
        root.loadedTitle = root.task.title
        root.loadedDescription = root.task.details
        root.loadedCategoryId = root.task.category_id
        root.loadedStatus = root.task.status
        root.refreshDailyTimeline()
        showDescriptionPreview = false
        statusField.currentIndex = statusField.indexOfValue(root.task.status)
        categoryField.currentIndex = -1
        for (let index = 0; index < root.board.categories.count; index += 1) {
            if (root.board.categories.get(index).id === root.task.category_id) {
                categoryField.currentIndex = index
                break
            }
        }
        root.visible = true
        root.forceActiveFocus()
    }

    // Keep the current board integration working while it migrates to loadTask().
    function openForTask(id) {
        root.loadTask(id)
    }

    function requestClose() {
        if (typeof root.board.requestTaskDetailsClose === "function") {
            root.board.requestTaskDetailsClose()
        } else {
            root.closeRequested()
            root.visible = false
        }
    }

    function saveTask() {
        if (!root.task) {
            return
        }
        const categoryId = root.board.categories.get(categoryField.currentIndex).id
        Database.saveTask({
            id: root.taskId,
            title: titleField.text,
            details: descriptionField.text,
            categoryId: categoryId,
            status: statusField.currentValue
        })
        root.task = Database.getTask(root.taskId)
        root.planeLink = Database.getTaskExternalLink(root.taskId)
        root.loadedTitle = root.task.title
        root.loadedDescription = root.task.details
        root.loadedCategoryId = root.task.category_id
        root.loadedStatus = root.task.status
        root.board.reload()
        root.board.syncPlaneTask(root.taskId, root.planeAssigneeIds)
    }

    function refreshTask() {
        root.task = Database.getTask(root.taskId)
        root.planeLink = root.task ? Database.getTaskExternalLink(root.taskId) : null
        root.board.reload()
        root.refreshDailyTimeline()
    }

    function planeMembers() {
        return root.planeLink && root.planeLink.projectId
            ? Database.listProviderMembers(root.board.selectedWorkspaceId, "plane", root.planeLink.projectId) : []
    }

    function setPlaneAssignee(memberId, enabled) {
        const next = root.planeAssigneeIds.slice()
        const index = next.indexOf(memberId)
        if (enabled && index === -1) next.push(memberId)
        if (!enabled && index !== -1) next.splice(index, 1)
        root.planeAssigneeIds = next
    }

    function refreshDailyTimeline() {
        if (!root.task) {
            root.dailyTimelineReport = null
            return
        }
        const local = WorkbenchTime.TimeMath.localPartsForUtc(new Date().toISOString(), root.board.reportTimezone)
        if (!local.valid) {
            root.dailyTimelineReport = null
            return
        }
        root.dailyTimelineDate = local.date
        const pieces = root.dailyTimelineDate.split("-")
        root.dailyTimelineReport = Reports.dailyReport(WorkbenchTime.TimeMath, {
            year: Number(pieces[0]), month: Number(pieces[1]), day: Number(pieces[2]),
            timezoneId: root.board.reportTimezone, firstDayOfWeek: root.board.firstDayOfWeek,
            currentUtc: new Date().toISOString()
        })
        root.dailyTimelineReport.sessionSegments = root.dailyTimelineReport.sessionSegments.filter(function(segment) {
            return segment.taskId === root.taskId
        })
    }

    function saveTimelineSession(startUtc, endUtc) {
        try {
            Database.createWorkSession({ taskId: root.taskId, startedAtUtc: startUtc,
                endedAtUtc: endUtc, timezoneId: root.board.reportTimezone })
            root.refreshTask()
        } catch (error) {
            correctionError.text = error.message
        }
    }

    function saveTimelineEdit(segment, startUtc, endUtc) {
        try {
            Database.updateWorkSession({ id: segment.sessionId, startedAtUtc: startUtc,
                endedAtUtc: endUtc, timezoneId: root.board.reportTimezone })
            root.refreshTask()
        } catch (error) {
            correctionError.text = error.message
        }
    }

    function openWorkSessionEditor(session) {
        longSessionConfirmation.inlineSession = false
        workSessionEditor.session = session
        workSessionEditor.title = session ? i18n("Edit work session") : i18n("Add work session")
        workSessionEditor.timezoneId = session ? session.timezone_id : root.board.reportTimezone
        const start = session ? WorkbenchTime.TimeMath.localPartsForUtc(session.started_at_utc, workSessionEditor.timezoneId) : null
        const end = session && session.ended_at_utc
            ? WorkbenchTime.TimeMath.localPartsForUtc(session.ended_at_utc, workSessionEditor.timezoneId) : null
        workSessionDateField.text = start && start.valid ? start.date : ""
        workSessionEndDateField.text = end && end.valid ? end.date : workSessionDateField.text
        workSessionStartField.text = start && start.valid ? localTimeText(start) : ""
        workSessionEndField.text = end && end.valid ? localTimeText(end) : ""
        workSessionStartOffset.model = []
        workSessionEndOffset.model = []
        workSessionError.text = ""
        workSessionEditor.open()
    }

    function openManualSessionForm() {
        longSessionConfirmation.inlineSession = false
        const now = WorkbenchTime.TimeMath.localPartsForUtc(new Date().toISOString(), root.board.reportTimezone)
        manualSessionStartField.text = now.valid ? now.date + " " + twoDigits(now.hour) + ":" + twoDigits(now.minute) : ""
        manualSessionDurationField.text = "01:00"
        manualSessionStartOffset.model = []
        manualSessionError.text = ""
        manualSessionLongConfirmed = false
        manualSessionOpen = true
        refreshManualSessionChoices()
        manualSessionStartField.forceActiveFocus()
    }

    function twoDigits(value) {
        return value < 10 ? "0" + value : String(value)
    }

    function threeDigits(value) {
        return value < 10 ? "00" + value : value < 100 ? "0" + value : String(value)
    }

    function localTimeText(parts) {
        return twoDigits(parts.hour) + ":" + twoDigits(parts.minute) + ":" + twoDigits(parts.second)
            + "." + threeDigits(parts.millisecond)
    }

    function validUtcInstant(value) {
        if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value)) {
            return false
        }
        const date = new Date(value)
        return !isNaN(date.getTime()) && date.toISOString() === value
    }

    function localDateTimeCandidates(dateText, timeText) {
        const date = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateText)
        const time = /^(\d{1,2}):(\d{2})(?::(\d{2})(?:\.(\d{1,3}))?)?$/.exec(timeText)
        if (!date || !time) {
            return { valid: false, error: i18n("Use a date in YYYY-MM-DD and a time in HH:MM format.") }
        }
        return WorkbenchTime.TimeMath.possibleUtcInstantsForLocal(
            Number(date[1]), Number(date[2]), Number(date[3]), Number(time[1]), Number(time[2]),
            time[3] === undefined ? 0 : Number(time[3]),
            time[4] === undefined ? 0 : Number((time[4] + "000").slice(0, 3)),
            workSessionEditor.timezoneId
        )
    }

    function offsetChoices(candidates) {
        return candidates.utcInstants.map(function(utc) {
            const parts = WorkbenchTime.TimeMath.localPartsForUtc(utc, workSessionEditor.timezoneId)
            const offset = Number(parts.offsetSeconds)
            const sign = offset < 0 ? "-" : "+"
            const absoluteOffset = Math.abs(offset)
            return {
                value: utc,
                label: i18n("UTC%1%2:%3 (%4)", sign, twoDigits(Math.floor(absoluteOffset / 3600)),
                    twoDigits(Math.floor((absoluteOffset % 3600) / 60)), parts.timeZoneAbbreviation)
            }
        })
    }

    function manualStartCandidates() {
        const match = /^(\d{4})-(\d{2})-(\d{2})\s+(\d{1,2}):(\d{2})$/.exec(manualSessionStartField.text)
        if (!match) {
            return { valid: false, error: i18n("Use a start date and time in YYYY-MM-DD HH:MM format.") }
        }
        return WorkbenchTime.TimeMath.possibleUtcInstantsForLocal(
            Number(match[1]), Number(match[2]), Number(match[3]), Number(match[4]), Number(match[5]), 0, 0,
            root.board.reportTimezone
        )
    }

    function manualOffsetChoices(candidates) {
        return candidates.utcInstants.map(function(utc) {
            const parts = WorkbenchTime.TimeMath.localPartsForUtc(utc, root.board.reportTimezone)
            const offset = Number(parts.offsetSeconds)
            const sign = offset < 0 ? "-" : "+"
            const absoluteOffset = Math.abs(offset)
            return {
                value: utc,
                label: i18n("UTC%1%2:%3 (%4)", sign, twoDigits(Math.floor(absoluteOffset / 3600)),
                    twoDigits(Math.floor((absoluteOffset % 3600) / 60)), parts.timeZoneAbbreviation)
            }
        })
    }

    function refreshManualSessionChoices() {
        const candidates = manualStartCandidates()
        manualSessionStartOffset.model = candidates.valid ? manualOffsetChoices(candidates) : []
        manualSessionStartOffset.currentIndex = candidates.valid && candidates.utcInstants.length === 1 ? 0 : -1
    }

    function manualDurationSeconds() {
        const match = /^(\d{1,3}):(\d{2})$/.exec(manualSessionDurationField.text)
        if (!match || Number(match[2]) >= 60) {
            fail(i18n("Use a duration in hours and minutes, for example 01:30."))
        }
        const seconds = (Number(match[1]) * 60 + Number(match[2])) * 60
        if (seconds <= 0) {
            fail(i18n("The duration must be greater than zero."))
        }
        return seconds
    }

    function saveInlineManualSession() {
        const candidates = manualStartCandidates()
        const startedAtUtc = selectedUtc(candidates, manualSessionStartOffset, i18n("start"))
        const durationSeconds = manualDurationSeconds()
        if (!manualSessionLongConfirmed && durationSeconds / 3600 >= root.board.unusualSessionHours) {
            longSessionConfirmation.durationText = root.board.formatSeconds(durationSeconds)
            longSessionConfirmation.inlineSession = true
            longSessionConfirmation.open()
            return
        }
        Database.createWorkSession({
            taskId: root.taskId,
            startedAtUtc: startedAtUtc,
            endedAtUtc: new Date(Date.parse(startedAtUtc) + durationSeconds * 1000).toISOString(),
            timezoneId: root.board.reportTimezone
        })
        manualSessionOpen = false
        root.refreshTask()
    }

    function attemptInlineManualSessionSave() {
        try {
            root.saveInlineManualSession()
        } catch (error) {
            manualSessionError.text = error.message
        }
    }

    function refreshOffsetChoices() {
        const start = localDateTimeCandidates(workSessionDateField.text, workSessionStartField.text)
        const end = localDateTimeCandidates(workSessionEndDateField.text, workSessionEndField.text)
        workSessionStartOffset.model = start.valid ? offsetChoices(start) : []
        workSessionEndOffset.model = end.valid ? offsetChoices(end) : []
        workSessionStartOffset.currentIndex = start.valid && start.utcInstants.length === 1 ? 0 : -1
        workSessionEndOffset.currentIndex = end.valid && end.utcInstants.length === 1 ? 0 : -1
    }

    function selectedUtc(candidates, selector, label) {
        if (!candidates.valid) {
            fail(candidates.error)
        }
        if (candidates.utcInstants.length > 1 && selector.currentIndex < 0) {
            fail(i18n("Choose the UTC offset for the ambiguous %1 time.", label))
        }
        return candidates.utcInstants.length === 1 ? candidates.utcInstants[0] : selector.currentValue
    }

    function fail(message) {
        throw new Error(message)
    }

    function saveWorkSession() {
        const startCandidates = localDateTimeCandidates(workSessionDateField.text, workSessionStartField.text)
        const endCandidates = localDateTimeCandidates(workSessionEndDateField.text, workSessionEndField.text)
        const startedAtUtc = selectedUtc(startCandidates, workSessionStartOffset, i18n("start"))
        const endedAtUtc = selectedUtc(endCandidates, workSessionEndOffset, i18n("end"))
        if (Date.parse(endedAtUtc) < Date.parse(startedAtUtc)) {
            fail(i18n("The end time cannot be before the start time."))
        }
        const durationHours = (Date.parse(endedAtUtc) - Date.parse(startedAtUtc)) / (60 * 60 * 1000)
        if (!workSessionEditor.longSessionConfirmed && durationHours >= root.board.unusualSessionHours) {
            longSessionConfirmation.durationText = root.board.formatSeconds(durationHours * 3600)
            longSessionConfirmation.open()
            return
        }
        if (workSessionEditor.session) {
            Database.updateWorkSession({
                id: workSessionEditor.session.id,
                startedAtUtc: startedAtUtc,
                endedAtUtc: endedAtUtc,
                timezoneId: workSessionEditor.timezoneId
            })
        } else {
            Database.createWorkSession({
                taskId: root.taskId,
                startedAtUtc: startedAtUtc,
                endedAtUtc: endedAtUtc,
                timezoneId: workSessionEditor.timezoneId
            })
        }
        root.refreshTask()
        workSessionEditor.close()
    }

    function attemptWorkSessionSave() {
        try {
            root.saveWorkSession()
        } catch (error) {
            workSessionError.text = error.message
        }
    }

    function attemptStatusEventSave() {
        if (!root.validUtcInstant(statusEventTimeField.text)) {
            statusEventError.text = i18n("The event time must be a valid UTC ISO timestamp.")
            return
        }
        try {
            Database.updateStatusEvent({
                id: statusEventEditor.event.id,
                status: statusEventField.currentValue,
                occurredAtUtc: statusEventTimeField.text
            })
            root.refreshTask()
            statusEventEditor.close()
        } catch (error) {
            statusEventError.text = error.message
        }
    }

    function openStatusEventEditor(event) {
        statusEventEditor.event = event
        statusEventField.currentIndex = statusEventField.indexOfValue(event.status)
        statusEventTimeField.text = event.occurred_at_utc
        statusEventError.text = ""
        statusEventEditor.open()
    }

    function confirmCorrectionDeletion(kind, id, label) {
        correctionDeletion.kind = kind
        correctionDeletion.itemId = id
        correctionDeletion.itemLabel = label
        correctionDeletion.open()
    }

    Rectangle {
        id: pageHeader
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: headerLayout.implicitHeight + Kirigami.Units.largeSpacing * 2
        color: Kirigami.Theme.backgroundColor

        RowLayout {
            id: headerLayout
            anchors.fill: parent
            anchors.leftMargin: Kirigami.Units.largeSpacing
            anchors.rightMargin: Kirigami.Units.largeSpacing
            anchors.topMargin: Kirigami.Units.largeSpacing
            anchors.bottomMargin: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            PlasmaComponents.Button {
                text: i18n("Back")
                onClicked: root.requestClose()
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 3
                    text: root.task ? root.task.title : i18n("Task details")
                    elide: Text.ElideRight
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: root.task ? i18n("Status: %1", root.board.statusLabel(statusField.currentValue)) : ""
                    color: Kirigami.Theme.disabledTextColor
                }

                Repeater {
                    model: root.planeMembers()

                    delegate: PlasmaComponents.CheckBox {
                        required property var modelData
                        Layout.fillWidth: true
                        text: modelData.memberName || modelData.memberEmail || modelData.memberId
                        checked: root.planeAssigneeIds.indexOf(modelData.memberId) !== -1
                        Accessible.name: i18n("Assign Plane task to %1", text)
                        onToggled: root.setPlaneAssignee(modelData.memberId, checked)
                    }
                }
            }
        }
    }

    Controls.ScrollView {
        id: detailsScroll
        anchors.top: pageHeader.bottom
        anchors.bottom: pageActions.top
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true
        leftPadding: Kirigami.Units.largeSpacing
        // Plasma renders scrollbars as an overlay, so reserve its width rather
        // than allowing fields and controls to disappear beneath it.
        rightPadding: Kirigami.Units.largeSpacing + Kirigami.Units.iconSizes.small
        topPadding: Kirigami.Units.largeSpacing
        bottomPadding: Kirigami.Units.largeSpacing
        contentWidth: availableWidth

        ColumnLayout {
            width: detailsScroll.availableWidth
            spacing: Kirigami.Units.largeSpacing

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: i18n("Title")
                color: Kirigami.Theme.disabledTextColor
            }

            PlasmaComponents.TextField {
                id: titleField
                Layout.fillWidth: true
                placeholderText: i18n("Give this task a clear, actionable name")
                Accessible.name: i18n("Task title")
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents.Label {
                        text: i18n("Category")
                        color: Kirigami.Theme.disabledTextColor
                    }

                    PlasmaComponents.ComboBox {
                        id: categoryField
                        Layout.fillWidth: true
                        model: root.board.categories
                        textRole: "name"
                        Accessible.name: i18n("Task category")
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents.Label {
                        text: i18n("Status")
                        color: Kirigami.Theme.disabledTextColor
                    }

                    PlasmaComponents.ComboBox {
                        id: statusField
                        Layout.fillWidth: true
                        model: root.board.workflowStatuses
                        textRole: "name"
                        valueRole: "id"
                        Accessible.name: i18n("Task status")
                    }
                }
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: i18n("Description")
                color: Kirigami.Theme.disabledTextColor
            }

            PlasmaComponents.TextArea {
                id: descriptionField
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 9
                placeholderText: i18n("Add context, notes, or Markdown")
                Accessible.name: i18n("Task description")
                wrapMode: TextEdit.Wrap
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: root.planeLink !== null
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 4
                    text: i18n("Plane")
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: root.planeLink ? i18n("%1 · %2", root.planeLink.remoteKey || i18n("New Plane item"),
                        root.planeLink.syncState.replace("_", " ")) : ""
                    color: root.planeLink && (root.planeLink.syncState === "conflict" || root.planeLink.syncState === "error")
                        ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.disabledTextColor
                    wrapMode: Text.Wrap
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    visible: root.planeLink && root.planeLink.syncError
                    text: root.planeLink ? root.planeLink.syncError : ""
                    color: Kirigami.Theme.negativeTextColor
                    wrapMode: Text.Wrap
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    visible: root.planeSyncMessage.length > 0
                    text: root.planeSyncMessage
                    color: Kirigami.Theme.disabledTextColor
                    wrapMode: Text.Wrap
                }

                RowLayout {
                    Layout.fillWidth: true

                    PlasmaComponents.Button {
                        text: i18n("Open in Plane")
                        visible: root.planeLink && root.planeLink.remoteUrl.length > 0
                        onClicked: Qt.openUrlExternally(root.planeLink.remoteUrl)
                    }

                    PlasmaComponents.Button {
                        text: i18n("Refresh from Plane")
                        enabled: root.planeLink && root.planeLink.remoteId.length > 0 && root.planeLink.syncState === "in_sync"
                        onClicked: root.board.planeIntegration.refreshTask(root.taskId, root.board.selectedWorkspaceId)
                    }

                    PlasmaComponents.Button {
                        text: root.planeLink && root.planeLink.syncState === "conflict"
                            ? i18n("Push my local changes") : i18n("Retry Plane sync")
                        enabled: root.planeLink && root.planeLink.syncState !== "in_sync"
                        onClicked: {
                            if (root.planeLink.syncState === "conflict") {
                                planeForcePushConfirmation.open()
                            } else {
                                root.board.syncPlaneTask(root.taskId, root.planeLink.assigneeIds)
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: i18n("Markdown is supported")
                    color: Kirigami.Theme.disabledTextColor
                }

                PlasmaComponents.Button {
                    text: root.showDescriptionPreview ? i18n("Edit description") : i18n("Preview")
                    checkable: true
                    checked: root.showDescriptionPreview
                    onClicked: root.showDescriptionPreview = checked
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.showDescriptionPreview
                text: Markdown.localOnly(descriptionField.text)
                textFormat: Text.MarkdownText
                wrapMode: Text.Wrap
                color: Kirigami.Theme.textColor
                onLinkActivated: function(link) {}
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Kirigami.Theme.disabledTextColor
                opacity: 0.35
            }

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: root.task ? i18n("Tracked time: %1", root.board.taskElapsedText(root.task)) : ""
                }

                PlasmaComponents.Button {
                    text: root.task && root.board.isTaskActive(root.taskId)
                        ? i18n("Pause") : i18n("Start")
                    onClicked: {
                        root.board.toggleTimer({ taskId: root.taskId })
                        root.task = Database.getTask(root.taskId)
                    }
                }
            }

            Kirigami.Heading {
                Layout.fillWidth: true
                level: 4
                text: i18n("Work sessions")
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: i18n("Report timezone: %1", root.board.reportTimezone)
                wrapMode: Text.Wrap
            }

            Loader {
                id: taskDailyTimelineLoader
                objectName: "task-daily-timeline-loader"
                Layout.fillWidth: true
                Layout.preferredHeight: item ? item.implicitHeight : 0
                active: root.visible && root.dailyTimelineReport !== null
                sourceComponent: Component {
                    DailyTimeline {
                        objectName: "task-daily-timeline"
                        report: root.dailyTimelineReport
                        localDate: root.dailyTimelineDate
                        timezoneId: root.board.reportTimezone
                        formatSeconds: root.board.formatSeconds
                        onSessionCreateRequested: function(startUtc, endUtc) {
                            root.saveTimelineSession(startUtc, endUtc)
                        }
                        onSessionEditRequested: function(segment, startUtc, endUtc) {
                            root.saveTimelineEdit(segment, startUtc, endUtc)
                        }
                        onSessionSelected: function(segment) {
                            const session = root.task.workSessions.find(function(candidate) {
                                return candidate.id === segment.sessionId
                            })
                            if (session) {
                                root.openWorkSessionEditor(session)
                            }
                        }
                    }
                }
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                visible: root.hasManualCorrections
                text: i18n("Manual corrections are present for this task.")
                color: Kirigami.Theme.positiveTextColor
                wrapMode: Text.Wrap
                Accessible.name: text
            }

            PlasmaComponents.Button {
                Layout.alignment: Qt.AlignLeft
                text: root.manualSessionOpen ? i18n("Cancel adding session") : i18n("Add work session")
                Accessible.name: text
                onClicked: {
                    if (root.manualSessionOpen) {
                        root.manualSessionOpen = false
                    } else {
                        root.openManualSessionForm()
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: root.manualSessionOpen
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: i18n("Start date and time")
                    color: Kirigami.Theme.disabledTextColor
                }

                PlasmaComponents.TextField {
                    id: manualSessionStartField
                    Layout.fillWidth: true
                    placeholderText: i18n("YYYY-MM-DD HH:MM")
                    Accessible.name: i18n("Work session start date and time")
                    onEditingFinished: root.refreshManualSessionChoices()
                }

                PlasmaComponents.ComboBox {
                    id: manualSessionStartOffset
                    Layout.fillWidth: true
                    visible: count > 1
                    textRole: "label"
                    valueRole: "value"
                    Accessible.name: i18n("Start-time UTC offset")
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: i18n("Duration")
                    color: Kirigami.Theme.disabledTextColor
                }

                RowLayout {
                    Layout.fillWidth: true

                    PlasmaComponents.TextField {
                        id: manualSessionDurationField
                        Layout.fillWidth: true
                        placeholderText: i18n("HH:MM")
                        Accessible.name: i18n("Work session duration in hours and minutes")
                    }

                    PlasmaComponents.Button {
                        text: i18n("Add session")
                        highlighted: true
                        onClicked: root.attemptInlineManualSessionSave()
                    }
                }

                PlasmaComponents.Label {
                    id: manualSessionError
                    Layout.fillWidth: true
                    visible: text.length > 0
                    color: Kirigami.Theme.negativeTextColor
                    wrapMode: Text.Wrap
                    Accessible.name: text
                }
            }

            Repeater {
                model: root.task ? root.task.workSessions : []

                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: root.board.formatTimestamp(modelData.started_at_utc) + (modelData.ended_at_utc
                    ? " - " + root.board.formatTimestamp(modelData.ended_at_utc) : i18n(" (active)"))
                            + (modelData.manually_edited ? i18n(" (corrected)") : "")
                        wrapMode: Text.Wrap
                    }

                    PlasmaComponents.Button {
                        text: i18n("Edit")
                        Accessible.name: i18n("Edit work session starting %1", root.board.formatTimestamp(modelData.started_at_utc))
                        onClicked: root.openWorkSessionEditor(modelData)
                    }

                    PlasmaComponents.Button {
                        text: i18n("Delete")
                        Accessible.name: i18n("Delete work session starting %1", root.board.formatTimestamp(modelData.started_at_utc))
                        onClicked: root.confirmCorrectionDeletion("workSession", modelData.id,
                            i18n("work session starting %1", root.board.formatTimestamp(modelData.started_at_utc)))
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Kirigami.Theme.disabledTextColor
                opacity: 0.35
            }

            Kirigami.Heading {
                Layout.fillWidth: true
                level: 4
                text: i18n("Status history")
            }

            Repeater {
                model: root.task ? root.task.statusEvents : []

                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: root.board.formatTimestamp(modelData.occurred_at_utc) + ": " + root.board.statusLabel(modelData.status)
                            + (modelData.manually_edited ? i18n(" (corrected)") : "")
                        wrapMode: Text.Wrap
                    }

                    PlasmaComponents.Button {
                        text: i18n("Edit")
                        Accessible.name: i18n("Edit status event at %1", root.board.formatTimestamp(modelData.occurred_at_utc))
                        onClicked: root.openStatusEventEditor(modelData)
                    }

                    PlasmaComponents.Button {
                        text: i18n("Delete")
                        Accessible.name: i18n("Delete status event at %1", root.board.formatTimestamp(modelData.occurred_at_utc))
                        onClicked: root.confirmCorrectionDeletion("statusEvent", modelData.id,
                            i18n("status event at %1", root.board.formatTimestamp(modelData.occurred_at_utc)))
                    }
                }
            }

            PlasmaComponents.Label {
                id: correctionError
                Layout.fillWidth: true
                visible: text.length > 0
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.Wrap
                Accessible.name: text
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Kirigami.Theme.disabledTextColor
                opacity: 0.35
            }

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.Button {
                    text: i18n("Archive task")
                    onClicked: {
                        Database.archiveTask(root.taskId)
                        root.board.reload()
                        root.requestClose()
                    }
                }

                Item { Layout.fillWidth: true }

                PlasmaComponents.Button {
                    text: i18n("Delete task")
                    onClicked: deleteConfirmation.open()
                }
            }
        }
    }

    Rectangle {
        id: pageActions
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        implicitHeight: actionLayout.implicitHeight + Kirigami.Units.largeSpacing * 2
        color: Kirigami.Theme.backgroundColor

        RowLayout {
            id: actionLayout
            anchors.fill: parent
            anchors.leftMargin: Kirigami.Units.largeSpacing
            anchors.rightMargin: Kirigami.Units.largeSpacing
            anchors.topMargin: Kirigami.Units.largeSpacing
            anchors.bottomMargin: Kirigami.Units.largeSpacing

            PlasmaComponents.Button {
                text: i18n("Close")
                onClicked: root.requestClose()
            }

            Item { Layout.fillWidth: true }

            PlasmaComponents.Button {
                text: i18n("Save changes")
                highlighted: true
                enabled: root.hasUnsavedChanges
                Accessible.name: i18n("Save task changes")
                onClicked: root.saveTask()
            }
        }
    }

    Item {
        id: popupHost
        anchors.fill: parent
    }

    Controls.Dialog {
        id: planeForcePushConfirmation
        parent: popupHost
        modal: true
        title: i18n("Overwrite Plane?")
        standardButtons: Controls.Dialog.Cancel | Controls.Dialog.Yes
        onAccepted: root.board.forcePushPlaneTask(root.taskId)
        contentItem: PlasmaComponents.Label {
            width: Kirigami.Units.gridUnit * 24
            wrapMode: Text.Wrap
            text: i18n("This replaces Plane’s managed task fields with your local title, description, status, and assignees.")
        }
    }

    Controls.Dialog {
        id: correctionDeletion
        parent: popupHost
        modal: true
        property string kind: ""
        property string itemId: ""
        property string itemLabel: ""
        title: i18n("Delete correction?")
        standardButtons: Controls.Dialog.Cancel | Controls.Dialog.Yes
        contentItem: PlasmaComponents.Label {
            width: Kirigami.Units.gridUnit * 24
            wrapMode: Text.Wrap
            text: i18n("Delete %1 permanently?", correctionDeletion.itemLabel)
            Accessible.name: text
        }
        onAccepted: {
            try {
                if (kind === "workSession") {
                    Database.deleteWorkSession(itemId)
                } else {
                    Database.deleteStatusEvent(itemId)
                }
                root.refreshTask()
            } catch (error) {
                correctionError.text = error.message
            }
        }
    }

    Controls.Dialog {
        id: workSessionEditor
        parent: popupHost
        modal: true
        property var session: null
        property string timezoneId: ""
        property bool longSessionConfirmed: false
        onOpened: {
            longSessionConfirmed = false
            root.refreshOffsetChoices()
        }
        contentItem: ColumnLayout {
            width: Kirigami.Units.gridUnit * 28
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: i18n("Enter local date and times in %1.", workSessionEditor.timezoneId)
                wrapMode: Text.Wrap
            }

            PlasmaComponents.TextField {
                id: workSessionDateField
                Layout.fillWidth: true
                placeholderText: i18n("Date (YYYY-MM-DD)")
                Accessible.name: i18n("Work session local date")
                onEditingFinished: root.refreshOffsetChoices()
            }

            PlasmaComponents.TextField {
                id: workSessionStartField
                Layout.fillWidth: true
                placeholderText: i18n("Start time (HH:MM[:SS.mmm])")
                Accessible.name: i18n("Work session local start time")
                onEditingFinished: root.refreshOffsetChoices()
            }

            PlasmaComponents.ComboBox {
                id: workSessionStartOffset
                Layout.fillWidth: true
                visible: count > 1
                textRole: "label"
                valueRole: "value"
                Accessible.name: i18n("Start-time UTC offset")
            }

            PlasmaComponents.TextField {
                id: workSessionEndField
                Layout.fillWidth: true
                placeholderText: i18n("End time (HH:MM[:SS.mmm])")
                Accessible.name: i18n("Work session local end time")
                onEditingFinished: root.refreshOffsetChoices()
            }

            PlasmaComponents.TextField {
                id: workSessionEndDateField
                Layout.fillWidth: true
                placeholderText: i18n("End date (YYYY-MM-DD)")
                Accessible.name: i18n("Work session local end date")
                onEditingFinished: root.refreshOffsetChoices()
            }

            PlasmaComponents.ComboBox {
                id: workSessionEndOffset
                Layout.fillWidth: true
                visible: count > 1
                textRole: "label"
                valueRole: "value"
                Accessible.name: i18n("End-time UTC offset")
            }

            PlasmaComponents.Label {
                id: workSessionError
                Layout.fillWidth: true
                visible: text.length > 0
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.Wrap
                Accessible.name: text
            }
        }
        footer: Controls.DialogButtonBox {
            Controls.Button {
                text: i18n("Cancel")
                onClicked: workSessionEditor.close()
            }
            Controls.Button {
                text: i18n("Save")
                onClicked: root.attemptWorkSessionSave()
            }
        }
    }

    Controls.Dialog {
        id: longSessionConfirmation
        parent: popupHost
        modal: true
        property string durationText: ""
        property bool inlineSession: false
        title: i18n("Unusually long work session")
        standardButtons: Controls.Dialog.Cancel | Controls.Dialog.Yes
        contentItem: PlasmaComponents.Label {
            width: Kirigami.Units.gridUnit * 24
            wrapMode: Text.Wrap
            text: i18n("This session lasts %1, exceeding the %2-hour warning threshold. Save it anyway?",
                longSessionConfirmation.durationText, root.board.unusualSessionHours)
        }
        onAccepted: {
            try {
                if (inlineSession) {
                    root.manualSessionLongConfirmed = true
                    root.saveInlineManualSession()
                } else {
                    workSessionEditor.longSessionConfirmed = true
                    root.saveWorkSession()
                }
            } catch (error) {
                if (inlineSession) {
                    manualSessionError.text = error.message
                } else {
                    workSessionError.text = error.message
                    workSessionEditor.open()
                }
            }
        }
    }

    Controls.Dialog {
        id: statusEventEditor
        parent: popupHost
        modal: true
        property var event: null
        title: i18n("Edit status event")
        contentItem: ColumnLayout {
            width: Kirigami.Units.gridUnit * 28
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.ComboBox {
                id: statusEventField
                Layout.fillWidth: true
                model: root.board.workflowStatuses
                textRole: "name"
                valueRole: "id"
                Accessible.name: i18n("Status event status")
            }

            PlasmaComponents.TextField {
                id: statusEventTimeField
                Layout.fillWidth: true
                placeholderText: i18n("Event time (UTC ISO)")
                Accessible.name: i18n("Status event time in UTC ISO format")
            }

            PlasmaComponents.Label {
                id: statusEventError
                Layout.fillWidth: true
                visible: text.length > 0
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.Wrap
                Accessible.name: text
            }
        }
        footer: Controls.DialogButtonBox {
            Controls.Button {
                text: i18n("Cancel")
                onClicked: statusEventEditor.close()
            }
            Controls.Button {
                text: i18n("Save")
                onClicked: root.attemptStatusEventSave()
            }
        }
    }

    Controls.Dialog {
        id: deleteConfirmation
        parent: popupHost
        modal: true
        title: i18n("Delete task?")
        standardButtons: Controls.Dialog.Cancel | Controls.Dialog.Yes
        contentItem: PlasmaComponents.Label {
            width: Kirigami.Units.gridUnit * 24
            wrapMode: Text.Wrap
            text: i18n("Deleting this task also permanently deletes its work-session and status history.")
        }
        onAccepted: {
            Database.deleteTask(root.taskId)
            root.board.reload()
            root.requestClose()
        }
    }
}
