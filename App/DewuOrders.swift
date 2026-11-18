import Foundation
import WebKit

/// Port of Scripting utils/dewu.ts: Dewu orders can only be read by
/// opening the order page in a WebView and hooking the page's own
/// buyerOrderList XHR. The signing headers (hsn/sk/ltk) come from the
/// native SDK and cannot be reproduced from a web view, so a 401 is
/// reported as-is instead of faked with placeholder data.
/// Only runs in the foreground app: there is no WebView in the Live
/// Activity extension, so Dewu is excluded from NativeHomeRefresh.
@MainActor enum NativeDewu {
    private static let ordersURL = "https://m.dewu.com/router/order/buyer/orderList"
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    /// Hook the page's own XHR and keep buyerOrderList responses in
    /// window.__dw. Verbatim port of dewu.ts XHR_HOOK.
    private static let xhrHook = """
    (function(){
      window.__dw = [];
      var oO = XMLHttpRequest.prototype.open, oS = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function(m,u){ this.__u = u; this.__m = m; return oO.apply(this, arguments) };
      XMLHttpRequest.prototype.send = function(b){
        var s = this;
        s.addEventListener('load', function(){
          try {
            if (/buyerOrderList/i.test(s.__u || '')) {
              window.__dw.push({ u: s.__u, m: s.__m, st: s.status, body: (s.responseText || '').slice(0, 200000) });
            }
          } catch(e) {}
        });
        return oS.apply(this, arguments)
      };
    })()
    """

    static func hasLogin() async -> Bool {
        let list = await WebCookieRequest.cookies(domain: "dewu.com")
        return list.contains { ["X-Auth-Token", "xAuthToken", "duToken"].contains($0.name) && !$0.value.isEmpty }
    }

    static func packages() async throws -> [NativeSyncParcel] {
        guard await hasLogin() else {
            throw NativeSyncError.noLogin("得物登录已失效，请重新授权")
        }
        // The shared cookie store already holds the login session from
        // PlatformWebLogin, so no cookies need to be set by hand here.
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.userContentController.addUserScript(
            WKUserScript(source: xhrHook, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let view = WKWebView(frame: .zero, configuration: config)
        view.customUserAgent = userAgent
        // Keep the view alive for the whole capture: a deallocated
        // WKWebView stops loading and drops the hooked responses. The
        // view is never added to a hierarchy; loading still proceeds
        // while the app is in the foreground.
        view.load(URLRequest(url: URL(string: ordersURL)!))
        try? await Task.sleep(nanoseconds: 7_000_000_000)
        let raw = await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            view.evaluateJavaScript("JSON.stringify(window.__dw||[])") { value, _ in
                cont.resume(returning: value as? String ?? "[]")
            }
        }
        guard let data = raw.data(using: .utf8),
              let hits = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NativeSyncError.badResponse("得物订单响应解析失败")
        }
        let ok = hits.filter {
            ($0["st"] as? NSNumber)?.intValue == 200 &&
            (($0["body"] as? String)?.count ?? 0) > 20
        }
        guard !ok.isEmpty else {
            if hits.contains(where: { ($0["st"] as? NSNumber)?.intValue == 401 }) {
                throw NativeSyncError.unavailable("得物接口要求原生签名，网页里签不出来（401）")
            }
            throw NativeSyncError.unavailable("没抓到得物订单请求，可能页面没加载出来")
        }
        let body = ok.last?["body"] as? String ?? ""
        guard let bodyData = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            throw NativeSyncError.badResponse("得物订单响应不是 JSON")
        }
        let dataDict = json["data"] as? [String: Any] ?? [:]
        let orders = dataDict["orderList"] as? [[String: Any]] ?? []
        // Dewu keeps a 60-day window in the Scripting sync layer.
        let cutoff = Date().timeIntervalSince1970 * 1000 - 60 * 24 * 3600 * 1000
        var out: [NativeSyncParcel] = []
        for rawOrder in orders {
            let order = LooseOrder.parse(rawOrder)
            guard !order.orderSn.isEmpty || !order.mailNo.isEmpty else { continue }
            if let t = order.orderTime, t < cutoff { continue }
            var parcel = NativeSyncParcel(source: "dewu")
            parcel.orderID = order.orderSn.isEmpty ? order.mailNo : order.orderSn
            parcel.mailNo = order.mailNo
            parcel.company = order.company
            parcel.title = order.itemTitle.isEmpty ? "得物订单" : order.itemTitle
            parcel.latest = order.statusHint.isEmpty ? "得物订单" : order.statusHint
            // No track refresh for Dewu (mirror Scripting): the loose
            // order only carries the status hint.
            out.append(parcel)
        }
        return out
    }
}
