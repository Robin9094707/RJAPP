import SwiftUI
import UIKit

/// Native calendar selection and accessibility, with a decoration for actual photo days.
struct PhotoCalendarView:UIViewRepresentable {
    @Binding var selection:Date
    var photos:[SharedRecord]
    func makeCoordinator()->Coordinator {Coordinator(self)}
    func makeUIView(context:Context)->UICalendarView {
        let view=UICalendarView();view.calendar = .current;view.locale = .autoupdatingCurrent
        view.fontDesign = .rounded;view.delegate=context.coordinator
        view.availableDateRange=DateInterval(start:Calendar.current.date(from:DateComponents(year:1900,month:1,day:1))!,end:.now)
        let behavior=UICalendarSelectionSingleDate(delegate:context.coordinator);view.selectionBehavior=behavior
        let components=Calendar.current.dateComponents([.year,.month,.day],from:selection)
        behavior.setSelected(components,animated:false);view.setVisibleDateComponents(components,animated:false)
        context.coordinator.selected=selection
        view.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        return view
    }
    func sizeThatFits(_ proposal:ProposedViewSize,uiView:UICalendarView,context:Context)->CGSize? {
        guard let width=proposal.width,width>0 else{return nil}
        // Let UIKit include its month header and all week rows at the current text size.
        // A fixed SwiftUI height can place that header outside the calendar's bounds.
        return uiView.systemLayoutSizeFitting(
            CGSize(width:width,height:UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority:.required,verticalFittingPriority:.fittingSizeLevel)
    }
    func updateUIView(_ view:UICalendarView,context:Context) {
        let old=context.coordinator.counts
        let counts=Dictionary(grouping:photos.compactMap{JournalDates.date($0)},by:{Calendar.current.startOfDay(for:$0)}).mapValues(\.count)
        context.coordinator.parent=self;context.coordinator.counts=counts
        if old != counts {
            let days=Set(old.keys).union(counts.keys).map{Calendar.current.dateComponents([.year,.month,.day],from:$0)}
            view.reloadDecorations(forDateComponents:days,animated:true)
        }
        if !Calendar.current.isDate(selection,inSameDayAs:context.coordinator.selected) {
            let c=Calendar.current.dateComponents([.year,.month,.day],from:selection)
            (view.selectionBehavior as? UICalendarSelectionSingleDate)?.setSelected(c,animated:true)
            view.setVisibleDateComponents(c,animated:true);context.coordinator.selected=selection
        }
    }
    final class Coordinator:NSObject,UICalendarViewDelegate,UICalendarSelectionSingleDateDelegate {
        var parent:PhotoCalendarView
        var selected:Date = .now
        var counts:[Date:Int]=[:]
        init(_ parent:PhotoCalendarView){self.parent=parent}
        func dateSelection(_ selection:UICalendarSelectionSingleDate,didSelectDate components:DateComponents?) {
            guard let components,let date=Calendar.current.date(from:components) else{return}
            selected=date;parent.selection=date;Haptics.impact(.soft)
        }
        func calendarView(_ calendarView:UICalendarView,decorationFor dateComponents:DateComponents)->UICalendarView.Decoration? {
            guard let date=Calendar.current.date(from:dateComponents),let count=counts[Calendar.current.startOfDay(for:date)] else{return nil}
            return .customView {
                let label=UILabel();label.text="\(count)";label.font = .systemFont(ofSize:10,weight:.bold);label.textColor = .systemPink;label.textAlignment = .center;label.accessibilityLabel="\(count) BeReal-Fotos";return label
            }
        }
    }
}
