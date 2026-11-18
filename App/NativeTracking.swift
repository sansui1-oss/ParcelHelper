import Foundation
import SwiftUI
import Security
import CryptoKit

// Manual tracking ported from Scripting/kdniao.ts and ui/trackSearch.tsx.
// Native iOS client uses the API credentials the user entered, never hardcodes
// a third-party API secret or pretends to have tracked a parcel.
struct NativeTrackLookup {
    var mailNo: String
    var company: String
    var shipperCode: String
    var latest: String
    var nodes: [TrackNode]
    var receiverCity: String = ""
    var receiverAddress: String = ""
    var provider: String = ""
}
/// Port of Scripting kdniao.ts needsClaim: is the Kdniao server telling us
/// to claim a free trial package? Only then may a client auto-claim.
/// Already-claimed, expired, or paywalled wording is not claimable.
/// Kept as a free function so unit tests can call it without an actor.
func kdniaoNeedsClaim(_ reason: String) -> Bool {
    let text = reason.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return false }
    let excluded = ["已领取", "已领过", "已使用", "已过期", "购买", "充值", "开通"]
    if excluded.contains(where: text.contains) { return false }
    let pattern = #"(请|需要|可|去).{0,8}领取|未领取|领取.{0,6}(试用|免费)|(试用|免费).{0,6}领取"#
    return text.range(of: pattern, options: .regularExpression) != nil
}

@MainActor enum NativeTracking {
    private static let service = "com.muxui.ParcelHelper.kdniao"
    static let shippers: [(String, String)] = [
        ("", "自动识别"), ("ZTO", "中通快递"), ("SF", "顺丰速运"),
        ("YTO", "圆通速递"), ("YUNDA", "韵达快递"), ("STO", "申通快递"),
        ("JT", "极兔速递"), ("EMS", "EMS"), ("YZPY", "中国邮政"),
        ("JD", "京东物流"), ("DBWL", "德邦快递"), ("HTKY", "百世快递"),
        ("DHL", "DHL"), ("FEDEX", "联邦快递"), ("UPS", "UPS")]
    private static let shippingCode: [String:String] = [
        "zhongtong":"ZTO", "shunfeng":"SF", "yuantong":"YTO",
        "yunda":"YUNDA", "shentong":"STO", "jtexpress":"JT",
        "ems":"EMS", "youzheng":"YZPY", "jd":"JD", "debang":"DBWL",
        "huitongkuaidi":"HTKY", "dhl":"DHL", "fedex":"FEDEX", "ups":"UPS"]
    static func get(_ name: String) -> String {
        let q:[String:Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var ref:CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &ref) == errSecSuccess,
              let data = ref as? Data else { return "" }
        return String(data:data,encoding:.utf8) ?? ""
    }
    static func save(_ name:String, value:String) {
        let q:[String:Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String:name
        ]
        SecItemDelete(q as CFDictionary)
        guard !value.isEmpty else { return }
        var item = q
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary,nil)
    }
    static var isConfigured:Bool { !get("businessID").isEmpty && !get("apiKey").isEmpty }
    static func setCredential(businessID:String, apiKey:String) throws {
        let id = businessID.trimmingCharacters(in:.whitespacesAndNewlines)
        let key = apiKey.trimmingCharacters(in:.whitespacesAndNewlines)
        guard id.range(of:#"^[0-9A-Za-z]{4,40}$"#,options:.regularExpression) != nil,
              key.count >= 8 && key.count <= 160 else {
            throw NativeSyncError.badResponse("请输入有效的快递鸟 EBusinessID 与 API Key")
        }
        save("businessID",value:id);save("apiKey",value:key)
    }
    static func clearCredential() {
        save("businessID",value:"");save("apiKey",value:"")
    }
    static func history() -> [String] {
        UserDefaults.standard.stringArray(forKey:"native.track.history") ?? []
    }
    static func remember(_ mail:String) {
        UserDefaults.standard.set(Array(([mail] + history().filter{$0 != mail}).prefix(9)),
                                  forKey:"native.track.history")
    }
    static func forget(_ mail:String) {
        UserDefaults.standard.set(history().filter{$0 != mail},forKey:"native.track.history")
    }
    static func clearHistory() {
        UserDefaults.standard.removeObject(forKey:"native.track.history")
    }
    static func phone(for mail:String) -> String {
        UserDefaults.standard.string(forKey:"native.track.phone."+mail) ?? ""
    }
    static func savePhone(_ phone:String, mail:String) {
        UserDefaults.standard.set(phone, forKey:"native.track.phone."+mail)
    }
    private static func detect(_ mail:String) async throws -> (String,String) {
        var component = URLComponents(string:"https://www.kuaidi100.com/autonumber/autoComNum")!
        component.queryItems = [
            URLQueryItem(name:"resultv2",value:"1"),
            URLQueryItem(name:"text",value:mail)]
        var request = URLRequest(url:component.url!,timeoutInterval:15)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1",forHTTPHeaderField:"User-Agent")
        request.setValue("https://www.kuaidi100.com/",forHTTPHeaderField:"Referer")
        let (data,response) = try await URLSession.shared.data(for:request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              let entry = (json["auto"] as? [[String:Any]])?.first,
              let original = entry["comCode"] as? String else {
            throw NativeSyncError.unavailable("无法识别快递公司，请手动选择快递公司")
        }
        return (shippingCode[original.lowercased()] ?? original.uppercased(),
                entry["name"] as? String ?? "")
    }
    private static func formEscape(_ value:String)->String {
        value.addingPercentEncoding(withAllowedCharacters:.alphanumerics) ?? value
    }
    private static func flatten(_ object:Any?, depth:Int=0)->String {
        guard let object, depth < 5 else { return "" }
        if let s = object as? String { return s }
        if let n = object as? NSNumber { return n.stringValue }
        if let a = object as? [Any] {
            return a.map{flatten($0,depth:depth+1)}.filter{ !$0.isEmpty }.joined(separator:" ")
        }
        if let d = object as? [String:Any] {
            let fav = ["Desc","AcceptStation","Station","Content","Text","Description","Remark"]
                .compactMap{d[$0]}.map{flatten($0,depth:depth+1)}.filter{ !$0.isEmpty }
            return (fav.isEmpty ? d.values.map{flatten($0,depth:depth+1)}.filter{ !$0.isEmpty } : fav)
                .joined(separator:" ")
        }
        return ""
    }
    /// Port of Scripting kdniao.ts needsClaim; implementation is the free
    /// function kdniaoNeedsClaim above so tests can call it directly.
    static func needsClaim(_ reason: String) -> Bool { kdniaoNeedsClaim(reason) }
    static func lookup(_ mailRaw:String, source:String?=nil, shipperCode:String="",
                       phone:String="") async throws -> NativeTrackLookup {
        let mail=mailRaw.trimmingCharacters(in:.whitespacesAndNewlines)
            .replacingOccurrences(of:" ",with:"")
        guard mail.range(of:#"^[A-Za-z0-9-]{8,40}$"#,options:.regularExpression) != nil else {
            throw NativeSyncError.badResponse("请填写有效的运单号（8 至 40 位字母、数字或短横线）")
        }
        // Prefer a first-party platform that already has a valid session.
        if let native = await NativeParcelSync.lookupShipment(mail,source:source) {
            remember(mail)
            return native
        }
        guard isConfigured else {
            throw NativeSyncError.noLogin("暂无可用物流接口，请先在「设置 → 账号授权 → 快递鸟」配置 API，或登录对应电商平台")
        }
        let id=get("businessID"),secret=get("apiKey")
        var chosen=shipperCode.trimmingCharacters(in:.whitespacesAndNewlines).uppercased()
        var company=shippers.first(where:{$0.0 == chosen})?.1 ?? ""
        if chosen.isEmpty {
            (chosen,company) = try await detect(mail)
        }
        let tail=phone.isEmpty ? self.phone(for:mail) : phone.trimmingCharacters(in:.whitespacesAndNewlines)
        if !tail.isEmpty {
            guard tail.range(of:#"^\d{4}$"#,options:.regularExpression) != nil else {
                throw NativeSyncError.badResponse("手机号尾号应为 4 位数字")
            }
        }
        var data:[String:Any] = ["LogisticCode":mail,"ShipperCode":chosen]
        if !tail.isEmpty { data["CustomerName"]=tail }
        let encoded=try JSONSerialization.data(withJSONObject:data,options:[.sortedKeys])
        guard let requestData=String(data:encoded,encoding:.utf8) else {
            throw NativeSyncError.badResponse("无法生成快递鸟请求参数")
        }
        let rawSign=requestData + secret
        let hex=Insecure.MD5.hash(data:Data(rawSign.utf8))
            .map{String(format:"%02x",$0)}.joined()
        let sign=Data(hex.utf8).base64EncodedString()
        let body="RequestData=" + formEscape(requestData) +
            "&EBusinessID=" + formEscape(id) +
            "&RequestType=8001&DataSign=" + formEscape(sign) + "&DataType=2"
        let url=URL(string:"https://api.kdniao.com/Ebusiness/EbusinessOrderHandle.aspx")!
        var req=URLRequest(url:url,timeoutInterval:25)
        req.httpMethod="POST"
        req.setValue("application/x-www-form-urlencoded",forHTTPHeaderField:"Content-Type")
        req.setValue("application/json",forHTTPHeaderField:"Accept")
        req.httpBody=Data(body.utf8)
        let (responseData,response)=try await URLSession.shared.data(for:req)
        guard let http=response as? HTTPURLResponse,(200..<300).contains(http.statusCode) else {
            throw NativeSyncError.unavailable("快递鸟网络请求失败")
        }
        guard let json=try? JSONSerialization.jsonObject(with:responseData) as? [String:Any] else {
            throw NativeSyncError.badResponse("快递鸟返回无法解析的数据")
        }
        let success=json["Success"] as? Bool ?? false
        if !success {
            let reason=json["Reason"] as? String ?? "查询失败"
            if reason.contains("手机尾号") {
                throw NativeSyncError.verify(reason+"，请填写收件人手机号后四位")
            }
            // Only when the server explicitly says to claim a trial does
            // the message say so. Auto-claim is NOT implemented here: the
            // Swift app has no Kdniao user token / login flow, so claiming
            // stays a manual step on the Kdniao website. Every other
            // failure keeps the server's own wording.
            if kdniaoNeedsClaim(reason) {
                throw NativeSyncError.unavailable("快递鸟：" + reason + "。可领取免费试用名额，领取后重试（App 内暂不支持自动领取）")
            }
            throw NativeSyncError.unavailable("快递鸟："+reason)
        }
        let traces=(json["Traces"] as? [[String:Any]] ?? [])
            .map{($0["AcceptTime"] as? String ?? "", flatten($0["AcceptStation"]))}
            .filter{ !$0.1.isEmpty }
            .sorted{$0.0 > $1.0}
            .prefix(60)
            .map{TrackNode(time:$0.0,text:$0.1)}
        let latest=traces.first?.text ?? ""
        guard !traces.isEmpty || !(json["State"] as? String ?? "").isEmpty else {
            throw NativeSyncError.unavailable("快递鸟没有返回这笔运单的有效物流轨迹")
        }
        if !tail.isEmpty { savePhone(tail,mail:mail) }
        remember(mail)
        return NativeTrackLookup(mailNo:mail,company:company,shipperCode:chosen,
                                 latest:latest,nodes:Array(traces),provider:"快递鸟")
    }
}
