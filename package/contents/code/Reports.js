.pragma library

.import "Database.js" as Database

function addTotal(totals, id, label, color, seconds) {
    if (!totals[id]) {
        totals[id] = { id: id, label: label, color: color || "", seconds: 0 }
    }
    totals[id].seconds += seconds
}

function orderedTotals(totals) {
    return Object.keys(totals).map(function(key) { return totals[key] }).sort(function(left, right) {
        if (right.seconds !== left.seconds) {
            return right.seconds - left.seconds
        }
        return left.label.localeCompare(right.label)
    })
}

function aggregate(timeMath, range, timezoneId, currentUtc) {
    const sessions = Database.listReportSessions(range.startUtc, range.endUtc, currentUtc)
    const dates = {}
    const categories = {}
    const tasks = {}
    const dailyCategories = {}
    let totalSeconds = 0

    for (let sessionIndex = 0; sessionIndex < sessions.length; sessionIndex += 1) {
        const session = sessions[sessionIndex]
        const segments = timeMath.splitInterval(
            session.startedAtUtc,
            session.endedAtUtc,
            range.startUtc,
            range.endUtc,
            timezoneId
        )
        for (let segmentIndex = 0; segmentIndex < segments.length; segmentIndex += 1) {
            const segment = segments[segmentIndex]
            const seconds = segment.durationSeconds
            totalSeconds += seconds
            addTotal(dates, segment.localDate, segment.localDate, "", seconds)
            addTotal(categories, session.categoryId, session.categoryName, session.categoryColor, seconds)
            addTotal(tasks, session.taskId, session.taskTitle, "", seconds)
            if (!dailyCategories[segment.localDate]) {
                dailyCategories[segment.localDate] = {}
            }
            addTotal(dailyCategories[segment.localDate], session.categoryId, session.categoryName, session.categoryColor, seconds)
        }
    }

    const byDate = orderedTotals(dates).sort(function(left, right) { return left.id.localeCompare(right.id) })
    const dailyByCategory = Object.keys(dailyCategories).sort().map(function(date) {
        return { date: date, categories: orderedTotals(dailyCategories[date]) }
    })
    return {
        startUtc: range.startUtc,
        endUtc: range.endUtc,
        totalSeconds: totalSeconds,
        byDate: byDate,
        byCategory: orderedTotals(categories),
        byTask: orderedTotals(tasks),
        dailyByCategory: dailyByCategory
    }
}

function weeklyReport(timeMath, input) {
    input = input || {}
    const range = timeMath.weekRange(
        input.year,
        input.month,
        input.day,
        input.timezoneId,
        input.firstDayOfWeek === undefined ? 1 : input.firstDayOfWeek
    )
    if (!range.valid) {
        throw new Error(range.error)
    }
    return aggregate(timeMath, range, input.timezoneId, input.currentUtc)
}

function monthlyReport(timeMath, input) {
    input = input || {}
    const range = timeMath.monthRange(input.year, input.month, input.timezoneId)
    if (!range.valid) {
        throw new Error(range.error)
    }
    return aggregate(timeMath, range, input.timezoneId, input.currentUtc)
}
