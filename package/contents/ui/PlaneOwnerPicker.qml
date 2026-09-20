import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: root

    required property var members
    property var assigneeIds: []
    property Item popupParent: null
    signal selectionChanged(var assigneeIds)

    readonly property var avatarColors: ["#7e22ce", "#2563eb", "#0891b2", "#be123c", "#7c3aed"]

    function memberLabel(member) {
        return member ? (member.memberName || member.memberEmail || member.memberId) : ""
    }

    function selectedMember() {
        for (let assigneeIndex = 0; assigneeIndex < root.assigneeIds.length; ++assigneeIndex) {
            for (let memberIndex = 0; memberIndex < root.members.length; ++memberIndex) {
                if (root.members[memberIndex].memberId === root.assigneeIds[assigneeIndex]) {
                    return root.members[memberIndex]
                }
            }
        }
        return null
    }

    function ownerLabel() {
        const member = root.selectedMember()
        if (member) {
            return root.assigneeIds.length > 1
                ? i18n("%1 +%2", root.memberLabel(member), root.assigneeIds.length - 1)
                : root.memberLabel(member)
        }
        return root.assigneeIds.length > 0 ? i18n("Assigned member unavailable") : i18n("Unassigned")
    }

    function initials(member) {
        const words = root.memberLabel(member).trim().split(/\s+/).filter(function(word) { return word.length > 0 })
        if (words.length === 0) {
            return "?"
        }
        return String(words[0][0] + (words.length > 1 ? words[words.length - 1][0] : "")).toUpperCase()
    }

    function avatarColor(member) {
        const key = member ? String(member.memberId || root.memberLabel(member)) : ""
        let value = 0
        for (let index = 0; index < key.length; ++index) {
            value = (value * 31 + key.charCodeAt(index)) >>> 0
        }
        return root.avatarColors[value % root.avatarColors.length]
    }

    function isSelected(memberId) {
        return root.assigneeIds.indexOf(memberId) !== -1
    }

    function matchingMembers() {
        const query = memberSearch.text.trim().toLowerCase()
        if (!query) {
            return root.members
        }
        return root.members.filter(function(member) {
            return (root.memberLabel(member) + " " + (member.memberEmail || "") + " " + member.memberId)
                .toLowerCase().indexOf(query) !== -1
        })
    }

    function chooseOwner(memberId) {
        const selection = memberId ? [memberId] : []
        root.selectionChanged(selection)
        ownerPopup.close()
        ownerButton.forceActiveFocus()
    }

    implicitWidth: ownerButton.implicitWidth
    implicitHeight: ownerButton.implicitHeight

    PlasmaComponents.Button {
        id: ownerButton
        anchors.fill: parent
        display: Controls.AbstractButton.TextBesideIcon
        Accessible.name: i18n("Plane owner: %1", root.ownerLabel())
        onClicked: ownerPopup.open()

        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing

            Rectangle {
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                radius: width / 2
                color: root.selectedMember() ? root.avatarColor(root.selectedMember()) : Kirigami.Theme.disabledTextColor

                PlasmaComponents.Label {
                    anchors.centerIn: parent
                    text: root.selectedMember() ? root.initials(root.selectedMember()) : "–"
                    color: "white"
                    font.bold: true
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: root.ownerLabel()
                elide: Text.ElideRight
            }

            Kirigami.Icon {
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                source: "arrow-down"
            }
        }
    }

    Controls.Popup {
        id: ownerPopup
        parent: root.popupParent || root
        x: ownerButton.mapToItem(parent, 0, ownerButton.height + Kirigami.Units.smallSpacing).x
        y: ownerButton.mapToItem(parent, 0, ownerButton.height + Kirigami.Units.smallSpacing).y
        width: Math.max(ownerButton.width, Kirigami.Units.gridUnit * 20)
        padding: Kirigami.Units.smallSpacing
        modal: false
        focus: true
        closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside
        onOpened: {
            memberSearch.text = ""
            memberSearch.forceActiveFocus()
        }

        background: Rectangle {
            radius: Kirigami.Units.smallSpacing
            color: Kirigami.Theme.backgroundColor
            border.color: Kirigami.Theme.disabledTextColor
        }

        contentItem: ColumnLayout {
            width: ownerPopup.width - ownerPopup.leftPadding - ownerPopup.rightPadding
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.TextField {
                id: memberSearch
                Layout.fillWidth: true
                placeholderText: i18n("Search members…")
                Accessible.name: i18n("Search Plane members")
            }

            ListView {
                id: memberList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, Kirigami.Units.gridUnit * 12)
                clip: true
                model: [{ memberId: "", memberName: i18n("Unassigned"), memberEmail: "" }].concat(root.matchingMembers())

                delegate: Controls.ItemDelegate {
                    id: memberRow
                    required property var modelData
                    width: memberList.width
                    highlighted: root.isSelected(modelData.memberId)
                    Accessible.name: modelData.memberId
                        ? i18n("Assign Plane task to %1", root.memberLabel(modelData))
                        : i18n("Clear Plane owner")
                    onClicked: root.chooseOwner(modelData.memberId)

                    contentItem: RowLayout {
                        spacing: Kirigami.Units.smallSpacing

                        Rectangle {
                            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                            radius: width / 2
                            color: modelData.memberId ? root.avatarColor(modelData) : Kirigami.Theme.disabledTextColor

                            PlasmaComponents.Label {
                                anchors.centerIn: parent
                                text: modelData.memberId ? root.initials(modelData) : "–"
                                color: "white"
                                font.bold: true
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            }
                        }

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: root.memberLabel(modelData)
                            elide: Text.ElideRight
                        }

                        Kirigami.Icon {
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                            visible: root.isSelected(modelData.memberId)
                            source: "dialog-ok"
                        }
                    }
                }
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                visible: root.matchingMembers().length === 0 && memberSearch.text.length > 0
                text: i18n("No matching members")
                color: Kirigami.Theme.disabledTextColor
            }
        }
    }
}
