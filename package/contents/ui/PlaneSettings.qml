import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "plane" as WorkbenchPlane

import "../code/Database.js" as Database

/** Optional Plane connection controls for the currently selected local workspace.
 *  The token is deliberately never read from, or written to, LocalStorage. */
ColumnLayout {
    id: root

    required property var board
    property var binding: null
    property var projects: []
    property var stateRows: []
    property string message: ""
    property bool failure: false
    property var requests: ({})

    function connectionId() {
        return binding && binding.connectionId ? binding.connectionId : "plane-" + board.selectedWorkspaceId
    }

    function refresh() {
        binding = board.selectedWorkspaceId ? Database.getWorkspaceProvider(board.selectedWorkspaceId) : null
        const config = binding && binding.config ? binding.config : ({})
        planeBaseUrl.text = config.baseUrl || "https://api.plane.so"
        planeWorkspace.text = config.workspace || ""
        planeAssigneeId.text = config.assigneeId || ""
        projects = []
        stateRows = []
        message = ""
        failure = false
        if (binding && binding.provider === "plane") {
            refreshProjectsAndMappings()
        }
    }

    function rememberBinding() {
        binding = Database.setWorkspaceProvider({
            workspaceId: board.selectedWorkspaceId,
            provider: "plane",
            connectionId: connectionId(),
            config: { baseUrl: planeBaseUrl.text.trim(), workspace: planeWorkspace.text.trim(),
                assigneeId: planeAssigneeId.text.trim() }
        })
        board.notifyWorkspaceProviderChanged()
    }

    function refreshProjectsAndMappings() {
        if (!binding || binding.provider !== "plane") {
            return
        }
        if (!planeBaseUrl.text.trim() || !planeWorkspace.text.trim()) {
            failure = true
            message = i18n("Plane is configured, but its API URL or workspace slug is missing.")
            return
        }
        failure = false
        message = i18n("Loading Plane projects and category mappings…")
        track(WorkbenchPlane.PlaneSync.fetchProjects(connectionId(), planeBaseUrl.text.trim(), planeWorkspace.text.trim()), "projects")
    }

    function refreshMappedProjectMetadata() {
        const mappings = Database.listProviderProjectMappings(board.selectedWorkspaceId)
        const requestedProjects = {}
        for (let index = 0; index < mappings.length; ++index) {
            const mapping = mappings[index]
            if (mapping.provider !== "plane" || requestedProjects[mapping.remoteProjectId]) {
                continue
            }
            requestedProjects[mapping.remoteProjectId] = true
            track(WorkbenchPlane.PlaneSync.fetchStates(connectionId(), planeBaseUrl.text.trim(), planeWorkspace.text.trim(), mapping.remoteProjectId), "states:" + mapping.remoteProjectId)
            track(WorkbenchPlane.PlaneSync.fetchMembers(connectionId(), planeBaseUrl.text.trim(), planeWorkspace.text.trim(), mapping.remoteProjectId), "members:" + mapping.remoteProjectId)
        }
    }

    function track(requestId, operation) {
        const next = Object.assign({}, requests)
        next[requestId] = operation
        requests = next
    }

    function connectAndDiscover() {
        if (!board.selectedWorkspaceId || !planeBaseUrl.text.trim() || !planeWorkspace.text.trim()) {
            failure = true
            message = i18n("Enter a Plane API URL and workspace slug.")
            return
        }
        if (planeToken.text.length > 0 && !WorkbenchPlane.PlaneSync.setToken(connectionId(), planeToken.text)) {
            failure = true
            message = WorkbenchPlane.PlaneSync.lastError
            return
        }
        rememberBinding()
        failure = false
        message = i18n("Checking Plane connection…")
        track(WorkbenchPlane.PlaneSync.validateConnection(connectionId(), planeBaseUrl.text.trim(), planeWorkspace.text.trim()), "validate")
    }

    function projectIndex(categoryId) {
        const mappings = Database.listProviderProjectMappings(board.selectedWorkspaceId)
        for (let mappingIndex = 0; mappingIndex < mappings.length; ++mappingIndex) {
            if (mappings[mappingIndex].categoryId === categoryId) {
                for (let projectIndex = 0; projectIndex < projects.length; ++projectIndex) {
                    if (projects[projectIndex].id === mappings[mappingIndex].remoteProjectId) return projectIndex + 1
                }
            }
        }
        return 0
    }

    function saveCategoryMapping(categoryId, categoryName, projectIndex) {
        try {
            if (projectIndex <= 0 || projectIndex > projects.length) {
                Database.removeProviderProjectMapping(categoryId)
                failure = false
                message = i18n("Saved: %1 stays local to this workbench.", categoryName)
                return
            }
            const project = projects[projectIndex - 1]
            Database.saveProviderProjectMapping({
                workspaceId: board.selectedWorkspaceId, categoryId: categoryId, provider: "plane",
                remoteProjectId: project.id, remoteProjectName: project.name || project.identifier || project.id
            })
            failure = false
            message = i18n("Saved: %1 now syncs with %2.", categoryName,
                project.name || project.identifier || project.id)
            track(WorkbenchPlane.PlaneSync.fetchStates(connectionId(), planeBaseUrl.text.trim(), planeWorkspace.text.trim(), project.id), "states:" + project.id)
            track(WorkbenchPlane.PlaneSync.fetchMembers(connectionId(), planeBaseUrl.text.trim(), planeWorkspace.text.trim(), project.id), "members:" + project.id)
        } catch (error) {
            failure = true
            message = error.message || i18n("Could not save the category mapping.")
        }
    }

    function saveStateMapping(row, localStatus, isOutbound) {
        try {
            Database.saveProviderStateMapping({
                workspaceId: board.selectedWorkspaceId, provider: "plane", projectId: row.projectId,
                remoteStateId: row.remoteStateId, remoteStateName: row.remoteStateName,
                localStatus: localStatus, isOutbound: isOutbound
            })
            const savedMappings = Database.listProviderStateMappings(board.selectedWorkspaceId, "plane", row.projectId)
            stateRows = stateRows.map(function(currentRow) {
                if (currentRow.projectId !== row.projectId) {
                    return currentRow
                }
                const saved = savedMappings.filter(function(mapping) {
                    return mapping.remoteStateId === currentRow.remoteStateId
                })[0]
                return saved ? Object.assign({}, currentRow, {
                    localStatus: saved.localStatus, isOutbound: saved.isOutbound
                }) : currentRow
            })
            failure = false
            message = i18n("Saved Plane state mapping for %1.", row.remoteStateName)
        } catch (error) {
            failure = true
            message = error.message || i18n("Could not save the Plane state mapping.")
        }
    }

    Layout.fillWidth: true
    spacing: Kirigami.Units.largeSpacing

    Kirigami.Heading {
        Layout.fillWidth: true
        level: 3
        text: root.binding && root.binding.provider === "plane" ? i18n("Plane connection") : i18n("Add Plane")
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Kirigami.Theme.disabledTextColor
        text: i18n("Plane is optional. This workspace stays usable offline; only mapped categories create and synchronize Plane work items.")
    }

    PlasmaComponents.TextField {
        id: planeBaseUrl
        Layout.fillWidth: true
        placeholderText: i18n("https://api.plane.so")
        Accessible.name: i18n("Plane API URL")
    }

    PlasmaComponents.TextField {
        id: planeWorkspace
        Layout.fillWidth: true
        placeholderText: i18n("Plane workspace slug")
        Accessible.name: i18n("Plane workspace slug")
    }

    PlasmaComponents.TextField {
        id: planeAssigneeId
        Layout.fillWidth: true
        placeholderText: i18n("Plane assignee ID for batch pull")
        Accessible.name: i18n("Plane assignee ID")
    }

    PlasmaComponents.TextField {
        id: planeToken
        Layout.fillWidth: true
        echoMode: TextInput.Password
        placeholderText: i18n("Personal access token (saved in KWallet)")
        Accessible.name: i18n("Plane personal access token")
    }

    RowLayout {
        Layout.fillWidth: true

        PlasmaComponents.Button {
            text: root.binding && root.binding.provider === "plane" ? i18n("Save connection") : i18n("Connect and discover")
            enabled: board.selectedWorkspaceId.length > 0
            onClicked: root.connectAndDiscover()
        }

        PlasmaComponents.Button {
            text: i18n("Sync linked tasks")
            enabled: root.binding && root.binding.provider === "plane"
            onClicked: root.board.syncPlaneWorkspace()
        }

        PlasmaComponents.Button {
            text: i18n("Disconnect Plane")
            enabled: root.binding && root.binding.provider === "plane"
            onClicked: {
                if (!WorkbenchPlane.PlaneSync.clearToken(root.connectionId())) {
                    root.failure = true
                    root.message = WorkbenchPlane.PlaneSync.lastError
                    return
                }
                Database.setWorkspaceProvider({ workspaceId: root.board.selectedWorkspaceId, provider: null })
                root.board.notifyWorkspaceProviderChanged()
                root.refresh()
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.binding && root.binding.provider === "plane"

        PlasmaComponents.Button {
            objectName: "refresh-plane-projects-button"
            icon.name: "view-refresh"
            text: i18n("Refresh projects and mappings")
            onClicked: root.refreshProjectsAndMappings()
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            color: Kirigami.Theme.disabledTextColor
            elide: Text.ElideRight
            text: i18n("Mapping changes are saved to this workbench only.")
        }
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        visible: root.message.length > 0
        wrapMode: Text.Wrap
        color: root.failure ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.positiveTextColor
        text: root.message
    }

    Kirigami.Heading {
        Layout.fillWidth: true
        visible: root.binding && root.binding.provider === "plane" && root.projects.length > 0
        level: 4
        text: i18n("Category mappings")
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        visible: root.binding && root.binding.provider === "plane" && root.projects.length > 0
        wrapMode: Text.Wrap
        color: Kirigami.Theme.disabledTextColor
        text: i18n("Choose a Plane project for each category. Changes save immediately to this workbench.")
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        visible: root.binding && root.binding.provider === "plane" && root.projects.length === 0 && !root.failure
        wrapMode: Text.Wrap
        color: Kirigami.Theme.disabledTextColor
        text: i18n("Loading Plane projects. Once available, choose which local categories should sync.")
    }

    Repeater {
        model: root.projects.length > 0 ? root.board.categories : []

        delegate: RowLayout {
            id: categoryMappingRow
            required property var model
            Layout.fillWidth: true

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: model.name
                elide: Text.ElideRight
            }

            PlasmaComponents.ComboBox {
                id: projectPicker
                Layout.preferredWidth: Kirigami.Units.gridUnit * 15
                model: [{ id: "", name: i18n("Local only") }].concat(root.projects)
                textRole: "name"
                function restoreSavedMapping() {
                    currentIndex = root.projectIndex(categoryMappingRow.model.id)
                }
                Component.onCompleted: restoreSavedMapping()
                onModelChanged: restoreSavedMapping()
                onActivated: root.saveCategoryMapping(categoryMappingRow.model.id,
                    categoryMappingRow.model.name, currentIndex)
            }
        }
    }

    Kirigami.Heading {
        Layout.fillWidth: true
        visible: root.stateRows.length > 0
        level: 4
        text: i18n("Plane state mappings")
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        visible: root.stateRows.length > 0
        wrapMode: Text.Wrap
        color: Kirigami.Theme.disabledTextColor
        text: i18n("Map each Plane state to a status in this workbench’s local workflow.")
    }

    Repeater {
        model: root.stateRows

        delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: modelData.projectName + ": " + modelData.remoteStateName
                elide: Text.ElideRight
            }

            PlasmaComponents.ComboBox {
                id: localStatusPicker
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                model: root.board.workflowStatuses
                textRole: "name"
                valueRole: "id"
                Component.onCompleted: currentIndex = indexOfValue(modelData.localStatus)
                onModelChanged: currentIndex = indexOfValue(modelData.localStatus)
                onActivated: root.saveStateMapping(modelData, currentValue, outboundState.checked)
            }

            PlasmaComponents.CheckBox {
                id: outboundState
                text: i18n("Use for push")
                checked: modelData.isOutbound
                onToggled: root.saveStateMapping(modelData, localStatusPicker.currentValue, checked)
            }
        }
    }

    Connections {
        target: WorkbenchPlane.PlaneSync
        function onCompleted(requestId, result) {
            const operation = root.requests[requestId]
            if (!operation) return
            const next = Object.assign({}, root.requests)
            delete next[requestId]
            root.requests = next
            if (!result.ok) {
                root.failure = true
                root.message = result.error || i18n("Plane request failed.")
                return
            }
            if (operation === "validate") {
                root.failure = false
                root.message = i18n("Connected to Plane. Select projects for this workspace’s categories.")
                root.track(WorkbenchPlane.PlaneSync.fetchProjects(root.connectionId(), planeBaseUrl.text.trim(), planeWorkspace.text.trim()), "projects")
            } else if (operation === "projects") {
                root.projects = result.data || []
                root.refreshMappedProjectMetadata()
                root.message = root.projects.length > 0
                    ? i18n("Connected to Plane. Review category mappings for this workbench.")
                    : i18n("Connected to Plane, but no projects were returned.")
            } else if (operation.indexOf("members:") === 0) {
                const projectId = operation.slice("members:".length)
                const members = (result.data || []).map(function(member) {
                    return { memberId: member.id, memberName: member.display_name || member.name || member.id,
                        memberEmail: member.email || "", memberPayload: member }
                })
                Database.replaceProviderMembers({ workspaceId: root.board.selectedWorkspaceId,
                    provider: "plane", projectId: projectId, members: members })
            } else if (operation.indexOf("states:") === 0) {
                const states = result.data || []
                const projectId = operation.slice("states:".length)
                const existing = Database.listProviderStateMappings(root.board.selectedWorkspaceId, "plane", projectId)
                for (let index = 0; index < states.length; ++index) {
                    const state = states[index]
                    const group = String(state.group || "").toLowerCase()
                    const defaultStatus = group === "completed" || group === "cancelled" ? "completed"
                        : group === "started" ? "in_progress" : group === "unstarted" ? "ready" : "backlog"
                    const existingMapping = existing.filter(function(mapping) {
                        return mapping.remoteStateId === state.id
                    })[0]
                    const localStatus = existingMapping ? existingMapping.localStatus : defaultStatus
                    let outbound = existingMapping ? existingMapping.isOutbound : false
                    for (let mappingIndex = 0; mappingIndex < existing.length; ++mappingIndex) {
                        outbound = outbound || (existing[mappingIndex].remoteStateId === state.id && existing[mappingIndex].isOutbound)
                    }
                    if (!existingMapping && !outbound && !existing.some(function(mapping) { return mapping.localStatus === localStatus && mapping.isOutbound })) {
                        outbound = true
                    }
                    Database.saveProviderStateMapping({ workspaceId: root.board.selectedWorkspaceId,
                        provider: "plane", projectId: projectId, remoteStateId: state.id, remoteStateName: state.name || state.id,
                        localStatus: localStatus, isOutbound: outbound })
                }
                const project = root.projects.filter(function(candidate) { return candidate.id === projectId })[0]
                const refreshed = Database.listProviderStateMappings(root.board.selectedWorkspaceId, "plane", projectId)
                root.stateRows = root.stateRows.filter(function(row) { return row.projectId !== projectId }).concat(refreshed.map(function(mapping) {
                    return { projectId: projectId, projectName: project ? (project.name || project.identifier || projectId) : projectId,
                        remoteStateId: mapping.remoteStateId, remoteStateName: mapping.remoteStateName,
                        localStatus: mapping.localStatus, isOutbound: mapping.isOutbound }
                }))
                root.message = i18n("Plane project metadata is ready. Review the state mappings before syncing.")
            }
        }
    }

    Component.onCompleted: refresh()
    onVisibleChanged: if (visible) refresh()
}
