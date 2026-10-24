import Foundation
@main struct RelationshipChecks {
    static func main(){
        var cal=Calendar(identifier:.gregorian);cal.timeZone=TimeZone(identifier:"Europe/Berlin")!
        func date(_ y:Int,_ m:Int,_ d:Int)->Date{cal.date(from:DateComponents(year:y,month:m,day:d,hour:12))!}
        let start=date(2026,5,3)
        let first=RelationshipMilestones(start:start,now:start,calendar:cal);assert(first.completedMonths==0 && first.currentMonth==1)
        let before=RelationshipMilestones(start:start,now:date(2026,6,2),calendar:cal);assert(before.completedMonths==0 && before.daysUntilMonthly==1)
        let next=RelationshipMilestones(start:start,now:date(2026,6,3),calendar:cal);assert(next.completedMonths==1 && next.currentMonth==2)
        let october=RelationshipMilestones(start:start,now:date(2026,10,24),calendar:cal);assert(october.completedMonths==5 && october.currentMonth==6 && october.daysUntilMonthly==10)
        let clamped=RelationshipMilestones(start:date(2026,1,31),now:date(2026,2,28),calendar:cal);assert(clamped.completedMonths==1 && clamped.currentMonth==2 && cal.component(.day,from:clamped.nextMonthlyDate)==31)
        let leap=RelationshipMilestones(start:date(2024,2,29),now:date(2025,2,28),calendar:cal);assert(leap.completedMonths==12 && leap.currentMonth==13)
        let future=RelationshipMilestones(start:start,now:date(2026,4,30),calendar:cal);assert(future.startsInFuture && future.currentMonth==0 && future.daysUntilMonthly==3)
        print("Relationship dates checked: month boundaries, leap day, future start and calendar days.")
    }
}
