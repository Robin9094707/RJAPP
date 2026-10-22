import AlarmKit
import CryptoKit
import EventKit
import Foundation
import Observation

@MainActor @Observable final class PlannerService {
    static let shared=PlannerService()
    var status="Wird beim Öffnen abgeglichen."
    private var working=false
    private var alarmError:String?
    private struct Link:Codable {var calendarID:String?;var reminderID:String?;var source:String;var nativeCalendar:String?;var nativeReminder:String?}
    func reconcile(app:AppState) async {
        guard !working,let me=app.me,let profile=app.profile else{return};working=true;defer{working=false}
        let namespace="rjlove.planner."+SHA256.hash(data:Data((profile.baseURL+me.id).utf8)).map{String(format:"%02x",$0)}.joined()
        var links=(UserDefaults.standard.data(forKey:namespace).flatMap{try? JSONDecoder().decode([String:Link].self,from:$0)}) ?? [:]
        let store=CalendarService.shared.store
        let canEvents=EKEventStore.authorizationStatus(for:.event) == .fullAccess
        let canReminders=EKEventStore.authorizationStatus(for:.reminder) == .fullAccess
        let records=app.records.filter{[RecordKind.calendar,.milestone,.reminder].contains($0.kind) && ($0.kind != .reminder || $0.payload.targetID==nil || $0.payload.targetID==me.id)}
        var failures:[String]=[]
        for record in records {
            let source=Self.signature(record.payload)
            var link=links[record.id] ?? Link(source:source)
            var payload=record.payload
            let date=(record.kind == .reminder ? payload.dueAt:payload.startAt)?.rjDate
            guard let date else{continue}
            do {
                if record.kind != .reminder,canEvents,payload.calendarSync != false {
                    let event=link.calendarID.flatMap{store.event(withIdentifier:$0)} ?? EKEvent(eventStore:store)
                    let native=Self.eventSignature(event)
                    if let previous=link.nativeCalendar,previous != native,link.source==source,event.calendar != nil {
                        payload.title=event.title;payload.startAt=event.startDate?.rjISO8601;payload.endAt=event.endDate?.rjISO8601;payload.location=event.location;payload.notes=event.notes
                        if record.kind == .milestone {payload.endAt=nil;payload.location=nil;payload.notes=nil}
                        if await app.saveRecord(id:record.id,kind:record.kind,payload:payload)==nil{continue}
                    } else {
                        event.title=payload.title ?? "Unsere Zeit";event.startDate=date;event.endDate=payload.endAt?.rjDate ?? date.addingTimeInterval(3600);event.notes=payload.notes ?? payload.text;event.location=payload.location
                        event.recurrenceRules=payload.recurrence=="yearly" ? [EKRecurrenceRule(recurrenceWith:.yearly,interval:1,end:nil)]:nil
                        if event.calendar==nil {event.calendar=store.defaultCalendarForNewEvents}
                        if link.nativeCalendar != Self.eventSignature(event) {try store.save(event,span:.futureEvents,commit:true)}
                    }
                    link.calendarID=event.eventIdentifier;link.nativeCalendar=Self.eventSignature(event)
                } else if let id=link.calendarID,let event=store.event(withIdentifier:id),canEvents {
                    try store.remove(event,span:.futureEvents,commit:true);link.calendarID=nil;link.nativeCalendar=nil
                }
                if canReminders,payload.reminderSync != false {
                    let reminder=(link.reminderID.flatMap{store.calendarItem(withIdentifier:$0)} as? EKReminder) ?? EKReminder(eventStore:store)
                    let native=Self.reminderSignature(reminder)
                    if let previous=link.nativeReminder,previous != native,link.source==source,reminder.calendar != nil {
                        payload.title=reminder.title
                        if record.kind == .reminder {payload.completed=reminder.isCompleted;if let components=reminder.dueDateComponents,let due=Calendar.current.date(from:components){payload.dueAt=due.rjISO8601}}
                        if await app.saveRecord(id:record.id,kind:record.kind,payload:payload)==nil{continue}
                    } else {
                        reminder.title=payload.title ?? "Gemeinsam geplant";reminder.notes=payload.notes ?? payload.text ?? payload.message
                        reminder.dueDateComponents=Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second],from:date)
                        reminder.recurrenceRules=payload.recurrence=="yearly" ? [EKRecurrenceRule(recurrenceWith:.yearly,interval:1,end:nil)]:nil
                        reminder.isCompleted=payload.completed ?? false
                        if reminder.calendar==nil {reminder.calendar=store.defaultCalendarForNewReminders()}
                        if link.nativeReminder != Self.reminderSignature(reminder){try store.save(reminder,commit:true)}
                    }
                    link.reminderID=reminder.calendarItemIdentifier;link.nativeReminder=Self.reminderSignature(reminder)
                } else if let id=link.reminderID,let reminder=store.calendarItem(withIdentifier:id) as? EKReminder,canReminders {
                    try store.remove(reminder,commit:true);link.reminderID=nil;link.nativeReminder=nil
                }
                link.source=Self.signature(payload);links[record.id]=link
            } catch{failures.append(error.localizedDescription)}
        }
        let live=Set(records.map(\.id))
        for (id,link) in links where !live.contains(id) {
            do {
                if canEvents,let identifier=link.calendarID,let event=store.event(withIdentifier:identifier){try store.remove(event,span:.futureEvents,commit:true)}
                if canReminders,let identifier=link.reminderID,let reminder=store.calendarItem(withIdentifier:identifier) as? EKReminder{try store.remove(reminder,commit:true)}
                links.removeValue(forKey:id)
            } catch{failures.append(error.localizedDescription)}
        }
        if let data=try? JSONEncoder().encode(links){UserDefaults.standard.set(data,forKey:namespace)}
        await reconcileAlarms(records,namespace:namespace)
        status=failures.first ?? alarmError ?? "Abgeglichen · \(records.count) gemeinsame Einträge. Kalender: \(canEvents ? "verbunden":"nicht freigegeben"), Erinnerungen: \(canReminders ? "verbunden":"nicht freigegeben")."
    }
    private static func signature(_ payload:RecordPayload)->String {let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys;return (try? encoder.encode(payload).base64EncodedString()) ?? ""}
    private static func eventSignature(_ event:EKEvent)->String {[event.title ?? "",event.startDate?.rjISO8601 ?? "",event.endDate?.rjISO8601 ?? "",event.notes ?? "",event.location ?? "",String(event.recurrenceRules?.count ?? 0)].joined(separator:"|")}
    private static func reminderSignature(_ reminder:EKReminder)->String {[reminder.title ?? "",reminder.dueDateComponents.flatMap{Calendar.current.date(from:$0)}?.rjISO8601 ?? "",String(reminder.isCompleted),reminder.notes ?? "",String(reminder.recurrenceRules?.count ?? 0)].joined(separator:"|")}
    static func occurrences(_ date:Date,yearly:Bool)->[Date] {
        guard yearly else{return date > .now ? [date]:[]}
        let cal=Calendar.current;let original=cal.dateComponents([.month,.day,.hour,.minute,.second],from:date);let year=cal.component(.year,from:.now)
        return (year...year+4).compactMap { y in
            var components=original;components.year=y
            if components.month==2,components.day==29,cal.range(of:.day,in:.month,for:cal.date(from:DateComponents(year:y,month:2,day:1))!)?.count==28 {components.day=28}
            return cal.date(from:components)
        }.filter{$0 > .now}
    }
    private func reconcileAlarms(_ records:[SharedRecord],namespace:String) async {
        alarmError=nil
        var desired:[String:(Date,String)]=[:]
        for record in records where record.payload.alarmEnabled==true && record.payload.completed != true {
            if record.kind == .reminder && record.payload.recurrence != "yearly" {continue}
            guard let date=(record.payload.dueAt ?? record.payload.startAt)?.rjDate else{continue}
            for occurrence in Self.occurrences(date,yearly:record.payload.recurrence=="yearly") {
                let hash=SHA256.hash(data:Data((record.id+occurrence.rjISO8601).utf8)).map{String(format:"%02x",$0)}.joined();let h=Array(hash.prefix(32));let id=String(h[0..<8])+"-"+String(h[8..<12])+"-"+String(h[12..<16])+"-"+String(h[16..<20])+"-"+String(h[20..<32])
                desired[id]=(occurrence,record.payload.title ?? "Unsere Zeit")
            }
        }
        let selected=desired.sorted{$0.value.0 < $1.value.0}.prefix(48)
        let allowed=Set(selected.map(\.key));let key=namespace+".alarms"
        var ledger=UserDefaults.standard.dictionary(forKey:key) as? [String:String] ?? [:]
        if let actual=try? AlarmManager.shared.alarms {
            let active=Set(actual.map{$0.id.uuidString.lowercased()})
            for id in ledger.keys.filter({!active.contains($0.lowercased())}){ledger.removeValue(forKey:id)}
        }
        if desired.count>48 {alarmError="Die nächsten 48 Jahres-/Terminwecker werden geplant; weitere werden beim Öffnen nachgerückt."}
        for id in ledger.keys.filter({!allowed.contains($0)}) {if let uuid=UUID(uuidString:id){try? AlarmManager.shared.cancel(id:uuid)};ledger.removeValue(forKey:id)}
        for (id,entry) in selected {
            let signature=entry.0.rjISO8601+entry.1
            guard ledger[id] != signature else{continue}
            if AlarmManager.shared.authorizationState != .authorized { let granted=await AlarmService.shared.requestAuthorization(); if !granted {alarmError="AlarmKit ist nicht freigegeben.";break} }
            if let uuid=UUID(uuidString:id) {
                if ledger[id] != nil{try? AlarmManager.shared.cancel(id:uuid)}
                do {try await RJLoveAlarmFactory.schedule(id:uuid,title:entry.1,senderName:"Unsere Zeit",fireDate:entry.0);ledger[id]=signature}
                catch{alarmError=error.localizedDescription}
            }
        }
        UserDefaults.standard.set(ledger,forKey:key)
    }
}
