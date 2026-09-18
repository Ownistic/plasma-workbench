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
    readonly property var zoomFactors: [0.75, 1, 1.5, 2, 3]
    readonly property int defaultZoomIndex: 3
    property int zoomIndex: defaultZoomIndex
    readonly property real zoomFactor: zoomFactors[Math.max(0, Math.min(zoomFactors.length - 1, zoomIndex))]
    readonly property real slotWidth: Kirigami.Units.gridUnit * zoomFactor
    property real laneHeight: Kirigami.Units.gridUnit * 1.35
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
    readonly property var segmentLayout: buildSegmentLayout()
    readonly property int laneCount: Math.max(1, segmentLayout.laneCount)
    readonly property int displayedLaneCount: Math.max(laneCount,
        createArea.dragging ? createArea.previewLane + 1 : 1)
    readonly property real trackHeight: displayedLaneCount * laneHeight
    readonly property real rulerHeight: Kirigami.Units.gridUnit * 1.4
    implicitHeight: zoomControls.height + Kirigami.Units.smallSpacing + trackHeight + rulerHeight
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

    function buildSegmentLayout() {
        const ordered = segments.slice().sort(function(left, right) {
            const startDifference = Date.parse(left.startUtc) - Date.parse(right.startUtc)
            if (startDifference !== 0) {
                return startDifference
            }
            const endDifference = Date.parse(right.endUtc) - Date.parse(left.endUtc)
            if (endDifference !== 0) {
                return endDifference
            }
            return String(left.sessionId).localeCompare(String(right.sessionId))
        })
        const laneEnds = []
        const entries = []
        for (let index = 0; index < ordered.length; index += 1) {
            const segment = ordered[index]
            const start = Date.parse(segment.startUtc)
            const end = Date.parse(segment.endUtc)
            let lane = laneEnds.length
            for (let candidate = 0; candidate < laneEnds.length; candidate += 1) {
                if (laneEnds[candidate] <= start) {
                    lane = candidate
                    break
                }
            }
            laneEnds[lane] = end
            entries.push({ segment: segment, lane: lane })
        }
        return { entries: entries, laneCount: laneEnds.length }
    }

    function laneForInterval(startUtc, endUtc) {
        const start = Date.parse(startUtc)
        const end = Date.parse(endUtc)
        if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) {
            return 0
        }
        for (let lane = 0; lane < laneCount; lane += 1) {
            let overlaps = false
            for (let index = 0; index < segmentLayout.entries.length; index += 1) {
                const entry = segmentLayout.entries[index]
                if (entry.lane !== lane) {
                    continue
                }
                if (start < Date.parse(entry.segment.endUtc) && end > Date.parse(entry.segment.startUtc)) {
                    overlaps = true
                    break
                }
            }
            if (!overlaps) {
                return lane
            }
        }
        return laneCount
    }

    function changeZoom(change) {
        const nextIndex = Math.max(0, Math.min(zoomFactors.length - 1, zoomIndex + change))
        if (nextIndex === zoomIndex) {
            return
        }
        const centerSlot = (flickable.contentX + flickable.width / 2) / slotWidth
        zoomIndex = nextIndex
        Qt.callLater(function() {
            flickable.contentX = Math.max(0, Math.min(flickable.contentWidth - flickable.width,
                centerSlot * root.slotWidth - flickable.width / 2))
        })
    }

    function resetZoom() {
        changeZoom(defaultZoomIndex - zoomIndex)
    }

    function beginDrawing(x) {
        if (!creationEnabled || !validRange) {
            return
        }
        createArea.pressX = x
        createArea.currentX = x
        createArea.dragging = true
        createArea.updatePreview()
    }

    function updateDrawing(x) {
        if (createArea.dragging) {
            createArea.currentX = x
            createArea.updatePreview()
        }
    }

    function cancelDrawing() {
        createArea.dragging = false
    }

    function completeDrawing(x) {
        if (!createArea.dragging) {
            return
        }
        const startX = Math.min(createArea.pressX, x)
        const endX = Math.max(createArea.pressX, x) + (Math.abs(x - createArea.pressX) < 3 ? slotWidth : 0)
        const startUtc = snappedUtcAt(startX)
        const endUtc = snappedUtcAt(endX)
        createArea.dragging = false
        if (Date.parse(endUtc) > Date.parse(startUtc)) {
            sessionCreateRequested(startUtc, endUtc)
        }
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

    Row {
        id: zoomControls
        anchors.top: parent.top
        anchors.right: parent.right
        spacing: Kirigami.Units.smallSpacing

        Controls.ToolButton {
            objectName: "daily-timeline-zoom-out"
            icon.name: "zoom-out"
            enabled: root.zoomIndex > 0
            Accessible.name: i18n("Zoom out timeline")
            onClicked: root.changeZoom(-1)
        }

        Controls.ToolButton {
            objectName: "daily-timeline-zoom-reset"
            text: i18n("%1%", Math.round(root.zoomFactor * 100))
            enabled: root.zoomIndex !== root.defaultZoomIndex
            Accessible.name: i18n("Reset timeline zoom to %1%", Math.round(root.zoomFactors[root.defaultZoomIndex] * 100))
            onClicked: root.resetZoom()
        }

        Controls.ToolButton {
            objectName: "daily-timeline-zoom-in"
            icon.name: "zoom-in"
            enabled: root.zoomIndex < root.zoomFactors.length - 1
            Accessible.name: i18n("Zoom in timeline")
            onClicked: root.changeZoom(1)
        }
    }

    Flickable {
        id: flickable
        objectName: "daily-timeline-flickable"
        anchors.top: zoomControls.bottom
        anchors.topMargin: Kirigami.Units.smallSpacing
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        contentWidth: root.implicitWidth
        contentHeight: root.trackHeight + root.rulerHeight
        boundsBehavior: Flickable.StopAtBounds
        interactive: !root.creationEnabled

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
                    height: root.trackHeight
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
                        height: root.trackHeight
                        color: Kirigami.Theme.disabledTextColor
                        opacity: 0.35
                    }

                    Controls.Label {
                        y: root.trackHeight
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
                y: createArea.previewLane * root.laneHeight + Kirigami.Units.smallSpacing
                width: Math.max(root.slotWidth,
                    Math.round((endX - startX) / root.slotWidth) * root.slotWidth)
                height: root.laneHeight - Kirigami.Units.smallSpacing * 2
                radius: Kirigami.Units.smallSpacing
                color: Kirigami.Theme.highlightColor
                opacity: 0.45
                border.width: 1
                border.color: Kirigami.Theme.highlightedTextColor
                z: 5
            }

            MouseArea {
                id: createArea
                objectName: "daily-timeline-create-area"
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: root.trackHeight
                enabled: root.creationEnabled && root.validRange
                property real pressX: 0
                property real currentX: 0
                property bool dragging: false
                property int previewLane: 0
                cursorShape: Qt.CrossCursor
                preventStealing: true
                z: root.creationEnabled ? 4 : 0
                function updatePreview() {
                    const startUtc = root.snappedUtcAt(Math.min(pressX, currentX))
                    const endUtc = root.snappedUtcAt(Math.max(pressX, currentX) + root.slotWidth)
                    previewLane = root.laneForInterval(startUtc, endUtc)
                }
                onPressed: root.beginDrawing(mouse.x)
                onPositionChanged: root.updateDrawing(mouse.x)
                onCanceled: root.cancelDrawing()
                onReleased: root.completeDrawing(mouse.x)
            }

            Rectangle {
                visible: root.currentMilliseconds >= root.startMilliseconds
                    && root.currentMilliseconds < root.endMilliseconds
                x: (root.currentMilliseconds - root.startMilliseconds) / (15 * 60 * 1000) * root.slotWidth
                y: 0
                width: 2
                height: root.trackHeight
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
                model: root.segmentLayout.entries

                delegate: Rectangle {
                    id: sessionBlock
                    required property var modelData
                    readonly property var segment: modelData.segment
                    x: root.segmentX(segment)
                    y: modelData.lane * root.laneHeight + Kirigami.Units.smallSpacing
                    width: root.segmentWidth(segment)
                    height: root.laneHeight - Kirigami.Units.smallSpacing * 2
                    radius: Kirigami.Units.smallSpacing
                    color: segment.categoryColor || Kirigami.Theme.highlightColor
                    border.width: activeFocus ? 2 : (segment.manuallyEdited ? 1 : 0)
                    border.color: Kirigami.Theme.textColor
                    opacity: segment.active ? 0.75 : 1
                    objectName: "timeline-session-" + segment.sessionId
                    activeFocusOnTab: root.editable && !segment.active && !root.creationEnabled
                    Accessible.role: segment.active ? Accessible.StaticText : Accessible.Button
                    Accessible.name: root.sessionName(segment)
                    Accessible.description: segment.manuallyEdited ? i18n("Manually edited work session") : ""
                    Accessible.onPressAction: {
                        if (!segment.active && !root.creationEnabled) root.sessionSelected(segment, sessionBlock)
                    }

                    Controls.ToolTip.visible: mouseArea.containsMouse
                    Controls.ToolTip.text: root.sessionName(segment)

                    Controls.Label {
                        id: sessionLabel
                        objectName: "timeline-session-label-" + segment.sessionId
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        text: segment.taskTitle
                        elide: Text.ElideRight
                        color: Kirigami.Theme.highlightedTextColor
                    }

                    Keys.onSpacePressed: {
                        if (!root.creationEnabled) root.sessionSelected(segment, sessionBlock)
                    }
                    Keys.onReturnPressed: {
                        if (!root.creationEnabled) root.sessionSelected(segment, sessionBlock)
                    }

                    MouseArea {
                        id: mouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: root.editable && !segment.active && !root.creationEnabled
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
                                root.sessionSelected(segment, sessionBlock)
                                return
                            }
                            let start = Date.parse(segment.sessionStartUtc)
                            let end = Date.parse(segment.sessionEndUtc)
                            if (mode === "start") {
                                start += delta
                            } else if (mode === "end") {
                                end += delta
                            } else {
                                start += delta
                                end += delta
                            }
                            if (end > start) {
                                root.sessionEditRequested(segment, new Date(start).toISOString(),
                                    new Date(end).toISOString(), sessionBlock)
                            }
                        }
                    }
                }
            }
        }
    }
}
