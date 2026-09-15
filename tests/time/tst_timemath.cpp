#include "timemath.h"

#include <QTest>

class TimeMathTest : public QObject
{
    Q_OBJECT

private slots:
    void splitsCrossMidnight();
    void splitsDstTransition();
    void calculatesWeekRange();
    void calculatesMonthRange();
    void convertsUtcToLocalDate();
    void convertsUtcToLocalParts();
    void resolvesNormalLocalTime();
    void detectsLocalDstGap();
    void detectsAmbiguousLocalTime();
    void formatsUtcForLocal();
    void rejectsInvalidInput();
    void clampsToReportRange();
};

void TimeMathTest::splitsCrossMidnight()
{
    TimeMath timeMath;
    const QVariantList segments = timeMath.splitInterval(
        QStringLiteral("2024-01-01T22:00:00.000Z"),
        QStringLiteral("2024-01-02T03:00:00.000Z"),
        QStringLiteral("2024-01-01T00:00:00.000Z"),
        QStringLiteral("2024-01-03T00:00:00.000Z"),
        QStringLiteral("Europe/Berlin"));

    QCOMPARE(segments.size(), 2);
    const QVariantMap first = segments.at(0).toMap();
    QCOMPARE(first.value(QStringLiteral("localDate")).toString(), QStringLiteral("2024-01-01"));
    QCOMPARE(first.value(QStringLiteral("durationSeconds")).toLongLong(), 3600LL);
    const QVariantMap second = segments.at(1).toMap();
    QCOMPARE(second.value(QStringLiteral("localDate")).toString(), QStringLiteral("2024-01-02"));
    QCOMPARE(second.value(QStringLiteral("durationSeconds")).toLongLong(), 14400LL);
}

void TimeMathTest::splitsDstTransition()
{
    TimeMath timeMath;
    const QVariantList segments = timeMath.splitInterval(
        QStringLiteral("2024-03-30T23:00:00.000Z"),
        QStringLiteral("2024-04-01T00:00:00.000Z"),
        QStringLiteral("2024-03-30T00:00:00.000Z"),
        QStringLiteral("2024-04-02T00:00:00.000Z"),
        QStringLiteral("Europe/Berlin"));

    QCOMPARE(segments.size(), 2);
    const QVariantMap dstDay = segments.at(0).toMap();
    QCOMPARE(dstDay.value(QStringLiteral("localDate")).toString(), QStringLiteral("2024-03-31"));
    QCOMPARE(dstDay.value(QStringLiteral("durationSeconds")).toLongLong(), 23 * 3600LL);
    QCOMPARE(dstDay.value(QStringLiteral("endUtc")).toString(), QStringLiteral("2024-03-31T22:00:00.000Z"));
    const QVariantMap followingDay = segments.at(1).toMap();
    QCOMPARE(followingDay.value(QStringLiteral("localDate")).toString(), QStringLiteral("2024-04-01"));
    QCOMPARE(followingDay.value(QStringLiteral("durationSeconds")).toLongLong(), 2 * 3600LL);
}

void TimeMathTest::calculatesWeekRange()
{
    TimeMath timeMath;
    const QVariantMap range = timeMath.weekRange(2024, 3, 31, QStringLiteral("Europe/Berlin"));

    QVERIFY(range.value(QStringLiteral("valid")).toBool());
    QCOMPARE(range.value(QStringLiteral("startUtc")).toString(), QStringLiteral("2024-03-24T23:00:00.000Z"));
    QCOMPARE(range.value(QStringLiteral("endUtc")).toString(), QStringLiteral("2024-03-31T22:00:00.000Z"));
}

void TimeMathTest::calculatesMonthRange()
{
    TimeMath timeMath;
    const QVariantMap range = timeMath.monthRange(2024, 3, QStringLiteral("Europe/Berlin"));

    QVERIFY(range.value(QStringLiteral("valid")).toBool());
    QCOMPARE(range.value(QStringLiteral("startUtc")).toString(), QStringLiteral("2024-02-29T23:00:00.000Z"));
    QCOMPARE(range.value(QStringLiteral("endUtc")).toString(), QStringLiteral("2024-03-31T22:00:00.000Z"));
}

void TimeMathTest::convertsUtcToLocalDate()
{
    TimeMath timeMath;
    QCOMPARE(timeMath.localDateForUtc(
                 QStringLiteral("2024-01-01T23:30:00.000Z"),
                 QStringLiteral("Europe/Berlin")),
             QStringLiteral("2024-01-02"));
    QVERIFY(timeMath.localDateForUtc(
                 QStringLiteral("2024-01-01T00:00:00.000Z"),
                 QStringLiteral("Mars/Olympus"))
                .isEmpty());
}

void TimeMathTest::convertsUtcToLocalParts()
{
    TimeMath timeMath;
    const QVariantMap parts = timeMath.localPartsForUtc(
        QStringLiteral("2024-01-15T12:05:06.007Z"), QStringLiteral("America/New_York"));

    QVERIFY(parts.value(QStringLiteral("valid")).toBool());
    QCOMPARE(parts.value(QStringLiteral("date")).toString(), QStringLiteral("2024-01-15"));
    QCOMPARE(parts.value(QStringLiteral("time")).toString(), QStringLiteral("07:05:06.007"));
    QCOMPARE(parts.value(QStringLiteral("year")).toInt(), 2024);
    QCOMPARE(parts.value(QStringLiteral("hour")).toInt(), 7);
    QCOMPARE(parts.value(QStringLiteral("offsetSeconds")).toInt(), -5 * 3600);
}

void TimeMathTest::resolvesNormalLocalTime()
{
    TimeMath timeMath;
    const QVariantMap result = timeMath.possibleUtcInstantsForLocal(
        2024, 1, 15, 13, 5, 0, 0, QStringLiteral("America/New_York"));

    QVERIFY(result.value(QStringLiteral("valid")).toBool());
    QVERIFY(!result.value(QStringLiteral("ambiguous")).toBool());
    QCOMPARE(result.value(QStringLiteral("utcInstants")).toList(),
             QVariantList({QStringLiteral("2024-01-15T18:05:00.000Z")}));
}

void TimeMathTest::detectsLocalDstGap()
{
    TimeMath timeMath;
    const QVariantMap result = timeMath.possibleUtcInstantsForLocal(
        2024, 3, 31, 2, 30, 0, 0, QStringLiteral("Europe/Berlin"));

    QVERIFY(!result.value(QStringLiteral("valid")).toBool());
    QCOMPARE(result.value(QStringLiteral("error")).toString(),
             QStringLiteral("The local date and time does not exist in this time zone."));
}

void TimeMathTest::detectsAmbiguousLocalTime()
{
    TimeMath timeMath;
    const QVariantMap result = timeMath.possibleUtcInstantsForLocal(
        2024, 10, 27, 2, 30, 0, 0, QStringLiteral("Europe/Berlin"));

    QVERIFY(result.value(QStringLiteral("valid")).toBool());
    QVERIFY(result.value(QStringLiteral("ambiguous")).toBool());
    const QVariantList instants = result.value(QStringLiteral("utcInstants")).toList();
    QCOMPARE(instants, QVariantList({QStringLiteral("2024-10-27T00:30:00.000Z"),
                                    QStringLiteral("2024-10-27T01:30:00.000Z")}));
}

void TimeMathTest::formatsUtcForLocal()
{
    TimeMath timeMath;
    const QString utc = QStringLiteral("2024-01-15T18:05:00.000Z");

    QCOMPARE(timeMath.formatUtcForLocal(utc, QStringLiteral("America/New_York"), true)
                 .value(QStringLiteral("formatted")).toString(),
             QStringLiteral("2024-01-15 13:05"));
    QCOMPARE(timeMath.formatUtcForLocal(utc, QStringLiteral("America/New_York"), false)
                 .value(QStringLiteral("formatted")).toString(),
             QStringLiteral("2024-01-15 1:05 PM"));
}

void TimeMathTest::rejectsInvalidInput()
{
    TimeMath timeMath;
    QVERIFY(!timeMath.isValidTimeZone(QStringLiteral("Mars/Olympus")));
    QVERIFY(!timeMath.weekRange(2024, 2, 30, QStringLiteral("Europe/Berlin")).value(QStringLiteral("valid")).toBool());
    QVERIFY(!timeMath.monthRange(2024, 13, QStringLiteral("Europe/Berlin")).value(QStringLiteral("valid")).toBool());
    QVERIFY(!timeMath.weekRange(2024, 1, 1, QStringLiteral("Mars/Olympus")).value(QStringLiteral("valid")).toBool());
    QVERIFY(timeMath.splitInterval(
        QStringLiteral("2024-01-01T00:00:00.000Z"),
        QStringLiteral("2024-01-02T00:00:00.000Z"),
        QStringLiteral("2024-01-01T00:00:00.000Z"),
        QStringLiteral("2024-01-03T00:00:00.000Z"),
        QStringLiteral("Mars/Olympus")).isEmpty());
}

void TimeMathTest::clampsToReportRange()
{
    TimeMath timeMath;
    const QVariantList segments = timeMath.splitInterval(
        QStringLiteral("2024-01-01T21:00:00.000Z"),
        QStringLiteral("2024-01-02T03:00:00.000Z"),
        QStringLiteral("2024-01-01T22:00:00.000Z"),
        QStringLiteral("2024-01-02T00:00:00.000Z"),
        QStringLiteral("Etc/UTC"));

    QCOMPARE(segments.size(), 1);
    const QVariantMap segment = segments.constFirst().toMap();
    QCOMPARE(segment.value(QStringLiteral("startUtc")).toString(), QStringLiteral("2024-01-01T22:00:00.000Z"));
    QCOMPARE(segment.value(QStringLiteral("endUtc")).toString(), QStringLiteral("2024-01-02T00:00:00.000Z"));
    QCOMPARE(segment.value(QStringLiteral("localDate")).toString(), QStringLiteral("2024-01-01"));
    QCOMPARE(segment.value(QStringLiteral("durationSeconds")).toLongLong(), 7200LL);
}

QTEST_APPLESS_MAIN(TimeMathTest)

#include "tst_timemath.moc"
