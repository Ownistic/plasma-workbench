import QtQuick
import QtTest
import "../../package/contents/ui/plane" as WorkbenchPlane

import "../../package/contents/ui" as WorkbenchUi
import "../../package/contents/ui/time" as WorkbenchTime
import "../../package/contents/code/Database.js" as Database

TestCase {
    name: "PlaneIntegration"

    property int databaseNumber: 0
    property var integration: null

    Item { id: board }

    Component {
        id: integrationComponent
        WorkbenchUi.PlaneIntegration { board: board }
    }

    SignalSpy {
        id: finished
        target: integration
        signalName: "syncFinished"
    }

    SignalSpy {
        id: planeCompleted
        target: WorkbenchPlane.PlaneSync
        signalName: "completed"
    }

    function init() {
        if (typeof WorkbenchPlane.PlaneSync.setTokenForTests !== "function")
            skip("Plane test adapters are disabled for this build")

        databaseNumber += 1
        Database.configureDatabaseForTests("workbench-plane-integration-" + Date.now() + "-" + databaseNumber)
        Database.setTimeZoneValidator(function(timezoneId) {
            return WorkbenchTime.TimeMath.isValidTimeZone(timezoneId)
        })
        Database.initialize()
        integration = createTemporaryObject(integrationComponent, board)
        verify(integration !== null)
        finished.clear()
        planeCompleted.clear()
    }

    function cleanup() {
        if (integration) {
            integration.destroy()
            integration = null
        }
    }

    function configureWorkspace() {
        const workspace = Database.listWorkspaces()[0]
        const category = Database.createCategory({ workspaceId: workspace.id, name: "Remote", color: "#3daee9" })
        Database.setWorkspaceProvider({ workspaceId: workspace.id, provider: "plane", connectionId: "test-connection",
            config: { baseUrl: "https://plane.example", workspace: "test-workspace", assigneeId: "member-1" } })
        Database.saveProviderProjectMapping({ workspaceId: workspace.id, categoryId: category.id, provider: "plane",
            remoteProjectId: "project-1", remoteProjectName: "Project" })
        Database.saveProviderStateMapping({ workspaceId: workspace.id, provider: "plane", projectId: "project-1",
            remoteStateId: "state-ready", remoteStateName: "Ready", localStatus: "ready", isOutbound: true })
        return { workspace: workspace, category: category }
    }

    function createLinkedTask(fixture, title) {
        const task = Database.createTask({ categoryId: fixture.category.id, title: title, details: "Local details", status: "ready" })
        Database.updateTaskExternalLink({ taskId: task.id, provider: "plane", remoteId: "remote-3", remoteKey: "PROJ-3",
            projectId: "project-1", assigneeIds: [], managedBaseline: { name: title, descriptionHtml: "<p>Local details</p>",
                state: "state-ready", priority: "none", assignees: [] }, remotePayload: {}, syncState: "in_sync" })
        return task
    }

    function test_queueCreatesAndLinksRemoteWorkItem() {
        const fixture = configureWorkspace()
        const task = Database.createTask({ categoryId: fixture.category.id, title: "Local title", details: "A < B", status: "ready", priority: "high" })
        WorkbenchPlane.PlaneSync.setTokenForTests("test-connection", "test-token")
        WorkbenchPlane.PlaneSync.setResponseQueueForTests([
            { networkError: 0, status: 200, body: '{"results":[]}' },
            { networkError: 0, status: 201,
                body: '{"id":"remote-1","identifier":"PROJ-1","project":{"id":"project-1"},"name":"Local title",' +
                    '"description_html":"<p>A &lt; B</p>","state":{"id":"state-ready"},"priority":"high","assignees":[{"id":"member-1"}],' +
                    '"updated_at":"2026-09-21T12:00:00.000Z"}' }
        ])

        integration.queueTask(task.id, fixture.workspace.id, ["member-1"])

        tryCompare(finished, "count", 1, 1000)
        compare(finished.signalArguments[0][0], task.id)
        verify(finished.signalArguments[0][1])
        const link = Database.getTaskExternalLink(task.id)
        compare(link.remoteId, "remote-1")
        compare(link.remoteKey, "PROJ-1")
        compare(link.projectId, "project-1")
        compare(link.syncState, "in_sync")
        compare(link.assigneeIds, ["member-1"])
        compare(link.managedBaseline.state, "state-ready")
        compare(link.managedBaseline.priority, "high")
        compare(Database.getTask(task.id).priority, "high")
        verify(link.remoteUrl.indexOf("PROJ-1") >= 0)
        compare(planeCompleted.count, 2)
        compare(planeCompleted.signalArguments[0][1].operation, "externalReference")
        compare(planeCompleted.signalArguments[1][1].operation, "create")
    }

    function test_pendingCreateRecoversRemoteWorkItemBeforeRetryingCreate() {
        const fixture = configureWorkspace()
        const task = Database.createTask({ categoryId: fixture.category.id, title: "Local title", details: "Local details",
            status: "ready", priority: "medium" })
        Database.updateTaskExternalLink({ taskId: task.id, provider: "plane", projectId: "project-1", assigneeIds: [],
            managedBaseline: { name: "Local title", descriptionHtml: "<p>Local details</p>", state: "state-ready",
                priority: "none", assignees: [] }, syncState: "pending_create" })
        WorkbenchPlane.PlaneSync.setTokenForTests("test-connection", "test-token")
        WorkbenchPlane.PlaneSync.setResponseQueueForTests([
            { networkError: 0, status: 200,
                body: '{"results":[{"id":"remote-recovered","identifier":"PROJ-9","project":{"id":"project-1"},' +
                    '"name":"Local title","description_html":"<p>Local details</p>","state":{"id":"state-ready"},' +
                    '"priority":"none","assignees":[],"external_source":"io.github.ownisticapps.worktodo",' +
                    '"external_id":"' + task.id + '"}]}' },
            { networkError: 0, status: 200,
                body: '{"id":"remote-recovered","identifier":"PROJ-9","project":{"id":"project-1"},' +
                    '"name":"Local title","description_html":"<p>Local details</p>","state":{"id":"state-ready"},' +
                    '"priority":"medium","assignees":[],"updated_at":"2026-09-21T12:00:00.000Z"}' }
        ])

        integration.queueTask(task.id, fixture.workspace.id)

        tryCompare(finished, "count", 1, 1000)
        verify(finished.signalArguments[0][1])
        const link = Database.getTaskExternalLink(task.id)
        compare(link.remoteId, "remote-recovered")
        compare(link.syncState, "in_sync")
        compare(link.managedBaseline.priority, "medium")
        compare(planeCompleted.count, 2)
        compare(planeCompleted.signalArguments[0][1].operation, "externalReference")
        compare(planeCompleted.signalArguments[1][1].operation, "update")
    }

    function test_legacyPendingCreateDoesNotPostAnotherRemoteWorkItem() {
        const fixture = configureWorkspace()
        const task = Database.createTask({ categoryId: fixture.category.id, title: "Legacy pending", status: "ready" })
        Database.updateTaskExternalLink({ taskId: task.id, provider: "plane", projectId: "project-1", assigneeIds: [],
            syncState: "pending_create" })

        integration.queueTask(task.id, fixture.workspace.id)

        tryCompare(finished, "count", 1, 1000)
        verify(!finished.signalArguments[0][1])
        verify(finished.signalArguments[0][2].indexOf("predates recoverable") >= 0)
        compare(planeCompleted.count, 0)
        const link = Database.getTaskExternalLink(task.id)
        compare(link.syncState, "error")
    }

    function test_ambiguousRecoveredCreateDoesNotPostAnotherRemoteWorkItem() {
        const fixture = configureWorkspace()
        const task = Database.createTask({ categoryId: fixture.category.id, title: "Ambiguous pending", status: "ready" })
        Database.updateTaskExternalLink({ taskId: task.id, provider: "plane", projectId: "project-1", assigneeIds: [],
            managedBaseline: { name: "Ambiguous pending", descriptionHtml: "<p></p>", state: "state-ready",
                priority: "none", assignees: [] }, syncState: "pending_create" })
        WorkbenchPlane.PlaneSync.setTokenForTests("test-connection", "test-token")
        WorkbenchPlane.PlaneSync.setResponseForTests(0, 200,
            '{"results":[{"id":"remote-a"},{"id":"remote-b"}]}')

        integration.queueTask(task.id, fixture.workspace.id)

        tryCompare(finished, "count", 1, 1000)
        verify(!finished.signalArguments[0][1])
        verify(finished.signalArguments[0][2].indexOf("More than one") >= 0)
        compare(planeCompleted.count, 1)
        compare(planeCompleted.signalArguments[0][1].operation, "externalReference")
        const link = Database.getTaskExternalLink(task.id)
        compare(link.syncState, "conflict")
    }

    function test_workspacePullCreatesMappedRemoteWorkItem() {
        const fixture = configureWorkspace()
        WorkbenchPlane.PlaneSync.setTokenForTests("test-connection", "test-token")
        WorkbenchPlane.PlaneSync.setResponseForTests(0, 200,
            '{"results":[{"id":"remote-2","identifier":"PROJ-2","project":{"id":"project-1"},' +
            '"name":"Remote title","description_stripped":"Imported details","state":{"id":"state-ready"},"priority":"urgent",' +
            '"assignees":[{"id":"member-1"}],"updated_at":"2026-09-21T12:00:00.000Z"}],"next_page_results":false}')

        integration.syncWorkspace(fixture.workspace.id)

        tryCompare(finished, "count", 2, 1000)
        verify(finished.signalArguments[0][1])
        compare(finished.signalArguments[1][0], "")
        verify(finished.signalArguments[1][1])
        const tasks = Database.listTasks({ workspaceId: fixture.workspace.id })
        compare(tasks.length, 1)
        compare(tasks[0].title, "Remote title")
        compare(tasks[0].details, "Imported details")
        compare(tasks[0].status, "ready")
        compare(tasks[0].priority, "urgent")
        const link = Database.getTaskExternalLink(tasks[0].taskId)
        compare(link.remoteId, "remote-2")
        compare(link.syncState, "in_sync")
        compare(link.assigneeIds, ["member-1"])
    }

    function test_queueMarksConflictWhenRemoteChangedSinceBaseline() {
        const fixture = configureWorkspace()
        const task = createLinkedTask(fixture, "Local title")
        WorkbenchPlane.PlaneSync.setTokenForTests("test-connection", "test-token")
        WorkbenchPlane.PlaneSync.setResponseForTests(0, 200,
            '{"id":"remote-3","identifier":"PROJ-3","project":{"id":"project-1"},"name":"Changed remotely",' +
            '"description_html":"<p>Local details</p>","state":{"id":"state-ready"},"assignees":[]}')

        integration.queueTask(task.id, fixture.workspace.id)

        tryCompare(finished, "count", 1, 1000)
        compare(finished.signalArguments[0][0], task.id)
        verify(!finished.signalArguments[0][1])
        verify(finished.signalArguments[0][2].indexOf("changed since") >= 0)
        const link = Database.getTaskExternalLink(task.id)
        compare(link.syncState, "conflict")
        verify(link.syncError.indexOf("changed since") >= 0)
    }

    function test_forcePushUpdatesExistingRemoteWorkItem() {
        const fixture = configureWorkspace()
        const task = createLinkedTask(fixture, "Local title")
        WorkbenchPlane.PlaneSync.setTokenForTests("test-connection", "test-token")
        WorkbenchPlane.PlaneSync.setResponseForTests(0, 200,
            '{"id":"remote-3","identifier":"PROJ-3","project":{"id":"project-1"},"name":"Local title",' +
            '"description_html":"<p>Local details</p>","state":{"id":"state-ready"},"assignees":[],' +
            '"updated_at":"2026-09-21T13:00:00.000Z"}')

        integration.forcePush(task.id, fixture.workspace.id)

        tryCompare(finished, "count", 1, 1000)
        compare(finished.signalArguments[0][0], task.id)
        verify(finished.signalArguments[0][1])
        const link = Database.getTaskExternalLink(task.id)
        compare(link.remoteId, "remote-3")
        compare(link.syncState, "in_sync")
        compare(link.managedBaseline.name, "Local title")
    }

    function test_createFailureRetainsPendingLinkAndRedactsCredential() {
        const fixture = configureWorkspace()
        const task = Database.createTask({ categoryId: fixture.category.id, title: "Local title", status: "ready" })
        WorkbenchPlane.PlaneSync.setTokenForTests("test-connection", "test-token-must-not-escape")
        WorkbenchPlane.PlaneSync.setResponseForTests(0, 403, '{"detail":"token rejected"}', "Access denied")

        integration.queueTask(task.id, fixture.workspace.id, [])

        tryCompare(finished, "count", 1, 1000)
        compare(finished.signalArguments[0][0], task.id)
        verify(!finished.signalArguments[0][1])
        verify(finished.signalArguments[0][2].indexOf("token rejected") >= 0)
        verify(finished.signalArguments[0][2].indexOf("test-token-must-not-escape") < 0)
        const link = Database.getTaskExternalLink(task.id)
        compare(link.syncState, "pending_create")
        verify(link.syncError.indexOf("token rejected") >= 0)
    }

    function test_workspacePullFollowsCursorUntilAllPagesAreImported() {
        const fixture = configureWorkspace()
        WorkbenchPlane.PlaneSync.setTokenForTests("test-connection", "test-token")
        WorkbenchPlane.PlaneSync.setResponseQueueForTests([
            { networkError: 0, status: 200,
                body: '{"results":[{"id":"remote-page-1","identifier":"PROJ-11","project":{"id":"project-1"},' +
                    '"name":"First page","state":{"id":"state-ready"},"assignees":[]}],"next_cursor":"cursor-2","next_page_results":true}' },
            { networkError: 0, status: 200,
                body: '{"results":[{"id":"remote-page-2","identifier":"PROJ-12","project":{"id":"project-1"},' +
                    '"name":"Second page","state":{"id":"state-ready"},"assignees":[]}],"next_page_results":false}' }
        ])

        integration.syncWorkspace(fixture.workspace.id)

        tryCompare(finished, "count", 3, 1000)
        compare(finished.signalArguments[2][0], "")
        verify(finished.signalArguments[2][1])
        const tasks = Database.listTasks({ workspaceId: fixture.workspace.id })
        compare(tasks.length, 2)
        compare(tasks[0].title, "First page")
        compare(tasks[1].title, "Second page")
        compare(Database.listProviderTaskLinks(fixture.workspace.id, "plane").length, 2)
    }

    function test_refreshUpdatesSynchronizedLocalTaskFromMappedRemoteState() {
        const fixture = configureWorkspace()
        const task = createLinkedTask(fixture, "Old title")
        WorkbenchPlane.PlaneSync.setTokenForTests("test-connection", "test-token")
        WorkbenchPlane.PlaneSync.setResponseForTests(0, 200,
            '{"id":"remote-3","identifier":"PROJ-3","project":{"id":"project-1"},"name":"Refreshed title",' +
            '"description_stripped":"Refreshed details","state":{"id":"state-ready"},"priority":"low","assignees":[{"id":"member-1"}],' +
            '"updated_at":"2026-09-21T14:00:00.000Z"}')

        integration.refreshTask(task.id, fixture.workspace.id)

        tryCompare(finished, "count", 1, 1000)
        compare(finished.signalArguments[0][0], task.id)
        verify(finished.signalArguments[0][1])
        const refreshed = Database.getTask(task.id)
        compare(refreshed.title, "Refreshed title")
        compare(refreshed.details, "Refreshed details")
        compare(refreshed.status, "ready")
        compare(refreshed.priority, "low")
        const link = Database.getTaskExternalLink(task.id)
        compare(link.syncState, "in_sync")
        compare(link.assigneeIds, ["member-1"])
    }

    function test_workspacePullRejectsMissingAssigneeWithoutMutatingTasks() {
        const workspace = Database.listWorkspaces()[0]
        Database.setWorkspaceProvider({ workspaceId: workspace.id, provider: "plane", connectionId: "test-connection",
            config: { baseUrl: "https://plane.example", workspace: "test-workspace" } })

        integration.syncWorkspace(workspace.id)

        tryCompare(finished, "count", 1, 1000)
        compare(finished.signalArguments[0][0], "")
        verify(!finished.signalArguments[0][1])
        verify(finished.signalArguments[0][2].indexOf("assignee ID") >= 0)
        compare(Database.listTasks({ workspaceId: workspace.id }).length, 0)
        compare(Database.listProviderTaskLinks(workspace.id, "plane").length, 0)
    }
}
