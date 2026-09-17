import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

import "time" as WorkbenchTime

Controls.Frame {
    id: root
    objectName: "daily-session-editor"

    required property string timezoneId
    required property var formatSeconds
    property string originalStartUtc: ""
    property string originalEndUtc: ""
    property bool editing: false
    property string taskTitle: ""
    property bool longConfirmationRequired: false
    property var startOffsetChoices: []
    property var endOffsetChoices: []
    property alias errorText: editorError.text

    signal saveRequested(string startUtc, string endUtc)
    signal cancelRequested()
    signal draftChanged()

    function twoDigits(value) {
        return value < 10 ? "0" + value : String(value)
    }

    function threeDigits(value) {
        return value < 10 ? "00" + value : value < 100 ? "0" + value : String(value)
    }

    function load(startUtc, endUtc, isEditing, title) {
        const start = WorkbenchTime.TimeMath.localPartsForUtc(startUtc, root.timezoneId)
        const end = WorkbenchTime.TimeMath.localPartsForUtc(endUtc, root.timezoneId)
        if (!start.valid || !end.valid) {
            editorError.text = i18n("The session time could not be displayed in %1.", root.timezoneId)
            return false
        }
        root.originalStartUtc = startUtc
        root.originalEndUtc = endUtc
        root.editing = isEditing
        root.taskTitle = title
        startDateField.text = start.date
        endDateField.text = end.date
        startTimeField.text = root.twoDigits(start.hour) + ":" + root.twoDigits(start.minute) + ":"
            + root.twoDigits(start.second) + "." + root.threeDigits(start.millisecond)
        endTimeField.text = root.twoDigits(end.hour) + ":" + root.twoDigits(end.minute) + ":"
            + root.twoDigits(end.second) + "." + root.threeDigits(end.millisecond)
        editorError.text = ""
        root.refreshOffsetChoices()
        return true
    }

    function focusFirstField() {
        startTimeField.forceActiveFocus()
        startTimeField.selectAll()
    }

    function candidates(dateText, timeText) {
        const date = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateText)
        const time = /^(\d{1,2}):(\d{2})(?::(\d{2})(?:\.(\d{1,3}))?)?$/.exec(timeText)
        if (!date || !time) {
            return { valid: false, error: i18n("Use YYYY-MM-DD for dates and HH:MM or HH:MM:SS for times.") }
        }
        return WorkbenchTime.TimeMath.possibleUtcInstantsForLocal(
            Number(date[1]), Number(date[2]), Number(date[3]), Number(time[1]), Number(time[2]),
            time[3] === undefined ? 0 : Number(time[3]),
            time[4] === undefined ? 0 : Number((time[4] + "000").slice(0, 3)), root.timezoneId)
    }

    function offsetChoices(candidatesResult) {
        return candidatesResult.utcInstants.map(function(utc) {
            const parts = WorkbenchTime.TimeMath.localPartsForUtc(utc, root.timezoneId)
            const offset = Number(parts.offsetSeconds)
            const sign = offset < 0 ? "-" : "+"
            const absolute = Math.abs(offset)
            return {
                value: utc,
                label: i18n("UTC%1%2:%3 (%4)", sign, root.twoDigits(Math.floor(absolute / 3600)),
                    root.twoDigits(Math.floor((absolute % 3600) / 60)), parts.timeZoneAbbreviation)
            }
        })
    }

    function choiceIndex(choices, originalUtc) {
        for (let index = 0; index < choices.length; index += 1) {
            if (choices[index].value === originalUtc) {
                return index
            }
        }
        return choices.length === 1 ? 0 : -1
    }

    function refreshOffsetChoices() {
        const start = root.candidates(startDateField.text, startTimeField.text)
        const end = root.candidates(endDateField.text, endTimeField.text)
        root.startOffsetChoices = start.valid ? root.offsetChoices(start) : []
        root.endOffsetChoices = end.valid ? root.offsetChoices(end) : []
        startOffsetSelector.currentIndex = root.choiceIndex(root.startOffsetChoices, root.originalStartUtc)
        endOffsetSelector.currentIndex = root.choiceIndex(root.endOffsetChoices, root.originalEndUtc)
    }

    function markChanged() {
        editorError.text = ""
        root.refreshOffsetChoices()
        root.draftChanged()
    }

    function offsetChanged() {
        editorError.text = ""
        root.draftChanged()
    }

    function resolvedUtc(candidatesResult, selector, label) {
        if (!candidatesResult.valid || candidatesResult.utcInstants.length === 0) {
            throw new Error(candidatesResult.error || i18n("The %1 time does not exist in %2.", label, root.timezoneId))
        }
        if (candidatesResult.utcInstants.length === 1) {
            return candidatesResult.utcInstants[0]
        }
        if (selector.currentIndex < 0) {
            throw new Error(i18n("Choose the UTC offset for the ambiguous %1 time.", label))
        }
        return selector.currentValue
    }

    function submit() {
        try {
            const startUtc = root.resolvedUtc(root.candidates(startDateField.text, startTimeField.text),
                startOffsetSelector, i18n("start"))
            const endUtc = root.resolvedUtc(root.candidates(endDateField.text, endTimeField.text),
                endOffsetSelector, i18n("end"))
            if (Date.parse(endUtc) <= Date.parse(startUtc)) {
                throw new Error(i18n("The end time must be later than the start time."))
            }
            editorError.text = ""
            root.saveRequested(startUtc, endUtc)
        } catch (error) {
            editorError.text = error.message
        }
    }

    Accessible.role: Accessible.Form
    Accessible.name: editing ? i18n("Edit work session") : i18n("Add work session")

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true

            Kirigami.Heading {
                Layout.fillWidth: true
                level: 4
                text: root.editing ? i18n("Edit session") : i18n("Add session")
            }

            PlasmaComponents.Button {
                objectName: "daily-session-cancel"
                text: i18n("Cancel")
                onClicked: root.cancelRequested()
            }

            PlasmaComponents.Button {
                objectName: "daily-session-save"
                text: root.longConfirmationRequired ? i18n("Save anyway")
                    : (root.editing ? i18n("Save changes") : i18n("Add session"))
                icon.name: "dialog-ok-apply"
                onClicked: root.submit()
            }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: root.taskTitle
            color: Kirigami.Theme.disabledTextColor
            elide: Text.ElideRight
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Kirigami.Units.smallSpacing
            rowSpacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label { text: i18n("Start") }
            ColumnLayout {
                Layout.fillWidth: true
                PlasmaComponents.TextField {
                    id: startDateField
                    objectName: "daily-session-start-date"
                    Layout.fillWidth: true
                    Accessible.name: i18n("Session start date")
                    onTextEdited: root.markChanged()
                }
                PlasmaComponents.TextField {
                    id: startTimeField
                    objectName: "daily-session-start"
                    Layout.fillWidth: true
                    Accessible.name: i18n("Session start time")
                    onTextEdited: root.markChanged()
                }
            }

            PlasmaComponents.ComboBox {
                id: startOffsetSelector
                objectName: "daily-session-start-offset"
                Layout.columnSpan: 2
                Layout.fillWidth: true
                visible: root.startOffsetChoices.length > 1
                model: root.startOffsetChoices
                textRole: "label"
                valueRole: "value"
                Accessible.name: i18n("Start-time UTC offset")
                onActivated: root.offsetChanged()
            }

            PlasmaComponents.Label { text: i18n("End") }
            ColumnLayout {
                Layout.fillWidth: true
                PlasmaComponents.TextField {
                    id: endDateField
                    objectName: "daily-session-end-date"
                    Layout.fillWidth: true
                    Accessible.name: i18n("Session end date")
                    onTextEdited: root.markChanged()
                }
                PlasmaComponents.TextField {
                    id: endTimeField
                    objectName: "daily-session-end"
                    Layout.fillWidth: true
                    Accessible.name: i18n("Session end time")
                    onTextEdited: root.markChanged()
                }
            }

            PlasmaComponents.ComboBox {
                id: endOffsetSelector
                objectName: "daily-session-end-offset"
                Layout.columnSpan: 2
                Layout.fillWidth: true
                visible: root.endOffsetChoices.length > 1
                model: root.endOffsetChoices
                textRole: "label"
                valueRole: "value"
                Accessible.name: i18n("End-time UTC offset")
                onActivated: root.offsetChanged()
            }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: i18n("Times use %1. Seconds are optional.", root.timezoneId)
            color: Kirigami.Theme.disabledTextColor
            wrapMode: Text.Wrap
        }

        PlasmaComponents.Label {
            id: editorError
            Layout.fillWidth: true
            visible: text.length > 0
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.Wrap
            Accessible.name: text
        }

    }
}
