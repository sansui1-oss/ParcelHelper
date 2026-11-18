#!/usr/bin/env python3
"""Mirror of miEndpointErrorText in App/MiExpressAccount.swift.
Swift is not available on this Linux VM, so the rendering is checked here.
"""
def text(path, code, msg):
    if path.endswith("/getList"):
        endpoint = "包裹列表"
    elif path.endswith("/query"):
        endpoint = "物流详情"
    elif path.endswith("/sendVerificationCode"):
        endpoint = "发送验证码"
    elif path.endswith("/checkVerificationCode"):
        endpoint = "校验验证码"
    elif path.endswith("/bind"):
        endpoint = "绑定手机号"
    else:
        endpoint = "快递服务"
    detail = f"：{msg}" if msg else ""
    hint = ("。可能是 assistant 会话不被服务端接受，建议解除小米授权后重新扫码登录；"
            "若仍为 4001，说明该服务可能限制第三方客户端") if code == "4001" else "。请检查官方账号验证与服务状态"
    return f"小米{endpoint}失败（服务代码 {code or '未知'}{detail}）{hint}"

CASES = [
    ("/cpa/express/phone/sendVerificationCode", "4001", "", ["发送验证码", "4001", "重新扫码登录"]),
    ("/cpa/express/phone/sendVerificationCode", "4001", "token invalid", ["token invalid"]),
    ("/cpa/express/phone/bind", "5000", "busy", ["绑定手机号", "5000", "busy"]),
    ("/cpa/express/v2/getList", "", "", ["包裹列表", "未知"]),
]
for path, code, msg, wants in CASES:
    out = text(path, code, msg)
    for w in wants:
        assert w in out, (path, code, msg, w, out)
    print(f"PASS {path} {code!r} -> {out}")
print("OK: MiError mapping checks pass.")
