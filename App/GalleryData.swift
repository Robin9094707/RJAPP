import Foundation

struct GalleryPage: Decodable {
    let records: [SharedRecord]
    let nextCursor: String?
    let hasMore: Bool
    enum CodingKeys: String, CodingKey { case records; case nextCursor="next_cursor",hasMore="has_more" }
}
extension APIClient {
    func galleryPage(cursor:String?=nil,query:String="",owner:String?=nil,album:String?=nil) async throws -> GalleryPage {
        var req=try request(path:"/v1/gallery",method:"GET")
        var url=URLComponents(url:req.url!,resolvingAgainstBaseURL:false)!
        url.queryItems=[URLQueryItem(name:"limit",value:"60"),URLQueryItem(name:"query",value:query)]
        for (name,value) in [("cursor",cursor),("owner",owner),("album",album)] {if let value,!value.isEmpty{url.queryItems?.append(URLQueryItem(name:name,value:value))}}
        req.url=url.url;return try await execute(req,as:GalleryPage.self)
    }
    func momentThumbnail(_ id:String) async throws -> URL {
        let (temp,response)=try await session.download(for:request(path:"/v1/moments/\(id)/thumbnail",method:"GET"))
        guard let http=response as? HTTPURLResponse,http.statusCode==200 else {try? FileManager.default.removeItem(at:temp);throw MediaError.unreadable}
        return temp
    }
}
