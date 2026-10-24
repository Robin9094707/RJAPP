#if DEBUG
import Foundation
import UIKit
@MainActor enum PreviewFixtures {
    static func moments()->[SharedRecord] {
        return (0..<12).map{index in
            let colors:[UIColor]=[.systemPink,.systemTeal,.systemPurple,.systemOrange]
            let image=UIGraphicsImageRenderer(size:CGSize(width:300,height:300)).image{context in
                colors[index%4].withAlphaComponent(0.3).setFill();context.fill(CGRect(x:0,y:0,width:300,height:300))
                let icon=UIImage(systemName:["leaf.fill","heart.fill","sun.max.fill","moon.stars.fill"][index%4])?.withTintColor(colors[index%4],renderingMode:.alwaysOriginal);icon?.draw(in:CGRect(x:90,y:70,width:120,height:120))
                (["Unser Spaziergang","Kleine Lieblingsmomente","Zusammen unterwegs","Ein Abend für uns"][index%4] as NSString).draw(in:CGRect(x:20,y:240,width:260,height:50),withAttributes:[.font:UIFont.systemFont(ofSize:17,weight:.semibold),.foregroundColor:UIColor.darkGray])
            }
            let bytes=image.jpegData(compressionQuality:0.8)!,date=Calendar.current.date(byAdding:.day,value:-index*9,to:.now)!
            var p=RecordPayload(caption:["Unser Spaziergang","Kleine Lieblingsmomente","Zusammen unterwegs","Ein Abend für uns"][index%4]);p.imageBase64=bytes.base64EncodedString();p.posterBase64=p.imageBase64;p.mediaKind="image";p.capturedAt=date.rjISO8601;p.latitude=51.43+Double(index%5)*0.007;p.longitude=6.76+Double(index%4)*0.01
            return SharedRecord(id:UUID().uuidString,kind:.moment,ownerID:index%2==0 ? "robin":"raphaela",payload:p,createdAt:date.rjISO8601,updatedAt:date.rjISO8601)
        }
    }
    static func media()->SelectedMedia {
        let image=UIGraphicsImageRenderer(size:CGSize(width:120,height:120)).image{context in UIColor.systemPink.setFill();context.fill(CGRect(x:0,y:0,width:120,height:120))}
        let bytes=image.jpegData(compressionQuality:0.8)!
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".jpg")
        try! bytes.write(to:file)
        return SelectedMedia(files:[file],mimeTypes:["image/jpeg"],kind:"image",capturedAt:.now,poster:bytes)
    }
}
#endif
