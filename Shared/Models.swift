import Foundation

struct TrackNode: Codable, Hashable, Identifiable {
    var time: String
    var text: String
    var id: String { "\(time)-\(text)" }
}

struct Parcel: Codable, Identifiable, Hashable {
    var uuid: String = UUID().uuidString
    var code: String = ""
    var codes: [String] = []
    var companyName: Int = 0
    var address: String = ""
    var phone: String = ""
    var notes: String = ""
    var status: Int = 1
    var type: String = "delivery"
    var codeTime: String = ""
    var smsContent: String = ""
    var courierStationName: String = ""
    var courierStationUuid: String = ""
    var createdAt: Double = Date().timeIntervalSince1970 * 1000
    var mailNo: String? = nil
    var shipperCode: String? = nil
    var trackCompany: String? = nil
    var trackLatest: String? = nil
    var trackNodes: [TrackNode] = []
    var trackUpdatedAt: Double? = nil
    var source: String? = nil
    var receiverCity: String? = nil
    var receiverAddress: String? = nil
    var receiverName: String? = nil
    var receiverPhone: String? = nil
    var orderId: String? = nil
    var pickedByUser: Bool = false
    var eta: String? = nil
    var etaAt: Double? = nil
    var pickedAt: Double? = nil
    var userTitle: String? = nil
    var itemTitle: String? = nil
    var srcApp: SourceApp? = nil
    var arrivedAt: Double? = nil
    var closed: String? = nil
    var id: String { uuid }
    var title: String { [userTitle, itemTitle, trackCompany].compactMap { $0 }.first(where: { !$0.isEmpty }) ?? "快递包裹" }
    /// Some carriers explicitly confirm recipient pickup in the newest
    /// tracking event even when platform summary still says "in transit".
    /// Never infer collection from a generic signed-by-station event.
    var latestPickupConfirmed: Bool {
        // The newest node is not always the pickup event: a provider can
        // append a generic summary node after the actual pickup node, so
        // scan every node plus the summary instead of only the first one.
        let texts = ([trackLatest ?? ""] + trackNodes.map(\.text))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        // Bare "已取件" / "已取出" were missing: the old list only matched
        // them when prefixed with 您/用户, so a plain "快件已取件" node
        // stayed "运输中" even though the parcel was already collected.
        let terms = ["您已取件", "已取件", "您已取走", "已取走", "已取出",
                     "用户已取", "用户取件成功", "取件成功", "取件完成",
                     "取件已完成", "已完成取件", "完成取件", "完成取货",
                     "取货成功", "包裹已取走",
                     "已被取走", "已领取", "已被领取", "本人签收",
                     "本人已签收", "签收人：本人", "签收人本人",
                     "收件人已取", "收件人取件", "已从驿站取出",
                     "已从快递柜取出"]
        let exclusions = ["快递员已取件", "揽收取件", "商家已取件", "驿站代签收",
                          "代为签收", "待取件", "请取件", "未取件"]
        for text in texts {
            guard !exclusions.contains(where: { text.contains($0) }) else { continue }
            if terms.contains(where: { text.contains($0) }) { return true }
        }
        // Direct delivery (no station, no pickup code): a "已签收 / 已送达 /
        // 已妥投" event with nowhere left to pick the parcel up from means
        // the recipient already has it. This mirrors the original
        // platformSync rule (delivered + no code + no station = picked).
        // Station parcels are excluded here: they have a code or a station
        // name, and a station "已签收" is the station signing, not the user.
        let hasCode = !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !codes.isEmpty
        // Only the dedicated station field counts here: `address` in this
        // model is often the recipient's home address, not a station.
        let hasStation = !courierStationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasCode && !hasStation {
            let delivered = ["已签收", "签收成功", "已妥投", "已送达",
                             "已送达收件人", "收件人签收"]
            let stationWords = ["驿站", "快递柜", "代收点", "自提点", "丰巢"]
            for text in texts {
                guard !exclusions.contains(where: { text.contains($0) }) else { continue }
                guard !stationWords.contains(where: { text.contains($0) }) else { continue }
                if delivered.contains(where: { text.contains($0) }) { return true }
            }
        }
        return false
    }
    var isDone: Bool { status == 2 || pickedByUser || latestPickupConfirmed }
    // The courier marked this package delivered, not necessarily picked up
    // personally. Do not conflate signature and user's pickup.
    var isSigned: Bool {
        guard !isDone else { return false }
        let text = (trackLatest?.isEmpty == false ? trackLatest : trackNodes.first?.text) ?? ""
        let excluded = ["待签收", "等待签收", "签收中", "未签收", "代签收",
                        "代为签收", "驿站签收", "网点签收", "快递柜签收", "暂存签收"]
        guard !excluded.contains(where: text.contains) else { return false }
        let signed = ["已签收", "签收成功", "已妥投", "本人签收",
                      "收件人签收", "已完成签收", "已送达收件人"]
        return text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "SIGN" ||
            signed.contains(where: text.contains)
    }
    var displayStatus: String {
        if isDone { return "已取件" }
        if isSigned { return "已签收" }
        if isPending { return "待取件" }
        return "运输中"
    }
    var isPending: Bool {
        guard !isDone, !isSigned, closed == nil else { return false }
        if arrivedAt != nil { return true }
        if !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && code != mailNo { return true }
        // The original model requires a real pickup code or arrival timestamp.
        return !codes.isEmpty
    }
    var isTransit: Bool { !isDone && !isSigned && !isPending && closed == nil }
    var stationText: String { !courierStationName.isEmpty ? courierStationName : (!address.isEmpty ? address : "其他驿站") }
    var displayCode: String { code == mailNo ? "" : code }
}
struct SourceApp: Codable, Hashable { var id: String?; var name: String? }
struct Station: Codable, Identifiable, Hashable {
    var courierStationUuid: String = UUID().uuidString
    var courierStationName: String = ""
    var phone: String = ""
    var address: String = ""
    var businessHours: String = ""
    var notes: String = ""
    var keywords: [String] = []
    var phones: [String] = []
    var id: String { courierStationUuid }
}
struct Preferences: Codable {
    var reminderEnabled = false
    var reminderAfterHours = 24
    var appearanceMode = "system"
    var simpleMode = false
    var liveActivityEnabled = false
    var widgetShowTransit = true
    var nickName = "包裹助手"
    var kdBusinessID = ""
    var kdAPIKey = ""
}
struct Snapshot: Codable {
    var parcels: [Parcel] = []
    var stations: [Station] = []
    var preferences = Preferences()
    var updatedAt = Date()
}

enum StationMatcher {
    static func match(_ stations: [Station], text: String) -> Station? {
        var best: (Station, Int)?
        for s in stations {
            var score = 0
            for raw in s.keywords where raw.count >= 2 && text.contains(raw) { score = max(score, 100 + raw.count) }
            if s.courierStationName.count >= 2 && text.contains(s.courierStationName) { score = max(score, 50 + s.courierStationName.count) }
            if s.address.count >= 4 && text.contains(s.address) { score = max(score, 20 + s.address.count) }
            if score > (best?.1 ?? 0) { best = (s, score) }
        }
        return best?.0
    }
}
