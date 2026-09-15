import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: root

    property alias cfg_firstDayOfWeek: firstDay.currentValue
    property alias cfg_reportTimezone: timezone.text
    property alias cfg_defaultStatusFilter: defaultStatuses.text
    property alias cfg_showArchivedTasks: showArchived.checked
    property alias cfg_use24HourTime: use24HourTime.checked
    property alias cfg_unusualSessionHours: unusualSessionHours.value

    implicitWidth: form.implicitWidth
    implicitHeight: form.implicitHeight

    Kirigami.FormLayout {
        id: form
        anchors.fill: parent

        PlasmaComponents.ComboBox {
            id: firstDay
            Kirigami.FormData.label: i18n("First day of week:")
            model: [
                { text: i18n("Monday"), value: 1 },
                { text: i18n("Sunday"), value: 7 }
            ]
            textRole: "text"
            valueRole: "value"
        }

        PlasmaComponents.TextField {
            id: timezone
            Kirigami.FormData.label: i18n("Report timezone:")
            placeholderText: i18n("System timezone")
        }

        PlasmaComponents.TextField {
            id: defaultStatuses
            Kirigami.FormData.label: i18n("Default status filters:")
            placeholderText: i18n("backlog,ready,in_progress,blocked")
        }

        PlasmaComponents.CheckBox {
            id: showArchived
            text: i18n("Show archived tasks")
        }

        PlasmaComponents.CheckBox {
            id: use24HourTime
            text: i18n("Use 24-hour time")
        }

        PlasmaComponents.SpinBox {
            id: unusualSessionHours
            Kirigami.FormData.label: i18n("Warn after hours:")
            from: 1
            to: 168
        }
    }
}
