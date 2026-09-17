import QtQuick
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "time" as WorkbenchTime

Item {
    id: root

    required property var report
    required property string localDate
    property string timezoneId: "Etc/UTC"
    property bool editable: true
    property bool creationEnabled: editable
    property var formatSeconds: function(seconds) { return Math.round(seconds / 60) + " min" }
    property real slotWidth: Kirigami.Units.gridUnit * 0.85
    property real laneHeight: Kirigami.Units.gridUnit * 1.35
    property int lanes: 1
    property double currentMilliseconds: Date.now()
    readonly property double startMilliseconds: report ? Date.parse(report.startUtc) : 0
    readonly property double endMilliseconds: report ? Date.parse(report.endUtc) : 0
    readonly property real rawSlotCount: (endMilliseconds - startMilliseconds) / (15 * 60 * 1000)
    readonly property bool validRange: Number.isFinite(startMilliseconds) && Number.isFinite(endMilliseconds)
        && Number.isInteger(rawSlotCount) && rawSlotCount >= 92 && rawSlotCount <= 100
    readonly property int slotCount: validRange ? rawSlotCount : 0
    readonly property int hourMarkerCount: validRange ? Math.ceil(slotCount / 4) : 0
    readonly property var segments: !validRange || !report || !Array.isArray(report.sessionSegments) ? []
        : report.sessionSegments.filter(function(segment) {
        return segment.localDate === root.localDate
    })
    implicitHeight: Math.max(laneHeight + Kirigami.Units.gridUnit * 3, Kirigami.Units.gridUnit * 5)
    implicitWidth: Math.max(Kirigami.Units.gridUnit * 24, slotCount * slotWidth)
    Accessible.name: i18n("15-minute work-session timeline for %1", localDate)
    Accessible.role: Accessible.Graphic

    signal sessionCreateRequested(string startUtc, string endUtc)
    signal sessionEditRequested(var segment, string startUtc, string endUtc, var source)
    signal sessionSelected(var segment, var source)

    function snappedUtcAt(x) {
        if (!validRange) {
            return ""
        }
        const slot = Math.max(0, Math.min(slotCount, Math.round(x / slotWidth)))
        return new Date(startMilliseconds + slot * 15 * 60 * 1000).toISOString()
    }

    function segmentX(segment) {
        return Math.max(0, (Date.parse(segment.startUtc) - startMilliseconds) / (15 * 60 * 1000)) * slotWidth
    }

    function segmentWidth(segment) {
        return Math.max(3, (Date.parse(segment.endUtc) - Date.parse(segment.startUtc)) / (15 * 60 * 1000) * slotWidth)
    }

    function localTime(utc) {
        const local = WorkbenchTime.TimeMath.localPartsForUtc(utc, root.timezoneId)
        if (!local.valid) {
            return utc
        }
        return String(local.hour).padStart(2, "0") + ":" + String(local.minute).padStart(2, "0")
    }

    function sessionName(segment) {
        return i18n("%1, %2 to %3, %4", segment.taskTitle, root.localTime(segment.startUtc),
            root.localTime(segment.endUtc), root.formatSeconds((Date.parse(segment.endUtc) - Date.parse(segment.startUtc)) / 1000))
    }

    function revealCurrentTime() {
        if (!validRange || currentMilliseconds < startMilliseconds || currentMilliseconds >= endMilliseconds) {
            return
        }
        const markerX = (currentMilliseconds - startMilliseconds) / (15 * 60 * 1000) * slotWidth
        flickable.contentX = Math.max(0, Math.min(flickable.contentWidth - flickable.width,
            markerX - flickable.width / 2))
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.visible
        onTriggered: root.currentMilliseconds = Date.now()
    }

    Component.onCompleted: Qt.callLater(root.revealCurrentTime)

    Flickable {
        id: flickable
        objectName: "daily-timeline-flickable"
        anchors.fill: parent
        clip: true
        contentWidth: root.implicitWidth
        contentHeight: root.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        Controls.ScrollBar.horizontal: Controls.ScrollBar {
            objectName: "daily-timeline-scrollbar"
            policy: Controls.ScrollBar.AlwaysOn
            Accessible.name: i18n("Timeline position")
        }

        Item {
            width: flickable.contentWidth
            height: flickable.contentHeight

            Repeater {
                model: root.slotCount

                delegate: Rectangle {
                    required property int index
                    x: index * root.slotWidth
                    width: 1
                    height: parent.height - Kirigami.Units.gridUnit * 1.4
                    color: index % 4 === 0 ? Kirigami.Theme.disabledTextColor : Kirigami.Theme.textColor
                    opacity: index % 4 === 0 ? 0.35 : 0.1
                }
            }

            Repeater {
                model: root.hourMarkerCount

                delegate: Item {
                    required property int index
                    x: index * 4 * root.slotWidth
                    width: 4 * root.slotWidth
                    height: parent.height

                    Rectangle {
                        anchors.top: parent.top
                        width: 1
                        height: parent.height - Kirigami.Units.gridUnit
                        color: Kirigami.Theme.disabledTextColor
                        opacity: 0.35
                    }

                    Controls.Label {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        horizontalAlignment: Text.AlignLeft
                        text: {
                            const local = WorkbenchTime.TimeMath.formatUtcForLocal(
                                new Date(root.startMilliseconds + index * 60 * 60 * 1000).toISOString(),
                                root.timezoneId, true)
                            return local.valid ? local.formatted.slice(-5) : ""
                        }
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        color: Kirigami.Theme.disabledTextColor
                    }
                }
            }

            Rectangle {
                readonly property real startX: Math.min(createArea.pressX, createArea.currentX)
                readonly property real endX: Math.max(createArea.pressX, createArea.currentX)
                visible: createArea.dragging
                x: Math.round(startX / root.slotWidth) * root.slotWidth
                y: Kirigami.Units.smallSpacing
                width: Math.max(root.slotWidth,
                    Math.round((endX - startX) / root.slotWidth) * root.slotWidth)
                height: root.laneHeight - Kirigami.Units.smallSpacing * 2
                radius: Kirigami.Units.smallSpacing
                color: Kirigami.Theme.highlightColor
                opacity: 0.45
                border.width: 1
                border.color: Kirigami.Theme.highlightedTextColor
                z: 2
            }

            MouseArea {
                id: createArea
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: parent.height - Kirigami.Units.gridUnit
                enabled: root.creationEnabled && root.validRange
                property real pressX: 0
                property real currentX: 0
                property bool dragging: false
                cursorShape: Qt.CrossCursor
                onPressed: {
                    pressX = mouse.x
                    currentX = mouse.x
                    dragging = true
                }
                onPositionChanged: currentX = mouse.x
                onCanceled: dragging = false
                onReleased: {
                    const startX = Math.min(pressX, mouse.x)
                    const endX = Math.max(pressX, mouse.x) + (Math.abs(mouse.x - pressX) < 3 ? root.slotWidth : 0)
                    const startUtc = root.snappedUtcAt(startX)
                    const endUtc = root.snappedUtcAt(endX)
                    dragging = false
                    if (Date.parse(endUtc) > Date.parse(startUtc)) {
                        root.sessionCreateRequested(startUtc, endUtc)
                    }
                }
            }

            Rectangle {
                visible: root.currentMilliseconds >= root.startMilliseconds
                    && root.currentMilliseconds < root.endMilliseconds
                x: (root.currentMilliseconds - root.startMilliseconds) / (15 * 60 * 1000) * root.slotWidth
                y: 0
                width: 2
                height: parent.height - Kirigami.Units.gridUnit
                color: Kirigami.Theme.negativeTextColor
                z: 3

                Controls.ToolTip.visible: nowHover.hovered
                Controls.ToolTip.text: i18n("Current time")
                HoverHandler { id: nowHover }
            }

            Controls.Label {
                anchors.centerIn: parent
                visible: !root.validRange
                text: i18n("The selected day cannot be displayed.")
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.Wrap
            }

            Repeater {
                model: root.segments

                delegate: Rectangle {
                    required property var modelData
                    x: root.segmentX(modelData)
                    y: Kirigami.Units.smallSpacing
                    width: root.segmentWidth(modelData)
                    height: root.laneHeight - Kirigami.Units.smallSpacing * 2
                    radius: Kirigami.Units.smallSpacing
                    color: modelData.categoryColor || Kirigami.Theme.highlightColor
                    border.width: activeFocus ? 2 : (modelData.manuallyEdited ? 1 : 0)
                    border.color: Kirigami.Theme.textColor
                    opacity: modelData.active ? 0.75 : 1
                    objectName: "timeline-session-" + modelData.sessionId
                    activeFocusOnTab: root.editable && !modelData.active
                    Accessible.role: modelData.active ? Accessible.StaticText : Accessible.Button
                    Accessible.name: root.sessionName(modelData)
                    Accessible.description: modelData.manuallyEdited ? i18n("Manually edited work session") : ""
                    Accessible.onPressAction: {
                        if (!modelData.active) root.sessionSelected(modelData, sessionBlock)
                    }

                    Controls.ToolTip.visible: mouseArea.containsMouse
                    Controls.ToolTip.text: root.sessionName(modelData)

                    Controls.Label {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        text: parent.width > Kirigami.Units.gridUnit * 5 ? modelData.taskTitle : ""
                        elide: Text.ElideRight
                        color: Kirigami.Theme.highlightedTextColor
                    }

                    Keys.onSpacePressed: root.sessionSelected(modelData, sessionBlock)
                    Keys.onReturnPressed: root.sessionSelected(modelData, sessionBlock)

                    MouseArea {
                        id: mouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: root.editable && !modelData.active
                        property real pressX: 0
                        property string mode: "move"
                        onPressed: {
                            pressX = mouse.x
                            mode = mouse.x < Kirigami.Units.smallSpacing * 3 ? "start"
                                : (mouse.x > parent.width - Kirigami.Units.smallSpacing * 3 ? "end" : "move")
                        }
                        onReleased: {
                            const delta = Math.round((mouse.x - pressX) / root.slotWidth) * 15 * 60 * 1000
                            if (delta === 0) {
                                root.sessionSelected(modelData, sessionBlock)
                                return
                            }
                            let start = Date.parse(modelData.sessionStartUtc)
                            let end = Date.parse(modelData.sessionEndUtc)
                            if (mode === "start") {
                                start += delta
                            } else if (mode === "end") {
                                end += delta
                            } else {
                                start += delta
                                end += delta
                            }
                            if (end > start) {
                                root.sessionEditRequested(modelData, new Date(start).toISOString(),
                                    new Date(end).toISOString(), sessionBlock)
                            }
                        }
                    }
                }
            }
        }
    }
}
