import CoreLocation
import MapKit
import SwiftUI

struct PhotoPlaceView:View {
    let payload:RecordPayload
    var body:some View {
        if let latitude=payload.latitude,let longitude=payload.longitude {
            let point=CLLocationCoordinate2D(latitude:latitude,longitude:longitude)
            VStack(alignment:.leading,spacing:8) {
                Label("Hier ist euer Moment entstanden",systemImage:"mappin.and.ellipse").font(.subheadline.bold())
                Map(initialPosition:.region(MKCoordinateRegion(center:point,span:MKCoordinateSpan(latitudeDelta:0.008,longitudeDelta:0.008)))) {
                    Marker("Aufnahmeort",coordinate:point).tint(.pink)
                }.mapStyle(.standard).frame(height:170).clipShape(RoundedRectangle(cornerRadius:18))
                Button("In Karten öffnen",systemImage:"arrow.up.right.square") {
                    let item=MKMapItem(placemark:MKPlacemark(coordinate:point));item.name="Unser Aufnahmeort";item.openInMaps()
                }.font(.caption)
            }
        }
    }
}
