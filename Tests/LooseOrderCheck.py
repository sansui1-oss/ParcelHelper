#!/usr/bin/env python3
"""Mirror of LooseOrder in App/LooseOrder.swift (port of Scripting
utils/orderLoose.ts). Swift is not available on this Linux VM, so the
flatten + key-regex parser is checked here.
"""
import re
from datetime import datetime

ORDER_ID_KEYS = re.compile(r"^(order_?sn|order_?id|order_?no|order_?code|ordersn|orderid|order_?num)$")
MAIL_KEYS = re.compile(r"((express|waybill|tracking|logistic|delivery|transport)[_a-z]*?(no|num|code|id|sn))|^mail_?no$")
TITLE_KEYS = re.compile(r"(goods|product|ware|item|sku)[_a-z]*?name$|^(goods_?title|title|subject|sku_?title)$")
STATUS_KEYS = re.compile(r"order_?status_?name|status_?name|status_?desc|status_?str|order_?state_?name|status_?text")
COMPANY_KEYS = re.compile(r"(express|shipping|logistics|carrier)[_a-z]*?name")
TIME_KEYS = re.compile(r"(order_?time|create_?time|add_?time|order_?date|create_?date|pay_?time)")

def s(v):
    if isinstance(v, str):
        return v.strip()
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        return str(v)
    return ""

def flat_map(o, out=None, depth=0):
    if out is None:
        out = []
    if depth > 5 or o is None or not isinstance(o, (dict, list)):
        return out
    if isinstance(o, dict):
        items = o.items()
    else:
        items = [(str(i), v) for i, v in enumerate(o)]
    for k, v in items:
        if isinstance(v, (dict, list)):
            flat_map(v, out, depth + 1)
            continue
        val = s(v)
        if not val:
            continue
        key = str(k).lower()
        if not any(ek == key for ek, _ in out):
            out.append((key, val))
    return out

def ms_of(raw):
    if not raw:
        return None
    if re.fullmatch(r"\d{13}", raw):
        return int(raw)
    if re.fullmatch(r"\d{10}", raw):
        return int(raw) * 1000
    m = re.match(r"(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?:[ T](\d{1,2}):(\d{1,2}))?", raw)
    if not m:
        return None
    y, mo, d, h, mi = (int(x) if x else 0 for x in m.groups())
    return int(datetime(y, mo, d, h, mi).timestamp() * 1000)

def first(flat, pattern, accept=None):
    for k, v in flat:
        if not pattern.search(k):
            continue
        if accept and not accept(v):
            continue
        return v
    return ""

def parse(raw):
    f = flat_map(raw)
    return {
        "orderSn": first(f, ORDER_ID_KEYS, lambda v: len(v) >= 6 and re.fullmatch(r"[A-Za-z0-9-]+", v)),
        "mailNo": first(f, MAIL_KEYS, lambda v: re.fullmatch(r"[A-Za-z0-9-]{8,}", v) is not None),
        "itemTitle": first(f, TITLE_KEYS, lambda v: 1 < len(v) < 120),
        "statusHint": first(f, STATUS_KEYS),
        "company": first(f, COMPANY_KEYS),
        "orderTime": ms_of(first(f, TIME_KEYS)),
    }

vip = parse({"orderSn": "1234567890123", "expressNo": "SF1234567890",
             "goodsName": "羽绒服", "orderStatusName": "已发货",
             "expressName": "顺丰速运", "orderTime": "2026-11-10 12:00"})
assert vip["orderSn"] == "1234567890123", vip
assert vip["mailNo"] == "SF1234567890", vip
assert vip["itemTitle"] == "羽绒服", vip
assert vip["statusHint"] == "已发货", vip
assert vip["company"] == "顺丰速运", vip
assert vip["orderTime"] is not None, vip
print("PASS vip-style order", vip)

dewu = parse({"data": {"order": {"orderId": "DW12345678", "productName": "球鞋", "statusDesc": "待发货"}}})
assert dewu["orderSn"] == "DW12345678", dewu
assert dewu["itemTitle"] == "球鞋", dewu
assert dewu["statusHint"] == "待发货", dewu
print("PASS dewu-style nested order", dewu)

no_mail = parse({"orderSn": "1234567890123456", "expressNo": "123"})
assert no_mail["mailNo"] == "", no_mail
print("PASS order number is not a mail number")

assert ms_of("1762800000000") == 1762800000000
assert ms_of("1762800000") == 1762800000000
assert ms_of("2026-11-10 12:00") is not None
assert ms_of("") is None
assert ms_of("abc") is None
print("OK: LooseOrder checks pass.")
