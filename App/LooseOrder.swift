import Foundation

/// Port of Scripting utils/orderLoose.ts: a lenient order parser for
/// platforms whose real order field names have no verified sample yet
/// (both handbooks had 0-order accounts). Values are found by key-name
/// regex on a flattened map; where a value cannot be identified it comes
/// back empty instead of a guessed business meaning. Tighten the field
/// names once real orders have been seen on device.
struct LooseOrder {
    var orderSn: String = ""
    var itemTitle: String = ""
    var statusHint: String = ""
    var mailNo: String = ""
    var company: String = ""
    var orderTime: Double? = nil

    /// Flatten an object to (lowercased key, value) pairs, depth at most 5.
    /// The first occurrence of a key wins (shallower levels are more
    /// trustworthy). Dictionary key order in Swift is unspecified, so two
    /// same-named keys at the same depth may resolve either way; the field
    /// regexes are distinct enough that this does not matter in practice.
    static func flatMapOf(_ raw: Any, depth: Int = 0, into out: inout [(key: String, value: String)]) {
        guard depth <= 5 else { return }
        if let dict = raw as? [String: Any] {
            for (k, v) in dict {
                if v is [String: Any] || v is [Any] {
                    flatMapOf(v, depth: depth + 1, into: &out)
                    continue
                }
                let val = stringValue(v)
                guard !val.isEmpty else { continue }
                let key = k.lowercased()
                if !out.contains(where: { $0.key == key }) { out.append((key, val)) }
            }
        } else if let arr = raw as? [Any] {
            for v in arr { flatMapOf(v, depth: depth + 1, into: &out) }
        }
    }

    private static func stringValue(_ v: Any) -> String {
        if v is Bool { return "" }
        if let s = v as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }

    /// 13-digit milliseconds, 10-digit seconds, or a "yyyy-MM-dd HH:mm"
    /// style date string. Returns milliseconds since epoch.
    static func msOf(_ raw: String) -> Double? {
        guard !raw.isEmpty else { return nil }
        if raw.range(of: #"^\d{13}$"#, options: .regularExpression) != nil { return Double(raw) }
        if raw.range(of: #"^\d{10}$"#, options: .regularExpression) != nil {
            return (Double(raw) ?? 0) * 1000
        }
        let pattern = #"(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?:[ T](\d{1,2}):(\d{1,2}))?"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) else { return nil }
        func group(_ i: Int) -> Int {
            guard let r = Range(m.range(at: i), in: raw) else { return 0 }
            return Int(raw[r]) ?? 0
        }
        var comps = DateComponents()
        comps.year = group(1)
        comps.month = group(2)
        comps.day = group(3)
        comps.hour = group(4)
        comps.minute = group(5)
        guard let date = Calendar.current.date(from: comps) else { return nil }
        return date.timeIntervalSince1970 * 1000
    }

    private static func first(_ flat: [(key: String, value: String)], pattern: String,
                              accept: ((String) -> Bool)? = nil) -> String {
        for (k, v) in flat {
            guard k.range(of: pattern, options: .regularExpression) != nil else { continue }
            if let accept, !accept(v) { continue }
            return v
        }
        return ""
    }

    /// Pull the fields we need out of any order object.
    static func parse(_ raw: Any) -> LooseOrder {
        var flat: [(key: String, value: String)] = []
        flatMapOf(raw, into: &flat)
        var order = LooseOrder()
        order.orderSn = first(flat, pattern: #"^(order_?sn|order_?id|order_?no|order_?code|ordersn|orderid|order_?num)$"#,
                              accept: { $0.count >= 6 && $0.range(of: #"^[A-Za-z0-9-]+$"#, options: .regularExpression) != nil })
        // Mail number: 8+ alphanumerics, and the key must look like a
        // tracking number. An order number must never stand in for one.
        order.mailNo = first(flat, pattern: #"((express|waybill|tracking|logistic|delivery|transport)[_a-z]*?(no|num|code|id|sn))|^mail_?no$"#,
                             accept: { $0.range(of: #"^[A-Za-z0-9-]{8,}$"#, options: .regularExpression) != nil })
        order.itemTitle = first(flat, pattern: #"(goods|product|ware|item|sku)[_a-z]*?name$|^(goods_?title|title|subject|sku_?title)$"#,
                                accept: { $0.count > 1 && $0.count < 120 })
        order.statusHint = first(flat, pattern: #"order_?status_?name|status_?name|status_?desc|status_?str|order_?state_?name|status_?text"#)
        order.company = first(flat, pattern: #"(express|shipping|logistics|carrier)[_a-z]*?name"#)
        order.orderTime = msOf(first(flat, pattern: #"(order_?time|create_?time|add_?time|order_?date|create_?date|pay_?time)"#))
        return order
    }
}
