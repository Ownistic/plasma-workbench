.pragma library

.import "Database.js" as Database

function addTotal(totals, id, label, color, seconds) {
    if (!totals[id]) {
        totals[id] = { id: id, label: label, color: color || "", seconds: 0 }
    }
    totals[id].seconds += seconds
}

function addInterval(intervals, id, label, color, startUtc, endUtc) {
    if (!intervals[id]) {
        intervals[id] = { id: id, label: label, color: color || "", intervals: [] }
    }
    intervals[id].intervals.push({ startUtc: startUtc, endUtc: endUtc })
}

function mergedTotals(intervals) {
    const totals = {}
    for (const id in intervals) {
        const intervalTotal = intervals[id]
        const sortedIntervals = intervalTotal.intervals.sort(function(left, right) {
            return left.startUtc.localeCompare(right.startUtc)
        })
        let seconds = 0
        let startUtc = ""
        let endUtc = ""
        for (let index = 0; index < sortedIntervals.length; index += 1) {
            const interval = sortedIntervals[index]
            if (!startUtc) {
                startUtc = interval.startUtc
                endUtc = interval.endUtc
            } else if (interval.startUtc <= endUtc) {
                if (interval.endUtc > endUtc) {
                    endUtc = interval.endUtc
                }
            } else {
                seconds += (Date.parse(endUtc) - Date.parse(startUtc)) / 1000
                startUtc = interval.startUtc
                endUtc = interval.endUtc
            }
        }
        if (startUtc) {
            seconds += (Date.parse(endUtc) - Date.parse(startUtc)) / 1000
        }
        totals[id] = {
            id: intervalTotal.id,
            label: intervalTotal.label,
            color: intervalTotal.color,
            seconds: seconds
        }
    }
    return totals
}

function orderedTotals(totals) {
    return Object.keys(totals).map(function(key) { return totals[key] }).sort(function(left, right) {
        if (right.seconds !== left.seconds) {
            return right.seconds - left.seconds
        }
        return left.label.localeCompare(right.label)
    })
}

function dateKeys(range) {
    const keys = []
    const cursor = new Date(range.startDate + "T00:00:00.000Z")
    const end = new Date(range.endDateExclusive + "T00:00:00.000Z")
    while (cursor < end) {
        keys.push(cursor.toISOString().slice(0, 10))
        cursor.setUTCDate(cursor.getUTCDate() + 1)
    }
    return keys
}

function weekStart(date, firstDayOfWeek) {
    const cursor = new Date(date + "T00:00:00.000Z")
    const currentDay = cursor.getUTCDay() || 7
    const delta = (currentDay - firstDayOfWeek + 7) % 7
    cursor.setUTCDate(cursor.getUTCDate() - delta)
    return cursor.toISOString().slice(0, 10)
}

function aggregate(timeMath, range, timezoneId, currentUtc, firstDayOfWeek, filter) {
    const sessions = Database.listReportSessions(range.startUtc, range.endUtc, currentUtc, filter)
    const dates = {}
    const categoryIntervals = {}
    const tasks = {}
    const dailyCategoryIntervals = {}
    const dailyTasks = {}
    const sessionSegments = []
    const weeks = {}
    let totalSeconds = 0

    const allDates = dateKeys(range)
    for (let dateIndex = 0; dateIndex < allDates.length; dateIndex += 1) {
        const date = allDates[dateIndex]
        addTotal(dates, date, date, "", 0)
        const calendarWeek = weekStart(date, firstDayOfWeek)
        addTotal(weeks, calendarWeek, calendarWeek, "", 0)
    }

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
            const calendarWeek = weekStart(segment.localDate, firstDayOfWeek)
            addTotal(weeks, calendarWeek, calendarWeek, "", seconds)
            addInterval(categoryIntervals, session.categoryId, session.categoryName, session.categoryColor,
                segment.startUtc, segment.endUtc)
            addTotal(tasks, session.taskId, session.taskTitle, "", seconds)
            if (!dailyCategoryIntervals[segment.localDate]) {
                dailyCategoryIntervals[segment.localDate] = {}
            }
            if (!dailyTasks[segment.localDate]) {
                dailyTasks[segment.localDate] = {}
            }
            addInterval(dailyCategoryIntervals[segment.localDate], session.categoryId, session.categoryName,
                session.categoryColor, segment.startUtc, segment.endUtc)
            addTotal(dailyTasks[segment.localDate], session.taskId, session.taskTitle, "", seconds)
            sessionSegments.push({
                sessionId: session.sessionId,
                taskId: session.taskId,
                taskTitle: session.taskTitle,
                categoryId: session.categoryId,
                categoryName: session.categoryName,
                categoryColor: session.categoryColor,
                startUtc: segment.startUtc,
                endUtc: segment.endUtc,
                sessionStartUtc: session.startedAtUtc,
                sessionEndUtc: session.endedAtUtc,
                localDate: segment.localDate,
                manuallyEdited: session.manuallyEdited,
                active: session.active
            })
        }
    }

    const byDate = orderedTotals(dates).sort(function(left, right) { return left.id.localeCompare(right.id) })
    const dailyByCategory = Object.keys(dailyCategoryIntervals).sort().map(function(date) {
        return { date: date, categories: orderedTotals(mergedTotals(dailyCategoryIntervals[date])) }
    })
    const dailyByTask = Object.keys(dailyTasks).sort().map(function(date) {
        return { date: date, tasks: orderedTotals(dailyTasks[date]) }
    })
    return {
        startUtc: range.startUtc,
        endUtc: range.endUtc,
        startDate: range.startDate,
        endDateExclusive: range.endDateExclusive,
        totalSeconds: totalSeconds,
        byDate: byDate,
        byWeek: orderedTotals(weeks).sort(function(left, right) { return left.id.localeCompare(right.id) }),
        byCategory: orderedTotals(mergedTotals(categoryIntervals)),
        byTask: orderedTotals(tasks),
        dailyByCategory: dailyByCategory,
        dailyByTask: dailyByTask,
        sessionSegments: sessionSegments
    }
}

function dailyReport(timeMath, input) {
    input = input || {}
    const range = timeMath.dayRange(input.year, input.month, input.day, input.timezoneId)
    if (!range.valid) {
        throw new Error(range.error)
    }
    return aggregate(timeMath, range, input.timezoneId, input.currentUtc,
        input.firstDayOfWeek === undefined ? 1 : input.firstDayOfWeek, input)
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
    return aggregate(timeMath, range, input.timezoneId, input.currentUtc,
        input.firstDayOfWeek === undefined ? 1 : input.firstDayOfWeek, input)
}

function monthlyReport(timeMath, input) {
    input = input || {}
    const range = timeMath.monthRange(input.year, input.month, input.timezoneId)
    if (!range.valid) {
        throw new Error(range.error)
    }
    return aggregate(timeMath, range, input.timezoneId, input.currentUtc,
        input.firstDayOfWeek === undefined ? 1 : input.firstDayOfWeek, input)
}

function yearlyReport(timeMath, input) {
    input = input || {}
    const range = timeMath.trailingYearRange(input.year, input.month, input.day, input.timezoneId)
    if (!range.valid) {
        throw new Error(range.error)
    }
    return aggregate(timeMath, range, input.timezoneId, input.currentUtc,
        input.firstDayOfWeek === undefined ? 1 : input.firstDayOfWeek, input)
}
