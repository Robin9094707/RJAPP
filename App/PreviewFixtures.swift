#if DEBUG
import Foundation
import UIKit
@MainActor enum PreviewFixtures {
    static func media()->SelectedMedia {
        let image=UIGraphicsImageRenderer(size:CGSize(width:120,height:120)).image{context in UIColor.systemPink.setFill();context.fill(CGRect(x:0,y:0,width:120,height:120))}
        let bytes=image.jpegData(compressionQuality:0.8)!
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".jpg")
        try! bytes.write(to:file)
        return SelectedMedia(files:[file],mimeTypes:["image/jpeg"],kind:"image",capturedAt:.now,poster:bytes)
    }
}
#endif
