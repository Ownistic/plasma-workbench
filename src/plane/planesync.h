#pragma once

#include <QObject>
#include <QByteArray>
#include <QHash>
#include <QPointer>
#include <QQmlEngine>
#include <QVariantMap>
#include <QtQml/qqml.h>

class QNetworkAccessManager;
class QNetworkReply;

// Native, provider-specific transport used by the provider-neutral QML data
// layer. It deliberately never exposes a stored credential to QML.
class PlaneSync : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(PlaneSync)
    QML_SINGLETON
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(bool walletAvailable READ walletAvailable CONSTANT)

public:
    explicit PlaneSync(QObject *parent = nullptr);

    QString lastError() const;
    bool walletAvailable() const;

    Q_INVOKABLE bool setToken(const QString &connectionId, const QString &token);
    Q_INVOKABLE bool clearToken(const QString &connectionId);
    Q_INVOKABLE bool hasToken(const QString &connectionId);

    Q_INVOKABLE QString validateConnection(const QString &connectionId, const QString &baseUrl,
                                           const QString &workspace);
    Q_INVOKABLE QString fetchProjects(const QString &connectionId, const QString &baseUrl,
                                      const QString &workspace);
    Q_INVOKABLE QString fetchStates(const QString &connectionId, const QString &baseUrl,
                                    const QString &workspace, const QString &projectId);
    Q_INVOKABLE QString fetchMembers(const QString &connectionId, const QString &baseUrl,
                                     const QString &workspace, const QString &projectId);
    Q_INVOKABLE QString fetchWorkItem(const QString &connectionId, const QString &baseUrl,
                                      const QString &workspace, const QString &projectId,
                                      const QString &workItemId);
    Q_INVOKABLE QString findWorkItemsByExternalReference(const QString &connectionId, const QString &baseUrl,
                                                         const QString &workspace, const QString &projectId,
                                                         const QString &externalSource, const QString &externalId);
    Q_INVOKABLE QString pullAssigned(const QString &connectionId, const QString &baseUrl,
                                     const QString &workspace, const QString &assigneeId,
                                     const QString &cursor = QString());
    Q_INVOKABLE QString createWorkItem(const QString &connectionId, const QString &baseUrl,
                                       const QString &workspace, const QString &projectId,
                                       const QVariantMap &fields);
    Q_INVOKABLE QString updateWorkItem(const QString &connectionId, const QString &baseUrl,
                                       const QString &workspace, const QString &projectId,
                                       const QString &workItemId, const QVariantMap &fields);

    // Kept public for deterministic native tests and to let clients preview a
    // request without possessing a credential.
    Q_INVOKABLE QVariantMap requestPreview(const QString &method, const QString &baseUrl,
                                           const QString &workspace, const QString &projectId,
                                           const QString &path, const QVariantMap &fields = {}) const;

    // Pure response decoder retained as a native test seam. It accepts no
    // credentials, transport object, or QML-visible state.
    static QVariantMap decodeResponseForTests(int networkError, int status,
                                              const QByteArray &raw,
                                              const QString &replyError,
                                              const QString &operation);

#ifdef WORKBENCH_TESTING_ADAPTERS
    // Compiled only into test builds. It is not invokable from QML and never
    // exists in the shipped module, so it cannot alter production credentials.
    Q_INVOKABLE void setTokenForTests(const QString &connectionId, const QString &token);
    Q_INVOKABLE void setResponseForTests(int networkError, int status, const QByteArray &body,
                                         const QString &replyError = QString());
    Q_INVOKABLE void setResponseQueueForTests(const QVariantList &responses);
#endif

signals:
    void completed(const QString &requestId, const QVariantMap &result);
    void lastErrorChanged();

private:
    QString begin(const QString &operation, const QString &connectionId, const QString &method,
                  const QString &baseUrl, const QString &workspace, const QString &projectId,
                  const QString &path, const QVariantMap &fields, const QVariantMap &query = {});
    QString tokenFor(const QString &connectionId);
    void setLastError(const QString &error);
    static QString encodedPathPart(const QString &value);
    static QVariantMap normalizedFields(const QVariantMap &fields, QString *error);
    static QVariantMap decodeReply(QNetworkReply *reply, const QString &operation);

    QNetworkAccessManager *m_network;
    QString m_lastError;
    quint64 m_nextRequestId = 1;
#ifdef WORKBENCH_TESTING_ADAPTERS
    QHash<QString, QString> m_testTokens;
    bool m_testResponseConfigured = false;
    int m_testNetworkError = 0;
    int m_testResponseStatus = 0;
    QByteArray m_testResponseBody;
    QString m_testReplyError;
    QVariantList m_testResponses;
#endif
};
