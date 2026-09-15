import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras

PlasmaExtras.ListSectionHeader {
    id: root

    required property string categoryName
    required property string categoryColor

    text: root.categoryName

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        Rectangle {
            Layout.preferredWidth: Kirigami.Units.smallSpacing
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            color: root.categoryColor
            radius: width / 2
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: root.categoryName
            font.bold: true
            elide: Text.ElideRight
        }
    }
}
