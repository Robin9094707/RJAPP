import AVKit
import Photos
import ImageIO
import SwiftUI
import UIKit

struct MomentPreview:View {
    @Environment(AppState.self) private var app
    let record:SharedRecord
    @State private var image:UIImage?
    var body:some View {
        GeometryReader { proxy in
        ZStack(alignment:.bottomTrailing){
            Color(.secondarySystemGroupedBackground)
            if let image{Image(uiImage:image).resizable().scaledToFill().frame(width:proxy.size.width,height:proxy.size.height).clipped()}
            else{Image(systemName:record.payload.mediaKind=="video" ? "video.fill":"photo").font(.title2).foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity)}
            if record.payload.mediaKind=="video"{Image(systemName:"play.fill").font(.caption.bold()).foregroundStyle(.white).padding(8).background(.black.opacity(0.4),in:Circle()).padding(7)}
            else if record.payload.mediaKind=="live"{Image(systemName:"livephoto").foregroundStyle(.white).padding(8)}
        }.frame(width:proxy.size.width,height:proxy.size.height).clipped()
        }.clipped().task(id:record.id+record.updatedAt){await load()}.onDisappear{image=nil}
    }
    private func load() async {
        let key=record.id+record.updatedAt
        if let cached=MomentPreviewCache.shared.image(for:key){image=cached;return}
        if let encoded=record.payload.posterBase64 ?? record.payload.imageBase64 {image=await MomentPreviewCache.shared.decode(encoded,key:key);return}
        await MomentVideoPreviewGate.shared.enter();defer{Task{await MomentVideoPreviewGate.shared.leave()}}
        guard !Task.isCancelled else{return}
        if record.payload.mediaKind != "video" {
            do {
                let file=try await app.api.momentThumbnail(record.id);defer{try? FileManager.default.removeItem(at:file)}
                let photo=await Task.detached(priority:.utility){()->UIImage? in
                    guard let source=CGImageSourceCreateWithURL(file as CFURL,nil),let thumb=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:500] as CFDictionary)else{return nil}
                    return UIImage(cgImage:thumb)
                }.value
                guard !Task.isCancelled else{return};if let photo{MomentPreviewCache.shared.save(photo,key:key);image=photo}
            }catch{}
            return
        }
        guard let id=record.payload.assetIDs?.first else{return}
        guard !Task.isCancelled else{return}
        do{
            let url=try await app.api.playbackURL(assetID:id),generator=AVAssetImageGenerator(asset:AVURLAsset(url:url))
            generator.maximumSize=CGSize(width:500,height:500);generator.appliesPreferredTrackTransform=true
            let result=try await generator.image(at:.zero);guard !Task.isCancelled else{return}
            let photo=UIImage(cgImage:result.image);MomentPreviewCache.shared.save(photo,key:key);image=photo
        }catch{}
    }
}
private actor MomentVideoPreviewGate {
    static let shared=MomentVideoPreviewGate()
    private var active=0
    private var waiters:[CheckedContinuation<Void,Never>]=[]
    func enter() async {if active<2{active += 1}else{await withCheckedContinuation{waiters.append($0)}}}
    func leave(){if waiters.isEmpty{active -= 1}else{waiters.removeFirst().resume()}}
}

struct MomentGalleryViewer:View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var records:[SharedRecord]
    @State private var selection:String
    @State private var detail:SharedRecord?
    @State private var exportFiles:[URL]=[]
    @State private var exporting=false
    @State private var sharing=false
    @State private var message:String?
    init(records:[SharedRecord],initialID:String){_records=State(initialValue:records);_selection=State(initialValue:initialID)}
    private var current:SharedRecord?{records.first{$0.id==selection}}
    var body:some View {
        NavigationStack {
            TabView(selection:$selection){ForEach(records){record in MomentGalleryPage(record:record,active:selection==record.id).tag(record.id)}}.tabViewStyle(.page(indexDisplayMode:.never)).background(.black)
            .safeAreaInset(edge:.bottom){if let current{VStack(spacing:6){Text(current.payload.caption ?? "Unser Moment").font(.subheadline).lineLimit(2);HStack{Text(current.ownerID==app.me?.id ? "Von dir":"Von "+(app.partner?.displayName ?? "Schatzi"));if let date=JournalDates.date(current){Text(date.formatted(date:.abbreviated,time:.shortened))}}.font(.caption).foregroundStyle(.secondary);if exporting{ProgressView("Original wird für dich vorbereitet …")};if let message{Text(message).font(.caption)}}.padding(14).frame(maxWidth:.infinity).background(.regularMaterial)}}
            .navigationTitle("\((records.firstIndex{$0.id==selection} ?? 0)+1) von \(records.count)").navigationBarTitleDisplayMode(.inline)
            .toolbar{
                ToolbarItem(placement:.cancellationAction){Button("Fertig"){dismiss()}}
                ToolbarItem(placement:.topBarTrailing){if current?.kind == .moment {Button("Infos",systemImage:"info.circle"){detail=current}}}
                ToolbarItem(placement:.topBarTrailing){
                    Menu {
                        Button("Original teilen",systemImage:"square.and.arrow.up"){Task{await export(save:false)}}
                        Button("In Apple Fotos sichern",systemImage:"square.and.arrow.down"){Task{await export(save:true)}}
                    }label:{Image(systemName:"ellipsis.circle")}
                    .disabled(exporting)
                }
            }
            .sheet(item:$detail){MomentDetailView(initialMoment:$0)}
            .sheet(isPresented:$sharing,onDismiss:clearExports){FileShareView(urls:exportFiles)}
            .onDisappear{if !sharing{clearExports()}}
            .onChange(of:app.records){_,values in let lookup=Dictionary(uniqueKeysWithValues:values.map{($0.id,$0)});records=records.compactMap{record in app.deletedRecordIDs.contains(record.id) ? nil:(lookup[record.id] ?? record)};if records.isEmpty{dismiss()}else if !records.contains(where:{$0.id==selection}){selection=records[0].id}}
            .onChange(of:selection){_,_ in message=nil}
        }
    }
    private func clearExports(){for file in exportFiles{try? FileManager.default.removeItem(at:file)};exportFiles=[]}
    private func export(save:Bool) async {
        guard let current else{return};exporting=true;message=nil;defer{exporting=false}
        do{
            clearExports()
            if current.payload.mediaKind=="video" || current.payload.mediaKind=="live" {
                for (i,id) in (current.payload.assetIDs ?? []).enumerated(){exportFiles.append(try await app.api.assetFile(id:id,mime:current.payload.mediaKind=="video" || i>0 ? "video/quicktime":"image/jpeg"))}
            }else{exportFiles=[try await app.api.momentImageFile(current)]}
            guard !exportFiles.isEmpty else{throw MediaError.unreadable}
            if !save{sharing=true;return}
            let auth=await PHPhotoLibrary.requestAuthorization(for:.addOnly)
            guard auth == .authorized || auth == .limited else{message="Bitte erlaube das Sichern in Apple Fotos.";clearExports();return}
            let files=exportFiles,kind=current.payload.mediaKind
            try await PHPhotoLibrary.shared().performChanges{
                if kind=="live",files.count==2{let r=PHAssetCreationRequest.forAsset();r.addResource(with:.photo,fileURL:files[0],options:nil);r.addResource(with:.pairedVideo,fileURL:files[1],options:nil)}
                else if kind=="video"{PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL:files[0])}
                else{PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL:files[0])}
            };message="In Apple Fotos gesichert.";clearExports()
        }catch{message=error.localizedDescription;clearExports()}
    }
}

private struct MomentGalleryPage:View {
    @Environment(AppState.self) private var app
    let record:SharedRecord
    let active:Bool
    @State private var image:UIImage?
    @State private var file:URL?
    @State private var player:AVPlayer?
    @State private var error:String?
    @State private var loading=false
    @State private var retry=0
    @State private var statusObserver:NSKeyValueObservation?
    var body:some View {
        ZStack{
            Color.black
            if record.payload.mediaKind=="video",let player,active{VideoPlayer(player:player)}
            else if let image,active{MomentZoomImage(image:image)}
            else{MomentPreview(record:record).aspectRatio(contentMode:.fit)}
            if loading{ProgressView().tint(.white).padding(20).background(.black.opacity(0.35),in:Circle())}
            if let error{VStack(spacing:14){Text(error).foregroundStyle(.white);Button("Erneut laden"){retry += 1}.buttonStyle(.borderedProminent)}.padding(24).background(.black.opacity(0.7),in:RoundedRectangle(cornerRadius:20))}
        }.task(id:"\(active)-\(retry)-\(record.updatedAt)"){await load()}.onDisappear{clear()}
    }
    private func clear(){statusObserver=nil;player?.pause();player?.replaceCurrentItem(with:nil);player=nil;image=nil;if let file{try? FileManager.default.removeItem(at:file)};file=nil}
    private func load() async {
        clear();error=nil;guard active else{return};loading=true;defer{loading=false}
        do{
            if record.payload.mediaKind=="video",let id=record.payload.assetIDs?.first {
                let url=try await app.api.playbackURL(assetID:id);try Task.checkCancellation()
                let item=AVPlayerItem(url:url);item.preferredForwardBufferDuration=15
                EveningPlaylistService.shared.stop();AudioStudioService.shared.stopPlayback()
                let p=AVPlayer(playerItem:item);player=p
                statusObserver=item.observe(\.status,options:[.new]){item,_ in if item.status == .failed{Task{@MainActor in if player?.currentItem === item{error="Das Video konnte nicht abgespielt werden. Bitte erneut laden."}}}}
                p.play()
            }else{
                let loaded=try await app.api.momentImageFile(record)
                guard !Task.isCancelled else{try? FileManager.default.removeItem(at:loaded);return}
                guard let photo=UIImage(contentsOfFile:loaded.path) else{try? FileManager.default.removeItem(at:loaded);throw MediaError.unreadable}
                file=loaded;image=photo
            };await app.markOpened(record)
        }catch{if !Task.isCancelled{self.error=error.localizedDescription}}
    }
}
private struct MomentZoomImage:UIViewRepresentable {
    let image:UIImage
    func makeCoordinator()->Coordinator{Coordinator()}
    func makeUIView(context:Context)->UIScrollView {
        let scroll=UIScrollView();scroll.minimumZoomScale=1;scroll.maximumZoomScale=6;scroll.delegate=context.coordinator;scroll.backgroundColor = .black
        let view=UIImageView(image:image);view.contentMode = .scaleAspectFit;view.autoresizingMask=[.flexibleWidth,.flexibleHeight];scroll.addSubview(view);context.coordinator.imageView=view
        return scroll
    }
    func updateUIView(_ scroll:UIScrollView,context:Context){if let view=context.coordinator.imageView{view.image=image;if scroll.zoomScale==1{view.frame=scroll.bounds}}}
    final class Coordinator:NSObject,UIScrollViewDelegate {var imageView:UIImageView?;func viewForZooming(in scrollView:UIScrollView)->UIView?{imageView}}
}

