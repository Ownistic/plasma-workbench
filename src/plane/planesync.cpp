#include "planesync.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>
#include <QUrlQuery>
#include <QUuid>
#include <QSet>
#include <QTimer>

#include <memory>

#ifdef WORKBENCH_HAVE_KWALLET
#include <KWallet>
#endif

namespace {
constexpr auto kWalletFolder = "Workbench Plane";
constexpr auto kWalletPrefix = "connection/";

QVariantMap failure(const QString &operation, const QString &error, int status = 0)
{
    return {{QStringLiteral("ok"), false}, {QStringLiteral("operation"), operation},
            {QStringLiteral("status"), status}, {QStringLiteral("error"), error}};
}

QVariant jsonToVariant(const QJsonValue &value)
{
    return value.toVariant();
}

QUrl apiUrl(const QString &baseUrl, const QString &path, const QVariantMap &query, QString *error)
{
    QUrl url(baseUrl.trimmed());
    if (!url.isValid() || url.scheme() != QStringLiteral("https")
        || url.host().isEmpty()) {
        *error = QStringLiteral("The Plane API URL must be an absolute HTTPS URL.");
        return {};
    }
    QString normalizedPath = url.path();
    if (normalizedPath.endsWith(QLatin1Char('/')))
        normalizedPath.chop(1);
    // path contains deliberately percent-encoded workspace/project components;
    // StrictMode preserves those escapes instead of escaping '%' a second time.
    url.setPath(normalizedPath + path, QUrl::StrictMode);
    QUrlQuery urlQuery;
    for (auto it = query.cbegin(); it != query.cend(); ++it)
        if (it.value().isValid() && !it.value().toString().isEmpty())
            urlQuery.addQueryItem(it.key(), it.value().toString());
    url.setQuery(urlQuery);
    return url;
}
} // namespace

PlaneSync::PlaneSync(QObject *parent)
    : QObject(parent), m_network(new QNetworkAccessManager(this))
{
}

QString PlaneSync::lastError() const { return m_lastError; }

bool PlaneSync::walletAvailable() const
{
#ifdef WORKBENCH_HAVE_KWALLET
    return true;
#else
    return false;
#endif
}

void PlaneSync::setLastError(const QString &error)
{
    if (m_lastError == error)
        return;
    m_lastError = error;
    emit lastErrorChanged();
}

QString PlaneSync::encodedPathPart(const QString &value)
{
    return QString::fromLatin1(QUrl::toPercentEncoding(value, QByteArray(), QByteArray("/")));
}

bool PlaneSync::setToken(const QString &connectionId, const QString &token)
{
    if (connectionId.trimmed().isEmpty() || token.trimmed().isEmpty()) {
        setLastError(QStringLiteral("A connection ID and Plane API token are required."));
        return false;
    }
#ifdef WORKBENCH_HAVE_KWALLET
    std::unique_ptr<KWallet::Wallet> wallet(KWallet::Wallet::openWallet(KWallet::Wallet::NetworkWallet(), 0));
    if (!wallet) {
        setLastError(QStringLiteral("KWallet is unavailable or access was declined."));
        return false;
    }
    const QString folder = QString::fromLatin1(kWalletFolder);
    const QString key = QString::fromLatin1(kWalletPrefix) + connectionId;
    if (!wallet->hasFolder(folder) && !wallet->createFolder(folder)) {
        setLastError(QStringLiteral("KWallet could not create the Workbench Plane folder."));
        return false;
    }
    if (!wallet->setFolder(folder) || wallet->writePassword(key, token) != 0) {
        setLastError(QStringLiteral("KWallet could not save the Plane API token."));
        return false;
    }
    setLastError({});
    return true;
#else
    Q_UNUSED(token)
    setLastError(QStringLiteral("This build does not include KWallet; Plane credentials cannot be stored safely."));
    return false;
#endif
}

bool PlaneSync::clearToken(const QString &connectionId)
{
#ifdef WORKBENCH_HAVE_KWALLET
    std::unique_ptr<KWallet::Wallet> wallet(KWallet::Wallet::openWallet(KWallet::Wallet::NetworkWallet(), 0));
    const QString folder = QString::fromLatin1(kWalletFolder);
    if (!wallet || !wallet->hasFolder(folder) || !wallet->setFolder(folder)) {
        setLastError(QStringLiteral("KWallet is unavailable or access was declined."));
        return false;
    }
    const int result = wallet->removeEntry(QString::fromLatin1(kWalletPrefix) + connectionId);
    if (result != 0) {
        setLastError(QStringLiteral("KWallet could not remove the Plane API token."));
        return false;
    }
    setLastError({});
    return true;
#else
    Q_UNUSED(connectionId)
    setLastError(QStringLiteral("This build does not include KWallet."));
    return false;
#endif
}

bool PlaneSync::hasToken(const QString &connectionId)
{
    return !tokenFor(connectionId).isEmpty();
}

QString PlaneSync::tokenFor(const QString &connectionId)
{
#ifdef WORKBENCH_TESTING_ADAPTERS
    const auto testToken = m_testTokens.constFind(connectionId);
    if (testToken != m_testTokens.cend())
        return testToken.value();
#endif
#ifdef WORKBENCH_HAVE_KWALLET
    if (connectionId.trimmed().isEmpty()) {
        setLastError(QStringLiteral("A Plane connection ID is required."));
        return {};
    }
    std::unique_ptr<KWallet::Wallet> wallet(KWallet::Wallet::openWallet(KWallet::Wallet::NetworkWallet(), 0));
    QString token;
    const QString folder = QString::fromLatin1(kWalletFolder);
    if (!wallet || !wallet->hasFolder(folder) || !wallet->setFolder(folder)
        || wallet->readPassword(QString::fromLatin1(kWalletPrefix) + connectionId, token) != 0 || token.isEmpty()) {
        setLastError(QStringLiteral("No Plane API token is available for this connection."));
        return {};
    }
    return token;
#else
    Q_UNUSED(connectionId)
    setLastError(QStringLiteral("This build does not include KWallet; Plane sync is unavailable."));
    return {};
#endif
}

#ifdef WORKBENCH_TESTING_ADAPTERS
void PlaneSync::setTokenForTests(const QString &connectionId, const QString &token)
{
    if (token.isEmpty())
        m_testTokens.remove(connectionId);
    else
        m_testTokens.insert(connectionId, token);
}

void PlaneSync::setResponseForTests(int networkError, int status, const QByteArray &body,
                                    const QString &replyError)
{
    m_testResponseConfigured = true;
    m_testNetworkError = networkError;
    m_testResponseStatus = status;
    m_testResponseBody = body;
    m_testReplyError = replyError;
}

void PlaneSync::setResponseQueueForTests(const QVariantList &responses)
{
    m_testResponses = responses;
    m_testResponseConfigured = !m_testResponses.isEmpty();
}
#endif

QVariantMap PlaneSync::normalizedFields(const QVariantMap &fields, QString *error)
{
    static const QSet<QString> allowed = {QStringLiteral("name"), QStringLiteral("description_html"),
                                          QStringLiteral("state"), QStringLiteral("priority"), QStringLiteral("assignees"),
                                          QStringLiteral("external_source"), QStringLiteral("external_id")};
    QVariantMap clean;
    for (auto it = fields.cbegin(); it != fields.cend(); ++it) {
        if (!allowed.contains(it.key())) {
            *error = QStringLiteral("Plane field '%1' is not managed by Workbench.").arg(it.key());
            return {};
        }
        if (it.key() == QStringLiteral("name") && it.value().toString().trimmed().isEmpty()) {
            *error = QStringLiteral("A Plane work item needs a title.");
            return {};
        }
        if ((it.key() == QStringLiteral("external_source") || it.key() == QStringLiteral("external_id"))
            && it.value().toString().trimmed().isEmpty()) {
            *error = QStringLiteral("Plane external references must not be empty.");
            return {};
        }
        clean.insert(it.key(), it.value());
    }
    if (clean.contains(QStringLiteral("priority"))) {
        static const QSet<QString> priorities = {QStringLiteral("none"), QStringLiteral("urgent"),
                                                  QStringLiteral("high"), QStringLiteral("medium"), QStringLiteral("low")};
        if (!priorities.contains(clean.value(QStringLiteral("priority")).toString())) {
            *error = QStringLiteral("Plane priority must be none, urgent, high, medium, or low.");
            return {};
        }
    }
    if (clean.contains(QStringLiteral("assignees")) && clean.value(QStringLiteral("assignees")).typeId() != QMetaType::QVariantList) {
        *error = QStringLiteral("Plane assignees must be a list of member IDs.");
        return {};
    }
    return clean;
}

QVariantMap PlaneSync::requestPreview(const QString &method, const QString &baseUrl, const QString &workspace,
                                      const QString &projectId, const QString &path, const QVariantMap &fields) const
{
    QString error;
    const QVariantMap clean = normalizedFields(fields, &error);
    if (!error.isEmpty())
        return failure(QStringLiteral("preview"), error);
    if (workspace.trimmed().isEmpty() || (!path.isEmpty() && path.contains(QStringLiteral(".."))))
        return failure(QStringLiteral("preview"), QStringLiteral("The Plane workspace or endpoint is invalid."));
    const QString prefix = QStringLiteral("/api/v1/workspaces/") + encodedPathPart(workspace)
        + (projectId.isEmpty() ? QString() : QStringLiteral("/projects/") + encodedPathPart(projectId));
    const QUrl url = apiUrl(baseUrl, prefix + path, {}, &error);
    if (!error.isEmpty())
        return failure(QStringLiteral("preview"), error);
    return {{QStringLiteral("ok"), true}, {QStringLiteral("method"), method.toUpper()},
            {QStringLiteral("url"), url.toString(QUrl::FullyEncoded)}, {QStringLiteral("body"), clean}};
}

QString PlaneSync::begin(const QString &operation, const QString &connectionId, const QString &method,
                         const QString &baseUrl, const QString &workspace, const QString &projectId,
                         const QString &path, const QVariantMap &fields, const QVariantMap &query)
{
    const QString requestId = QStringLiteral("plane-%1").arg(m_nextRequestId++);
    const QVariantMap preview = requestPreview(method, baseUrl, workspace, projectId, path, fields);
    if (!preview.value(QStringLiteral("ok")).toBool()) {
        const QVariantMap result = failure(operation, preview.value(QStringLiteral("error")).toString());
        QTimer::singleShot(0, this, [this, requestId, result] { emit completed(requestId, result); });
        return requestId;
    }
    const QString token = tokenFor(connectionId);
    if (token.isEmpty()) {
        const QVariantMap result = failure(operation, m_lastError);
        QTimer::singleShot(0, this, [this, requestId, result] { emit completed(requestId, result); });
        return requestId;
    }
    QString urlError;
    QUrl url(preview.value(QStringLiteral("url")).toString());
    QUrlQuery urlQuery(url);
    for (auto it = query.cbegin(); it != query.cend(); ++it)
        if (!it.value().toString().isEmpty()) urlQuery.addQueryItem(it.key(), it.value().toString());
    url.setQuery(urlQuery);
    QNetworkRequest request(url);
    request.setRawHeader("X-API-Key", token.toUtf8());
    request.setRawHeader("Accept", "application/json");
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    QNetworkReply *reply = nullptr;
    const QByteArray body = QJsonDocument::fromVariant(preview.value(QStringLiteral("body")).toMap()).toJson(QJsonDocument::Compact);
#ifdef WORKBENCH_TESTING_ADAPTERS
    if (m_testResponseConfigured) {
        int networkError = m_testNetworkError;
        int status = m_testResponseStatus;
        QByteArray responseBody = m_testResponseBody;
        QString replyError = m_testReplyError;
        if (!m_testResponses.isEmpty()) {
            const QVariantMap response = m_testResponses.takeFirst().toMap();
            networkError = response.value(QStringLiteral("networkError"), networkError).toInt();
            status = response.value(QStringLiteral("status"), status).toInt();
            responseBody = response.value(QStringLiteral("body")).toByteArray();
            replyError = response.value(QStringLiteral("replyError"), replyError).toString();
            m_testResponseConfigured = !m_testResponses.isEmpty();
        }
        const QVariantMap result = decodeResponseForTests(networkError, status, responseBody, replyError, operation);
        if (!result.value(QStringLiteral("ok")).toBool())
            setLastError(result.value(QStringLiteral("error")).toString());
        else
            setLastError({});
        QTimer::singleShot(0, this, [this, requestId, result] { emit completed(requestId, result); });
        return requestId;
    }
#endif
    if (method == QStringLiteral("GET")) reply = m_network->get(request);
    else if (method == QStringLiteral("POST")) reply = m_network->post(request, body);
    else if (method == QStringLiteral("PATCH")) reply = m_network->sendCustomRequest(request, "PATCH", body);
    else {
        const QVariantMap result = failure(operation, QStringLiteral("Unsupported Plane HTTP method."));
        QTimer::singleShot(0, this, [this, requestId, result] { emit completed(requestId, result); });
        return requestId;
    }
    connect(reply, &QNetworkReply::finished, this, [this, reply, requestId, operation] {
        const QVariantMap result = decodeReply(reply, operation);
        if (!result.value(QStringLiteral("ok")).toBool()) setLastError(result.value(QStringLiteral("error")).toString());
        else setLastError({});
        emit completed(requestId, result);
        reply->deleteLater();
    });
    return requestId;
}

QVariantMap PlaneSync::decodeReply(QNetworkReply *reply, const QString &operation)
{
    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QByteArray raw = reply->readAll();
    return decodeResponseForTests(static_cast<int>(reply->error()), status, raw,
                                  reply->errorString(), operation);
}

QVariantMap PlaneSync::decodeResponseForTests(int networkError, int status, const QByteArray &raw,
                                              const QString &replyError, const QString &operation)
{
    const QJsonDocument document = QJsonDocument::fromJson(raw);
    if (networkError != static_cast<int>(QNetworkReply::NoError) || status < 200 || status >= 300) {
        QString detail;
        if (document.isObject()) detail = document.object().value(QStringLiteral("detail")).toString();
        if (detail.isEmpty()) detail = replyError;
        return failure(operation, QStringLiteral("Plane request failed (%1): %2").arg(status).arg(detail.left(500)), status);
    }
    QVariantMap result = {{QStringLiteral("ok"), true}, {QStringLiteral("operation"), operation},
                           {QStringLiteral("status"), status}};
    if (document.isObject()) {
        const QVariantMap object = document.object().toVariantMap();
        result.insert(QStringLiteral("data"), object.value(QStringLiteral("results"), object));
        result.insert(QStringLiteral("nextCursor"), object.value(QStringLiteral("next_cursor")));
        result.insert(QStringLiteral("hasMore"), object.value(QStringLiteral("next_page_results")).toBool());
    } else if (document.isArray()) result.insert(QStringLiteral("data"), jsonToVariant(document.array()));
    else result.insert(QStringLiteral("data"), QVariantMap());
    return result;
}

QString PlaneSync::validateConnection(const QString &connectionId, const QString &baseUrl, const QString &workspace)
{ return begin(QStringLiteral("validate"), connectionId, QStringLiteral("GET"), baseUrl, workspace, {}, QStringLiteral("/projects/"), {}, {}); }
QString PlaneSync::fetchProjects(const QString &connectionId, const QString &baseUrl, const QString &workspace)
{ return begin(QStringLiteral("projects"), connectionId, QStringLiteral("GET"), baseUrl, workspace, {}, QStringLiteral("/projects/"), {}, {}); }
QString PlaneSync::fetchStates(const QString &connectionId, const QString &baseUrl, const QString &workspace, const QString &projectId)
{ return begin(QStringLiteral("states"), connectionId, QStringLiteral("GET"), baseUrl, workspace, projectId, QStringLiteral("/states/"), {}, {}); }
QString PlaneSync::fetchMembers(const QString &connectionId, const QString &baseUrl, const QString &workspace, const QString &projectId)
{ return begin(QStringLiteral("members"), connectionId, QStringLiteral("GET"), baseUrl, workspace, projectId, QStringLiteral("/members/"), {}, {}); }
QString PlaneSync::fetchWorkItem(const QString &connectionId, const QString &baseUrl, const QString &workspace, const QString &projectId, const QString &workItemId)
{ return begin(QStringLiteral("workItem"), connectionId, QStringLiteral("GET"), baseUrl, workspace, projectId, QStringLiteral("/work-items/") + encodedPathPart(workItemId) + QStringLiteral("/"), {}, {}); }
QString PlaneSync::findWorkItemsByExternalReference(const QString &connectionId, const QString &baseUrl, const QString &workspace, const QString &projectId, const QString &externalSource, const QString &externalId)
{ return begin(QStringLiteral("externalReference"), connectionId, QStringLiteral("GET"), baseUrl, workspace, projectId, QStringLiteral("/work-items/"), {}, {{QStringLiteral("external_source"), externalSource}, {QStringLiteral("external_id"), externalId}}); }
QString PlaneSync::pullAssigned(const QString &connectionId, const QString &baseUrl, const QString &workspace, const QString &assigneeId, const QString &cursor)
{ return begin(QStringLiteral("pullAssigned"), connectionId, QStringLiteral("GET"), baseUrl, workspace, {}, QStringLiteral("/work-items/"), {}, {{QStringLiteral("assignee"), assigneeId}, {QStringLiteral("cursor"), cursor}, {QStringLiteral("expand"), QStringLiteral("state")}, {QStringLiteral("per_page"), 100}}); }
QString PlaneSync::createWorkItem(const QString &connectionId, const QString &baseUrl, const QString &workspace, const QString &projectId, const QVariantMap &fields)
{ return begin(QStringLiteral("create"), connectionId, QStringLiteral("POST"), baseUrl, workspace, projectId, QStringLiteral("/work-items/"), fields, {}); }
QString PlaneSync::updateWorkItem(const QString &connectionId, const QString &baseUrl, const QString &workspace, const QString &projectId, const QString &workItemId, const QVariantMap &fields)
{ return begin(QStringLiteral("update"), connectionId, QStringLiteral("PATCH"), baseUrl, workspace, projectId, QStringLiteral("/work-items/") + encodedPathPart(workItemId) + QStringLiteral("/"), fields, {}); }
