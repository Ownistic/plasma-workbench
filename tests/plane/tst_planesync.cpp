#include "planesync.h"

#include <QSignalSpy>
#include <QTest>

class PlaneSyncTest : public QObject
{
    Q_OBJECT
private slots:
    void previewsProjectRequest();
    void encodesPathComponents();
    void onlyAllowsManagedFields();
    void rejectsInvalidBaseUrl();
    void rejectsPlainHttpBaseUrl();
    void failuresAreDeliveredAsynchronously();
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

QTEST_GUILESS_MAIN(PlaneSyncTest)
#include "tst_planesync.moc"
