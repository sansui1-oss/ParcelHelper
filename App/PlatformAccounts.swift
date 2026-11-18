import SwiftUI
import WebKit
import Security

// Based on the original Scripting project's platform list and login endpoints.
// WebKit sessions remain on the device. Authentication is not equivalent to
// having a working private H5 order API, which can change without notice.

@MainActor enum PddSessionVault {
    private static let service = "com.muxui.ParcelHelper.pdd"
    static var token: String {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "access",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ token: String) {
        guard token.count >= 8, token.count <= 4096 else { return }
        clear()
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "access",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(token.utf8)]
        SecItemAdd(q as CFDictionary, nil)
    }
    static func clear() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "access"]
        SecItemDelete(q as CFDictionary)
    }
}

private struct PlatformWebsite: Identifiable {
    let id: String
    let title: String
    let login: URL?
    let validCookie: String?
    let domain: String?
    let note: String
    let home: URL?
}

private enum PlatformCatalog {
    static let rows: [PlatformWebsite] = [
        .init(id: "taobao", title: "淘宝", login: URL(string: "https://login.taobao.com/member/login.jhtml"), validCookie: "unb", domain: "taobao.com", note: "网页登录", home: URL(string: "https://www.taobao.com/") ),
        .init(id: "cainiao", title: "菜鸟", login: URL(string: "https://login.taobao.com/member/login.jhtml"), validCookie: "unb", domain: "taobao.com", note: "网页登录", home: URL(string: "https://www.cainiao.com/") ),
        .init(id: "jd", title: "京东", login: URL(string: "https://plogin.m.jd.com/login/login?appid=0&returnurl=https%3A%2F%2Fhome.m.jd.com%2FmyJd%2Fnewhome.action"), validCookie: "pt_key", domain: "jd.com", note: "网页登录", home: URL(string: "https://m.jd.com/") ),
        .init(id: "pdd", title: "拼多多", login: URL(string: "https://mobile.yangkeduo.com/login.html"), validCookie: "PDDAccessToken", domain: "yangkeduo.com", note: "网页登录", home: URL(string: "https://mobile.yangkeduo.com/") ),
        .init(id: "fengchao", title: "丰巢", login: nil, validCookie: nil, domain: nil, note: "平台入口", home: URL(string: "https://www.fcbox.com/") ),
        .init(id: "mi", title: "小米快递聚合", login: nil, validCookie: nil, domain: nil, note: "平台入口", home: URL(string: "https://www.mi.com/") ),
        .init(id: "vip", title: "唯品会", login: URL(string: "https://m.vip.com/v3/index.html#/pages/userCenter/userCenter"), validCookie: "VIP_TANK", domain: "vip.com", note: "网页登录", home: URL(string: "https://m.vip.com/") ),
        .init(id: "dewu", title: "得物", login: URL(string: "https://m.dewu.com/router/order/buyer/orderList"), validCookie: "X-Auth-Token", domain: "dewu.com", note: "网页登录", home: URL(string: "https://m.dewu.com/") ),
        .init(id: "douyin", title: "抖音", login: nil, validCookie: nil, domain: nil, note: "平台入口", home: URL(string: "https://www.douyin.com/") )
    ]
}

@MainActor private enum PlatformSession {
    private static func enabled(_ id: String) -> Bool {
        guard id == "taobao" || id == "cainiao" else { return true }
        let key = "native.platform.enabled." + id
        return UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
    static func isEnabled(_ id: String) -> Bool { enabled(id) }
    static func setEnabled(_ id: String, _ enabled: Bool) {
        guard id == "taobao" || id == "cainiao" else { return }
        UserDefaults.standard.set(enabled, forKey: "native.platform.enabled." + id)
    }
    static func hasRawTaobaoSession() async -> Bool {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await cookieStore.allCookies()
        return cookies.contains {
            ["unb", "tracknick"].contains($0.name) &&
            !$0.value.isEmpty &&
            ($0.domain == "taobao.com" || $0.domain.hasSuffix(".taobao.com")) &&
            ($0.expiresDate == nil || $0.expiresDate! > Date())
        }
    }
    static func isLoggedIn(_ p: PlatformWebsite) async -> Bool {
        if !enabled(p.id) { return false }
        if p.id == "pdd" && !PddSessionVault.token.isEmpty { return true }
        guard let marker = p.validCookie, let domain = p.domain else { return false }
        // Some platforms accept more than one login cookie: Vipshop counts
        // VIP_TANK, m_vipruid or WAP[login] (VipRUID alone does not count);
        // Dewu counts X-Auth-Token, xAuthToken or duToken.
        let markers: [String]
        switch p.id {
        case "vip": markers = ["VIP_TANK", "m_vipruid", "WAP[login]"]
        case "dewu": markers = ["X-Auth-Token", "xAuthToken", "duToken"]
        default: markers = [marker]
        }
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        return cookies.contains { cookie in
            (markers.contains(cookie.name) || ((p.id == "taobao" || p.id == "cainiao") && cookie.name == "tracknick")) &&
            !cookie.value.isEmpty &&
            (cookie.domain == domain || cookie.domain.hasSuffix("." + domain)) &&
            (cookie.expiresDate == nil || cookie.expiresDate! > Date())
        }
    }
    static func clear(_ p: PlatformWebsite) async {
        if p.id == "pdd" { PddSessionVault.clear() }
        if p.id == "taobao" || p.id == "cainiao" {
            setEnabled(p.id, false)
            let other = p.id == "taobao" ? "cainiao" : "taobao"
            if enabled(other) { return }
        }
        guard let domain = p.domain else { return }
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await store.allCookies()
        for cookie in cookies where cookie.domain == domain || cookie.domain.hasSuffix("." + domain) {
            await store.deleteCookie(cookie)
        }
    }
}

private struct PlatformBrandMark: View {
    let id: String
    var body: some View {
        Group {
            if UIImage(named: "brand_" + id) != nil {
                Image("brand_" + id)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(Circle())
            } else {
                // No brand asset yet (Vipshop / Dewu): a neutral badge
                // instead of an empty circle.
                Circle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: 42, height: 42)
                    .overlay { Image(systemName: "bag.fill").foregroundStyle(.secondary) }
            }
        }
        .accessibilityLabel(id)
    }
}

struct PlatformAccountsPage: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var authenticated: Set<String> = []
    @State private var loginTarget: PlatformWebsite?
    @State private var finishedLogin: PlatformWebsite?
    @State private var revokeTarget: PlatformWebsite?
    @State private var notice: String?
    @State private var isSyncing = false
    @State private var showFengchao = false
    @State private var showXiaomi = false
    @State private var lastGlobalSync = UserDefaults.standard.double(forKey: "native.account.lastSync")
    @State private var refreshVersion = 0
    @State private var loginSyncBusy = false

    private let blue = Color(red: 0.19, green: 0.49, blue: 0.96)
    private var majorPlatforms: [PlatformWebsite] {
        PlatformCatalog.rows.filter { $0.id != "douyin" }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("授权电商平台")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 11)
                VStack(spacing: 0) {
                    ForEach(majorPlatforms) { platform in
                        row(platform)
                        if platform.id != majorPlatforms.last?.id {
                            Divider().padding(.leading, 76).padding(.trailing, 16)
                        }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 27, style: .continuous))
                .padding(.horizontal, 18)

                Text("淘宝与菜鸟共用登录会话，可分别停用订单和取件码来源。")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 33)
                    .padding(.top, 11)

                Text("同步")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                    .padding(.top, 29)
                    .padding(.bottom, 11)
                Button(action: syncAll) {
                    HStack(spacing: 12) {
                        if isSyncing { ProgressView().tint(blue) }
                        else { Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 20, weight: .medium)).foregroundStyle(blue) }
                        Text(isSyncing ? "正在同步包裹…" : "立即同步包裹")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        if lastGlobalSync > 0 {
                            Text(Date(timeIntervalSince1970: lastGlobalSync).formatted(date: .omitted, time: .shortened) + " 已同步")
                                .font(.system(size: 12)).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 19)
                    .frame(minHeight: 62)
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSyncing)
                .padding(.horizontal, 18)

                Text("其他")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .padding(.horizontal, 18).padding(.top, 29).padding(.bottom, 11)
                VStack(spacing: 0) {
                    NavigationLink {
                        DouyinImportView()
                    } label: {
                        HStack(spacing: 14) {
                            PlatformBrandMark(id: "douyin")
                            VStack(alignment: .leading, spacing: 3) {
                                Text("抖音").font(.system(size: 16, weight: .medium)).foregroundStyle(.primary)
                                Text("打开官方页面 · 复制后自动识别").font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer()

                        }.padding(.horizontal, 19).frame(minHeight: 69)
                    }.buttonStyle(.plain)
                    Divider().padding(.leading, 76).padding(.trailing, 16)
                    NavigationLink {
                        CourierSettings()
                    } label: {
                        HStack(spacing: 14) {
                            Image("brand_kdniao")
                                .resizable().scaledToFill()
                                .frame(width: 42, height: 42)
                                .clipShape(Circle())
                            Text("快递鸟（查单兜底）")
                                .font(.system(size: 16, weight: .medium)).foregroundStyle(.primary)
                            Spacer()
                            Text("未配置").font(.caption).foregroundStyle(.secondary)

                        }.padding(.horizontal, 19).frame(minHeight: 69)
                    }.buttonStyle(.plain)
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 18)
            }
            .padding(.bottom, 120)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("账号授权")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showFengchao) { FengchaoAccountPage() }
        .navigationDestination(isPresented: $showXiaomi) { XiaomiAccountPage() }
        .task { await refresh() }
        .onAppear { Task { await refresh() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
        .sheet(item: $loginTarget, onDismiss: {
            guard let platform = finishedLogin else { return }
            finishedLogin = nil
            Task {
                await refresh()
                if (platform.id == "taobao" || platform.id == "cainiao"),
                   await PlatformSession.hasRawTaobaoSession() {
                    PlatformSession.setEnabled(platform.id, true)
                    await refresh()
                }
                if await PlatformSession.isLoggedIn(platform) {
                    if platform.id == "taobao" || platform.id == "jd" || platform.id == "pdd" {
                        let started = await NativeWebAutoSync.shared.request(platform.id, force: true)
                        notice = started
                            ? platform.title + "：登录成功，已开始读取官方购物订单"
                            : platform.title + "：已登录，但自动同步无法读取当前会话"
                    } else if NativeParcelSync.platforms.contains(platform.id) {
                        loginSyncBusy = true
                        do {
                            let result = try await NativeParcelSync.run(platform.id, force: true)
                            notice = platform.title + "：授权完成，" + result.description
                        } catch {
                            notice = platform.title + "：已检测到登录，但同步失败：" + error.localizedDescription
                        }
                        loginSyncBusy = false
                    } else {
                        notice = platform.title + "：已检测到登录"
                    }
                } else {
                    notice = platform.title + "：登录未完成，未检测到有效会话"
                }
            }
        }) { platform in
            NavigationStack {
                if let url = platform.login {
                    PlatformWebLogin(url: url, platformID: platform.id) {
                        loginTarget = nil
                    }
                        .navigationTitle(platform.title + "登录")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("关闭") { loginTarget = nil }
                            }
                        }
                }
            }
        }
        .alert(
            "确认解除授权？",
            isPresented: Binding(get: { revokeTarget != nil }, set: { if !$0 { revokeTarget = nil } })
        ) {
            Button("解除授权", role: .destructive) {
                guard let platform = revokeTarget else { return }
                revokeTarget = nil
                Task {
                    if platform.id == "fengchao" { NativeFengchao.logout() }
                    else if platform.id == "mi" { NativeMiExpress.clearSession() }
                    else { await PlatformSession.clear(platform) }
                    await refresh()
                    notice = platform.title + "：登录数据已清除"
                }
            }
            Button("取消", role: .cancel) { revokeTarget = nil }
        } message: {
            Text("将清除设备内的网页登录会话。")
        }
        .alert("授权及同步状态",
               isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("确定") { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }

    private func row(_ platform: PlatformWebsite) -> some View {
        let authorized = isAuthorized(platform)
        return HStack(spacing: 14) {
            NavigationLink {
                destination(for: platform)
            } label: {
                HStack(spacing: 14) {
                    PlatformBrandMark(id: platform.id)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(platform.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(detailStatus(platform, authorized: authorized))
                            .font(.system(size: 12))
                            .foregroundStyle(authorized ? blue : .secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            Button {
                if authorized { revokeTarget = platform }
                else { authorize(platform) }
            } label: {
                Text(authorized ? "解除授权" : "授权")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(authorized ? Color(red: 0.95, green: 0.36, blue: 0.31) : .white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 35)
                    .background(
                        authorized ? Color.red.opacity(0.17) : blue,
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)

        }
        .padding(.horizontal, 19)
        .frame(minHeight: 72)
    }

    @ViewBuilder private func destination(for platform: PlatformWebsite) -> some View {
        switch platform.id {
        case "fengchao": FengchaoAccountPage()
        case "mi": XiaomiAccountPage()
        default: PlatformAccountDetail(platform: platform)
        }
    }
    private func authorize(_ platform: PlatformWebsite) {
        switch platform.id {
        case "fengchao": showFengchao = true
        case "mi": showXiaomi = true
        default:
            guard platform.login != nil else {
                notice = "此平台暂不支持在线授权"
                return
            }
            finishedLogin = platform
            loginTarget = platform
        }
    }
    private func isAuthorized(_ platform: PlatformWebsite) -> Bool {
        switch platform.id {
        case "fengchao": return NativeFengchao.hasSession
        case "mi": return NativeMiExpress.hasSession
        default: return authenticated.contains(platform.id)
        }
    }
    private func detailStatus(_ platform: PlatformWebsite, authorized: Bool) -> String {
        guard authorized else { return "未授权" }
        let date = UserDefaults.standard.double(forKey: "native.sync.success." + platform.id)
        if date > 0 {
            return "已授权 · 上次同步 " +
                Date(timeIntervalSince1970: date).formatted(date: .omitted, time: .shortened)
        }
        return "已授权"
    }
    private func refresh() async {
        refreshVersion += 1
        var values: Set<String> = []
        for platform in PlatformCatalog.rows where platform.login != nil {
            if await PlatformSession.isLoggedIn(platform) { values.insert(platform.id) }
        }
        authenticated = values
    }
    private func syncAll() {
        guard !isSyncing else { return }
        isSyncing = true
        Task {
            var reports: [String] = []
            var successes = 0
            for id in NativeParcelSync.platforms {
                guard let platform = PlatformCatalog.rows.first(where: { $0.id == id }),
                      isAuthorized(platform) else { continue }
                do {
                    let result = try await NativeParcelSync.run(id)
                    reports.append(result.description)
                    successes += 1
                } catch {
                    reports.append(platform.title + "：" + error.localizedDescription)
                }
            }
            if successes > 0 {
                lastGlobalSync = Date().timeIntervalSince1970
                UserDefaults.standard.set(lastGlobalSync, forKey: "native.account.lastSync")
            }
            for id in ["jd", "taobao", "pdd"] where authenticated.contains(id) {
                let queued = await NativeWebAutoSync.shared.request(id, force: true)
                if queued {
                    reports.append((id == "jd" ? "京东" : (id == "pdd" ? "拼多多" : "淘宝")) + "：已开始读取购物订单")
                }
            }
            if reports.isEmpty { reports.append("尚无可自动同步的已授权账号") }
            isSyncing = false
            notice = reports.joined(separator: "\n")
        }
    }
}

private struct PlatformAccountDetail: View {
    let platform: PlatformWebsite
    @State private var authorized = false
    @State private var loginPresented = false
    @State private var showRevokeConfirmation = false
    @State private var isSyncing = false
    @State private var webOrdersPresented = false
    @State private var pddOrdersPresented = false
    @State private var resultNotice: String?
    @State private var lastSync = 0.0
    @State private var lastError = ""
    @State private var pddMobiles: [NativeParcelSync.PddMobile] = []
    @State private var pddPhoneMessage = ""
    @State private var pddPhoneLoading = false
    @AppStorage("native.platform.enabled.taobao") private var tbEnabled = true
    @AppStorage("native.platform.enabled.cainiao") private var cnEnabled = true
    private let blue = Color(red: 0.19, green: 0.49, blue: 0.96)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                accountCard
                    .padding(.top, 26)
                if platform.id == "taobao" || platform.id == "cainiao" {
                    textHeader("数据来源")
                    card {
                        Toggle(isOn: $tbEnabled) {
                            Label("读取淘宝订单", systemImage: "bag")
                        }.tint(blue)
                        Divider()
                        Toggle(isOn: $cnEnabled) {
                            Label("读取菜鸟驿站取件码", systemImage: "shippingbox")
                        }.tint(blue)
                    }
                    Text("两个平台共用一次淘宝登录，但可以分别停用数据来源。")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.top, 10).padding(.horizontal, 15)
                }
                if platform.id == "pdd" {
                    textHeader("取件手机号")
                    card {
                        if pddPhoneLoading {
                            ProgressView("正在读取…")
                        } else if pddMobiles.isEmpty {
                            Text(authorized ? "未绑定手机号" : "请先授权拼多多")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(pddMobiles) { mobile in
                                HStack(spacing: 9) {
                                    Text(mobile.masked + (mobile.alias.isEmpty ? "" : "（" + mobile.alias + "）"))
                                    Spacer(minLength: 0)
                                    if mobile.commonlyUsed {
                                        Text("常用").font(.caption).foregroundStyle(blue)
                                    }
                                }
                                .font(.subheadline)
                                Divider()
                            }
                        }
                        if authorized {
                            Button {
                                Task { await loadPddMobiles() }
                            } label: {
                                Label("刷新绑定手机号", systemImage: "arrow.clockwise")
                            }.tint(blue).disabled(pddPhoneLoading)
                            Text("绑定、解绑及修改备注需要拼多多官方安全验证，当前仅支持读取列表。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if !pddPhoneMessage.isEmpty {
                            Text(pddPhoneMessage).font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                textHeader("同步")
                card {
                    HStack(spacing: 11) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 20)).foregroundStyle(blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("上次同步").font(.system(size: 16))
                            Text(syncStatusText)
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Button(isSyncing ? "同步中…" : "立即同步", action: syncNow)
                            .buttonStyle(.bordered)
                            .tint(blue)
                            .disabled(isSyncing || !authorized)
                    }
                    if (platform.id == "jd" || platform.id == "taobao") && authorized {
                        Divider()
                        Button {
                            webOrdersPresented = true
                        } label: {
                            Label("打开订单网页排查", systemImage: "globe")
                        }
                        .tint(blue)
                    }
                    if platform.id == "pdd" && authorized {
                        Divider()
                        Button {
                            pddOrdersPresented = true
                        } label: {
                            Label("读取拼多多购物订单", systemImage: "list.bullet.rectangle")
                        }
                        .tint(blue)
                    }
                }
                if !lastError.isEmpty {
                    Text(lastError)
                        .font(.caption).foregroundStyle(.orange)
                        .padding(.top, 8).padding(.horizontal, 15)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 110)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(platform.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh(); if platform.id == "pdd" && authorized { await loadPddMobiles() } }
        .onChange(of: tbEnabled) { _, _ in Task { await refresh() } }
        .onChange(of: cnEnabled) { _, _ in Task { await refresh() } }
        .sheet(isPresented: $loginPresented, onDismiss: {
            Task {
                // A cancelled login is not treated as success.
                if (platform.id == "taobao" || platform.id == "cainiao"),
                   await PlatformSession.hasRawTaobaoSession() {
                    PlatformSession.setEnabled(platform.id, true)
                }
                await refresh()
                if authorized {
                    switch platform.id {
                    case "taobao", "jd", "pdd":
                        let queued = await NativeWebAutoSync.shared.request(platform.id, force: true)
                        resultNotice = queued
                            ? platform.title + "：登录成功，已启动购物订单同步"
                            : platform.title + "：已登录，但当前网页会话未能用于自动同步"
                    case "cainiao":
                        isSyncing = true
                        do {
                            let summary = try await NativeParcelSync.run(platform.id, force: true)
                            resultNotice = platform.title + "：登录成功，" + summary.description
                        } catch {
                            resultNotice = platform.title + "：已检测到登录，但订单同步失败：" + error.localizedDescription
                        }
                        isSyncing = false
                        await refresh()
                    default:
                        resultNotice = platform.title + "：已检测到网页会话"
                    }
                } else {
                    resultNotice = platform.title + "：登录未完成，请重试"
                }
            }
        }) {
            NavigationStack {
                if let url = platform.login {
                    PlatformWebLogin(url: url, platformID: platform.id) {
                        loginPresented = false
                    }
                        .navigationTitle(platform.title + "登录")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("关闭") { loginPresented = false }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $webOrdersPresented) {
            NavigationStack {
                NativeWebOrderPage(platform: platform.id) { outcome in
                    webOrdersPresented = false
                    resultNotice = outcome
                    Task { await refresh() }
                }
            }
        }
        .sheet(isPresented: $pddOrdersPresented) {
            NavigationStack {
                PddOrderSyncPage { outcome in
                    pddOrdersPresented = false
                    resultNotice = outcome
                    Task { await refresh() }
                }
            }
        }
        .alert("解除 " + platform.title + " 授权？",
               isPresented: $showRevokeConfirmation) {
            Button("解除授权", role: .destructive) {
                Task {
                    await PlatformSession.clear(platform)
                    await refresh()
                    resultNotice = platform.title + "：已解除授权"
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除此平台在设备上的登录授权，之后需要重新登录才能同步。")
        }
        .alert("授权与同步结果",
               isPresented: Binding(get: { resultNotice != nil },
                                    set: { if !$0 { resultNotice = nil } })) {
            Button("确定") { resultNotice = nil }
        } message: {
            Text(resultNotice ?? "")
        }
    }

    private var accountCard: some View {
        card {
            HStack(spacing: 14) {
                PlatformBrandMark(id: platform.id)
                    .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(platform.title)
                        .font(.system(size: 17, weight: .semibold))
                    Text(authorized ? "已授权" : "未授权")
                        .font(.system(size: 13))
                        .foregroundStyle(authorized ? blue : .secondary)
                }
                Spacer(minLength: 4)
                Button {
                    if authorized { showRevokeConfirmation = true }
                    else { loginPresented = true }
                } label: {
                    Text(authorized ? "解除授权" : "授权")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(authorized ? Color.red : .white)
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .background(authorized ? Color.red.opacity(0.16) : blue,
                                    in: Capsule())
                }.buttonStyle(.plain)
            }
            .frame(minHeight: 69)
        }
    }

    private func textHeader(_ title: String) -> some View {
        Text(title).font(.system(size: 13)).foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.top, 27).padding(.bottom, 10)
    }
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(.horizontal, 18).padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
    private var syncStatusText: String {
        if isSyncing { return "正在读取平台数据…" }
        if lastSync > 0 {
            return Date(timeIntervalSince1970: lastSync)
                .formatted(date: .numeric, time: .shortened)
        }
        return "从未同步"
    }
    private func refresh() async {
        authorized = await PlatformSession.isLoggedIn(platform)
        lastSync = UserDefaults.standard.double(forKey: "native.sync.success." + platform.id)
        lastError = UserDefaults.standard.string(forKey: "native.sync.result." + platform.id) ?? ""
    }
    private func loadPddMobiles() async {
        guard authorized && !pddPhoneLoading else { return }
        pddPhoneLoading = true
        defer { pddPhoneLoading = false }
        do {
            pddMobiles = try await NativeParcelSync.pddBoundMobiles()
            pddPhoneMessage = ""
        } catch {
            pddPhoneMessage = "读取失败：" + error.localizedDescription
        }
    }
    private func syncNow() {
        guard authorized && !isSyncing else { return }
        if platform.id == "taobao" || platform.id == "jd" || platform.id == "pdd" {
            isSyncing = true
            Task {
                let queued = await NativeWebAutoSync.shared.request(platform.id, force: true)
                isSyncing = false
                resultNotice = queued
                    ? platform.title + "：已开始读取购物订单，请稍后查看列表"
                    : platform.title + "：当前账号未检测到有效网页登录会话"
            }
            return
        }
        guard NativeParcelSync.platforms.contains(platform.id) else {
            resultNotice = "该平台目前不支持自动同步"
            return
        }
        isSyncing = true
        Task {
            defer { isSyncing = false }
            do {
                let response = try await NativeParcelSync.run(platform.id, force: true)
                resultNotice = response.description
            } catch {
                resultNotice = "同步失败：" + error.localizedDescription
            }
            await refresh()
        }
    }
}

// Auto-finish only after a first-party login credential can be verified.
// A navigation event alone never counts as a successful login.
private struct PlatformWebLogin: UIViewRepresentable {
    let url: URL
    let platformID: String
    let onAuthenticated: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(platformID: platformID, onAuthenticated: onAuthenticated)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        context.coordinator.attach(to: view)
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.onAuthenticated = onAuthenticated
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.detach(from: uiView)
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
        let platformID: String
        var onAuthenticated: () -> Void
        private var completed = false
        private var verification: Task<Void, Never>?
        private var didLoadPage = false

        init(platformID: String, onAuthenticated: @escaping () -> Void) {
            self.platformID = platformID
            self.onAuthenticated = onAuthenticated
        }

        func attach(to view: WKWebView) {
            view.configuration.websiteDataStore.httpCookieStore.add(self)
        }

        func detach(from view: WKWebView) {
            verification?.cancel()
            view.configuration.websiteDataStore.httpCookieStore.remove(self)
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            if didLoadPage { scheduleVerification() }
        }

        // Keep login in ParcelHelper: merchant pages frequently offer custom
        // app schemes (pinduoduo://, taobao://, openapp.jdmobile://, etc.).
        // Never hand those URLs to UIApplication or the system browser.
        private func isWebNavigation(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased() else { return false }
            return scheme == "https" || scheme == "http" || scheme == "about"
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(isWebNavigation(url) ? .allow : .cancel)
        }

        // target=_blank / window.open: display web-based login or verification
        // in the same WebView rather than activating another app.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard navigationAction.targetFrame == nil,
                  let url = navigationAction.request.url,
                  isWebNavigation(url) else { return nil }
            webView.load(navigationAction.request)
            return nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didLoadPage = true
            if platformID == "pdd",
               let host = webView.url?.host,
               host == "yangkeduo.com" || host.hasSuffix(".yangkeduo.com") {
                webView.evaluateJavaScript(Self.pddTokenScript) { [weak self] value, _ in
                    guard let self else { return }
                    if let token = value as? String, !token.isEmpty {
                        Task { @MainActor in
                            PddSessionVault.save(token)
                            self.scheduleVerification()
                        }
                    } else {
                        self.scheduleVerification()
                    }
                }
            }
            scheduleVerification()
        }

        private func scheduleVerification() {
            guard !completed else { return }
            verification?.cancel()
            verification = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: 850_000_000) }
                catch { return }
                guard let self, !Task.isCancelled, !self.completed else { return }
                let ok: Bool
                if self.platformID == "taobao" || self.platformID == "cainiao" {
                    ok = await PlatformSession.hasRawTaobaoSession()
                } else if let p = PlatformCatalog.rows.first(where: { $0.id == self.platformID }) {
                    ok = await PlatformSession.isLoggedIn(p)
                } else {
                    ok = false
                }
                guard ok, !Task.isCancelled, !self.completed else { return }
                self.completed = true
                self.onAuthenticated()
            }
        }

        private static let pddTokenScript = #"""
        (function() {
          try {
            for(var j=0;j<localStorage.length;j++) {
              var k=localStorage.key(j),v=localStorage.getItem(k);
              if(/token|access/i.test(k)&&typeof v==='string'&&v.length>=8)return v;
            }
          }catch(e){}
          return '';
        })()
        """#
    }
}
