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

QVariantMap localPartsResult(const QDateTime &dateTime, const QTimeZone &timeZone)
{
    const QDateTime local = dateTime.toTimeZone(timeZone);
    return {
        {QStringLiteral("valid"), true},
        {QStringLiteral("utc"), dateTime.toUTC().toString(Qt::ISODateWithMs)},
        {QStringLiteral("date"), local.date().toString(Qt::ISODate)},
        {QStringLiteral("time"), local.time().toString(Qt::ISODateWithMs)},
        {QStringLiteral("year"), local.date().year()},
        {QStringLiteral("month"), local.date().month()},
        {QStringLiteral("day"), local.date().day()},
        {QStringLiteral("hour"), local.time().hour()},
        {QStringLiteral("minute"), local.time().minute()},
        {QStringLiteral("second"), local.time().second()},
        {QStringLiteral("millisecond"), local.time().msec()},
        {QStringLiteral("offsetSeconds"), local.offsetFromUtc()},
        {QStringLiteral("timeZoneAbbreviation"), local.timeZoneAbbreviation()},
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

QVariantMap TimeMath::localPartsForUtc(const QString &utc, const QString &timeZoneId) const
{
    QTimeZone timeZone;
    QDateTime dateTime;
    if (!timeZoneForId(timeZoneId, &timeZone)) {
        return invalidResult(QStringLiteral("The time zone ID is invalid."));
    }
    if (!utcDateTime(utc, &dateTime)) {
        return invalidResult(QStringLiteral("The UTC instant is invalid."));
    }
    return localPartsResult(dateTime, timeZone);
}

QVariantMap TimeMath::possibleUtcInstantsForLocal(int year, int month, int day,
                                                   int hour, int minute, int second,
                                                   int millisecond,
                                                   const QString &timeZoneId) const
{
    const QDate date(year, month, day);
    const QTime time(hour, minute, second, millisecond);
    if (!date.isValid() || !time.isValid()) {
        return invalidResult(QStringLiteral("The local date and time is invalid."));
    }

    QTimeZone timeZone;
    if (!timeZoneForId(timeZoneId, &timeZone)) {
        return invalidResult(QStringLiteral("The time zone ID is invalid."));
    }

    const QDateTime before(date, time, timeZone, QDateTime::TransitionResolution::RelativeToBefore);
    const QDateTime after(date, time, timeZone, QDateTime::TransitionResolution::RelativeToAfter);
    QVariantList utcInstants;
    for (const QDateTime &candidate : {before, after}) {
        const QDateTime utc = candidate.toUTC();
        if (candidate.isValid() && utc.toTimeZone(timeZone).date() == date
            && utc.toTimeZone(timeZone).time() == time
            && !utcInstants.contains(utc.toString(Qt::ISODateWithMs))) {
            utcInstants.append(utc.toString(Qt::ISODateWithMs));
        }
    }

    if (utcInstants.isEmpty()) {
        return invalidResult(QStringLiteral("The local date and time does not exist in this time zone."));
    }
    std::sort(utcInstants.begin(), utcInstants.end(), [](const QVariant &left, const QVariant &right) {
        return left.toString() < right.toString();
    });
    return {
        {QStringLiteral("valid"), true},
        {QStringLiteral("ambiguous"), utcInstants.size() > 1},
        {QStringLiteral("utcInstants"), utcInstants},
    };
}

QVariantMap TimeMath::formatUtcForLocal(const QString &utc, const QString &timeZoneId,
                                        bool use24Hour) const
{
    const QVariantMap parts = localPartsForUtc(utc, timeZoneId);
    if (!parts.value(QStringLiteral("valid")).toBool()) {
        return parts;
    }

    QDateTime dateTime;
    utcDateTime(utc, &dateTime);
    QTimeZone timeZone(timeZoneId.toUtf8());
    const QDateTime local = dateTime.toTimeZone(timeZone);
    return {
        {QStringLiteral("valid"), true},
        {QStringLiteral("formatted"), local.toString(use24Hour
            ? QStringLiteral("yyyy-MM-dd HH:mm")
            : QStringLiteral("yyyy-MM-dd h:mm AP"))},
    };
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
