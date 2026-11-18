#!/usr/bin/env python3
"""Mirror of Parcel.latestPickupConfirmed (Shared/Models.swift) before/after the fix.
Swift is not available on this Linux VM, so the term lists are copied verbatim
from the Swift source and checked here to prove the fix changes the outcome
for the reported cases without changing the station-sign cases.
"""
OLD_TERMS = ["您已取件", "您已取走", "用户已取", "用户取件成功",
             "取件成功", "取件完成", "已取走", "包裹已取走",
             "已被取走", "已领取", "已被领取", "本人签收",
             "收件人已取", "收件人取件", "已从驿站取出"]
NEW_TERMS = ["您已取件", "已取件", "您已取走", "已取走", "已取出",
             "用户已取", "用户取件成功", "取件成功", "取件完成",
             "取件已完成", "已完成取件", "完成取件", "完成取货",
             "取货成功", "包裹已取走",
             "已被取走", "已领取", "已被领取", "本人签收",
             "本人已签收", "签收人：本人", "签收人本人",
             "收件人已取", "收件人取件", "已从驿站取出",
             "已从快递柜取出"]
EXCLUSIONS = ["快递员已取件", "揽收取件", "商家已取件", "驿站代签收",
              "代为签收", "待取件", "请取件", "未取件"]
DELIVERED = ["已签收", "签收成功", "已妥投", "已送达", "已送达收件人", "收件人签收"]
STATION_WORDS = ["驿站", "快递柜", "代收点", "自提点", "丰巢"]

def old(texts):
    newest = texts[0] if texts else ""
    if any(e in newest for e in EXCLUSIONS):
        return False
    return any(t in newest for t in OLD_TERMS)

def new(texts, code="", station=""):
    for text in texts:
        if any(e in text for e in EXCLUSIONS):
            continue
        if any(t in text for t in NEW_TERMS):
            return True
    if not code and not station:
        for text in texts:
            if any(e in text for e in EXCLUSIONS):
                continue
            if any(w in text for w in STATION_WORDS):
                continue
            if any(d in text for d in DELIVERED):
                return True
    return False

# (texts newest-first, code, station, expected_new, description)
CASES = [
    (["快件已取件"], "", "", True, "plain 已取件, no station/code"),
    (["您已在新师范35号楼西头校园菜鸟驿站完成取件，感谢使用菜鸟驿站，期待再次为您服务。"], "", "", True, "screenshot 79040463671372: 完成取件 (no 已 prefix)"),
    (["快件已取出"], "", "", True, "plain 已取出"),
    (["快件已取件", "快件已到达XX转运中心"], "", "", True, "picked node is not the newest node"),
    (["本人签收"], "", "", True, "本人签收"),
    (["已签收，签收人：本人"], "", "", True, "签收人：本人"),
    (["快件已送达"], "", "", True, "direct delivery 已送达, no station/code"),
    (["快件已签收"], "", "", True, "direct delivery 已签收, no station/code"),
    (["快件已妥投"], "", "", True, "direct delivery 已妥投"),
    (["快件已签收"], "", "菜鸟驿站幸福路店", False, "station signed: must stay NOT picked"),
    (["快件已签收"], "8-1234", "", False, "has pickup code: must stay NOT picked (still to collect)"),
    (["快件已送达菜鸟驿站"], "", "", False, "delivered to station, not to recipient"),
    (["快递员已取件"], "", "", False, "courier collected it, not the recipient"),
    (["驿站代签收"], "", "", False, "station signed on behalf"),
    (["快件运输中"], "", "", False, "genuinely in transit"),
    (["快件已到达XX转运中心"], "", "", False, "transit hub arrival"),
    (["您已取件"], "", "", True, "already worked before"),
    (["已领取"], "", "", True, "already worked before"),
    (["【驿站】包裹已签收！如有问题请联系：代收点16657897305，您的快递已经妥投，投诉电话：037961271875，可关注“申通快递”官方微信公众号获取实时物流信息"], "", "", False, "screenshot 773448582203513: station-signed, must stay NOT picked"),
    (["您已在新师范35号楼西头校园菜鸟驿站完成取件，感谢使用菜鸟驿站，期待再次为您服务。"], "", "", True, "screenshot 79032142932381: 完成取件"),
]

fails = 0
for texts, code, station, expected, desc in CASES:
    o, n = old(texts), new(texts, code, station)
    ok = (n == expected)
    fails += (not ok)
    print(f"{'PASS' if ok else 'FAIL'}  old={o!s:5} new={n!s:5} expected={expected!s:5}  {desc}  {texts}")
print(f"\n{len(CASES)-fails}/{len(CASES)} new-logic cases pass")
assert fails == 0
print("OK: fix changes the reported cases and keeps station-sign cases unpicked.")
