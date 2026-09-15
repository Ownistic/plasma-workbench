#include "timemath.h"

#include <QDate>
#include <QDateTime>
#include <QTime>
#include <QTimeZone>

#include <algorithm>

namespace {

QVariantMap invalidResult(const QString &error)
{
    return {{QStringLiteral("valid"), false}, {QStringLiteral("error"), error}};
}

QVariantMap rangeResult(const QDateTime &start, const QDateTime &end, const QTimeZone &timeZone)
{
    return {
        {QStringLiteral("valid"), true},
        {QStringLiteral("startUtc"), start.toUTC().toString(Qt::ISODateWithMs)},
        {QStringLiteral("endUtc"), end.toUTC().toString(Qt::ISODateWithMs)},
        {QStringLiteral("startDate"), start.toTimeZone(timeZone).date().toString(Qt::ISODate)},
        {QStringLiteral("endDateExclusive"), end.toTimeZone(timeZone).date().toString(Qt::ISODate)},
    };
}

bool timeZoneForId(const QString &timeZoneId, QTimeZone *timeZone)
{
    const QByteArray id = timeZoneId.toUtf8();
    if (id.isEmpty() || !QTimeZone::isTimeZoneIdAvailable(id)) {
        return false;
    }

    *timeZone = QTimeZone(id);
    return timeZone->isValid();
}

bool utcDateTime(const QString &value, QDateTime *dateTime)
{
    // Report data is persisted as UTC, never as an unqualified local timestamp.
    if (!value.endsWith(QLatin1Char('Z'))) {
        return false;
    }

    *dateTime = QDateTime::fromString(value, Qt::ISODateWithMs);
    if (!dateTime->isValid()) {
        *dateTime = QDateTime::fromString(value, Qt::ISODate);
    }
    return dateTime->isValid() && dateTime->timeSpec() == Qt::UTC;
}

QDateTime localMidnight(const QDate &date, const QTimeZone &timeZone)
{
    return QDateTime(date, QTime(0, 0), timeZone).toUTC();
}

} // namespace

TimeMath::TimeMath(QObject *parent)
    : QObject(parent)
{
}

bool TimeMath::isValidTimeZone(const QString &timeZoneId) const
{
    QTimeZone timeZone;
    return timeZoneForId(timeZoneId, &timeZone);
}

QString TimeMath::systemTimeZoneId() const
{
    return QString::fromUtf8(QTimeZone::systemTimeZoneId());
}

QString TimeMath::localDateForUtc(const QString &utc, const QString &timeZoneId) const
{
    QTimeZone timeZone;
    QDateTime dateTime;
    if (!timeZoneForId(timeZoneId, &timeZone) || !utcDateTime(utc, &dateTime)) {
        return {};
    }
    return dateTime.toTimeZone(timeZone).date().toString(Qt::ISODate);
}

QVariantMap TimeMath::weekRange(int year, int month, int day, const QString &timeZoneId,
                                int firstDayOfWeek) const
{
    const QDate date(year, month, day);
    if (!date.isValid()) {
        return invalidResult(QStringLiteral("The local date is invalid."));
    }
    if (firstDayOfWeek < 1 || firstDayOfWeek > 7) {
        return invalidResult(QStringLiteral("The first day of week must be from 1 (Monday) to 7 (Sunday)."));
    }

    QTimeZone timeZone;
    if (!timeZoneForId(timeZoneId, &timeZone)) {
        return invalidResult(QStringLiteral("The time zone ID is invalid."));
    }

    const int daysSinceWeekStart = (date.dayOfWeek() - firstDayOfWeek + 7) % 7;
    const QDate startDate = date.addDays(-daysSinceWeekStart);
    const QDate endDate = startDate.addDays(7);
    const QDateTime start = localMidnight(startDate, timeZone);
    const QDateTime end = localMidnight(endDate, timeZone);
    if (!start.isValid() || !end.isValid() || start >= end) {
        return invalidResult(QStringLiteral("The local week does not map to a valid UTC range."));
    }
    return rangeResult(start, end, timeZone);
}

QVariantMap TimeMath::monthRange(int year, int month, const QString &timeZoneId) const
{
    const QDate startDate(year, month, 1);
    if (!startDate.isValid()) {
        return invalidResult(QStringLiteral("The local month is invalid."));
    }

    QTimeZone timeZone;
    if (!timeZoneForId(timeZoneId, &timeZone)) {
        return invalidResult(QStringLiteral("The time zone ID is invalid."));
    }

    const QDateTime start = localMidnight(startDate, timeZone);
    const QDateTime end = localMidnight(startDate.addMonths(1), timeZone);
    if (!start.isValid() || !end.isValid() || start >= end) {
        return invalidResult(QStringLiteral("The local month does not map to a valid UTC range."));
    }
    return rangeResult(start, end, timeZone);
}

QVariantList TimeMath::splitInterval(const QString &startUtc, const QString &endUtc,
                                     const QString &reportStartUtc, const QString &reportEndUtc,
                                     const QString &timeZoneId) const
{
    QTimeZone timeZone;
    QDateTime start;
    QDateTime end;
    QDateTime reportStart;
    QDateTime reportEnd;
    if (!timeZoneForId(timeZoneId, &timeZone)
        || !utcDateTime(startUtc, &start)
        || !utcDateTime(endUtc, &end)
        || !utcDateTime(reportStartUtc, &reportStart)
        || !utcDateTime(reportEndUtc, &reportEnd)
        || start >= end
        || reportStart >= reportEnd) {
        return {};
    }

    const QDateTime clampedStart = std::max(start, reportStart);
    const QDateTime clampedEnd = std::min(end, reportEnd);
    if (clampedStart >= clampedEnd) {
        return {};
    }

    QVariantList segments;
    QDateTime segmentStart = clampedStart;
    while (segmentStart < clampedEnd) {
        const QDate localDate = segmentStart.toTimeZone(timeZone).date();
        QDateTime nextMidnight = localMidnight(localDate.addDays(1), timeZone);
        if (!nextMidnight.isValid() || nextMidnight <= segmentStart) {
            return {};
        }

        const QDateTime segmentEnd = std::min(nextMidnight, clampedEnd);
        const qint64 durationSeconds = segmentStart.secsTo(segmentEnd);
        if (durationSeconds <= 0) {
            return {};
        }
        segments.append(QVariantMap{
            {QStringLiteral("startUtc"), segmentStart.toString(Qt::ISODateWithMs)},
            {QStringLiteral("endUtc"), segmentEnd.toString(Qt::ISODateWithMs)},
            {QStringLiteral("localDate"), localDate.toString(Qt::ISODate)},
            {QStringLiteral("durationSeconds"), durationSeconds},
        });
        segmentStart = segmentEnd;
    }
    return segments;
}
