import Foundation

/// needsClaim cases for kdniaoNeedsClaim (App/NativeTracking.swift),
/// ported from Scripting kdniao.ts. Only wording that tells the user to
/// claim a trial counts; already-claimed, expired or paywalled wording
/// does not.
struct NeedsClaimTests {
    static func runAll() {
        let claimable = ["请领取免费试用", "未领取试用套餐", "试用套餐领取",
                         "免费试用可领取", "去领取试用套餐", "请先领取试用",
                         "需要领取免费试用套餐"]
        for text in claimable {
            precondition(kdniaoNeedsClaim(text), "should be claimable: \(text)")
        }
        let notClaimable = ["已领取", "已领过", "套餐已过期，请购买", "请购买套餐",
                            "试用已使用", "请充值后使用", "需要开通套餐",
                            "没有可用套餐", ""]
        for text in notClaimable {
            precondition(!kdniaoNeedsClaim(text), "should NOT be claimable: \(text)")
        }
        print("PASS NeedsClaimTests (\(claimable.count + notClaimable.count) checks)")
    }
}
