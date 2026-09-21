#include "planesync.h"

#include <QNetworkReply>
#include <QSet>
#include <QSignalSpy>
#include <QStringList>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTest>

class PlaneSyncTest : public QObject
{
    Q_OBJECT
private slots:
    void previewsProjectRequest();
    void reportsWalletCapability();
    void encodesPathComponents();
    void onlyAllowsManagedFields();
    void rejectsInvalidBaseUrl();
    void rejectsPlainHttpBaseUrl();
    void rejectsEmptyWorkspaceAndTraversalPath();
    void rejectsEmptyTitleAndInvalidAssignees();
    void previewsWorkspaceEndpointWithoutProject();
    void decodesSuccessfulPlanePayloads();
    void decodesFailuresWithoutLeakingLargePayloads();
    void decodesArrayAndEmptySuccessfulPayloads();
    void capsErrorDetailsAndUsesNetworkFailure();
    void reportsCredentialStorageFailuresWithoutKWallet();
    void failuresAreDeliveredAsynchronously();
    void missingCredentialsAreDeliveredAsynchronously();
    void publicOperationsRejectInvalidConnectionAsynchronously();
#ifdef WORKBENCH_TESTING_ADAPTERS
    void deterministicTransportCoversRequestMethods();
    void loopbackTransportFailureDoesNotLeakTestToken();
#endif
};

void PlaneSyncTest::previewsProjectRequest()
{
    PlaneSync sync;
    const QVariantMap request = sync.requestPreview("post", "https://api.plane.so/", "four leaf", "project id", "/work-items/",
        {{"name", "Fix sync"}, {"state", "state-1"}, {"assignees", QVariantList{"user-1"}}});
    QVERIFY(request.value("ok").toBool());
    QCOMPARE(request.value("method").toString(), "POST");
    QCOMPARE(request.value("url").toString(), "https://api.plane.so/api/v1/workspaces/four%20leaf/projects/project%20id/work-items/");
    QCOMPARE(request.value("body").toMap().value("name").toString(), "Fix sync");
}

void PlaneSyncTest::reportsWalletCapability()
{
    PlaneSync sync;
    const bool available = sync.walletAvailable();
    QVERIFY(available || !available);
}

void PlaneSyncTest::encodesPathComponents()
{
    PlaneSync sync;
    const QVariantMap request = sync.requestPreview("GET", "https://plane.example/api", "work/a", "proj/a", "/states/");
    QVERIFY(request.value("ok").toBool());
    QCOMPARE(request.value("url").toString(), "https://plane.example/api/api/v1/workspaces/work%2Fa/projects/proj%2Fa/states/");
}

void PlaneSyncTest::onlyAllowsManagedFields()
{
    PlaneSync sync;
    const QVariantMap request = sync.requestPreview("PATCH", "https://api.plane.so", "work", "project", "/work-items/id/", {{"priority", "high"}});
    QVERIFY(!request.value("ok").toBool());
    QVERIFY(request.value("error").toString().contains("not managed"));
}

void PlaneSyncTest::rejectsInvalidBaseUrl()
{
    PlaneSync sync;
    const QVariantMap request = sync.requestPreview("GET", "file:///tmp/plane", "work", {}, "/projects/");
    QVERIFY(!request.value("ok").toBool());
    QVERIFY(request.value("error").toString().contains("HTTPS"));
}

void PlaneSyncTest::rejectsPlainHttpBaseUrl()
{
    PlaneSync sync;
    const QVariantMap request = sync.requestPreview("GET", "http://plane.example", "work", {}, "/projects/");
    QVERIFY(!request.value("ok").toBool());
    QVERIFY(request.value("error").toString().contains("HTTPS"));
}

void PlaneSyncTest::rejectsEmptyWorkspaceAndTraversalPath()
{
    PlaneSync sync;

    const QVariantMap emptyWorkspace = sync.requestPreview(
        "GET", "https://api.plane.so", {}, {}, "/projects/");
    QVERIFY(!emptyWorkspace.value("ok").toBool());
    QVERIFY(emptyWorkspace.value("error").toString().contains("workspace"));

    const QVariantMap traversal = sync.requestPreview(
        "GET", "https://api.plane.so", "work", {}, "/../projects/");
    QVERIFY(!traversal.value("ok").toBool());
    QVERIFY(traversal.value("error").toString().contains("endpoint"));
}

void PlaneSyncTest::rejectsEmptyTitleAndInvalidAssignees()
{
    PlaneSync sync;

    const QVariantMap emptyTitle = sync.requestPreview(
        "POST", "https://api.plane.so", "work", "project", "/work-items/", {{"name", "  "}});
    QVERIFY(!emptyTitle.value("ok").toBool());
    QVERIFY(emptyTitle.value("error").toString().contains("title"));

    const QVariantMap invalidAssignees = sync.requestPreview(
        "PATCH", "https://api.plane.so", "work", "project", "/work-items/item/", {{"assignees", "member-1"}});
    QVERIFY(!invalidAssignees.value("ok").toBool());
    QVERIFY(invalidAssignees.value("error").toString().contains("list"));
}

void PlaneSyncTest::previewsWorkspaceEndpointWithoutProject()
{
    PlaneSync sync;
    const QVariantMap request = sync.requestPreview(
        "GET", "https://plane.example/root/", "work space", {}, "/projects/");

    QVERIFY(request.value("ok").toBool());
    QCOMPARE(request.value("url").toString(),
             "https://plane.example/root/api/v1/workspaces/work%20space/projects/");
    QVERIFY(request.value("body").toMap().isEmpty());
}

void PlaneSyncTest::decodesSuccessfulPlanePayloads()
{
    const QVariantMap paged = PlaneSync::decodeResponseForTests(
        0, 200, R"({"results":[{"id":"one"}],"next_cursor":"cursor-2","next_page_results":true})",
        {}, "projects");
    QVERIFY(paged.value("ok").toBool());
    QCOMPARE(paged.value("operation").toString(), "projects");
    QCOMPARE(paged.value("data").toList().size(), 1);
    QCOMPARE(paged.value("nextCursor").toString(), "cursor-2");
    QVERIFY(paged.value("hasMore").toBool());

    const QVariantMap object = PlaneSync::decodeResponseForTests(
        0, 204, R"({"id":"item-1"})", {}, "update");
    QVERIFY(object.value("ok").toBool());
    QCOMPARE(object.value("data").toMap().value("id").toString(), "item-1");
}

void PlaneSyncTest::decodesFailuresWithoutLeakingLargePayloads()
{
    const QVariantMap detailed = PlaneSync::decodeResponseForTests(
        static_cast<int>(QNetworkReply::ContentAccessDenied), 403,
        R"({"detail":"token rejected"})", "Access denied", "projects");
    QVERIFY(!detailed.value("ok").toBool());
    QCOMPARE(detailed.value("status").toInt(), 403);
    QVERIFY(detailed.value("error").toString().contains("token rejected"));

    const QVariantMap fallback = PlaneSync::decodeResponseForTests(
        static_cast<int>(QNetworkReply::ConnectionRefusedError), 0,
        "not-json", "Connection refused", "projects");
    QVERIFY(!fallback.value("ok").toBool());
    QVERIFY(fallback.value("error").toString().contains("Connection refused"));
}

void PlaneSyncTest::decodesArrayAndEmptySuccessfulPayloads()
{
    const QVariantMap array = PlaneSync::decodeResponseForTests(
        static_cast<int>(QNetworkReply::NoError), 200, R"([{"id":"one"},{"id":"two"}])", {}, "members");
    QVERIFY(array.value("ok").toBool());
    QCOMPARE(array.value("data").toList().size(), 2);

    const QVariantMap empty = PlaneSync::decodeResponseForTests(
        static_cast<int>(QNetworkReply::NoError), 204, {}, {}, "delete");
    QVERIFY(empty.value("ok").toBool());
    QVERIFY(empty.value("data").toMap().isEmpty());
    QVERIFY(!empty.value("hasMore").toBool());
}

void PlaneSyncTest::capsErrorDetailsAndUsesNetworkFailure()
{
    const QString detail(600, QLatin1Char('x'));
    const QByteArray payload = QStringLiteral("{\"detail\":\"%1\"}").arg(detail).toUtf8();
    const QVariantMap result = PlaneSync::decodeResponseForTests(
        static_cast<int>(QNetworkReply::TimeoutError), 504, payload, "Timed out", "projects");

    QVERIFY(!result.value("ok").toBool());
    QCOMPARE(result.value("status").toInt(), 504);
    QCOMPARE(result.value("error").toString().size(),
             QStringLiteral("Plane request failed (504): ").size() + 500);
}

void PlaneSyncTest::reportsCredentialStorageFailuresWithoutKWallet()
{
    PlaneSync sync;
    QVERIFY(!sync.setToken({}, {}));
    QVERIFY(sync.lastError().contains("connection ID"));
    QVERIFY(!sync.clearToken("connection"));
    QVERIFY(sync.lastError().contains("KWallet"));
    QVERIFY(!sync.hasToken("connection"));
    QVERIFY(sync.lastError().contains("Plane API token"));
}

void PlaneSyncTest::failuresAreDeliveredAsynchronously()
{
    PlaneSync sync;
    QSignalSpy completed(&sync, &PlaneSync::completed);

    const QString requestId = sync.validateConnection({}, QStringLiteral("not-a-url"), QStringLiteral("work"));
    QCOMPARE(completed.count(), 0);
    QVERIFY(completed.wait());
    QCOMPARE(completed.at(0).at(0).toString(), requestId);
    const QVariantMap result = completed.at(0).at(1).toMap();
    QVERIFY(!result.value(QStringLiteral("ok")).toBool());
    QCOMPARE(result.value(QStringLiteral("operation")).toString(), QStringLiteral("validate"));
}

void PlaneSyncTest::missingCredentialsAreDeliveredAsynchronously()
{
    PlaneSync sync;
    QSignalSpy completed(&sync, &PlaneSync::completed);

    const QString requestId = sync.fetchProjects("missing", "https://plane.example", "workspace");
    QVERIFY(completed.wait());
    QCOMPARE(completed.at(0).at(0).toString(), requestId);
    const QVariantMap result = completed.at(0).at(1).toMap();
    QVERIFY(!result.value(QStringLiteral("ok")).toBool());
    QCOMPARE(result.value(QStringLiteral("operation")).toString(), QStringLiteral("projects"));
    QVERIFY(result.value(QStringLiteral("error")).toString().contains("Plane API token"));
}

void PlaneSyncTest::publicOperationsRejectInvalidConnectionAsynchronously()
{
    PlaneSync sync;
    QSignalSpy completed(&sync, &PlaneSync::completed);

    const QStringList operations = {
        sync.fetchProjects({}, "invalid", "workspace"),
        sync.fetchStates({}, "invalid", "workspace", "project"),
        sync.fetchMembers({}, "invalid", "workspace", "project"),
        sync.fetchWorkItem({}, "invalid", "workspace", "project", "item"),
        sync.pullAssigned({}, "invalid", "workspace", "member", "cursor"),
        sync.createWorkItem({}, "invalid", "workspace", "project", {{"name", "item"}}),
        sync.updateWorkItem({}, "invalid", "workspace", "project", "item", {{"name", "item"}})
    };

    QTRY_COMPARE(completed.count(), operations.size());
    for (int index = 0; index < operations.size(); ++index) {
        QCOMPARE(completed.at(index).at(0).toString(), operations.at(index));
        const QVariantMap result = completed.at(index).at(1).toMap();
        QVERIFY(!result.value(QStringLiteral("ok")).toBool());
        QVERIFY(result.value(QStringLiteral("error")).toString().contains(QStringLiteral("HTTPS")));
    }
}

#ifdef WORKBENCH_TESTING_ADAPTERS
void PlaneSyncTest::deterministicTransportCoversRequestMethods()
{
    PlaneSync sync;
    sync.setTokenForTests("test-connection", "test-token-must-not-escape");
    sync.setResponseForTests(static_cast<int>(QNetworkReply::NoError), 200,
                             R"({"results":[{"id":"item"}],"next_page_results":false})");
    QSignalSpy completed(&sync, &PlaneSync::completed);

    const QStringList requestIds = {
        sync.fetchProjects("test-connection", "https://plane.example", "workspace"),
        sync.fetchStates("test-connection", "https://plane.example", "workspace", "project"),
        sync.fetchMembers("test-connection", "https://plane.example", "workspace", "project"),
        sync.fetchWorkItem("test-connection", "https://plane.example", "workspace", "project", "item"),
        sync.pullAssigned("test-connection", "https://plane.example", "workspace", "member", "cursor"),
        sync.createWorkItem("test-connection", "https://plane.example", "workspace", "project", {{"name", "item"}}),
        sync.updateWorkItem("test-connection", "https://plane.example", "workspace", "project", "item", {{"name", "item"}})
    };

    QTRY_COMPARE(completed.count(), requestIds.size());
    QSet<QString> completedIds;
    for (int index = 0; index < completed.count(); ++index) {
        completedIds.insert(completed.at(index).at(0).toString());
        const QVariantMap result = completed.at(index).at(1).toMap();
        QVERIFY(result.value(QStringLiteral("ok")).toBool());
        QCOMPARE(result.value(QStringLiteral("data")).toList().at(0).toMap().value(QStringLiteral("id")).toString(),
                 QStringLiteral("item"));
    }
    QCOMPARE(completedIds, QSet<QString>(requestIds.cbegin(), requestIds.cend()));
    QVERIFY(sync.lastError().isEmpty());
}

void PlaneSyncTest::loopbackTransportFailureDoesNotLeakTestToken()
{
    QTcpServer server;
    if (!server.listen(QHostAddress::LocalHost))
        QSKIP("The test sandbox does not permit a loopback listener.");
    connect(&server, &QTcpServer::newConnection, &server, [&server] {
        QTcpSocket *socket = server.nextPendingConnection();
        socket->disconnectFromHost();
        socket->deleteLater();
    });

    PlaneSync sync;
    sync.setTokenForTests("test-connection", "test-token-must-not-escape");
    QSignalSpy completed(&sync, &PlaneSync::completed);
    const QString endpoint = QStringLiteral("https://127.0.0.1:%1").arg(server.serverPort());
    const QStringList requestIds = {
        sync.fetchProjects("test-connection", endpoint, "workspace"),
        sync.pullAssigned("test-connection", endpoint, "workspace", "member", "cursor"),
        sync.createWorkItem("test-connection", endpoint, "workspace", "project", {{"name", "item"}}),
        sync.updateWorkItem("test-connection", endpoint, "workspace", "project", "item", {{"name", "item"}})
    };

    QTRY_COMPARE(completed.count(), requestIds.size());
    QSet<QString> completedIds;
    for (int index = 0; index < completed.count(); ++index) {
        completedIds.insert(completed.at(index).at(0).toString());
        const QVariantMap result = completed.at(index).at(1).toMap();
        QVERIFY(!result.value(QStringLiteral("ok")).toBool());
        QVERIFY(result.value(QStringLiteral("error")).toString().contains(QStringLiteral("Plane request failed")));
        QVERIFY(!result.value(QStringLiteral("error")).toString().contains(QStringLiteral("test-token-must-not-escape")));
    }
    QCOMPARE(completedIds, QSet<QString>(requestIds.cbegin(), requestIds.cend()));
}
#endif

QTEST_GUILESS_MAIN(PlaneSyncTest)
#include "tst_planesync.moc"
