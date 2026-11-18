import Foundation

/// Dedupe key cases for parcelDuplicateKeys (Shared/Storage.swift).
/// Mail numbers normalize the same way as NativeParcelSync.codeKey:
/// fullwidth digits become halfwidth, spaces and dashes are stripped,
/// everything is uppercased. Order ids match exactly (uppercased).
struct DedupeTests {
    static func runAll() {
        let fullwidth = parcelDuplicateKeys(mailNo: "７８００００００００００００", orderId: "")
        precondition(fullwidth == ["mail:780000000000000"],
                     "fullwidth digits must normalize: \(fullwidth)")
        let dashed = parcelDuplicateKeys(mailNo: "SF 1234-5678-9012", orderId: "")
        precondition(dashed == ["mail:SF123456789012"],
                     "spaces and dashes must be stripped: \(dashed)")
        let order = parcelDuplicateKeys(mailNo: "", orderId: "pdd:123456")
        precondition(order == ["order:PDD:123456"],
                     "order id must be kept, uppercased: \(order)")
        let both = parcelDuplicateKeys(mailNo: "JT1234567890123", orderId: "vip:987654")
        precondition(both == ["mail:JT1234567890123", "order:VIP:987654"],
                     "mail key must come first: \(both)")
        let short = parcelDuplicateKeys(mailNo: "ABC123", orderId: "")
        precondition(short.isEmpty, "a 6-char code is not a mail number: \(short)")
        let empty = parcelDuplicateKeys(mailNo: "", orderId: "")
        precondition(empty.isEmpty, "no identities means no keys")
        print("PASS DedupeTests (6 checks)")
    }
}
