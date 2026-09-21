import QtQuick
import "plane" as WorkbenchPlane
import "../code/Database.js" as Database

// Coordinates the optional native Plane transport with the provider-neutral
// LocalStorage records. Local writes always complete before this object starts
// an asynchronous request.
Item {
    id: root

    required property var board
    readonly property string planeExternalSource: "io.github.ownisticapps.worktodo"
    property var requests: ({})
    property var activeTasks: ({})
    signal syncFinished(string taskId, bool ok, string message)

    function remember(requestId, context) {
        const next = Object.assign({}, requests)
        next[requestId] = context
        requests = next
    }

    function claim(taskId) {
        if (activeTasks[taskId]) return false
        const next = Object.assign({}, activeTasks)
        next[taskId] = true
        activeTasks = next
        return true
    }

    function release(taskId) {
        const next = Object.assign({}, activeTasks)
        delete next[taskId]
        activeTasks = next
    }

    function configuration(workspaceId) {
        const binding = Database.getWorkspaceProvider(workspaceId)
        if (!binding || binding.provider !== "plane") return null
        const config = binding.config || ({})
        if (!binding.connectionId || !config.baseUrl || !config.workspace) return null
        return { connectionId: binding.connectionId, baseUrl: config.baseUrl, workspace: config.workspace,
            assigneeId: config.assigneeId || "" }
    }

    function projectForCategory(workspaceId, categoryId) {
        const mappings = Database.listProviderProjectMappings(workspaceId)
        for (let index = 0; index < mappings.length; ++index) {
            if (mappings[index].provider === "plane" && mappings[index].categoryId === categoryId) return mappings[index]
        }
        return null
    }

    function outboundState(workspaceId, projectId, status) {
        const mappings = Database.listProviderStateMappings(workspaceId, "plane", projectId)
        for (let index = 0; index < mappings.length; ++index) {
            if (mappings[index].localStatus === status && mappings[index].isOutbound) return mappings[index].remoteStateId
        }
        return ""
    }

    function htmlFor(details) {
        const escaped = String(details || "").replace(/&/g, "&amp;").replace(/</g, "&lt;")
            .replace(/>/g, "&gt;").replace(/\n/g, "<br>")
        return "<p>" + escaped + "</p>"
    }

    function fieldsFor(task, workspaceId, projectId, assigneeIds) {
        const state = outboundState(workspaceId, projectId, task.status)
        if (!state) throw new Error("Map an outbound Plane state for '" + task.status.replace("_", " ") + "' before syncing.")
        return { name: task.title, description_html: htmlFor(task.details), state: state, priority: task.priority,
            assignees: assigneeIds || [] }
    }

    function createFieldsFor(task, workspaceId, projectId, assigneeIds) {
        const fields = fieldsFor(task, workspaceId, projectId, assigneeIds)
        fields.external_source = planeExternalSource
        fields.external_id = task.id
        return fields
    }

    function hasRecoverableCreateBaseline(link) {
        return !!link && !!link.managedBaseline && Object.keys(link.managedBaseline).length > 0
    }

    function queueTask(taskId, workspaceId, assigneeIds) {
        if (!claim(taskId)) return
        const task = Database.getTask(taskId)
        if (!task) { release(taskId); return }
        const config = configuration(workspaceId)
        const project = projectForCategory(workspaceId, task.category_id)
        let link = Database.getTaskExternalLink(taskId)
        if ((!link || link.provider !== "plane") && (!config || !project)) { release(taskId); return }
        try {
            if (!config) throw new Error("Connect this workspace to Plane before syncing this task.")
            if (!project || (link && link.projectId && project.remoteProjectId !== link.projectId)) {
                throw new Error("This task's category is not mapped to its Plane project.")
            }
            let fields
            if (!link) {
                fields = fieldsFor(task, workspaceId, project.remoteProjectId, assigneeIds || [])
                link = Database.updateTaskExternalLink({ taskId: taskId, provider: "plane", projectId: project.remoteProjectId,
                    assigneeIds: assigneeIds || [], managedBaseline: managedBaselineForRemote(fields), syncState: "pending_create" })
            } else if (assigneeIds !== undefined) {
                link = Database.updateTaskExternalLink({ taskId: taskId, assigneeIds: assigneeIds, syncState: link.remoteId ? "pending_push" : "pending_create", syncError: null })
            }
            if (!fields) fields = fieldsFor(task, workspaceId, project.remoteProjectId, link.assigneeIds)
            if (!link.remoteId) {
                if (!hasRecoverableCreateBaseline(link)) {
                    const message = "This pending Plane creation predates recoverable create tracking. Link it to the existing Plane work item before retrying."
                    Database.markPending(taskId, "error", message)
                    release(taskId)
                    syncFinished(taskId, false, message)
                    return
                }
                const requestId = WorkbenchPlane.PlaneSync.findWorkItemsByExternalReference(config.connectionId, config.baseUrl,
                    config.workspace, project.remoteProjectId, planeExternalSource, task.id)
                remember(requestId, { kind: "resolvePendingCreate", taskId: taskId, workspaceId: workspaceId,
                    projectId: project.remoteProjectId, fields: fields })
                return
            }
            const requestId = WorkbenchPlane.PlaneSync.fetchWorkItem(config.connectionId, config.baseUrl, config.workspace,
                link.projectId, link.remoteId)
            remember(requestId, { kind: "fetchBeforePush", taskId: taskId, workspaceId: workspaceId, projectId: link.projectId,
                remoteId: link.remoteId, fields: fields })
        } catch (error) {
            Database.markPending(taskId, link && link.remoteId ? "error" : "pending_create", error.message)
            release(taskId)
            syncFinished(taskId, false, error.message)
        }
    }

    function ids(value) {
        const values = Array.isArray(value) ? value
            : (value && typeof value.length === "number" ? Array.from(value) : [])
        return values.map(function(item) { return typeof item === "string" ? item : item.id }).filter(function(id) { return !!id }).sort()
    }

    function managedBaselineForRemote(remote) {
        const state = remote.state && typeof remote.state === "object" ? remote.state.id : remote.state
        return { name: remote.name || "", descriptionHtml: remote.description_html || "", state: state || "",
            priority: remote.priority || "none", assignees: ids(remote.assignees) }
    }

    function sameBaseline(left, right) {
        return JSON.stringify(left || {}) === JSON.stringify(right || {})
    }

    function completeSuccess(context, remote, notify) {
        const link = Database.getTaskExternalLink(context.taskId)
        const project = remote.project && typeof remote.project === "object" ? remote.project.id : (remote.project || context.projectId)
        const key = remote.identifier || remote.key || (link ? link.remoteKey : "")
        const url = key ? "https://app.plane.so/" + configuration(context.workspaceId).workspace + "/browse/" + key + "/" : (link ? link.remoteUrl : "")
        Database.updateTaskExternalLink({ taskId: context.taskId, provider: "plane", remoteId: remote.id || context.remoteId,
            remoteKey: key, remoteUrl: url, projectId: project, remoteUpdatedAt: remoteTime(remote.updated_at),
            assigneeIds: ids(remote.assignees), managedBaseline: managedBaselineForRemote(remote), remotePayload: remote,
            lastSyncedAt: new Date().toISOString(), syncState: "in_sync", syncError: null })
        if (notify !== false) syncFinished(context.taskId, true, "")
    }

    function remoteTime(value) {
        const timestamp = Date.parse(value || "")
        return isNaN(timestamp) ? null : new Date(timestamp).toISOString()
    }

    function forcePush(taskId, workspaceId) {
        if (!claim(taskId)) return
        const link = Database.getTaskExternalLink(taskId)
        const task = Database.getTask(taskId)
        const config = configuration(workspaceId)
        if (!link || !link.remoteId || !task || !config) { release(taskId); return }
        try {
            const requestId = WorkbenchPlane.PlaneSync.updateWorkItem(config.connectionId, config.baseUrl, config.workspace,
                link.projectId, link.remoteId, fieldsFor(task, workspaceId, link.projectId, link.assigneeIds))
            remember(requestId, { kind: "push", taskId: taskId, workspaceId: workspaceId, projectId: link.projectId, remoteId: link.remoteId })
        } catch (error) {
            Database.markPending(taskId, "error", error.message)
            release(taskId)
            syncFinished(taskId, false, error.message)
        }
    }

    function localStatusForRemote(workspaceId, projectId, remoteState) {
        const stateId = remoteState && typeof remoteState === "object" ? remoteState.id : remoteState
        const mappings = Database.listProviderStateMappings(workspaceId, "plane", projectId)
        for (let index = 0; index < mappings.length; ++index) {
            if (mappings[index].remoteStateId === stateId) return mappings[index].localStatus
        }
        return ""
    }

    function refreshTask(taskId, workspaceId) {
        const link = Database.getTaskExternalLink(taskId)
        const config = configuration(workspaceId)
        if (!link || link.provider !== "plane" || !link.remoteId || !config) return
        const request = WorkbenchPlane.PlaneSync.fetchWorkItem(config.connectionId, config.baseUrl, config.workspace,
            link.projectId, link.remoteId)
        remember(request, { kind: "refresh", taskId: taskId, workspaceId: workspaceId, projectId: link.projectId,
            remoteId: link.remoteId })
    }

    function syncWorkspace(workspaceId) {
        const config = configuration(workspaceId)
        if (!config || !config.assigneeId) {
            syncFinished("", false, "Enter the Plane assignee ID in integration settings before pulling assigned work.")
            return
        }
        const request = WorkbenchPlane.PlaneSync.pullAssigned(config.connectionId, config.baseUrl, config.workspace,
            config.assigneeId)
        remember(request, { kind: "batch", workspaceId: workspaceId })
    }

    function syncRemoteItem(workspaceId, remote) {
        const remoteId = remote.id || ""
        if (!remoteId) return
        const projectId = remote.project && typeof remote.project === "object" ? remote.project.id : remote.project
        const mappings = Database.listProviderProjectMappings(workspaceId)
        let categoryId = ""
        for (let index = 0; index < mappings.length; ++index) {
            if (mappings[index].provider === "plane" && mappings[index].remoteProjectId === projectId) {
                categoryId = mappings[index].categoryId
                break
            }
        }
        if (!categoryId) return
        const links = Database.listProviderTaskLinks(workspaceId, "plane")
        let link = null
        for (let index = 0; index < links.length; ++index) {
            if (links[index].remoteId === remoteId) { link = links[index]; break }
        }
        const status = localStatusForRemote(workspaceId, projectId, remote.state)
        if (!status) return
        if (!link) {
            const task = Database.createTask({ categoryId: categoryId, title: remote.name || "Plane work item",
                details: remote.description_stripped || "", status: status, priority: remote.priority || "none" })
            completeSuccess({ taskId: task.id, workspaceId: workspaceId, projectId: projectId, remoteId: remoteId }, remote)
            return
        }
        const task = Database.getTask(link.taskId)
        if (!task) return
        if (link.syncState !== "in_sync" || task.updated_at_utc !== link.lastLocalUpdatedAt) {
            Database.markPending(link.taskId, "conflict", "Plane changed while local changes are pending.")
            return
        }
        Database.saveTask({ id: task.id, title: remote.name || task.title, details: remote.description_stripped || "",
            categoryId: categoryId, status: status, priority: remote.priority || "none" })
        completeSuccess({ taskId: task.id, workspaceId: workspaceId, projectId: projectId, remoteId: remoteId }, remote)
    }

    Connections {
        target: WorkbenchPlane.PlaneSync
        function onCompleted(requestId, result) {
            const context = root.requests[requestId]
            if (!context) return
            const next = Object.assign({}, root.requests)
            delete next[requestId]
            root.requests = next
            if (!result.ok) {
                Database.markPending(context.taskId, context.kind === "create" || context.kind === "resolvePendingCreate"
                    ? "pending_create" : "error", result.error)
                root.release(context.taskId)
                root.syncFinished(context.taskId, false, result.error)
                return
            }
            const remote = result.data || ({})
            if (context.kind === "batch") {
                const items = Array.isArray(remote) ? remote
                    : (remote && typeof remote.length === "number" ? Array.from(remote) : [])
                for (let index = 0; index < items.length; ++index) root.syncRemoteItem(context.workspaceId, items[index])
                if (result.hasMore && result.nextCursor) {
                    const config = root.configuration(context.workspaceId)
                    if (config) {
                        const request = WorkbenchPlane.PlaneSync.pullAssigned(config.connectionId, config.baseUrl,
                            config.workspace, config.assigneeId, result.nextCursor)
                        root.remember(request, { kind: "batch", workspaceId: context.workspaceId })
                        return
                    }
                }
                root.syncFinished("", true, "Plane linked tasks synchronized.")
                return
            }
            if (context.kind === "resolvePendingCreate") {
                const matches = Array.isArray(remote) ? remote
                    : (remote && typeof remote.length === "number" ? Array.from(remote) : [])
                if (matches.length > 1) {
                    const message = "More than one Plane work item has this Workbench external reference. Resolve the duplicate before retrying."
                    Database.markPending(context.taskId, "conflict", message)
                    root.release(context.taskId)
                    root.syncFinished(context.taskId, false, message)
                    return
                }
                if (matches.length === 1) {
                    const found = matches[0]
                    const link = Database.getTaskExternalLink(context.taskId)
                    if (!found.id) {
                        const message = "Plane returned an invalid work item while resolving a pending creation."
                        Database.markPending(context.taskId, "pending_create", message)
                        root.release(context.taskId)
                        root.syncFinished(context.taskId, false, message)
                        return
                    }
                    if (!link || !root.sameBaseline(root.managedBaselineForRemote(found), link.managedBaseline)) {
                        const message = "The recovered Plane work item changed since its original creation. Resolve the conflict before retrying."
                        Database.markPending(context.taskId, "conflict", message)
                        root.release(context.taskId)
                        root.syncFinished(context.taskId, false, message)
                        return
                    }
                    root.completeSuccess(context, found, false)
                    const config = root.configuration(context.workspaceId)
                    if (!config) {
                        const message = "Connect this workspace to Plane before syncing this task."
                        Database.markPending(context.taskId, "error", message)
                        root.release(context.taskId)
                        root.syncFinished(context.taskId, false, message)
                        return
                    }
                    const request = WorkbenchPlane.PlaneSync.updateWorkItem(config.connectionId, config.baseUrl, config.workspace,
                        context.projectId, found.id, context.fields)
                    root.remember(request, { kind: "push", taskId: context.taskId, workspaceId: context.workspaceId,
                        projectId: context.projectId, remoteId: found.id })
                    return
                }
                const config = root.configuration(context.workspaceId)
                if (!config) {
                    const message = "Connect this workspace to Plane before syncing this task."
                    Database.markPending(context.taskId, "pending_create", message)
                    root.release(context.taskId)
                    root.syncFinished(context.taskId, false, message)
                    return
                }
                const task = Database.getTask(context.taskId)
                if (!task) { root.release(context.taskId); return }
                const request = WorkbenchPlane.PlaneSync.createWorkItem(config.connectionId, config.baseUrl, config.workspace,
                    context.projectId, root.createFieldsFor(task, context.workspaceId, context.projectId,
                        Database.getTaskExternalLink(context.taskId).assigneeIds))
                root.remember(request, { kind: "create", taskId: context.taskId, workspaceId: context.workspaceId,
                    projectId: context.projectId })
                return
            }
            if (context.kind === "fetchBeforePush") {
                const link = Database.getTaskExternalLink(context.taskId)
                if (link && !root.sameBaseline(root.managedBaselineForRemote(remote), link.managedBaseline)) {
                    Database.markPending(context.taskId, "conflict", "Plane changed since the last sync.")
                    root.release(context.taskId)
                    root.syncFinished(context.taskId, false, "Plane changed since the last sync.")
                    return
                }
                const config = root.configuration(context.workspaceId)
                const request = WorkbenchPlane.PlaneSync.updateWorkItem(config.connectionId, config.baseUrl, config.workspace,
                    context.projectId, context.remoteId, context.fields)
                root.remember(request, { kind: "push", taskId: context.taskId, workspaceId: context.workspaceId,
                    projectId: context.projectId, remoteId: context.remoteId })
                return
            }
            if (context.kind === "refresh") {
                const link = Database.getTaskExternalLink(context.taskId)
                if (!link || link.syncState !== "in_sync") {
                    Database.markPending(context.taskId, "conflict", "Refresh found remote changes while local changes are pending.")
                    root.release(context.taskId)
                    root.syncFinished(context.taskId, false, "Refresh found remote changes while local changes are pending.")
                    return
                }
                const task = Database.getTask(context.taskId)
                const status = root.localStatusForRemote(context.workspaceId, context.projectId, remote.state)
                if (!task || !status) {
                    Database.markPending(context.taskId, "error", "Map this Plane state before refreshing the task.")
                    root.release(context.taskId)
                    root.syncFinished(context.taskId, false, "Map this Plane state before refreshing the task.")
                    return
                }
                Database.saveTask({ id: context.taskId, title: remote.name || task.title,
                    details: remote.description_stripped || "", categoryId: task.category_id, status: status,
                    priority: remote.priority || "none" })
                root.completeSuccess(context, remote)
                return
            }
            root.completeSuccess(context, remote)
            root.release(context.taskId)
        }
    }
}
