import Foundation
@main struct GalleryChecks {
    static func main(){
        for width in [320.0,375,393,430,744,834,1024] {
            let side=GalleryMetrics.tileSide(width:width)
            precondition(side>0 && abs(3*side+6+36-width)<0.001)
        }
        print("Gallery geometry verified: three equal square columns on iPhone and iPad widths.")
    }
}
