import Foundation

enum GalleryMetrics {
    static func tileSide(width:Double,padding:Double=18,gap:Double=3)->Double {max(1,(width-2*padding-2*gap)/3)}
}
