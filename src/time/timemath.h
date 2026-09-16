#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QtQml/qqml.h>
#include <QVariantList>
#include <QVariantMap>

class TimeMath : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(TimeMath)
    QML_SINGLETON

public:
    explicit TimeMath(QObject *parent = nullptr);

    Q_INVOKABLE bool isValidTimeZone(const QString &timeZoneId) const;
    Q_INVOKABLE QString systemTimeZoneId() const;
    Q_INVOKABLE QString localDateForUtc(const QString &utc, const QString &timeZoneId) const;
    Q_INVOKABLE QVariantMap localPartsForUtc(const QString &utc, const QString &timeZoneId) const;
    Q_INVOKABLE QVariantMap possibleUtcInstantsForLocal(int year, int month, int day,
                                                         int hour, int minute, int second,
                                                         int millisecond,
                                                         const QString &timeZoneId) const;
    Q_INVOKABLE QVariantMap formatUtcForLocal(const QString &utc, const QString &timeZoneId,
                                               bool use24Hour) const;

    Q_INVOKABLE QVariantMap dayRange(int year, int month, int day,
                                     const QString &timeZoneId) const;
    Q_INVOKABLE QVariantMap weekRange(int year, int month, int day,
                                       const QString &timeZoneId,
                                       int firstDayOfWeek = 1) const;
    Q_INVOKABLE QVariantMap monthRange(int year, int month,
                                       const QString &timeZoneId) const;
    Q_INVOKABLE QVariantList splitInterval(const QString &startUtc,
                                           const QString &endUtc,
                                           const QString &reportStartUtc,
                                           const QString &reportEndUtc,
                                           const QString &timeZoneId) const;
};
