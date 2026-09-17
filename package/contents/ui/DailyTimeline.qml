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
    property var formatSeconds: function(seconds) { return Math.round(seconds / 60) + " min" }
    property real slotWidth: Kirigami.Units.gridUnit * 0.85
    property real laneHeight: Kirigami.Units.gridUnit * 1.35
    property int lanes: 1
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
    implicitHeight: laneHeight + Kirigami.Units.gridUnit * 2
    implicitWidth: Math.max(Kirigami.Units.gridUnit * 24, slotCount * slotWidth)
    Accessible.name: i18n("15-minute work-session timeline for %1", localDate)

    signal sessionCreateRequested(string startUtc, string endUtc)
    signal sessionEditRequested(var segment, string startUtc, string endUtc)
    signal sessionSelected(var segment)

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

    Flickable {
        id: flickable
        anchors.fill: parent
        clip: true
        contentWidth: root.implicitWidth
        contentHeight: root.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        Item {
            width: flickable.contentWidth
            height: flickable.contentHeight

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

            MouseArea {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: parent.height - Kirigami.Units.gridUnit
                enabled: root.editable && root.validRange
                property real pressX: 0
                onPressed: pressX = mouse.x
                onReleased: {
                    const startX = Math.min(pressX, mouse.x)
                    const endX = Math.max(pressX, mouse.x) + (Math.abs(mouse.x - pressX) < 3 ? root.slotWidth : 0)
                    const startUtc = root.snappedUtcAt(startX)
                    const endUtc = root.snappedUtcAt(endX)
                    if (Date.parse(endUtc) > Date.parse(startUtc)) {
                        root.sessionCreateRequested(startUtc, endUtc)
                    }
                }
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
                    border.width: modelData.manuallyEdited ? 1 : 0
                    border.color: Kirigami.Theme.textColor
                    opacity: modelData.active ? 0.75 : 1
                    objectName: "timeline-session-" + modelData.sessionId

                    Controls.ToolTip.visible: mouseArea.containsMouse
                    Controls.ToolTip.text: modelData.taskTitle + "\n" + modelData.startUtc + " - " + modelData.endUtc

                    Controls.Label {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        text: parent.width > Kirigami.Units.gridUnit * 5 ? modelData.taskTitle : ""
                        elide: Text.ElideRight
                        color: Kirigami.Theme.highlightedTextColor
                    }

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
                                root.sessionSelected(modelData)
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
                                root.sessionEditRequested(modelData, new Date(start).toISOString(), new Date(end).toISOString())
                            }
                        }
                    }
                }
            }
        }
    }
}
