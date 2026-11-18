import Foundation
import SwiftUI
import WebKit
import CryptoKit

// Native iOS adaptation of the Scripting source modules:
// utils/pddExpress.ts, utils/cainiao.ts, utils/mtop.ts and utils/model.ts.
// These are H5 endpoints used by the original project, NOT contracted public
// third-party APIs. No captcha bypass; failure must never be called success.

enum NativeSyncError: LocalizedError {
    case noLogin(String), verify(String), unavailable(String), badResponse(String)
    var errorDescription: String? {
        switch self {
        case .noLogin(let x), .verify(let x), .unavailable(let x), .badResponse(let x): return x
        }
    }
}
struct NativeSyncParcel {
    var source: String
    var orderID: String = ""
    var mailNo: String = ""
    var title: String = ""
    var company: String = ""
    var code: String = ""
    var station: String = ""
    var latest: String = ""
    var tracks: [TrackNode] = []
    var arrived: Bool = false
    var eta: String = ""
}
struct NativeSyncResult {
    let name: String
    let found: Int
    let imported: Int
    let errors: [String]
    var description: String {
        if !errors.isEmpty { return "\(name)：导入 \(imported) 件；" + errors.joined(separator: "；") }
        return "\(name)：发现 \(found) 件，新增或更新 \(imported) 件"
    }
}
private enum SyncJSON {
    static func dict(_ v: Any?) -> [String: Any] { v as? [String: Any] ?? [:] }
    static func list(_ v: Any?) -> [[String: Any]] { v as? [[String: Any]] ?? [] }
    static func str(_ v: Any?) -> String {
        if let s = v as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }
    static func first(_ d: [String: Any], _ keys: [String]) -> String {
        for key in keys {
            let s = str(d[key])
            if !s.isEmpty { return s }
        }
        return ""
    }
    static func isMail(_ value: String) -> Bool {
        let s = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return (8...40).contains(s.count) &&
               s.range(of: #"^[A-Za-z0-9-]+$"#, options: .regularExpression) != nil
    }
    static func pickup(_ raw: String) -> String {
        let t = raw.replacingOccurrences(of: "取件码", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let blocked = ["", "0", "-1", "needsms", "need_sms", "null", "none", "true", "false"]
        return blocked.contains(t.lowercased()) ? "" : String(t.prefix(50))
    }
}

@MainActor enum WebCookieRequest {
    static let store = WKWebsiteDataStore.default().httpCookieStore
    static func cookies(domain: String) async -> [HTTPCookie] {
        await store.allCookies().filter {
            ($0.domain == domain || $0.domain.hasSuffix("." + domain)) &&
            ($0.expiresDate == nil || ($0.expiresDate ?? .distantPast) > Date())
        }
    }
    static func headers(domain: String) async throws -> [String: String] {
        let cookies = await cookies(domain: domain)
        guard !cookies.isEmpty else {
            throw NativeSyncError.noLogin("尚未检测到\(domain)网页会话，请先网页登录")
        }
        return [
            "Cookie": cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "),
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 Version/17.5 Mobile/15E148 Safari/604.1",
            "Accept": "application/json"
        ]
    }
    static func request(_ url: URL, method: String = "GET", headers: [String: String], body: Data? = nil) async throws -> ([String: Any], HTTPURLResponse) {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 18)
        req.httpMethod = method
        req.httpBody = body
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NativeSyncError.badResponse("服务器未返回 HTTP 响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw NativeSyncError.noLogin("账号会话失效或访问受限（HTTP \(http.statusCode)）")
            }
            throw NativeSyncError.unavailable("请求失败（HTTP \(http.statusCode)）")
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return (json, http)
        }
        // The original Scripting/pddExpress.ts also accepts the H5Response
        // wrappers returned by some PDD mdkd endpoints.
        if url.host == "api.pinduoduo.com", let source = String(data: data, encoding: .utf8) {
            let tags = ["RESULT", "result", "DATA", "data", "DATA_JSON", "body"]
            for tag in tags {
                let escaped = NSRegularExpression.escapedPattern(for: tag)
                guard let regex = try? NSRegularExpression(
                    pattern: "<" + escaped + ">([\\s\\S]*?)</" + escaped + ">",
                    options: [.caseInsensitive]),
                    let match = regex.firstMatch(in: source,
                        range: NSRange(source.startIndex..., in: source)),
                    let range = Range(match.range(at: 1), in: source) else { continue }
                let nested = String(source[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&amp;", with: "&")
                if let blob = nested.data(using: .utf8),
                   let object = try? JSONSerialization.jsonObject(with: blob) as? [String: Any] {
                    return (object, http)
                }
            }
            let fields = ["identification_code", "expire_mills", "mobile_info_desc",
                          "error_code", "error_msg"]
            var extracted: [String: Any] = [:]
            for field in fields {
                let escaped = NSRegularExpression.escapedPattern(for: field)
                guard let regex = try? NSRegularExpression(
                    pattern: "<" + escaped + ">([^<]+)</" + escaped + ">",
                    options: [.caseInsensitive]),
                    let match = regex.firstMatch(in: source,
                        range: NSRange(source.startIndex..., in: source)),
                    let range = Range(match.range(at: 1), in: source) else { continue }
                extracted[field] = String(source[range])
            }
            if extracted["identification_code"] != nil {
                return (["result": extracted], http)
            }
            let summary = source.replacingOccurrences(of: "<[^>]*>", with: " ",
                options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if summary.localizedCaseInsensitiveContains("登录") ||
               summary.localizedCaseInsensitiveContains("验证") {
                throw NativeSyncError.noLogin("拼多多会话失效或需要官方 App 安全验证")
            }
        }
        throw NativeSyncError.badResponse("接口返回非 JSON，可能需要在平台内完成验证")
    }
}

@MainActor enum NativeParcelSync {
    static let platforms = ["pdd", "cainiao", "fengchao", "mi", "vip", "dewu"]
    // Throttle user-triggered refreshes too: no bursts into private endpoints.
    static let minGap: TimeInterval = 30
    // Shared "just checked" grace (Scripting v1.2.1 widgetRefresh): a
    // platform that synced successfully less than 10 minutes ago is not
    // fetched again unless the call is forced. No App Group is involved:
    // this app has no home-screen widget; Live Activity is pushed
    // from the app itself.
    static let recentGrace: TimeInterval = 10 * 60

    static func displayName(_ id: String) -> String {
        switch id {
        case "pdd": return "拼多多驿站包裹"
        case "cainiao": return "菜鸟"
        case "fengchao": return "丰巢"
        case "mi": return "小米"
        case "vip": return "唯品会"
        case "dewu": return "得物"
        default: return id
        }
    }

    static func run(_ id: String, force: Bool = false) async throws -> NativeSyncResult {
        guard platforms.contains(id) else {
            throw NativeSyncError.unavailable("该平台尚未完成 Swift 原生查询适配")
        }
        if !force {
            let lastSuccess = UserDefaults.standard.double(forKey: "native.sync.success." + id)
            if lastSuccess > 0 && Date().timeIntervalSince1970 - lastSuccess < recentGrace {
                return NativeSyncResult(name: displayName(id), found: 0, imported: 0,
                                        errors: ["10 分钟内已同步过，已跳过"])
            }
        }
        let key = "native.sync.at." + id
        let last = UserDefaults.standard.double(forKey: key)
        if !force && Date().timeIntervalSince1970 - last < minGap {
            throw NativeSyncError.unavailable("请求过于频繁，请稍后再试")
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
        do {
            let incoming: [NativeSyncParcel]
            if id == "pdd" { incoming = try await pddPackages() }
            else if id == "cainiao" { incoming = try await cainiaoPackages() }
            else if id == "fengchao" { incoming = try await NativeFengchao.packages() }
            else if id == "vip" { incoming = try await NativeVip.packages() }
            else if id == "dewu" { incoming = try await NativeDewu.packages() }
            else { incoming = try await NativeMiExpress.packages() }
            let count = merge(incoming)
            let result = NativeSyncResult(
                name: displayName(id),
                found: incoming.count, imported: count, errors: [])
            UserDefaults.standard.set(result.description, forKey: "native.sync.result." + id)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "native.sync.success." + id)
            if ParcelStore.shared.snapshot.preferences.liveActivityEnabled {
                await LiveActivityCoordinator.update(with: ParcelStore.shared.snapshot.parcels)
            }
            return result
        } catch {
            let detail = error.localizedDescription
            UserDefaults.standard.set(detail, forKey: "native.sync.result." + id)
            throw error
        }
    }

    // Scripting utils/platformSync.ts and utils/codes.ts compatibility.
    private static func codeKey(_ raw: String) -> String {
        let half = raw.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? raw
        return half.filter { !$0.isWhitespace && !"-－—_".contains($0) }.uppercased()
    }
    private static func normalizedCode(_ raw: String) -> String {
        let prefix = #"^(取件码|提货码|取货码|自提码|凭码)[:：\s]*"#
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: prefix, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let garbage = ["needsms", "need sms", "none", "null", "undefined",
                       "待出码", "待生成", "暂无", "无", "--", "—", "/", "0"]
        guard !garbage.contains(trimmed.lowercased()),
              trimmed.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]{1,19}$"#, options: .regularExpression) != nil
        else { return "" }
        return trimmed
    }
    private static func isAggregator(_ source: String?) -> Bool {
        ["cainiao", "fengchao", "mi"].contains(source ?? "")
    }
    private static func arrivalKind(_ text: String) -> String {
        let noPickup = ["转运中心", "分拨中心", "集散中心", "运转中心", "揽收", "正在派送", "派件中"]
        // "已签收" can mean an express station signed on behalf of the user.
        // Only unequivocal pickup wording should mark an item as collected.
        // Bare "已取件" / "已取出" were missing from this list (only the
        // 您-prefixed forms were here), so a plain pickup node stayed
        // "transit" in the merge layer even though Models.swift already
        // recognised the same wording via latestPickupConfirmed.
        let signedTerms = ["已取走", "已取件", "已取出", "您已取件", "本人签收",
                           "本人已签收", "签收人：本人", "签收人本人",
                           "已领取", "取件完成", "取件已完成", "已完成取件",
                           "完成取件", "完成取货", "取货成功",
                           "用户已取", "取件成功",
                           "已被取走", "已被领取", "用户取件成功", "收件人已取",
                           "已从驿站取出", "已从快递柜取出"]
        let waitingForSignature = ["待签收", "等待签收", "签收中",
                                   "快递员已取件", "揽收取件", "待取件",
                                   "未取件", "请取件"].contains(where: { text.contains($0) })
        if !waitingForSignature && signedTerms.contains(where: { text.contains($0) }) {
            return "picked"
        }
        if noPickup.contains(where: { text.contains($0) }) { return "transit" }
        if ["待取件", "已到站", "已暂存", "已存放", "已放入", "已代收", "送达代收点",
            "请及时取", "请及时领取", "凭取件码", "待领取", "快递柜", "驿站", "代收点"]
            .contains(where: { text.contains($0) }) { return "arrived" }
        return "transit"
    }

    // Updates should supplement, not overwrite user decisions. Source loyalty,
    // code merging, deduplication, transit history and pickup statuses follow
    // the supplied original platformSync.ts and codes.ts design.
    @discardableResult static func merge(_ rows: [NativeSyncParcel]) -> Int {
        let store = ParcelStore.shared
        var changed = 0
        for row in rows {
            let mail = row.mailNo.trimmingCharacters(in: .whitespacesAndNewlines)
            let code = normalizedCode(row.code)
            guard SyncJSON.isMail(mail) || (row.arrived && !code.isEmpty) else { continue }
            let orderKey = row.orderID.isEmpty ? "" : row.source + ":" + row.orderID
            // Manual delete is a user decision: never silently re-import this
            // shipment on the next platform refresh.
            guard !store.isDeletedShipment(source: row.source, order: orderKey,
                                           mail: mail, code: code, station: row.station)
            else { continue }
            // Latest provider state takes precedence over old route events.
            let currentStatus = row.latest.isEmpty ? (row.tracks.first?.text ?? "") : row.latest
            let newestTrack = row.tracks.first?.text ?? ""
            let trackKind = arrivalKind(newestTrack)
            let kind = trackKind == "picked" ? "picked" : arrivalKind(currentStatus)
            let wasArrived = row.arrived || !code.isEmpty || kind == "arrived"
            if ["已取消", "退款成功", "已关闭", "退货成功"].contains(where: { row.latest.contains($0) }) {
                continue
            }
            let normalizedMail = codeKey(mail)
            var previous = store.snapshot.parcels.first(where: {
                (!normalizedMail.isEmpty && codeKey($0.mailNo ?? "") == normalizedMail) ||
                (!orderKey.isEmpty && $0.orderId == orderKey &&
                 (mail.isEmpty || ($0.mailNo ?? "").isEmpty ||
                  codeKey($0.mailNo ?? "") == codeKey(mail))) ||
                (mail.isEmpty && wasArrived && !code.isEmpty &&
                 codeKey($0.code) == codeKey(code) && $0.stationText == row.station)
            })
            if kind == "picked" && previous == nil { continue }
            // A carrier "signed" event is not necessarily the user's pickup:
            // an express station may have signed on the recipient's behalf.
            // Do not import historical signed parcels as new transit records.
            let signed = ["已签收", "签收成功", "已妥投", "SIGN", "收件人签收"].contains {
                currentStatus.contains($0)
            }
            if signed && code.isEmpty && previous == nil { continue }
            // An old order with no actual route detail should not become a
            // new fake in-transit shipment.
            if previous == nil && !wasArrived && row.latest.isEmpty && row.tracks.isEmpty { continue }
            // Central dedupe, AFTER the guards above: the same mail number
            // (normalized) or the same platform order id with a different
            // mail number still belongs to the same card. Running it here
            // keeps the guards seeing a genuinely new picked/signed parcel
            // as new, so they still drop it.
            if previous == nil {
                previous = store.findDuplicate(mailNo: mail, orderId: orderKey)
            }
            // Vipshop / Dewu orders without a mail number only update an
            // existing card, never create a new one (Scripting
            // platformSync.ts: same rule as Pinduoduo).
            if (row.source == "vip" || row.source == "dewu") && previous == nil && mail.isEmpty { continue }
            var p = previous ?? Parcel()
            let priorSource = p.source
            let oldNodes = p.trackNodes
            let oldLatest = p.trackLatest ?? ""
            let previousCodes = p.codes
            if p.orderId == nil && !orderKey.isEmpty { p.orderId = orderKey }
            if p.mailNo == nil && !mail.isEmpty { p.mailNo = mail }

            if priorSource == nil || priorSource?.isEmpty == true ||
                (!isAggregator(row.source) && isAggregator(priorSource)) {
                p.source = row.source
                let names = ["pdd": "拼多多", "cainiao": "菜鸟", "taobao": "淘宝",
                             "jd": "京东", "fengchao": "丰巢", "mi": "小米",
                             "vip": "唯品会", "dewu": "得物"]
                p.srcApp = SourceApp(id: row.source, name: names[row.source] ?? row.source)
            }
            if (p.itemTitle == nil || p.itemTitle?.isEmpty == true ||
                p.itemTitle == "拼多多订单"), !row.title.isEmpty { p.itemTitle = row.title }
            if (p.trackCompany == nil || p.trackCompany?.isEmpty == true), !row.company.isEmpty {
                p.trackCompany = row.company
            }
            if !row.station.isEmpty {
                p.courierStationName = row.station
                if let station = StationMatcher.match(store.snapshot.stations,
                    text: [row.station, row.latest].joined(separator: " ")) {
                    p.courierStationName = station.courierStationName
                    p.courierStationUuid = station.id
                }
            }
            let shouldStoreCode = !code.isEmpty && codeKey(code) != codeKey(mail)
            if shouldStoreCode && !p.codes.contains(where: { codeKey($0) == codeKey(code) }) {
                p.codes.append(code)
                p.codes = Array(p.codes.prefix(3))
            }
            if shouldStoreCode && p.code.isEmpty { p.code = code }
            if !row.tracks.isEmpty {
                let unique = Array(row.tracks.prefix(60))
                p.trackNodes = unique
                p.trackUpdatedAt = Date().timeIntervalSince1970 * 1000
            }
            // A summary status is not a timestamped courier event.
            // Keep the last real track nodes until the provider returns actual
            // dated events; never inject the current device time as route history.
            let coarse = row.source == "cainiao" && row.tracks.isEmpty && kind == "transit"
            if !row.latest.isEmpty && !coarse { p.trackLatest = row.latest }
            if !row.eta.isEmpty && !wasArrived { p.eta = row.eta }

            if !p.isDone && !p.pickedByUser {
                if kind == "picked" {
                    p.status = 2
                    p.pickedAt = p.pickedAt ?? Date().timeIntervalSince1970 * 1000
                } else if wasArrived && p.arrivedAt == nil {
                    p.arrivedAt = Date().timeIntervalSince1970 * 1000
                }
                // Direct delivery, no station and no pickup code: a signed /
                // delivered event with nowhere left to pick the parcel up
                // from means the recipient already has it. Without this,
                // an existing parcel whose latest node is only "已签收" or
                // "已送达" stayed "运输中" forever in the merge layer.
                // Station parcels are excluded: they carry a code or a
                // station name, and their "已签收" is the station signing.
                let directDelivered = ["已签收", "签收成功", "已妥投", "已送达",
                                       "已送达收件人", "收件人签收", "SIGN"]
                    .contains(where: { currentStatus.contains($0) })
                    && !["驿站", "快递柜", "代收点", "自提点", "丰巢"]
                        .contains(where: { currentStatus.contains($0) })
                let hasPickupCode = !p.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !p.codes.isEmpty
                let hasStationName = !p.courierStationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !row.station.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if p.status != 2 && directDelivered && !hasPickupCode && !hasStationName {
                    p.status = 2
                    p.pickedAt = p.pickedAt ?? Date().timeIntervalSince1970 * 1000
                }
            }
            if wasArrived { p.eta = nil; p.etaAt = nil }
            if p.pickedByUser { p.status = 2 }
            let needsWrite = previous == nil ||
                p.status != previous?.status || p.arrivedAt != previous?.arrivedAt ||
                p.pickedAt != previous?.pickedAt || p.trackNodes != oldNodes ||
                p.trackLatest != oldLatest || p.codes != previousCodes ||
                p.stationText != previous?.stationText ||
                p.source != priorSource
            if needsWrite {
                store.upsert(p)
                if previous != nil {
                    Task { await ParcelNotifications.notifyUpdate(previous: previous, current: p) }
                }
                changed += 1
            }
        }
        return changed
    }

    struct PddMobile: Identifiable {
        let id: String
        let masked: String
        let alias: String
        let commonlyUsed: Bool
    }
    static func pddBoundMobiles() async throws -> [PddMobile] {
        let response = try await pddJSON("/api/apoc/express/detail", body: ["entry_source": 17])
        let result = SyncJSON.dict(response["result"])
        let data = SyncJSON.dict(response["data"])
        let records = SyncJSON.list(result["new_binding_list"]).isEmpty
            ? (SyncJSON.list(data["new_binding_list"]).isEmpty
                ? SyncJSON.list(response["new_binding_list"])
                : SyncJSON.list(data["new_binding_list"]))
            : SyncJSON.list(result["new_binding_list"])
        return records.compactMap { record -> PddMobile? in
            let mobileID = SyncJSON.first(record, ["mobile_id", "mobileId"])
            let masked = SyncJSON.first(record, ["mock_mobile", "mobile_des", "mobile_desc"])
            if mobileID.isEmpty && masked.isEmpty { return nil }
            return PddMobile(id: mobileID.isEmpty ? masked : mobileID,
                             masked: masked.isEmpty ? "已绑定手机号" : masked,
                             alias: SyncJSON.str(record["alias"]),
                             commonlyUsed: record["commonly_used"] as? Bool == true)
        }
    }

    private static func pddJSON(_ path: String, body: [String: Any]? = nil, referer: String? = nil) async throws -> [String: Any] {
        let cookies = await WebCookieRequest.cookies(domain: "yangkeduo.com")
        var headers: [String: String] = [
            "Referer": referer ?? "https://m.pinduoduo.net/mdkd/package?pr_page_from=scheme",
            "Content-Type": "application/json;charset=UTF-8",
            "Accept": "application/json",
            "User-Agent": "Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) AppleWebKit/605.1.15 Version/17.5 Mobile/15E148 Safari/604.1"
        ]
        if !cookies.isEmpty {
            headers["Cookie"] = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        }
        let token = cookies.first(where: { $0.name == "PDDAccessToken" })?.value ?? PddSessionVault.token
        guard !token.isEmpty || !cookies.isEmpty else {
            throw NativeSyncError.noLogin("未找到拼多多有效网页登录会话")
        }
        if !token.isEmpty { headers["AccessToken"] = token }
        let requestBody = body.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        let url = URL(string: "https://api.pinduoduo.com" + path)!
        let (json, _) = try await WebCookieRequest.request(url, method: body == nil ? "GET" : "POST",
                                                          headers: headers, body: requestBody)
        let code = SyncJSON.str(json["error_code"])
        if code == "40001" { throw NativeSyncError.noLogin("拼多多登录已失效，请重新授权") }
        if code == "54001" { throw NativeSyncError.verify("拼多多要求安全验证，请在官方 App 中完成验证后重试") }
        if !code.isEmpty && code != "0" && code != "1000000" {
            throw NativeSyncError.unavailable(SyncJSON.str(json["error_msg"]).isEmpty ?
                "拼多多接口错误 \(code)" : SyncJSON.str(json["error_msg"]))
        }
        return json
    }

    private static func pddPackages() async throws -> [NativeSyncParcel] {
        let json = try await pddJSON("/api/express_trackbox/station/package",
                                     body: ["entry_source": "9", "dynamic_qrcode": false,
                                            "install_token": "", "dp_source": "", "redirect_app": false])
        let root = SyncJSON.dict(json["result"])
        let groups = SyncJSON.list(root["combine_list"])
        var output: [NativeSyncParcel] = []
        for group in groups {
            let station = SyncJSON.first(group, ["company_name", "station_name"])
            let list = SyncJSON.list(group["combine_track_list"]).isEmpty ?
                       SyncJSON.list(group["list"]) : SyncJSON.list(group["combine_track_list"])
            for item in list {
                var p = NativeSyncParcel(source: "pdd")
                p.mailNo = SyncJSON.first(item, ["tracking_number", "mail_no"])
                p.company = SyncJSON.first(item, ["shipping_name", "shipping_company",
                                                   "shipping_company_name", "express_company_name"])
                if p.company.isEmpty {
                    p.company = SyncJSON.first(SyncJSON.dict(item["shipping"]),
                                                ["shipping_name", "shipping_company_name", "name"])
                }
                p.station = station
                p.code = SyncJSON.pickup(SyncJSON.str(item["pick_code"]))
                p.arrived = !p.code.isEmpty
                if SyncJSON.isMail(p.mailNo) {
                    // Detailed route is fetched only for a small, bounded batch.
                    if output.count < 12 {
                        do {
                            let (name, tracks, eta) = try await pddTrack(p.mailNo)
                            if !name.isEmpty { p.company = name }
                            p.tracks = tracks
                            p.latest = tracks.first?.text ?? ""
                            p.eta = eta
                        } catch {
                            // An individual shipment must not abort other packages.
                            p.latest = ""
                        }
                    }
                }
                output.append(p)
            }
        }
        return output
    }

    private static func pddTrack(_ mail: String) async throws -> (String, [TrackNode], String) {
        guard var parts = URLComponents(string: "https://api.pinduoduo.com/api/express/shipping/track") else {
            throw NativeSyncError.badResponse("运单接口不可用")
        }
        parts.queryItems = [URLQueryItem(name: "tracking_number", value: mail),
                            URLQueryItem(name: "entry_source", value: "9")]
        // Same request error handling as station API, but query is GET.
        let path = "/api/express/shipping/track?" + (parts.percentEncodedQuery ?? "")
        let response = try await pddJSON(path)
        let shipping = SyncJSON.dict(response["shipping"])
        let nodes = SyncJSON.list(shipping["traces"]).compactMap { o -> TrackNode? in
            let text = SyncJSON.first(o, ["info", "desc"])
            guard !text.isEmpty else { return nil }
            return TrackNode(time: SyncJSON.str(o["time"]), text: text)
        }
        let forecast = SyncJSON.dict(shipping["time_forecast"])
        return (SyncJSON.str(shipping["shipping_name"]), nodes,
                SyncJSON.str(forecast["time_forecast_desc"]))
    }

    private static func mtop(_ api: String, data: [String: Any]) async throws -> [String: Any] {
        let params = try JSONSerialization.data(withJSONObject: data, options: [.sortedKeys])
        guard let json = String(data: params, encoding: .utf8) else {
            throw NativeSyncError.badResponse("请求参数编码失败")
        }
        var cookies = await WebCookieRequest.cookies(domain: "taobao.com")
        guard !cookies.isEmpty else { throw NativeSyncError.noLogin("请先登录淘宝/菜鸟") }
        var lastFailure = "接口请求失败"
        for attempt in 0..<2 {
            let token = cookies.first(where: { $0.name == "_m_h5_tk" })?.value
                .components(separatedBy: "_").first ?? ""
            let time = String(Int64(Date().timeIntervalSince1970 * 1000))
            let signed = "\(token)&\(time)&12574478&\(json)"
            let hash = Insecure.MD5.hash(data: Data(signed.utf8))
                .map { String(format: "%02x", $0) }.joined()
            var components = URLComponents(string: "https://h5api.m.taobao.com/h5/\(api.lowercased())/1.0/")!
            components.queryItems = [
                .init(name: "jsv", value: "2.7.4"),
                .init(name: "appKey", value: "12574478"),
                .init(name: "t", value: time),
                .init(name: "sign", value: hash),
                .init(name: "api", value: api),
                .init(name: "v", value: "1.0"),
                .init(name: "type", value: "originaljson"),
                .init(name: "dataType", value: "json"),
                .init(name: "data", value: json)
            ]
            var headers = try await WebCookieRequest.headers(domain: "taobao.com")
            headers["Referer"] = "https://h5.m.taobao.com/"
            let (result, response) = try await WebCookieRequest.request(components.url!, headers: headers)
            let returned = (result["ret"] as? [String])?.first ?? ""
            if returned.hasPrefix("SUCCESS") { return result }
            lastFailure = returned.isEmpty ? "MTOP 业务返回失败" : returned
            let refresh = ["TOKEN_EMPTY", "TOKEN_EXPIRED", "TOKEN_EXOIRED", "ILLEGAL_ACCESS"]
            guard attempt == 0 && refresh.contains(where: { returned.uppercased().contains($0) }) else { break }
            // Cookie rotation from the gateway response. No credential is logged.
            let headerFields = response.allHeaderFields.reduce(into: [String: String]()) { out, item in
                out[String(describing: item.key)] = String(describing: item.value)
            }
            let fresh = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: components.url!)
            for cookie in fresh { await WebCookieRequest.store.setCookie(cookie) }
            cookies = await WebCookieRequest.cookies(domain: "taobao.com")
        }
        throw NativeSyncError.unavailable("菜鸟 MTOP 请求失败：\(lastFailure)")
    }

    private static func cainiaoPackages() async throws -> [NativeSyncParcel] {
        var out: [NativeSyncParcel] = []
        let api = "mtop.cainiao.lpc.packageservice.queryPdsPackageDataList"
        for page in 1...2 {
            let json = try await mtop(api, data: [
                "pageSize": 50, "currentPage": page,
                "needTemporality": false,
                "needDynInfo": "{'needFindTemporality':true,'needAppointment':true}"
            ])
            let outer = SyncJSON.dict(json["data"])
            let body = SyncJSON.dict(outer["data"]).isEmpty ? outer : SyncJSON.dict(outer["data"])
            let entries = SyncJSON.list(body["packages"])
            for pkg in entries {
                let mail = SyncJSON.first(pkg, ["mailNo", "mail_no"])
                guard SyncJSON.isMail(mail) else { continue }
                let station = SyncJSON.dict(pkg["packageStation"])
                let feature = SyncJSON.dict(pkg["feature"])
                let items = SyncJSON.list(pkg["packageItem"])
                let firstItem = items.first ?? [:]
                var parcel = NativeSyncParcel(source: "cainiao")
                parcel.mailNo = mail
                let carrier = SyncJSON.dict(pkg["cpInfo"])
                let logistics = SyncJSON.dict(pkg["logisticsCompany"])
                parcel.company = SyncJSON.first(pkg, ["cpName", "cp_name", "companyName",
                    "cpCode", "logisticsCompanyName", "expressCompanyName", "expressName"])
                if parcel.company.isEmpty {
                    parcel.company = SyncJSON.first(carrier, ["cpName", "companyName", "name", "cpCode"])
                }
                if parcel.company.isEmpty {
                    parcel.company = SyncJSON.first(logistics, ["name", "companyName", "cpName"])
                }
                parcel.title = SyncJSON.first(feature, ["recommendPackageTitle", "recommend_package_title"])
                if parcel.title.isEmpty { parcel.title = SyncJSON.first(firstItem, ["itemTitle", "item_title"]) }
                parcel.station = SyncJSON.first(station, ["pointName", "point_name", "stationName", "name"])
                parcel.code = SyncJSON.pickup(SyncJSON.first(station, ["authCode", "auth_code", "showPickupCode", "pickUpCode", "pickupCode"]))
                if parcel.code.isEmpty {
                    parcel.code = SyncJSON.pickup(SyncJSON.first(feature, ["stationOrderPickUpCode", "station_order_pick_up_code"]))
                }
                let status = SyncJSON.first(pkg, ["statusDesc", "status", "packageStatus"])
                let upperStatus = status.uppercased()
                if ["CANCEL", "REJECT", "RETURN", "LOST"].contains(upperStatus) &&
                   parcel.code.isEmpty { continue }
                // SIGN is delivered/picked, not an in-transit parcel. Propagate
                // it to the merge layer so an existing parcel is marked picked,
                // but do not insert historical signed parcels as new packages.
                parcel.latest = upperStatus == "SIGN" ? "已签收" : status
                parcel.arrived = !parcel.code.isEmpty
                if out.count < 4 {
                    if let detail = await cainiaoTrack(mail) {
                        if !detail.company.isEmpty { parcel.company = detail.company }
                        if !detail.nodes.isEmpty {
                            parcel.tracks = detail.nodes
                            // Avoid replacing final platform SIGN with older route text.
                            if upperStatus != "SIGN" {
                                parcel.latest = detail.nodes.first?.text ?? status
                            }
                        }
                    }
                }
                out.append(parcel)
            }
            let total = Int(SyncJSON.str(body["totalPage"])) ?? 1
            if page >= total || entries.isEmpty { break }
        }
        return out
    }

    // Original utils/cainiao.ts: trackMailNo() with a PID query first, falling
    // back to carrier detection + queryalltrace. A failed trace lookup does not
    // invalidate the rest of the order-list import. Shared with the Vipshop
    // import, which looks up tracks for parcels that have a mail number.
    static func cainiaoTrack(_ mail: String) async -> (company: String, nodes: [TrackNode])? {
        var result: [String: Any]?
        do {
            result = try await mtop("mtop.cainiao.logisticsdetail.packages.pid.orderCode.mailNo.get",
                                    data: ["mailNo": mail])
        } catch {
            var companyCode = ""
            if let cp = try? await mtop("mtop.taobao.logisticsDetailTraceQueryService.queryCpByMailNo",
                                         data: ["mailNo": mail]) {
                let d = SyncJSON.dict(cp["data"])
                let list = SyncJSON.list(d["result"])
                companyCode = SyncJSON.first(list.first ?? [:], ["tpCode", "cpCode"])
            }
            result = try? await mtop("mtop.taobao.logisticstracedetailservice.queryalltrace", data: [
                "mailNo": mail, "cpCode": companyCode, "actor": "RECEIVER",
                "isShowAllDetail": true, "isShowExceptionDetail": true,
                "isShowExpressMan": true, "isShowConsignDetail": true,
                "isShowDeliveryProgress": true, "isShowStationProxyOrder": true,
                "isShowServiceProvider": true, "isStandard": true,
                "isUnique": true, "ignoreInvalidNode": true
            ])
        }
        guard let result else { return nil }
        let data = SyncJSON.dict(result["data"])
        let payload = SyncJSON.dict(data["data"]).isEmpty ? data : SyncJSON.dict(data["data"])
        let first = SyncJSON.list(payload["result"]).first ?? payload
        let company = SyncJSON.first(first, ["cpName", "cp_name", "companyName", "logisticsCompanyName", "cpCode"])
        var nodes: [TrackNode] = []
        for key in ["detailList", "traceList", "transitList"] {
            let list = SyncJSON.list(first[key])
            if !list.isEmpty {
                nodes = list.compactMap { record -> TrackNode? in
                    let text = SyncJSON.first(record, ["standerdDesc", "statusDesc", "desc", "content", "action", "status"])
                    guard !text.isEmpty else { return nil }
                    return TrackNode(time: SyncJSON.first(record, ["time", "ocurrTimeStr", "occurTimeStr", "gmtCreate", "statusTime"]),
                                     text: text)
                }
                break
            }
        }
        return (company, nodes)
    }

    // Native port of the exact three identity-code endpoints in
    // 包裹助手(1).scripting/utils/identity.ts and utils/pddExpress.ts.
    // These are private H5 interfaces: valid authorization is required and
    // endpoint availability can change. Never fabricate a platform identity.
    struct IdentityResult {
        var code: String
        var expiresAt: Date
        var certified: Bool?
        var name: String?
        var maskedID: String?
        var mobile: String?
    }
    private static func identityData(_ value: Any?) -> [String: Any] {
        let direct = SyncJSON.dict(value)
        let nested = SyncJSON.dict(direct["data"])
        return nested.isEmpty ? direct : nested
    }
    private static func identityCodeIn(_ value: Any?, depth: Int = 0) -> String? {
        guard depth <= 6 else { return nil }
        if let raw = value as? String {
            return raw.range(of: #"^[A-Z]{2}[0-9A-Z]{8,26}$"#,
                             options: .regularExpression) != nil ? raw : nil
        }
        if let rows = value as? [Any] {
            for row in rows {
                if let found = identityCodeIn(row, depth: depth + 1) { return found }
            }
        }
        if let dict = value as? [String: Any] {
            for key in dict.keys.sorted(by: { a, b in
                let ap = a.lowercased().contains("code") || a.lowercased().contains("identity")
                let bp = b.lowercased().contains("code") || b.lowercased().contains("identity")
                return ap && !bp
            }) {
                if let found = identityCodeIn(dict[key], depth: depth + 1) { return found }
            }
        }
        return nil
    }
    private static func identityExpiry(_ value: Any?, depth: Int = 0) -> TimeInterval? {
        guard depth <= 6 else { return nil }
        if let dict = value as? [String: Any] {
            for (key, raw) in dict where key.lowercased().contains("expir") {
                let n = (raw as? NSNumber)?.doubleValue ??
                        Double(SyncJSON.str(raw)) ?? 0
                if n > 0 {
                    // Original Scripting handles second and millisecond durations.
                    return n > 1_000_000 ? n / 1000 : n
                }
            }
            for entry in dict.values {
                if let n = identityExpiry(entry, depth: depth + 1) { return n }
            }
        } else if let rows = value as? [Any] {
            for entry in rows {
                if let n = identityExpiry(entry, depth: depth + 1) { return n }
            }
        }
        return nil
    }
    private static func hasTaobaoCookie() async -> Bool {
        let cookies = await WebCookieRequest.cookies(domain: "taobao.com")
        return cookies.contains {
            ["unb", "tracknick", "cookie2", "_m_h5_tk"].contains($0.name) &&
            !$0.value.isEmpty
        }
    }
    static func hasIdentitySession(_ platform: String) async -> Bool {
        if platform == "pdd" {
            let cookie = await WebCookieRequest.cookies(domain: "yangkeduo.com")
            return !PddSessionVault.token.isEmpty ||
                    cookie.contains { $0.name == "PDDAccessToken" && !$0.value.isEmpty }
        }
        return await hasTaobaoCookie()
    }
    static func identityCode(_ platform: String) async throws -> IdentityResult {
        guard ["taobao", "cainiao", "pdd"].contains(platform) else {
            throw NativeSyncError.unavailable("暂不支持该平台身份码")
        }
        guard await hasIdentitySession(platform) else {
            throw NativeSyncError.noLogin(platform == "pdd" ?
                "请先在「账号授权」登录拼多多" : "请先在「账号授权」登录淘宝")
        }
        if platform == "pdd" {
            let result = try await pddJSON(
                "/api/express_trackbox/generate_identification_code",
                body: ["entry_source": "APP"],
                referer: "https://m.pinduoduo.net/mdkd/package?pr_page_from=scheme&tab=ID_CODE")
            let body = SyncJSON.dict(result["result"])
            let code = SyncJSON.str(body["identification_code"])
            guard !code.isEmpty else {
                throw NativeSyncError.badResponse("拼多多接口没有返回身份码，可能需要官方 App 安全验证")
            }
            let raw = (body["expire_mills"] as? NSNumber)?.doubleValue ??
                Double(SyncJSON.str(body["expire_mills"])) ?? 0
            let millis = raw > 0 ? raw : 5 * 60 * 1000
            let mobileInfo = SyncJSON.dict(body["mobile_info"])
            let mobile = SyncJSON.first(mobileInfo,
                ["mobile_desc", "mobile", "mobile_info_desc"])
            let mobileText = mobile.isEmpty ?
                SyncJSON.str(body["mobile_info_desc"]) : mobile
            return IdentityResult(code: code,
                expiresAt: Date().addingTimeInterval(millis / 1000),
                certified: nil, name: nil, maskedID: nil,
                mobile: mobileText.isEmpty ? nil : mobileText)
        }
        if platform == "cainiao" {
            let response = try await mtop(
                "mtop.cainiao.nbpickup.identitycode.get",
                data: ["appName": "GUOGUO", "verifyVersion": "V2"])
            let content = identityData(response["data"])
            let model = SyncJSON.dict(content["model"])
            let code = SyncJSON.str(model["identityCode"])
            guard !code.isEmpty else {
                throw NativeSyncError.badResponse("菜鸟接口没有返回实名身份码")
            }
            let seconds = max(60, Double(SyncJSON.str(model["expireTime"])) ?? 600)
            let certified = SyncJSON.str(model["certificated"]) == "true"
            return IdentityResult(code: code,
                expiresAt: Date().addingTimeInterval(seconds),
                certified: certified,
                name: SyncJSON.str(model["fullname"]).isEmpty ? nil :
                      SyncJSON.str(model["fullname"]),
                maskedID: SyncJSON.str(model["idCardNumber"]).isEmpty ? nil :
                          SyncJSON.str(model["idCardNumber"]),
                mobile: nil)
        }
        let response = try await mtop(
            "mtop.cainiao.pickup.identity.getIdentityMessage", data: [:])
        let content = identityData(response["data"])
        guard let code = identityCodeIn(content) else {
            throw NativeSyncError.badResponse("淘宝接口没有返回有效身份码")
        }
        let seconds = max(60, identityExpiry(content) ?? 300)
        return IdentityResult(code: code,
            expiresAt: Date().addingTimeInterval(seconds),
            certified: nil, name: nil, maskedID: nil, mobile: nil)
    }

    // The manual search and details screen share the same track endpoints.
    // Returning nil means this source had no verified shipment data.
    static func lookupShipment(_ mail:String, source:String?=nil) async -> NativeTrackLookup? {
        let usePdd=(source == "pdd" || source == nil || source == "")
        let useCainiao=(source == "cainiao" || source == "taobao" || source == nil || source == "")
        if usePdd, let detail=try? await pddTrack(mail), !detail.1.isEmpty {
            return NativeTrackLookup(mailNo:mail,company:detail.0,
                shipperCode:"",latest:detail.1.first?.text ?? "",
                nodes:detail.1,provider:"拼多多")
        }
        if useCainiao, let detail=await cainiaoTrack(mail), !detail.nodes.isEmpty {
            return NativeTrackLookup(mailNo:mail,company:detail.company,
                shipperCode:"",latest:detail.nodes.first?.text ?? "",
                nodes:detail.nodes,provider:"菜鸟")
        }
        return nil
    }

}


// Refresh only while the app is foregrounded. iOS doesn't guarantee
// unattended background polling for an ordinary unsigned/sideloaded app.
@MainActor enum NativeHomeRefresh {
    private static var running = false
    private static var lastStarted: TimeInterval =
        UserDefaults.standard.double(forKey: "native.home.lastAttempt")

    static func refresh(force: Bool = false) async -> [String] {
        guard !running else { return force ? ["同步正在进行"] : [] }
        let configured = UserDefaults.standard.object(forKey: "native.refresh.app") as? Int ?? 15
        let interval = TimeInterval(max(5, min(120, configured))) * 60
        let now = Date().timeIntervalSince1970
        guard force || now - lastStarted >= interval else { return [] }
        lastStarted = now
        UserDefaults.standard.set(now, forKey: "native.home.lastAttempt")
        running = true
        defer { running = false }

        var results: [String] = []
        for id in NativeParcelSync.platforms {
            // Skip platform sessions that were never authorized.
            if id == "mi" && !NativeMiExpress.hasSession { continue }
            if id == "cainiao" &&
                (UserDefaults.standard.object(forKey: "native.platform.enabled.cainiao") as? Bool) == false {
                continue
            }
            if id == "fengchao" && !NativeFengchao.hasSession { continue }
            // Dewu needs a foreground WebView to hook the order page; it is
            // never polled automatically.
            if id == "dewu" { continue }
            if id == "vip" && !await NativeVip.hasLogin() { continue }
            if id == "pdd" {
                let platformCookies = await WebCookieRequest.cookies(domain: "yangkeduo.com")
                if PddSessionVault.token.isEmpty && platformCookies.isEmpty { continue }
            }
            if id == "cainiao" {
                let platformCookies = await WebCookieRequest.cookies(domain: "taobao.com")
                if platformCookies.isEmpty { continue }
            }
            do {
                let result = try await NativeParcelSync.run(id, force: force)
                results.append(result.description)
            } catch {
                if force { results.append("\(id)：\(error.localizedDescription)") }
            }
        }
        // Persist the latest state and update ActivityKit. No Home Screen
        // widget timeline is scheduled in this sideloaded configuration.
        ParcelStore.shared.persist()
        UserDefaults.standard.set(Date().timeIntervalSince1970,
                                  forKey: "native.home.lastRefresh")
        if force && results.isEmpty { return ["没有已授权且支持自动同步的平台"] }
        return results
    }
}
