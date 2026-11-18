#!/usr/bin/env python3
"""Mirror of kdniaoNeedsClaim in App/NativeTracking.swift (port of
Scripting kdniao.ts needsClaim). Swift is not available on this Linux VM,
so the regex logic is checked here.
"""
import re

EXCLUDED = ["已领取", "已领过", "已使用", "已过期", "购买", "充值", "开通"]
PATTERN = re.compile(r"(请|需要|可|去).{0,8}领取|未领取|领取.{0,6}(试用|免费)|(试用|免费).{0,6}领取")

def needs_claim(reason):
    t = reason.strip()
    if not t:
        return False
    if any(x in t for x in EXCLUDED):
        return False
    return PATTERN.search(t) is not None

CLAIMABLE = ["请领取免费试用", "未领取试用套餐", "试用套餐领取",
             "免费试用可领取", "去领取试用套餐", "请先领取试用",
             "需要领取免费试用套餐"]
NOT_CLAIMABLE = ["已领取", "已领过", "套餐已过期，请购买", "请购买套餐",
                 "试用已使用", "请充值后使用", "需要开通套餐",
                 "没有可用套餐", ""]
for text in CLAIMABLE:
    assert needs_claim(text), text
    print(f"PASS claimable {text!r}")
for text in NOT_CLAIMABLE:
    assert not needs_claim(text), text
    print(f"PASS not claimable {text!r}")
print(f"OK: needsClaim checks pass ({len(CLAIMABLE) + len(NOT_CLAIMABLE)} cases).")
