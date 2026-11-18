import Foundation
import Combine

// Shared mail/code normalization: fullwidth to halfwidth, strip
// whitespace and -－—_, uppercase. A free function so the dedupe keys
// (and their tests) can use it without touching the @MainActor store.
func parcelNormalizedCodeKey(_ raw: String) -> String {
    let half = raw.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? raw
    return half.filter { !$0.isWhitespace && !"-－—_".contains($0) }.uppercased()
}

// Dedupe identities for one parcel, usable from tests without a store
// instance. Mail numbers are normalized the same way as
// NativeParcelSync.codeKey; order ids are only uppercased, so a platform
// order id matches exactly.
func parcelDuplicateKeys(mailNo: String, orderId: String) -> [String] {
    var result: [String] = []
    let mail = parcelNormalizedCodeKey(mailNo)
    if mail.range(of: #"^[A-Z0-9]{8,40}$"#, options: .regularExpression) != nil {
        result.append("mail:" + mail)
    }
    let order = orderId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if !order.isEmpty { result.append("order:" + order) }
    return result
}

@MainActor final class ParcelStore: ObservableObject {
    static let shared = ParcelStore()
    @Published private(set) var snapshot: Snapshot
    private let url: URL
    // Keep JSON encoding and filesystem writes off the scrolling/UI thread.
    // A serial queue preserves save ordering (new snapshots always win).
    private let persistenceQueue = DispatchQueue(label: "ParcelHelper.snapshot.write", qos: .utility)
    private static let ignoredAutoStationsKey = "native.stations.ignoredAutoNames.v1"
    private var localURL: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("parcelhelper-snapshot.json") }

    // Tombstones prevent a removed delivery from being silently recreated by
    // the next automatic platform refresh.
    private static let ignoredKey = "native.deleted.shipments.v1"
    /// Shared with NativeParcelSync.codeKey: fullwidth to halfwidth, strip
    /// whitespace and -－—_, uppercase. Both sides of every comparison use
    /// this, so a mail number typed with a fullwidth digit or a dash still
    /// matches the stored one.
    private static func normalized(_ raw: String) -> String {
        parcelNormalizedCodeKey(raw)
    }
    // Track every stable identity available at deletion time. A later sync can
    // supply a tracking number missing in the first import; a one-key tombstone
    // would allow the same explicitly deleted package to reappear.
    private static func keys(mail: String, order: String, source: String,
                             code: String = "", station: String = "") -> [String] {
        var result: [String] = []
        let validMail = normalized(mail)
        if validMail.range(of: #"^[A-Z0-9-]{8,40}$"#, options: .regularExpression) != nil {
            result.append("mail:" + validMail)
        }
        let normalizedOrder = normalized(order)
        if !normalizedOrder.isEmpty { result.append("order:" + normalizedOrder) }
        let pick = normalized(code), loc = normalized(station)
        if pick.range(of: #"^[A-Z0-9_-]{2,20}$"#, options: .regularExpression) != nil,
           !loc.isEmpty {
            result.append("pickup:" + source + ":" + pick + ":" + loc)
        }
        return result
    }

    func isDeletedShipment(source: String, order: String, mail: String,
                           code: String = "", station: String = "") -> Bool {
        // Match ANY identity of the parcel, not just the strongest one:
        // a later sync can supply a tracking number that the deleted
        // record did not have, and a one-key tombstone would let the same
        // explicitly deleted package reappear under its other identity.
        // The pickup key still requires source + code + station together,
        // so a bare reused pickup code alone cannot suppress a different
        // tracking number.
        let candidates = Self.keys(mail: mail, order: order, source: source,
                                   code: code, station: station)
        guard !candidates.isEmpty else { return false }
        let ignored = Set(UserDefaults.standard.stringArray(forKey: Self.ignoredKey) ?? [])
        return candidates.contains(where: ignored.contains)
    }

    /// A user who manually re-adds a deleted parcel (manual lookup or
    /// import confirm) must not have it suppressed again by the next
    /// platform sync. Call this from manual-save paths before upserting.
    func removeDeletion(mail: String, order: String, source: String = "",
                        code: String = "", station: String = "") {
        let candidates = Self.keys(mail: mail, order: order, source: source,
                                   code: code, station: station)
        guard !candidates.isEmpty else { return }
        var ignored = UserDefaults.standard.stringArray(forKey: Self.ignoredKey) ?? []
        let doomed = Set(candidates)
        ignored.removeAll(where: doomed.contains)
        UserDefaults.standard.set(ignored, forKey: Self.ignoredKey)
    }

    private func recordDeletion(_ parcel: Parcel) {
        let source = parcel.source ?? parcel.srcApp?.id ?? ""
        let candidates = Self.keys(mail: parcel.mailNo ?? "", order: parcel.orderId ?? "",
                                   source: source, code: parcel.displayCode,
                                   station: parcel.stationText)
        guard !candidates.isEmpty else { return }
        var ignored = UserDefaults.standard.stringArray(forKey: Self.ignoredKey) ?? []
        let removed = Set(candidates)
        ignored.removeAll(where: removed.contains)
        ignored.insert(contentsOf: candidates, at: 0)
        UserDefaults.standard.set(Array(ignored.prefix(1500)), forKey: Self.ignoredKey)
    }

    /// Merge only exact carrier tracking numbers (or identical legacy order
    /// IDs without tracking numbers). Product titles are NOT unique identities.
    /// Port of Scripting utils/dedupe.ts: every parcel registers all of its
    /// identities (mail number and platform order id), and merging re-indexes
    /// every key of the merged record to the survivor, so A==B and B==C
    /// collapse transitively instead of leaving a stray copy behind.
    private static func collapseExactDuplicates(_ items: [Parcel]) -> [Parcel] {
        var merged: [Parcel] = []
        var indices: [String: Int] = [:]
        for parcel in items {
            let keys = parcelDuplicateKeys(mailNo: parcel.mailNo ?? "", orderId: parcel.orderId ?? "")
            guard !keys.isEmpty else { merged.append(parcel); continue }
            var at: Int?
            for k in keys {
                if let i = indices[k] { at = i; break }
            }
            if let i = at {
                merged[i] = mergeDuplicates(merged[i], parcel)
                for k in parcelDuplicateKeys(mailNo: merged[i].mailNo ?? "", orderId: merged[i].orderId ?? "") {
                    indices[k] = i
                }
            } else {
                let idx = merged.count
                merged.append(parcel)
                for k in keys { indices[k] = idx }
            }
        }
        return merged
    }

    /// Port of dedupe.ts mergeTwo: the record with the newer track update
    /// (falling back to creation time) is the base; the other one only
    /// contributes codes, title, station, address and state. A picked
    /// record never merges back into "to collect".
    private static func mergeDuplicates(_ prev: Parcel, _ p: Parcel) -> Parcel {
        let prevTime = prev.trackUpdatedAt ?? prev.createdAt
        let pTime = p.trackUpdatedAt ?? p.createdAt
        let fresher = pTime > prevTime ? p : prev
        let older = fresher.uuid == p.uuid ? prev : p
        var merged = fresher
        merged.uuid = prev.uuid
        if prev.status == 2 || p.status == 2 { merged.status = 2 }
        merged.pickedByUser = prev.pickedByUser || p.pickedByUser
        merged.pickedAt = prev.pickedAt ?? p.pickedAt
        if merged.userTitle == nil { merged.userTitle = older.userTitle }
        if merged.itemTitle == nil || merged.itemTitle?.isEmpty == true || merged.itemTitle == "拼多多订单" {
            if let title = older.itemTitle, !title.isEmpty { merged.itemTitle = title }
        }
        if merged.trackCompany == nil || merged.trackCompany?.isEmpty == true {
            merged.trackCompany = older.trackCompany
        }
        if merged.mailNo == nil { merged.mailNo = older.mailNo }
        if merged.shipperCode == nil { merged.shipperCode = older.shipperCode }
        if merged.orderId == nil { merged.orderId = older.orderId }
        if merged.code.isEmpty { merged.code = older.code }
        if merged.courierStationName.isEmpty { merged.courierStationName = older.courierStationName }
        if merged.courierStationUuid.isEmpty { merged.courierStationUuid = older.courierStationUuid }
        if merged.address.isEmpty { merged.address = older.address }
        if merged.phone.isEmpty { merged.phone = older.phone }
        if merged.eta == nil { merged.eta = older.eta }
        if merged.etaAt == nil { merged.etaAt = older.etaAt }
        if merged.trackUpdatedAt == nil { merged.trackUpdatedAt = older.trackUpdatedAt }
        if merged.trackNodes.isEmpty { merged.trackNodes = older.trackNodes }
        if merged.trackLatest == nil { merged.trackLatest = older.trackLatest }
        if merged.arrivedAt == nil { merged.arrivedAt = older.arrivedAt }
        if merged.srcApp == nil { merged.srcApp = older.srcApp }
        if merged.source == nil { merged.source = older.source }
        for code in ([older.code] + older.codes).filter({ !$0.isEmpty }) {
            if !merged.codes.contains(code) { merged.codes.append(code) }
        }
        merged.createdAt = min(prev.createdAt, p.createdAt)
        return merged
    }

    /// Central duplicate lookup: mail number first (normalized, so a
    /// fullwidth digit or a dash does not hide a match), then platform
    /// order id exact match. Used before a new parcel is created.
    func findDuplicate(mailNo: String, orderId: String) -> Parcel? {
        let keys = parcelDuplicateKeys(mailNo: mailNo, orderId: orderId)
        guard !keys.isEmpty else { return nil }
        for key in keys where key.hasPrefix("mail:") {
            if let found = snapshot.parcels.first(where: {
                parcelDuplicateKeys(mailNo: $0.mailNo ?? "", orderId: $0.orderId ?? "").contains(key)
            }) { return found }
        }
        for key in keys where key.hasPrefix("order:") {
            if let found = snapshot.parcels.first(where: {
                parcelDuplicateKeys(mailNo: $0.mailNo ?? "", orderId: $0.orderId ?? "").contains(key)
            }) { return found }
        }
        return nil
    }

    private init() {
        // A third-party signing profile need not provide an App Group.
        // Keep the only authoritative copy in this app's own Documents.
        let localFile = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("parcelhelper-snapshot.json")
        url = localFile
        let data = try? Data(contentsOf: localFile)
        snapshot = data.flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) } ?? Snapshot()
        snapshot.parcels = Self.collapseExactDuplicates(snapshot.parcels)
        // Migrate station names already present in the existing parcel database.
        if discoverStations() { persist() }
    }
    func persist() {
        snapshot.parcels = Self.collapseExactDuplicates(snapshot.parcels)
        _ = discoverStations()
        snapshot.updatedAt = Date()
        let current = snapshot
        let destination = url
        persistenceQueue.async {
            do {
                let data = try JSONEncoder().encode(current)
                try data.write(to: destination, options: .atomic)
            } catch {
                print("ParcelStore save failed: \(error)")
            }
        }
        // ActivityKit supplies state directly to the Live Activity extension.
        // There is no Home Screen widget or shared container to refresh.
        let rows = snapshot.parcels
        let enabled = snapshot.preferences.liveActivityEnabled
        Task { await LiveActivityCoordinator.update(with: enabled ? rows : []) }
    }
    func upsert(_ parcel: Parcel) {
        if let i = snapshot.parcels.firstIndex(where: { $0.uuid == parcel.uuid }) {
            snapshot.parcels[i] = parcel
        } else if let dup = findDuplicate(mailNo: parcel.mailNo ?? "", orderId: parcel.orderId ?? ""),
                  let i = snapshot.parcels.firstIndex(where: { $0.uuid == dup.uuid }) {
            // A new record for an already-known mail number or order id
            // merges into the existing card instead of creating a second
            // one. A picked card never reverts to "to collect" this way.
            var merged = parcel
            merged.uuid = dup.uuid
            if dup.isDone {
                merged.status = 2
                merged.pickedByUser = dup.pickedByUser
                merged.pickedAt = dup.pickedAt ?? merged.pickedAt
            }
            snapshot.parcels[i] = merged
        } else {
            snapshot.parcels.insert(parcel, at: 0)
        }
        persist()
    }
    /// Avoid duplicates when an SMS automation runs more than once. A pickup
    /// code is not globally unique: only match it together with its station
    /// and only for recent, still-open parcels.
    @discardableResult
    func upsertRecognizedText(_ incoming: Parcel) -> Bool {
        let body = incoming.smsContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = Self.normalized(incoming.displayCode)
        let location = Self.normalized(incoming.courierStationName)
        let mail = Self.normalized(incoming.mailNo ?? "")
        let cutoff = Date().timeIntervalSince1970 * 1000 - 14 * 24 * 3600 * 1000
        let index = snapshot.parcels.firstIndex { old in
            if !body.isEmpty && old.smsContent.trimmingCharacters(in: .whitespacesAndNewlines) == body {
                return true
            }
            if !mail.isEmpty && Self.normalized(old.mailNo ?? "") == mail { return true }
            return old.type == "delivery" && !old.isDone &&
                !code.isEmpty && !location.isEmpty &&
                Self.normalized(old.displayCode) == code &&
                Self.normalized(old.courierStationName) == location &&
                old.createdAt >= cutoff
        }
        guard let i = index else {
            upsert(incoming)
            return false
        }
        var existing = snapshot.parcels[i]
        if existing.code.isEmpty { existing.code = incoming.code }
        if existing.mailNo == nil { existing.mailNo = incoming.mailNo }
        if existing.courierStationName.isEmpty { existing.courierStationName = incoming.courierStationName }
        if existing.address.isEmpty { existing.address = incoming.address }
        if existing.trackCompany == nil || existing.trackCompany?.isEmpty == true {
            existing.trackCompany = incoming.trackCompany
        }
        if existing.smsContent.isEmpty { existing.smsContent = incoming.smsContent }
        if existing.arrivedAt == nil && !existing.isDone { existing.arrivedAt = incoming.arrivedAt }
        snapshot.parcels[i] = existing
        persist()
        return true
    }

    /// Only called after the user reviews the imported details and confirms save.
    /// For duplicates, update selected fields without resetting pickup state or history.
    func importDouyin(_ incoming: Parcel) -> Bool {
        // The user explicitly confirmed this import, so a previous manual
        // delete of the same shipment no longer blocks it.
        removeDeletion(mail: incoming.mailNo ?? "", order: incoming.orderId ?? "")
        guard let mail = incoming.mailNo?.trimmingCharacters(in: .whitespacesAndNewlines), !mail.isEmpty else {
            upsert(incoming)
            return false
        }
        if let index = snapshot.parcels.firstIndex(where: {
            ($0.mailNo ?? "").caseInsensitiveCompare(mail) == .orderedSame
        }) {
            var existing = snapshot.parcels[index]
            if existing.userTitle == nil || existing.userTitle?.isEmpty == true {
                existing.userTitle = incoming.userTitle
            }
            if existing.trackCompany == nil || existing.trackCompany?.isEmpty == true {
                existing.trackCompany = incoming.trackCompany
            }
            if existing.orderId == nil || existing.orderId?.isEmpty == true {
                existing.orderId = incoming.orderId
            }
            if existing.code.isEmpty { existing.code = incoming.code }
            if existing.courierStationName.isEmpty { existing.courierStationName = incoming.courierStationName }
            if existing.trackLatest == nil || existing.trackLatest?.isEmpty == true {
                existing.trackLatest = incoming.trackLatest
            }
            if existing.smsContent.isEmpty { existing.smsContent = incoming.smsContent }
            if existing.arrivedAt == nil && !existing.isDone { existing.arrivedAt = incoming.arrivedAt }
            if existing.source == nil || existing.source?.isEmpty == true {
                existing.source = "douyin"
                existing.srcApp = incoming.srcApp
            }
            snapshot.parcels[index] = existing
            persist()
            return true
        }
        upsert(incoming)
        return false
    }

    func markDone(_ id: String, done: Bool) {
        guard let i = snapshot.parcels.firstIndex(where: { $0.uuid == id }) else { return }
        snapshot.parcels[i].status = done ? 2 : 1
        snapshot.parcels[i].pickedByUser = done
        snapshot.parcels[i].pickedAt = done ? Date().timeIntervalSince1970 * 1000 : nil
        persist()
    }
    func delete(_ id: String) {
        guard let parcel = snapshot.parcels.first(where: { $0.uuid == id }) else { return }
        recordDeletion(parcel)
        snapshot.parcels.removeAll { $0.uuid == id }
        persist()
    }

    /// Create an editable station only from a clearly labelled pickup location,
    /// never from generic "arrived in city" or carrier/status text.
    private static func normalizedStationName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func verifiedStationName(for parcel: Parcel) -> String? {
        let knownTypes = ["驿站", "代收点", "快递超市", "快递柜", "自提点", "取件点", "服务站"]
        let invalid = ["其他驿站", "快递驿站", "菜鸟驿站", "代收点", "快递柜", "自提点"]
        let preferred = normalizedStationName(parcel.courierStationName)
        // Some logistics services identify a pickup shop by its branch name
        // ("上东一号一期10栋1单元店") without the word "驿站".
        // Only trust the dedicated pickup-station field when a parcel has
        // actual pickup evidence; never create stations from the recipient
        // address, a generic courier status or a sorting hub.
        let excluded = ["分拨中心", "转运中心", "集散中心", "运转中心", "揽收",
                        "运输中", "派送中", "已签收", "已送达", "其他驿站",
                        "快递驿站", "菜鸟驿站", "其他站点", "未知驿站"]
        let explicitPickup = parcel.isPending || parcel.isDone
        let hasUsefulName = preferred.count >= 4 && preferred.count <= 65 &&
            !invalid.contains(preferred) &&
            !excluded.contains(where: preferred.contains) &&
            !["暂无", "未知", "其他", "快递包裹"].contains(preferred)
        if hasUsefulName &&
            (knownTypes.contains(where: preferred.contains) || explicitPickup) {
            return preferred
        }

        // For imported route records, require explicit store/locker language
        // with a location name. Avoid city sorting hubs and random addresses.
        let text = ([parcel.trackLatest ?? ""] + parcel.trackNodes.prefix(12).map(\.text))
            .joined(separator: "\n")
        let pattern = #"(?:放入|存放在|已入库至|已存入|已送至|已送达|已到达|寄存于)[：:\s]*([一-龥A-Za-z0-9·（）()\-]{2,36}?(?:快递超市|驿站|代收点|快递柜|自提点|取件点))"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let result = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(result.range(at: 1), in: text)
        else { return nil }
        let name = normalizedStationName(String(text[range]))
        guard name.count >= 4, !invalid.contains(name),
              !["分拨中心", "转运中心", "揽收"].contains(where: name.contains)
        else { return nil }
        return name
    }

    @discardableResult private func discoverStations() -> Bool {
        var modified = false
        let ignored = Set(UserDefaults.standard.stringArray(forKey: Self.ignoredAutoStationsKey) ?? [])
        for i in snapshot.parcels.indices {
            guard snapshot.parcels[i].type == "delivery" else { continue }
            let currentID = snapshot.parcels[i].courierStationUuid
            if !currentID.isEmpty,
               snapshot.stations.contains(where: { $0.id == currentID }) {
                continue // Preserve any manually edited station association.
            }
            guard let name = Self.verifiedStationName(for: snapshot.parcels[i]),
                  !ignored.contains(name) else { continue }
            if let existing = snapshot.stations.first(where: {
                Self.normalizedStationName($0.courierStationName)
                    .localizedCaseInsensitiveCompare(name) == .orderedSame
            }) {
                if snapshot.parcels[i].courierStationUuid != existing.id {
                    snapshot.parcels[i].courierStationUuid = existing.id
                    modified = true
                }
                continue
            }
            var station = Station()
            station.courierStationName = name
            let address = Self.normalizedStationName(snapshot.parcels[i].address)
            // A generic recipient address is NOT a station address.
            if address.count >= 5 && address.count <= 100 &&
               (address.contains(name) || ["驿站", "代收点", "快递柜", "快递超市"]
                .contains(where: address.contains)) {
                station.address = address
            }
            station.keywords = [name]
            station.notes = "从物流信息自动识别，可自行核对名称和补全地址"
            snapshot.stations.append(station)
            snapshot.parcels[i].courierStationUuid = station.id
            modified = true
        }
        return modified
    }

    func upsertStation(_ s: Station) {
        if let i = snapshot.stations.firstIndex(where: { $0.id == s.id }) { snapshot.stations[i] = s }
        else { snapshot.stations.append(s) }
        // A new manual record explicitly overrides a previous ignored auto match.
        let name = Self.normalizedStationName(s.courierStationName)
        var ignored = UserDefaults.standard.stringArray(forKey: Self.ignoredAutoStationsKey) ?? []
        ignored.removeAll { $0 == name }
        UserDefaults.standard.set(ignored, forKey: Self.ignoredAutoStationsKey)
        persist()
    }
    func removeStation(_ id: String) {
        guard let station = snapshot.stations.first(where: { $0.id == id }) else { return }
        let name = Self.normalizedStationName(station.courierStationName)
        var ignored = UserDefaults.standard.stringArray(forKey: Self.ignoredAutoStationsKey) ?? []
        if !ignored.contains(name) { ignored.append(name) }
        UserDefaults.standard.set(ignored, forKey: Self.ignoredAutoStationsKey)
        snapshot.stations.removeAll { $0.id == id }
        persist()
    }
    func changePreferences(_ f: (inout Preferences) -> Void) { f(&snapshot.preferences); persist() }

}

