import Foundation

enum MotionPresentation {
    static func symbol(_ value:String)->String {
        switch value{case "Auto":"car.fill";case "Fahrrad":"figure.outdoor.cycle";case "Laufen":"figure.run";case "Zu Fuß":"figure.walk";case "Stationär":"figure.stand";default:"figure.stand.questionmark"}
    }
    static func title(_ value:String)->String {value=="Stationär" ? "In Ruhe":value=="Unbekannt" ? "Noch keine Bewegung erkannt":value}
}
