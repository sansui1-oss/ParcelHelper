import Foundation
import WebKit

/// Port of Scripting utils/vip.ts: Vipshop orders via the H5 gateway.
/// Plain GET + Cookie, no signature and no WebView needed. mars_cid is
/// taken from the vip.com cookie jar and put in BOTH the query string and
/// the Cookie header; it is never invented, because the session is bound
/// to the device id from login and an invented one invalidates it.
/// Field names in the order list have no verified sample yet (the handbook
/// account had 0 orders), so orders go through the LooseOrder parser.
@MainActor enum NativeVip {
    /// Public constant hard-coded in the H5 page JavaScript.
    private static let apiKey = "8cec5243ade04ed3a02c5972bcda0d3f"
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
    private static let ordersURL = "https://mapi.vip.com/vips-mobile/rest/order/mina_programs/get_union_order_list/v1"

    static func cookies() async -> [HTTPCookie] {
        await WebCookieRequest.cookies(domain: "vip.com")
    }
    private static func cookieValue(_ name: String, in list: [HTTPCookie]) -> String {
        list.first(where: { $0.name == name })?.value ?? ""
    }
    /// Real login marker: VIP_TANK or m_vipruid. VipRUID alone does not
    /// count — the handbook found user/check still returns userId 0 then.
    static func hasLogin() async -> Bool {
        let list = await cookies()
        return list.contains { ["VIP_TANK", "m_vipruid", "WAP[login]"].contains($0.name) && !$0.value.isEmpty }
    }

    static func packages() async throws -> [NativeSyncParcel] {
        let list = await cookies()
        guard list.contains(where: { ["VIP_TANK", "m_vipruid", "WAP[login]"].contains($0.name) && !$0.value.isEmpty }) else {
            throw NativeSyncError.noLogin("唯品会登录已失效，请重新授权")
        }
        let mars = cookieValue("mars_cid", in: list)
        let marsCid = mars.isEmpty ? (cookieValue("vip_cid", in: list).isEmpty
            ? cookieValue("VipCID", in: list) : cookieValue("vip_cid", in: list)) : mars
        guard !marsCid.isEmpty else {
            throw NativeSyncError.noLogin("唯品会缺少设备标识（mars_cid），请重新授权")
        }
        let encodedMars = marsCid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? marsCid
        let query = [
            "api_key=" + apiKey,
            "mars_cid=" + encodedMars,
            "mobile_platform=2",
            "app_name=shop_wap",
            "client=wap",
            "client_type=wap",
            "source_app=shop_wap",
            "app_version=4.0",
            "format=json",
            "ver=2.0",
            "standby_id=other",
            "union_mark=nature",
            "mobile_channel=nature",
            "sd_tuijian=0",
            "warehouse=VIP_",
            "page=1",
            "page_size=50",
        ].joined(separator: "&")
        guard let url = URL(string: ordersURL + "?" + query) else {
            throw NativeSyncError.badResponse("唯品会请求地址无效")
        }
        var request = URLRequest(url: url, timeoutInterval: 22)
        request.httpMethod = "GET"
        request.setValue(list.map { "\($0.name)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://m.vip.com/", forHTTPHeaderField: "Referer")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NativeSyncError.unavailable("唯品会请求失败")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeSyncError.badResponse("唯品会返回非 JSON 数据")
        }
        // Both code 1 and code 200 have been seen as success.
        let codeRaw = json["code"]
        let code = (codeRaw as? NSNumber)?.intValue ??
            Int((codeRaw as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
        guard code == 1 || code == 200 else {
            let msg = (json["msg"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let text = msg.isEmpty ? "唯品会返回 \(code)" : msg
            if text.range(of: "user id not found|未登录|not login|login required|请重新登录",
                          options: [.regularExpression, .caseInsensitive]) != nil {
                throw NativeSyncError.noLogin("唯品会登录已失效，请重新授权")
            }
            throw NativeSyncError.unavailable(text)
        }
        let dataDict = json["data"] as? [String: Any] ?? [:]
        let orders = dataDict["orders"] as? [[String: Any]] ?? []
        // Only the last 30 days (the list comes back newest first).
        let cutoff = Date().timeIntervalSince1970 * 1000 - 30 * 24 * 3600 * 1000
        var out: [NativeSyncParcel] = []
        for raw in orders {
            let order = LooseOrder.parse(raw)
            guard !order.orderSn.isEmpty || !order.mailNo.isEmpty else { continue }
            if let t = order.orderTime, t < cutoff { continue }
            var parcel = NativeSyncParcel(source: "vip")
            parcel.orderID = order.orderSn.isEmpty ? order.mailNo : order.orderSn
            parcel.mailNo = order.mailNo
            parcel.company = order.company
            parcel.title = order.itemTitle.isEmpty ? "唯品会订单" : order.itemTitle
            parcel.latest = order.statusHint.isEmpty ? "唯品会订单" : order.statusHint
            if !parcel.mailNo.isEmpty, out.count < 4,
               let detail = await NativeParcelSync.cainiaoTrack(parcel.mailNo) {
                if !detail.company.isEmpty { parcel.company = detail.company }
                if !detail.nodes.isEmpty {
                    parcel.tracks = detail.nodes
                    parcel.latest = detail.nodes.first?.text ?? parcel.latest
                }
            }
            out.append(parcel)
        }
        return out
    }
}
