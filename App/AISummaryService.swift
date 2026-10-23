import Foundation

struct AIIntegrationStatus:Decodable {
    let available:Bool
    let model:String
    let myConsent:Bool
    let partnerConsent:Bool
    let dailyLimit:Int
    enum CodingKeys:String,CodingKey {case available,model;case myConsent="my_consent",partnerConsent="partner_consent",dailyLimit="daily_limit"}
}
struct AIDaySummary:Decodable {
    struct Content:Decodable {let title:String;let intro:String;let highlights:[Highlight];let reflection:String;let question:String}
    struct Highlight:Decodable {let title:String;let detail:String;let recordIDs:[String];enum CodingKeys:String,CodingKey{case title,detail;case recordIDs="record_ids"}}
    let summary:Content
    let model:String
    let generatedAt:String
    let sourceCount:Int
    let totalCount:Int
    let cached:Bool
    enum CodingKeys:String,CodingKey{case summary,model,cached;case generatedAt="generated_at",sourceCount="source_count",totalCount="total_count"}
}
extension APIClient {
    func aiStatus() async throws -> AIIntegrationStatus {try await execute(try request(path:"/v1/ai/status",method:"GET"),as:AIIntegrationStatus.self)}
    func setAIConsent(_ enabled:Bool) async throws -> AIIntegrationStatus {try await execute(try request(path:"/v1/ai/consent",method:"POST",body:encoder.encode(["enabled":enabled])),as:AIIntegrationStatus.self)}
    func aiSummary(day:Date) async throws -> AIDaySummary {
        let cal=Calendar.current,start=cal.startOfDay(for:day)
        guard let end=cal.date(byAdding:.day,value:1,to:start) else{throw APIClientError.invalidResponse}
        var request=try request(path:"/v1/ai/summary",method:"POST",body:encoder.encode(["start":start.rjISO8601,"end":end.rjISO8601]));request.timeoutInterval=65
        let config=URLSessionConfiguration.default;config.timeoutIntervalForRequest=65;config.timeoutIntervalForResource=80
        let session=URLSession(configuration:config);defer{session.finishTasksAndInvalidate()}
        let (data,response)=try await session.data(for:request)
        guard let http=response as? HTTPURLResponse else{throw APIClientError.invalidResponse}
        guard http.statusCode==200 else{let issue=try? decoder.decode(APIErrorEnvelope.self,from:data);throw APIClientError.server(status:http.statusCode,message:issue?.message ?? "Der Rückblick konnte gerade nicht erstellt werden.")}
        return try decoder.decode(AIDaySummary.self,from:data)
    }
}
