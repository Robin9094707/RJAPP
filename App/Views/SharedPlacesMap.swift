import MapKit
import SwiftUI

struct SharedPlacePin:Hashable {
    let id:String
    let title:String
    let subtitle:String
    let latitude:Double
    let longitude:Double
    let glyph:String
    let mine:Bool
}
struct SharedPlacesMap:UIViewRepresentable {
    var pins:[SharedPlacePin]
    var selected:(String)->Void
    func makeCoordinator()->Coordinator{Coordinator(self)}
    func makeUIView(context:Context)->MKMapView {
        let map=MKMapView();map.delegate=context.coordinator;map.showsCompass=true;map.showsScale=true
        map.register(MKMarkerAnnotationView.self,forAnnotationViewWithReuseIdentifier:"place")
        map.register(MKMarkerAnnotationView.self,forAnnotationViewWithReuseIdentifier:MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        return map
    }
    func updateUIView(_ map:MKMapView,context:Context){
        let coordinator=context.coordinator;coordinator.parent=self
        guard coordinator.pins != pins else{return};coordinator.pins=pins
        map.removeAnnotations(map.annotations);map.addAnnotations(pins.map{Pin($0)})
        if !coordinator.fitted,!pins.isEmpty{map.showAnnotations(map.annotations,animated:false);coordinator.fitted=true}
    }
    final class Pin:NSObject,MKAnnotation {
        let place:SharedPlacePin
        var coordinate:CLLocationCoordinate2D{CLLocationCoordinate2D(latitude:place.latitude,longitude:place.longitude)}
        var title:String?{place.title};var subtitle:String?{place.subtitle}
        init(_ place:SharedPlacePin){self.place=place}
    }
    final class Coordinator:NSObject,MKMapViewDelegate {
        var parent:SharedPlacesMap;var pins:[SharedPlacePin]=[];var fitted=false
        init(_ parent:SharedPlacesMap){self.parent=parent}
        func mapView(_ mapView:MKMapView,viewFor annotation:MKAnnotation)->MKAnnotationView? {
            if let cluster=annotation as? MKClusterAnnotation{let view=mapView.dequeueReusableAnnotationView(withIdentifier:MKMapViewDefaultClusterAnnotationViewReuseIdentifier,for:cluster) as! MKMarkerAnnotationView;view.markerTintColor = .systemPurple;view.glyphText="\(cluster.memberAnnotations.count)";return view}
            guard let pin=annotation as? Pin else{return nil}
            let view=mapView.dequeueReusableAnnotationView(withIdentifier:"place",for:pin) as! MKMarkerAnnotationView
            view.clusteringIdentifier="rj-places";view.markerTintColor=pin.place.mine ? .systemPink:.systemPurple;view.glyphText=pin.place.glyph;view.canShowCallout=false;return view
        }
        func mapView(_ mapView:MKMapView,didSelect view:MKAnnotationView){
            if let cluster=view.annotation as? MKClusterAnnotation {
                var rect=MKMapRect.null
                for point in cluster.memberAnnotations{let p=MKMapPoint(point.coordinate);rect=rect.union(MKMapRect(x:p.x,y:p.y,width:500,height:500))}
                mapView.setVisibleMapRect(rect,edgePadding:UIEdgeInsets(top:50,left:50,bottom:50,right:50),animated:true)
            }else if let pin=view.annotation as? Pin{parent.selected(pin.place.id);mapView.deselectAnnotation(pin,animated:false)}
        }
    }
}
struct MomentsAtlasView:View {
    @Environment(AppState.self) private var app
    let records:[SharedRecord]
    @State private var selection:SharedRecord?
    private var pins:[SharedPlacePin]{records.compactMap{record in guard let a=record.payload.latitude,let b=record.payload.longitude,a.isFinite,b.isFinite,abs(a)<=90,abs(b)<=180 else{return nil};return SharedPlacePin(id:record.id,title:record.payload.caption ?? "Unser Moment",subtitle:JournalDates.date(record)?.formatted(date:.abbreviated,time:.shortened) ?? "",latitude:a,longitude:b,glyph:record.payload.mediaKind=="video" ? "▶︎":"📷",mine:record.ownerID==app.me?.id)}}
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            if pins.isEmpty{ContentUnavailableView("Eure Erinnerungen bekommen einen Ort",systemImage:"map",description:Text("Hier erscheinen Momente mit freigegebenen Foto-Metadaten oder einem Aufnahmeort aus der App. Fehlende Orte werden nicht geraten."))}
            else{SharedPlacesMap(pins:pins){id in selection=records.first{$0.id==id}}.frame(minHeight:420).clipShape(RoundedRectangle(cornerRadius:24));Text("\(pins.count) Momente mit Ort · Rosa: du · Lila: dein Lieblingsmensch").font(.caption).foregroundStyle(.secondary)}
            if pins.count<records.count{Text("\(records.count-pins.count) Momente haben keinen freigegebenen Aufnahmeort.").font(.caption).foregroundStyle(.secondary)}
        }.sheet(item:$selection){record in MomentGalleryViewer(records:records,initialID:record.id)}
    }
}
