import Foundation

struct LoveCountdown:Codable,Identifiable,Hashable,Sendable {
    var id:String
    var title:String
    var date:String
    var yearly:Bool
    var anniversary:Bool
    var origin:Date? {date.rjDate}
    func nextDate(at now:Date = .now,calendar:Calendar = .current)->Date? {
        guard let origin else{return nil}
        guard yearly else{return origin}
        let today=calendar.startOfDay(for:now)
        let startYear=max(calendar.component(.year,from:now),calendar.component(.year,from:origin))
        var components=calendar.dateComponents([.month,.day,.hour,.minute,.second],from:origin)
        for year in startYear...startYear+2 {
            components.year=year
            if components.month==2,calendar.date(from:DateComponents(year:year,month:2,day:1)).flatMap({calendar.range(of:.day,in:.month,for:$0)?.count})==28,components.day==29 {components.day=28}
            if let candidate=calendar.date(from:components),calendar.startOfDay(for:candidate)>=today {return candidate}
            components=calendar.dateComponents([.month,.day,.hour,.minute,.second],from:origin)
        }
        return nil
    }
    func days(at now:Date = .now)->Int? {
        guard let date=nextDate(at:now) else{return nil}
        return Calendar.current.dateComponents([.day],from:Calendar.current.startOfDay(for:now),to:Calendar.current.startOfDay(for:date)).day
    }
    init?(record:SharedRecord) {
        guard record.kind == .milestone,let date=record.payload.startAt,date.rjDate != nil else{return nil}
        id=record.id;title=record.payload.title ?? "Unsere Zeit";self.date=date
        anniversary=record.payload.countdownType=="anniversary"
        yearly=anniversary || record.payload.recurrence=="yearly"
    }
    init(id:String,title:String,date:String,yearly:Bool,anniversary:Bool) {
        self.id=id;self.title=title;self.date=date;self.yearly=yearly;self.anniversary=anniversary
    }
}
