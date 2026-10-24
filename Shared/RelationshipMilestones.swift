import Foundation

struct RelationshipMilestones:Sendable {
    let start:Date
    let completedMonths:Int
    let currentMonth:Int
    let nextMonthlyDate:Date
    let nextMonthlyNumber:Int
    let daysUntilMonthly:Int
    let togetherDays:Int
    let startsInFuture:Bool
    init(start:Date,now:Date = .now,calendar:Calendar = .current) {
        let origin=calendar.startOfDay(for:start),today=calendar.startOfDay(for:now)
        self.start=origin;startsInFuture=origin>today
        let a=calendar.dateComponents([.year,.month],from:origin),b=calendar.dateComponents([.year,.month],from:today)
        var months=max(0,((b.year ?? 0)-(a.year ?? 0))*12+(b.month ?? 0)-(a.month ?? 0))
        if let boundary=calendar.date(byAdding:.month,value:months,to:origin),boundary>today{months=max(0,months-1)}
        completedMonths=months;currentMonth=startsInFuture ? 0:months+1;nextMonthlyNumber=startsInFuture ? 0:months+1
        nextMonthlyDate=startsInFuture ? origin:(calendar.date(byAdding:.month,value:months+1,to:origin) ?? origin)
        daysUntilMonthly=max(0,calendar.dateComponents([.day],from:today,to:nextMonthlyDate).day ?? 0)
        togetherDays=max(0,calendar.dateComponents([.day],from:origin,to:today).day ?? 0)
    }
}
