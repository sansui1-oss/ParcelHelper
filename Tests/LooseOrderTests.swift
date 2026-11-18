import Foundation

/// Loose parser cases for LooseOrder (App/LooseOrder.swift), ported from
/// Scripting utils/orderLoose.ts. Field names come from key-name regexes
/// because no real Vipshop/Dewu order sample exists yet.
struct LooseOrderTests {
    static func runAll() {
        // Vipshop-style flat order.
        let vip = LooseOrder.parse([
            "orderSn": "1234567890123",
            "expressNo": "SF1234567890",
            "goodsName": "羽绒服",
            "orderStatusName": "已发货",
            "expressName": "顺丰速运",
            "orderTime": "2026-11-10 12:00",
        ] as [String: Any])
        precondition(vip.orderSn == "1234567890123", "vip orderSn: \(vip.orderSn)")
        precondition(vip.mailNo == "SF1234567890", "vip mailNo: \(vip.mailNo)")
        precondition(vip.itemTitle == "羽绒服", "vip title: \(vip.itemTitle)")
        precondition(vip.statusHint == "已发货", "vip status: \(vip.statusHint)")
        precondition(vip.company == "顺丰速运", "vip company: \(vip.company)")
        precondition(vip.orderTime != nil, "vip orderTime must parse")
        // Dewu-style nested order.
        let dewu = LooseOrder.parse([
            "data": ["order": ["orderId": "DW12345678",
                               "productName": "球鞋",
                               "statusDesc": "待发货"]],
        ] as [String: Any])
        precondition(dewu.orderSn == "DW12345678", "dewu orderSn: \(dewu.orderSn)")
        precondition(dewu.itemTitle == "球鞋", "dewu title: \(dewu.itemTitle)")
        precondition(dewu.statusHint == "待发货", "dewu status: \(dewu.statusHint)")
        // An order number must never stand in for a mail number.
        let noMail = LooseOrder.parse([
            "orderSn": "1234567890123456", "expressNo": "123",
        ] as [String: Any])
        precondition(noMail.mailNo.isEmpty, "short expressNo must not be a mail number")
        // Timestamps: 13-digit ms, 10-digit seconds, date string, junk.
        precondition(LooseOrder.msOf("1762800000000") == 1_762_800_000_000, "13-digit ms")
        precondition(LooseOrder.msOf("1762800000") == 1_762_800_000_000, "10-digit seconds")
        precondition(LooseOrder.msOf("2026-11-10 12:00") != nil, "date string must parse")
        precondition(LooseOrder.msOf("") == nil, "empty time must be nil")
        precondition(LooseOrder.msOf("abc") == nil, "junk time must be nil")
        print("PASS LooseOrderTests (16 checks)")
    }
}
