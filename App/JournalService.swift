import Foundation

struct JournalPage:Decodable {
    var records:[SharedRecord]
    var farts:[FartClip]
    var counts:[String:Int]
    var hearts:[String:Int]
    var hasMore:Bool
    var nextOffset:Int
    enum CodingKeys:String,CodingKey {case records,farts,counts,hearts;case hasMore="has_more",nextOffset="next_offset"}
}
extension APIClient {
    func journal(day:Date) async throws -> JournalPage {
        let cal=Calendar.current,start=cal.startOfDay(for:day)
        guard let end=cal.date(byAdding:.day,value:1,to:start) else{throw APIClientError.invalidResponse}
        var offset=0,result:JournalPage?
        repeat {
            try Task.checkCancellation()
            var req=try request(path:"/v1/journal",method:"GET")
            var url=URLComponents(url:req.url!,resolvingAgainstBaseURL:false)!
            url.queryItems=[URLQueryItem(name:"start",value:start.rjISO8601),URLQueryItem(name:"end",value:end.rjISO8601),URLQueryItem(name:"offset",value:String(offset))];req.url=url.url
            let page=try await execute(req,as:JournalPage.self)
            if result==nil {result=page}else{result!.records += page.records;result!.farts += page.farts;result!.counts=page.counts;result!.hearts=page.hearts}
            if !page.hasMore{break}
            guard page.nextOffset>offset else{throw APIClientError.invalidResponse};offset=page.nextOffset
        }while true
        guard let result else{throw APIClientError.invalidResponse};return result
    }
}
enum JournalDates {
    static func key(_ date:Date)->String {
        var cal=Calendar(identifier:.gregorian);cal.timeZone = .autoupdatingCurrent
        let c=cal.dateComponents([.year,.month,.day],from:date)
        return String(format:"%04d-%02d-%02d",c.year ?? 2000,c.month ?? 1,c.day ?? 1)
    }
    static func date(_ record:SharedRecord)->Date? {
        if record.kind == .moment || record.kind == .instant || record.kind == .poop{return (record.payload.capturedAt ?? record.createdAt).rjDate}
        if record.kind == .ritual{return record.payload.startAt?.rjDate ?? record.createdAt.rjDate}
        return record.createdAt.rjDate
    }
}
struct SharedActivityItem:Identifiable {
    let id:String
    let owner:String
    let date:Date
    let title:String
    let text:String
    let symbol:String
    var record:SharedRecord?
    var clip:FartClip?
    static func make(records:[SharedRecord],farts:[FartClip])->[Self] {
        let words:[RecordKind:(String,String)]=[
            .poop:("Ein stilles Kapitel","toilet.fill"),.instant:("Ein echtes Jetzt","camera.on.rectangle.fill"),.moment:("Ein Moment für euch","photo.fill"),
            .chat:("Ein paar Worte","bubble.left.fill"),.wish:("Ein Wunsch für uns","sparkles"),
            .checkin:("So geht es mir","face.smiling.fill"),.gratitude:("Das mag ich an dir","heart.text.square.fill"),
            .coupon:("Ein Liebesgutschein","gift.fill"),.milestone:("Unsere gemeinsame Zeit","calendar.badge.heart"),
            .calendar:("Ein Termin gespeichert","calendar"),.reminder:("Eine Erinnerung","checklist"),
            .note:("Eine gemeinsame Notiz","note.text"),.ritual:("Unser Abendritual","moon.stars.fill")]
        var items=records.compactMap{r->Self? in
            guard let pair=words[r.kind],let date=JournalDates.date(r) else{return nil}
            let text=r.payload.caption ?? r.payload.text ?? r.payload.notes ?? ""
            let title=(r.payload.title?.isEmpty == false ? r.payload.title: nil) ?? pair.0
            return Self(id:r.id,owner:r.ownerID,date:date,title:title,text:text,symbol:pair.1,record:r)
        }
        items += farts.compactMap{c in guard let date=c.date else{return nil};return Self(id:c.id,owner:c.ownerID,date:date,title:c.title,text:c.caption,symbol:"cloud.fill",clip:c)}
        return items.sorted{$0.date == $1.date ? $0.id>$1.id:$0.date>$1.date}
    }
}
