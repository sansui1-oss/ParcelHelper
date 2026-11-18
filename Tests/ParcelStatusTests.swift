import Foundation

/// Status-classification cases for the "already picked up but still shows
/// 运输中" bug. Run via Tests.main (DouyinParserTests.swift calls
/// ParcelStatusTests.runAll()) or from an Xcode test target.
///
/// These mirror Tests/ParcelStatusCheck.py, which is the runnable copy on
/// machines without a Swift toolchain.
struct ParcelStatusTests {
    static func runAll() {
        func parcel(latest: String, nodes: [String] = [], code: String = "",
                    station: String = "") -> Parcel {
            var p = Parcel()
            p.trackLatest = latest
            p.trackNodes = nodes.map { TrackNode(time: "2026-11-18 10:00:00", text: $0) }
            p.code = code
            p.courierStationName = station
            return p
        }
        // Explicit pickup wording the old list missed.
        precondition(parcel(latest: "快件已取件").latestPickupConfirmed,
                     "plain 已取件 should be picked")
        // Screenshot 2026-11-18: ZTO 79040463671372, "您已在新师范35号楼西头
        // 校园菜鸟驿站完成取件……" — "完成取件" has no 已 prefix, so the
        // earlier "已完成取件" / "取件完成" terms did not match it.
        precondition(parcel(latest: "您已在新师范35号楼西头校园菜鸟驿站完成取件，感谢使用菜鸟驿站，期待再次为您服务。").latestPickupConfirmed,
                     "完成取件 (screenshot) should be picked")
        precondition(parcel(latest: "快件已取出").latestPickupConfirmed,
                     "plain 已取出 should be picked")
        precondition(parcel(latest: "运输中",
                            nodes: ["快件已取件", "快件已到达XX转运中心"]).latestPickupConfirmed,
                     "picked node below the newest node should still count")
        precondition(parcel(latest: "已签收，签收人：本人").latestPickupConfirmed,
                     "签收人：本人 should be picked")
        // Direct delivery: no code, no station, nowhere left to collect from.
        precondition(parcel(latest: "快件已送达").latestPickupConfirmed,
                     "direct 已送达 should be picked")
        precondition(parcel(latest: "快件已签收").latestPickupConfirmed,
                     "direct 已签收 should be picked")
        precondition(parcel(latest: "快件已妥投").latestPickupConfirmed,
                     "direct 已妥投 should be picked")
        // Station / courier cases must NOT flip to picked.
        precondition(!parcel(latest: "快件已签收", station: "菜鸟驿站幸福路店").latestPickupConfirmed,
                     "station-signed parcel must stay not picked")
        precondition(!parcel(latest: "快件已签收", code: "8-1234").latestPickupConfirmed,
                     "parcel with a pickup code must stay not picked")
        precondition(!parcel(latest: "快件已送达菜鸟驿站").latestPickupConfirmed,
                     "delivered to a station must stay not picked")
        precondition(!parcel(latest: "快递员已取件").latestPickupConfirmed,
                     "courier pickup must stay not picked")
        precondition(!parcel(latest: "驿站代签收").latestPickupConfirmed,
                     "station signing on behalf must stay not picked")
        precondition(!parcel(latest: "快件运输中").latestPickupConfirmed,
                     "genuinely in-transit parcel must stay not picked")
        // Display status follows the same rule.
        precondition(parcel(latest: "快件已取件").isDone, "已取件 should be done")
        precondition(parcel(latest: "快件已取件").displayStatus == "已取件",
                     "displayStatus should be 已取件")
        precondition(parcel(latest: "快件已签收", station: "菜鸟驿站幸福路店").isSigned,
                     "station-signed parcel should show 已签收, not 已取件")
        precondition(parcel(latest: "快件运输中").isTransit,
                     "in-transit parcel should stay in transit")
        print("PASS ParcelStatusTests (16 checks)")
    }
}
