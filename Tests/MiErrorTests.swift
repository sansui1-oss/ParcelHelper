import Foundation

/// Error-text cases for Xiaomi business failures (see
/// MiExpressAccount.swift: miEndpointErrorText). The screenshot case is
/// 4001 at the send-verification-code step: the old code showed only
/// "小米业务返回失败（4001）", which gives the user no next step, and did
/// not even say which step failed.
struct MiErrorTests {
    static func runAll() {
        let t4001 = miEndpointErrorText(path: "/cpa/express/phone/sendVerificationCode",
                                        code: "4001", serverMessage: "")
        precondition(t4001.contains("发送验证码"), "4001 text must name the step")
        precondition(t4001.contains("4001"), "4001 text must keep the code")
        precondition(t4001.contains("重新扫码登录"), "4001 text must tell the user to re-authorize")
        let t4001msg = miEndpointErrorText(path: "/cpa/express/phone/sendVerificationCode",
                                           code: "4001", serverMessage: "token invalid")
        precondition(t4001msg.contains("token invalid"), "server message must be kept, not dropped")
        let tBind = miEndpointErrorText(path: "/cpa/express/phone/bind",
                                        code: "5000", serverMessage: "busy")
        precondition(tBind.contains("绑定手机号") && tBind.contains("5000") && tBind.contains("busy"),
                     "bind errors must name the step and keep code + server message")
        let tList = miEndpointErrorText(path: "/cpa/express/v2/getList", code: "", serverMessage: "")
        precondition(tList.contains("包裹列表") && tList.contains("未知"),
                     "missing code must render as 未知, not an empty code")
        print("PASS MiErrorTests (4 checks)")
    }
}
