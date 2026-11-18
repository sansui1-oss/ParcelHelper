import SwiftUI
import UIKit
import MapKit

// Colors and card spacing follow theme.ts in the original Scripting project.
enum AppTheme {
    static func color(_ key: String) -> Color {
        switch key {
        case "green": return Color(red: 0.482, green: 0.714, blue: 0.38)
        case "orange": return Color(red: 0.941, green: 0.541, blue: 0.18)
        case "purple": return Color(red: 0.42, green: 0.36, blue: 0.82)
        default: return Color(red: 47/255, green: 123/255, blue: 246/255)
        }
    }
    static var accent: Color { color(UserDefaults.standard.string(forKey: "native.appearance.color") ?? "blue") }
}
private var accent: Color { AppTheme.accent }
private enum PH {
    static let page = Color(uiColor: UIColor { t in t.userInterfaceStyle == .dark ? .black : UIColor(red: 241/255, green: 241/255, blue: 245/255, alpha: 1) })
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let soft = Color(uiColor: .tertiarySystemGroupedBackground)
    static let orange = Color(red: 240/255, green: 138/255, blue: 46/255)
    static let green = Color(red: 52/255, green: 168/255, blue: 83/255)
    static var purple: Color { AppTheme.accent }
}
struct MainView: View {
    @AppStorage("native.appearance.color") private var themeColor = "blue"
    var body: some View {
        TabView {
            NavigationStack { PickupHome() }.tabItem { Label("取件", systemImage: "shippingbox.fill") }
            NavigationStack { ParcelsHome() }.tabItem { Label("包裹", systemImage: "shippingbox") }
            NavigationStack { StatsHome() }.tabItem { Label("统计", systemImage: "chart.bar.fill") }
            NavigationStack { SettingsHome() }.tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        .tint(AppTheme.color(themeColor))
        .id(themeColor)
        .background(alignment: .topLeading) {
            NativeWebAutoSyncHost()
        }
    }
}
struct BigHeading: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 35, weight: .bold)).tracking(-1)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4).padding(.bottom, 7)
    }
}
struct NumberCard: View {
    let label: String; let value: String; let icon: String; let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: icon).foregroundStyle(tint).font(.system(size: 20))
                Spacer()
            }
            Text(value).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).frame(height: 123)
        .background(PH.card, in: RoundedRectangle(cornerRadius: 22))
    }
}
struct PHCard<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View { content().background(PH.card, in: RoundedRectangle(cornerRadius: 22)) }
}
struct PHSectionHeader: View {
    let title: String; var count: Int? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).font(.system(size: 22, weight: .bold)).lineLimit(1)
            if let count { Text("(\(count))").font(.system(size: 16)).foregroundStyle(.tertiary) }
            Spacer(minLength: 0)
        }
    }
}

// Reusable, intentionally lightweight dashboard design language.
private struct DashboardHero: View {
    let eyebrow: String
    let value: String
    let unit: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(value)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(unit)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            Image(systemName: symbol)
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: 48, height: 48)
                .background(.white.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(
                    colors: [accent, Color(red: 0.15, green: 0.30, blue: 0.57)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
}

private struct DashboardSection: View {
    let title: String
    let subtitle: String?
    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 21, weight: .bold))
            Spacer()
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }
}

private struct DashboardEmpty: View {
    let title: String
    let subtitle: String
    let symbol: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(accent)
                .frame(width: 74, height: 74)
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 24))
            Text(title).font(.system(size: 17, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 36)
        .background(PH.card, in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct PickupParcelRow: View {
    let parcel: Parcel
    var body: some View {
        HStack(spacing: 12) {
            CourierBrandView(company: parcel.trackCompany ?? "",
                             shipperCode: parcel.shipperCode ?? "",
                             source: parcel.source ?? parcel.srcApp?.id, size: 44)
            VStack(alignment: .leading, spacing: 5) {
                Text(parcel.displayCode.isEmpty ? "待取件" : parcel.displayCode)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(parcel.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)

        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(PH.card, in: RoundedRectangle(cornerRadius: 20))
    }
}
struct ParcelCell: View {
    @EnvironmentObject private var store: ParcelStore
    let parcel: Parcel
    private var resolvedStation: String {
        store.snapshot.stations.first(where: { $0.id == parcel.courierStationUuid })?
            .courierStationName ?? parcel.stationText
    }
    private var statusColor: Color {
        parcel.isDone || parcel.isSigned ? PH.green : parcel.isPending ? PH.orange : accent
    }
    private var mainTitle: String {
        if parcel.isPending, !parcel.displayCode.isEmpty { return parcel.displayCode }
        if let name = parcel.userTitle, !name.isEmpty { return name }
        if let name = parcel.itemTitle, !name.isEmpty { return name }
        if parcel.isDone { return "已完成取件" }
        return parcel.title
    }
    private var status: String {
        parcel.displayStatus
    }
    var body: some View {
        HStack(spacing: 12) {
            CourierBrandView(company: parcel.trackCompany ?? "",
                             shipperCode: parcel.shipperCode ?? "",
                             source: parcel.source ?? parcel.srcApp?.id, size: 48)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(mainTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.80)
                    Spacer(minLength: 0)
                    Text(status)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(statusColor.opacity(0.12), in: Capsule())
                }
                if let company = parcel.trackCompany, !company.isEmpty {
                    Text(company)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let latest = parcel.trackLatest, !latest.isEmpty {
                    Text(latest).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(accent.opacity(0.78))
                    Text(resolvedStation)
                        .lineLimit(1)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PH.card, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
    }
}
private struct PickupGroup: Identifiable { let name: String; let items: [Parcel]; var id: String { name } }
struct PickupHome: View {
    @EnvironmentObject private var store: ParcelStore
    @State private var refreshing = false
    @State private var refreshNotice: String?
    @AppStorage("native.id.taobao.enabled") private var showTaobaoIdentity = true
    @AppStorage("native.id.cainiao.enabled") private var showCainiaoIdentity = true
    @AppStorage("native.id.pdd.enabled") private var showPddIdentity = true

    private var pending: [Parcel] {
        store.snapshot.parcels
            .filter { $0.type == "delivery" && $0.isPending }
            .sorted { ($0.arrivedAt ?? $0.createdAt) > ($1.arrivedAt ?? $1.createdAt) }
    }
    private var picked: [Parcel] {
        store.snapshot.parcels.filter { $0.type == "delivery" && $0.isDone }
    }
    private var monthPicked: Int {
        picked.filter {
            Calendar.current.isDate(
                Date(timeIntervalSince1970: ($0.pickedAt ?? $0.createdAt) / 1000),
                equalTo: Date(), toGranularity: .month)
        }.count
    }
    private var groups: [PickupGroup] {
        let grouped = Dictionary(grouping: pending) { parcel -> String in
            let text = [parcel.address, parcel.courierStationName, parcel.smsContent]
                .joined(separator: " ")
            if let linked = store.snapshot.stations.first(where: {
                $0.id == parcel.courierStationUuid
            }) {
                return linked.courierStationName
            }
            return StationMatcher.match(store.snapshot.stations, text: text)?
                .courierStationName ?? parcel.stationText
        }
        return grouped.map { PickupGroup(name: $0.key, items: $0.value) }
            .sorted { ($0.name == "其他驿站" ? 1 : 0, $0.name) <
                      ($1.name == "其他驿站" ? 1 : 0, $1.name) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("取件").font(.system(size: 32, weight: .bold))
                    Spacer()
                    Text(Date.now, format: .dateTime.month().day().weekday(.wide))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                DashboardHero(
                    eyebrow: "我的取件清单",
                    value: "\(pending.count)",
                    unit: "件待领取",
                    detail: pending.isEmpty ? "当前没有待取包裹，轻松的一天" :
                        "分布在 \(groups.count) 个取件点，记得及时取件",
                    symbol: "shippingbox.fill"
                )
                HStack(spacing: 10) {
                    statChip("本月已取", value: "\(monthPicked)", symbol: "checkmark.circle.fill", tint: PH.green)
                    statChip("累计已取", value: "\(picked.count)", symbol: "archivebox.fill", tint: accent)
                }

                if showTaobaoIdentity || showCainiaoIdentity || showPddIdentity {
                    VStack(alignment: .leading, spacing: 7) {
                        DashboardSection("身份码", subtitle: "到站后快速出示")
                        HStack(spacing: 10) {
                            if showTaobaoIdentity { identityButton("淘宝", platform: "taobao") }
                            if showCainiaoIdentity { identityButton("菜鸟", platform: "cainiao") }
                            if showPddIdentity { identityButton("拼多多", platform: "pdd") }
                            Spacer(minLength: 0)
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 23))
                                .foregroundStyle(accent.opacity(0.8))
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(PH.card, in: RoundedRectangle(cornerRadius: 19))
                    }
                }

                if pending.isEmpty {
                    DashboardEmpty(title: "包裹都取完啦", subtitle: "新包裹到站后会出现在这里",
                                   symbol: "checkmark.seal.fill")
                } else {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 11) {
                            DashboardSection(group.name, subtitle: "\(group.items.count) 件")
                            ForEach(group.items) { parcel in
                                NavigationLink {
                                    ParcelDetail(parcelID: parcel.uuid)
                                } label: {
                                    PickupParcelRow(parcel: parcel)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        UIPasteboard.general.string = parcel.displayCode
                                    } label: {
                                        Label("复制取件码", systemImage: "doc.on.doc")
                                    }
                                    .disabled(parcel.displayCode.isEmpty)
                                    Button {
                                        store.markDone(parcel.uuid, done: true)
                                        ParcelNotifications.cancel(parcel.uuid)
                                    } label: {
                                        Label("标记已取", systemImage: "checkmark.circle")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 15)
            .padding(.bottom, 110)
        }
        .background(PH.page)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await refreshAllAsync() } } label: {
                    if refreshing { ProgressView() }
                    else { Image(systemName: "arrow.clockwise") }
                }
                .accessibilityLabel("同步包裹")
                .disabled(refreshing)
            }
        }
        .refreshable { await refreshAllAsync() }
        .task { _ = await NativeHomeRefresh.refresh() }
        .alert("同步结果", isPresented: Binding(
            get: { refreshNotice != nil },
            set: { if !$0 { refreshNotice = nil } })) {
                Button("确定") { refreshNotice = nil }
            } message: {
                Text(refreshNotice ?? "")
            }
    }

    private func statChip(_ label: String, value: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 27, height: 27)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.system(size: 17, weight: .bold, design: .rounded))
                Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(PH.card, in: RoundedRectangle(cornerRadius: 17))
    }

    private func identityButton(_ name: String, platform: String) -> some View {
        NavigationLink {
            IdentityDetailPage(title: name, platform: platform)
        } label: {
            VStack(spacing: 5) {
                Image("brand_" + platform)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 39, height: 39)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                Text(name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 59)
        }
        .buttonStyle(.plain)
    }

    private func refreshAllAsync() async {
        guard !refreshing else { return }
        refreshing = true
        let result = await NativeHomeRefresh.refresh(force: true)
        refreshing = false
        refreshNotice = result.joined(separator: "\n")
    }
}
struct ParcelsHome: View {
    @EnvironmentObject private var store: ParcelStore
    @State private var filter = 0
    @State private var search = ""
    @State private var searchExpanded = false
    @FocusState private var searchFocused: Bool
    @State private var finding = false
    @State private var importing = false
    @State private var deleteTarget: Parcel?
    @State private var selectedParcel: Parcel?

    private var counts: [Int] {
        let rows = store.snapshot.parcels.filter { $0.type == "delivery" }
        return [rows.count, rows.filter(\.isTransit).count,
                rows.filter(\.isPending).count,
                rows.filter { $0.isDone || $0.isSigned }.count]
    }
    private var visible: [Parcel] {
        store.snapshot.parcels.filter { p in
            guard p.type == "delivery" else { return false }
            let state = filter == 0 || (filter == 1 && p.isTransit) ||
                (filter == 2 && p.isPending) ||
                (filter == 3 && (p.isDone || p.isSigned))
            let text = [p.title, p.displayCode, p.mailNo ?? "", p.stationText,
                        p.smsContent, p.trackLatest ?? "", p.trackCompany ?? ""]
                .joined(separator: " ")
            return state && (search.isEmpty || text.localizedCaseInsensitiveContains(search))
        }
        .sorted { (($0.isDone || $0.isSigned) ? 1 : 0, -$0.createdAt) <
                  (($1.isDone || $1.isSigned) ? 1 : 0, -$1.createdAt) }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        Text("包裹")
                            .font(.system(size: 32, weight: .bold))
                        Spacer()
                        Text("共 \(counts[0]) 件")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("物流总览")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.80))
                            Text("\(counts[1]) 件运输中")
                                .font(.system(size: 25, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("\(counts[2]) 件待取 · \(counts[3]) 件已完成")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.77))
                        }
                        Spacer()
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 33))
                            .foregroundStyle(.white.opacity(0.88))
                            .frame(width: 60, height: 60)
                            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 20))
                    }
                    .padding(20)
                    .background(LinearGradient(
                        colors: [accent, Color(red: 0.12, green: 0.26, blue: 0.50)],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 25))

                    if searchExpanded {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                            TextField("搜索取件码、商品、快递或驿站", text: $search)
                                .font(.system(size: 14))
                                .textInputAutocapitalization(.never)
                                .focused($searchFocused)
                                .submitLabel(.search)
                            if !search.isEmpty {
                                Button {
                                    search = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityLabel("清除搜索内容")
                            }
                        }
                        .padding(.horizontal, 15)
                        .frame(height: 47)
                        .background(PH.card, in: RoundedRectangle(cornerRadius: 16))
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    Picker("包裹状态", selection: $filter) {
                        Text("全部 \(counts[0])").tag(0)
                        Text("在途 \(counts[1])").tag(1)
                        Text("待取 \(counts[2])").tag(2)
                        Text("完成 \(counts[3])").tag(3)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.bottom, 8)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 5, trailing: 18))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if visible.isEmpty {
                DashboardEmpty(
                    title: search.isEmpty ? "还没有这类包裹" : "没有搜索结果",
                    subtitle: search.isEmpty ? "点击右上角加号，添加或查找包裹" : "试试取件码、运单号或驿站名称",
                    symbol: "shippingbox"
                )
                .listRowInsets(EdgeInsets(top: 20, leading: 18, bottom: 12, trailing: 18))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(visible) { p in
                    Button {
                        selectedParcel = p
                    } label: {
                        ParcelCell(parcel: p)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 5, leading: 18, bottom: 5, trailing: 18))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { deleteTarget = p } label: {
                            Label("删除", systemImage: "trash.fill")
                        }
                        .tint(.red)
                        Button {
                            store.markDone(p.uuid, done: !p.isDone)
                            if !p.isDone { ParcelNotifications.cancel(p.uuid) }
                        } label: {
                            Label(p.isDone ? "恢复" : "已取",
                                  systemImage: p.isDone ? "arrow.uturn.backward" : "checkmark")
                        }
                        .tint(accent)
                    }
                    .contextMenu {
                        Button(p.isDone ? "恢复待取" : "标记已取") {
                            store.markDone(p.uuid, done: !p.isDone)
                        }
                        Button("删除包裹", role: .destructive) { deleteTarget = p }
                    }
                }
            }
            Color.clear.frame(height: 65)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(PH.page)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        searchExpanded.toggle()
                        if !searchExpanded {
                            search = ""
                            searchFocused = false
                        }
                    }
                    if searchExpanded { searchFocused = true }
                } label: {
                    Image(systemName: searchExpanded ? "xmark" : "magnifyingglass")
                }
                .accessibilityLabel(searchExpanded ? "收起搜索" : "搜索包裹")
                Button { importing = true } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .accessibilityLabel("导入包裹")
                Button { finding = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加包裹")
            }
        }
        .refreshable { _ = await NativeHomeRefresh.refresh(force: true) }
        .sheet(isPresented: $finding) {
            NavigationStack { NativeTrackSearchPage() }
        }
        .sheet(isPresented: $importing) {
            NavigationStack { PlatformsHome() }
        }
        .navigationDestination(item: $selectedParcel) { target in
            ParcelDetail(parcelID: target.uuid)
        }
        .alert("删除包裹？", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("取消", role: .cancel) { deleteTarget = nil }
            Button("删除", role: .destructive) {
                guard let target = deleteTarget else { return }
                store.delete(target.uuid)
                ParcelNotifications.cancel(target.uuid)
                deleteTarget = nil
            }
        } message: {
            Text("删除后将无法恢复。")
        }
    }
}
struct ParcelEditor: View {
    @EnvironmentObject private var store: ParcelStore
    @Environment(\.dismiss) private var dismiss
    @State var parcel: Parcel
    @State private var sms = ""
    var body: some View {
        Form {
            Section("包裹信息") {
                TextField("商品 / 备注标题", text: Binding(get: { parcel.userTitle ?? "" }, set: { parcel.userTitle = $0 }))
                TextField("取件码", text: $parcel.code)
                TextField("运单号", text: Binding(get: { parcel.mailNo ?? "" }, set: { parcel.mailNo = $0 })).textInputAutocapitalization(.characters)
                TextField("快递公司", text: Binding(get: { parcel.trackCompany ?? "" }, set: { parcel.trackCompany = $0 }))
                TextField("驿站名称", text: $parcel.courierStationName)
                TextField("地址", text: $parcel.address)
                TextField("手机号", text: $parcel.phone).keyboardType(.phonePad)
                TextField("备注", text: $parcel.notes, axis: .vertical)
            }
            Section("短信识别 · 本机解析") {
                TextField("粘贴短信", text: $sms, axis: .vertical).lineLimit(3...6)
                Button("识别短信") {
                    let parsed = SMSParser.parse(sms)
                    if !parsed.code.isEmpty { parcel.code = parsed.code }
                    if !parsed.trackingNumber.isEmpty { parcel.mailNo = parsed.trackingNumber }
                    if !parsed.station.isEmpty { parcel.courierStationName = parsed.station }
                    if !parsed.address.isEmpty { parcel.address = parsed.address }
                    if !parsed.company.isEmpty { parcel.trackCompany = parsed.company }
                    parcel.smsContent = sms
                    if !parsed.code.isEmpty { parcel.arrivedAt = Date().timeIntervalSince1970 * 1000 }
                }
                Button("从剪贴板粘贴") { sms = UIPasteboard.general.string ?? "" }
            }
            Section("状态") { Toggle("已取件", isOn: Binding(get: { parcel.isDone }, set: { parcel.status = $0 ? 2 : 1; parcel.pickedByUser = $0 })) }
        }
        .navigationTitle("编辑包裹")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存") {
                store.upsert(parcel)
                if store.snapshot.preferences.reminderEnabled {
                    Task { await ParcelNotifications.schedule(parcel, afterHours: store.snapshot.preferences.reminderAfterHours) }
                }
                if store.snapshot.preferences.liveActivityEnabled { Task { await LiveActivityCoordinator.update(with: store.snapshot.parcels) } }
                dismiss()
            } }
        }
    }
}
// A geocoded destination pin, not a live parcel route.
private struct ParcelDestinationMap: View {
    let address: String
    @State private var position: MapCameraPosition = .automatic
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let coordinate {
                Map(position: $position) {
                    Marker("收货地", systemImage: "mappin.circle.fill", coordinate: coordinate)
                        .tint(.blue)
                }
                .mapControlVisibility(.hidden)
                .overlay(alignment: .bottomLeading) {
                    Label("收货地位置 · 非实时运输轨迹", systemImage: "location")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(.regularMaterial, in: Capsule())
                        .padding(12)
                }
            } else {
                ZStack {
                    Color(uiColor: .secondarySystemGroupedBackground)
                    VStack(spacing: 9) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 29))
                            .foregroundStyle(.secondary)
                        Text(isLoading ? "正在定位收货地…" : "暂时无法定位收货地")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(address)
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                }
            }
        }
        .task(id: address) {
            isLoading = true
            coordinate = nil
            defer { isLoading = false }
            guard let result = try? await CLGeocoder().geocodeAddressString(address),
                  let coordinate = result.first?.location?.coordinate else { return }
            self.coordinate = coordinate
            position = .region(MKCoordinateRegion(center: coordinate,
                              span: MKCoordinateSpan(latitudeDelta: 0.045, longitudeDelta: 0.045)))
        }
    }
}

struct ParcelDetail: View {
    @EnvironmentObject private var store: ParcelStore
    @Environment(\.dismiss) private var dismiss
    let parcelID: String
    @State private var edit = false
    @State private var isRefreshing = false
    @State private var detailError: String?
    @State private var deleteConfirm = false
    @State private var toast: String?
    private var parcel: Parcel? { store.snapshot.parcels.first { $0.uuid == parcelID } }
    private var calendar: Calendar { Calendar.current }

    var body: some View {
        Group {
            if let p = parcel {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let destination = [p.receiverAddress, p.receiverCity]
                            .compactMap({ $0 }).first(where: { !$0.isEmpty }) {
                            ParcelDestinationMap(address: destination)
                                .frame(height: 210)
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        courierHeader(p)
                        if isRefreshing { ProgressView("正在查询物流详情…").padding(.vertical,8) }
                        if let detailError { Text(detailError).font(.caption).foregroundStyle(.orange) }
                        HStack(spacing: 7) {
                            Image(systemName: p.isDone || p.isSigned ? "checkmark.seal.fill" :
                                      p.isPending ? "checkmark.circle.fill" : "shippingbox.fill")
                                .foregroundStyle(p.isDone || p.isSigned ? PH.green :
                                                    p.isPending ? PH.orange : accent)
                            Text(p.isDone ? "已完成取件" :
                                 p.isSigned ? "物流显示已签收" :
                                 p.isPending ? "包裹已到站" : "运输中")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .font(.subheadline)
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(PH.card, in: RoundedRectangle(cornerRadius: 18))
                        infoCard(p)
                        if let eta = p.eta, !eta.isEmpty {
                            HStack {
                                Image(systemName: "clock").foregroundStyle(accent)
                                Text("预计到达")
                                Spacer()
                                Text(eta).fontWeight(.semibold).foregroundStyle(accent)
                            }
                            .padding(17).background(PH.card, in: RoundedRectangle(cornerRadius: 20))
                        }
                        trackCard(p)
                        HStack(spacing: 9) {
                            detailAction(
                                label: p.isDone ? "恢复待取" : "标记已取",
                                icon: p.isDone ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill",
                                tint: accent
                            ) {
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    store.markDone(p.uuid, done: !p.isDone)
                                }
                                if !p.isDone { ParcelNotifications.cancel(p.uuid) }
                                showToast(p.isDone ? "已恢复待取" : "已标记为已取")
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            detailAction(
                                label: "复制取件码",
                                icon: "doc.on.doc.fill",
                                tint: accent,
                                disabled: p.displayCode.isEmpty
                            ) {
                                UIPasteboard.general.string = p.displayCode
                                showToast("取件码已复制")
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                            }
                            detailAction(
                                label: "删除包裹",
                                icon: "trash.fill",
                                tint: .red
                            ) {
                                deleteConfirm = true
                            }
                        }
                    }.padding(18).padding(.bottom, 24)
                }
                .background(PH.page)
                .overlay(alignment: .bottom) {
                    if let toast {
                        Label(toast, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(Color.primary.opacity(0.80), in: Capsule())
                            .padding(.bottom, 20)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                            .allowsHitTesting(false)
                    }
                }
                .navigationTitle("物流详情")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement:.topBarTrailing) {
                        Button { refreshDetail() } label:{Image(systemName:"arrow.clockwise")}
                            .disabled(isRefreshing || p.mailNo == nil)
                        Button("编辑") {edit=true}
                    }
                }
                .task(id:parcelID) {
                    guard let p=parcel, p.mailNo != nil,
                          p.trackNodes.isEmpty || p.trackUpdatedAt == nil else {return}
                    refreshDetail()
                }
                .sheet(isPresented: $edit) {
                    NavigationStack { ParcelEditor(parcel: p) }
                }
                .alert("删除包裹？", isPresented: $deleteConfirm) {
                    Button("取消", role: .cancel) { deleteConfirm = false }
                    Button("删除", role: .destructive) {
                        store.delete(p.uuid)
                        ParcelNotifications.cancel(p.uuid)
                        dismiss()
                    }
                } message: {
                    Text("删除后将无法恢复。")
                }
            } else {
                ContentUnavailableView("包裹不存在", systemImage: "shippingbox")
            }
        }
    }


    private func showToast(_ message: String) {
        withAnimation(.easeOut(duration: 0.18)) { toast = message }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_650_000_000)
            if toast == message {
                withAnimation(.easeIn(duration: 0.18)) { toast = nil }
            }
        }
    }

    private func detailAction(
        label: String, icon: String, tint: Color, disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 61)
            .background(tint.opacity(disabled ? 0.05 : 0.10),
                        in: RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    private func refreshDetail() {
        guard !isRefreshing, let p=parcel, let mail=p.mailNo, !mail.isEmpty else {return}
        isRefreshing=true
        detailError=nil
        Task {
            defer {isRefreshing=false}
            do {
                let latest=try await NativeTracking.lookup(mail,source:p.source,
                    shipperCode:p.shipperCode ?? "",phone:"")
                guard var current=store.snapshot.parcels.first(where:{$0.uuid == parcelID}) else {return}
                if !latest.nodes.isEmpty {current.trackNodes=latest.nodes}
                if !latest.latest.isEmpty {current.trackLatest=latest.latest}
                if !latest.company.isEmpty {current.trackCompany=latest.company}
                if !latest.shipperCode.isEmpty {current.shipperCode=latest.shipperCode}
                current.trackUpdatedAt=Date().timeIntervalSince1970*1000
                store.upsert(current)
            } catch {
                detailError=error.localizedDescription
            }
        }
    }

    private func courierHeader(_ p: Parcel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                CourierBrandView(company:p.trackCompany ?? "",
                    shipperCode:p.shipperCode ?? "",
                    source:p.source ?? p.srcApp?.id,size:57)
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.trackCompany ?? p.title)
                        .font(.system(size: 20, weight: .bold))
                        .lineLimit(2)
                    Text(p.displayStatus)
                        .font(.subheadline)
                        .foregroundStyle(p.isDone || p.isSigned ? PH.green : p.isPending ? PH.orange : accent)
                }
                Spacer(minLength: 0)
            }
            if let mail = p.mailNo, !mail.isEmpty {
                HStack(spacing: 8) {
                    Text(mail).font(.system(.subheadline, design: .rounded))
                        .textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = mail
                        showToast("运单号已复制")
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                            .labelStyle(.titleOnly)
                    }.font(.subheadline).foregroundStyle(accent)
                }
            }
            if let title = p.itemTitle, !title.isEmpty {
                Text(title).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
            }
        }.padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PH.card, in: RoundedRectangle(cornerRadius: 22))
    }
    private func infoCard(_ p: Parcel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("取件信息", systemImage: "shippingbox")
                .font(.headline)
            if p.isPending || !p.displayCode.isEmpty {
                HStack {
                    Text("取件码").foregroundStyle(.secondary)
                    Spacer()
                    Text(p.displayCode.isEmpty ? "暂无取件码" : p.displayCode)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                }
            }
            HStack(alignment: .top) {
                Text("驿站").foregroundStyle(.secondary)
                Spacer()
                Text(store.snapshot.stations.first(where: { $0.id == p.courierStationUuid })?
                     .courierStationName ?? p.stationText)
                    .multilineTextAlignment(.trailing)
            }
            if let city = p.receiverCity, !city.isEmpty {
                HStack {
                    Text("收货地").foregroundStyle(.secondary)
                    Spacer()
                    Text(city)
                }
            }
        }
        .font(.subheadline)
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(PH.card, in: RoundedRectangle(cornerRadius: 22))
    }
    private func routeCard(_ p: Parcel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("物流路线", systemImage: "map").font(.headline)
            if let origin = p.address.isEmpty ? nil : p.address,
               let destination = p.receiverCity ?? p.receiverAddress, !destination.isEmpty {
                HStack(spacing: 8) {
                    Text(origin).lineLimit(2)
                    Image(systemName: "arrow.right").foregroundStyle(accent)
                    Text(destination).lineLimit(2)
                }.font(.subheadline)
            } else {
                Text("暂未获取可用的运输地点")
                    .foregroundStyle(.secondary).font(.subheadline)
            }
            if let latest = p.trackLatest, !latest.isEmpty {
                Text(latest).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(PH.card, in: RoundedRectangle(cornerRadius: 22))
    }
    private func trackCard(_ p: Parcel) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("物流轨迹", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.headline)
            if p.trackNodes.isEmpty {
                Text(p.trackLatest ?? "暂无物流轨迹")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(p.trackNodes.enumerated()), id: \.offset) { index, node in
                        HStack(alignment: .top, spacing: 13) {
                            Circle()
                                .fill(index == 0 ? accent : Color.secondary.opacity(0.6))
                                .frame(width: 10, height: 10)
                                .frame(width: 14, height: 14)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(node.text)
                                    .font(.system(size: 14))
                                    .foregroundStyle(index == 0 ? Color.primary : Color.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if !node.time.isEmpty {
                                    Text(node.time)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.bottom, index == p.trackNodes.count - 1 ? 0 : 21)
                        .background(alignment: .topLeading) {
                            if index < p.trackNodes.count - 1 {
                                GeometryReader { geometry in
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.24))
                                        .frame(width: 2, height: geometry.size.height)
                                        .offset(x: 6, y: 11)
                                }
                            }
                        }
                    }
                }
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(PH.card, in: RoundedRectangle(cornerRadius: 22))
    }
}
struct StatsHome: View {
    @EnvironmentObject private var store: ParcelStore

    private var parcels: [Parcel] { store.snapshot.parcels.filter { $0.type == "delivery" } }
    private var picked: [Parcel] { parcels.filter(\.isDone) }
    private var pending: Int { parcels.filter(\.isPending).count }
    private var monthCount: Int {
        picked.filter {
            Calendar.current.isDate(
                Date(timeIntervalSince1970: ($0.pickedAt ?? $0.createdAt) / 1000),
                equalTo: Date(), toGranularity: .month)
        }.count
    }
    private var monthAverage: String {
        let calendar = Calendar.current
        guard let oldest = picked.map({
            Date(timeIntervalSince1970: ($0.pickedAt ?? $0.createdAt) / 1000)
        }).min() else { return "0.0" }
        let first = calendar.date(from: calendar.dateComponents([.year, .month],
                                                              from: oldest)) ?? oldest
        let latest = calendar.date(from: calendar.dateComponents([.year, .month],
                                                               from: Date())) ?? Date()
        let monthSpan = (calendar.dateComponents([.month], from: first,
                                                 to: latest).month ?? 0) + 1
        return String(format: "%.1f", Double(picked.count) / Double(max(1, monthSpan)))
    }
    private var ranking: [(String, Int)] {
        Dictionary(grouping: picked) { p in
            store.snapshot.stations.first(where: { $0.id == p.courierStationUuid })?
                .courierStationName ?? p.stationText
        }
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
            .prefix(3).map { $0 }
    }
    private var months: [(String, Int)] {
        let cal = Calendar.current
        return (0..<5).reversed().compactMap { offset -> (String, Int)? in
            guard let d = cal.date(byAdding: .month, value: -offset, to: Date()) else { return nil }
            let count = picked.filter {
                cal.isDate(Date(timeIntervalSince1970: ($0.pickedAt ?? $0.createdAt) / 1000), equalTo: d, toGranularity: .month)
            }.count
            return ("\(cal.component(.month, from: d))月", count)
        }
    }
    // Estimate the average *clock time of arrival*, not elapsed delivery duration.
    // Only timestamped last-mile arrival events count. "codeTime" is pickup
    // code metadata and is not a trustworthy logistics arrival timestamp.
    private var arrivalSamples: [Int] {
        parcels.compactMap { parcel -> Int? in
            let matching = parcel.trackNodes.filter { node in
                let text = node.text
                let arrivals = ["已到达", "已到站", "已入库", "入库成功", "已入柜",
                                "已放入", "已存放", "已暂存", "代收点", "驿站签收",
                                "派送至", "已投递", "送达驿站", "已代收", "已送达"]
                let exclusions = ["预计", "即将", "将于", "转运中心", "分拨中心",
                                  "集散中心", "运转中心", "揽收", "已取走", "已领取",
                                  "本人签收", "运输中", "派送中", "正在派送"]
                return arrivals.contains(where: { text.contains($0) }) &&
                       !exclusions.contains(where: { text.contains($0) })
            }
            // Most carriers return newest -> oldest; retain the earliest
            // matching arrival for each parcel, never double-count its updates.
            return matching.reversed().compactMap { clockMinute(from: $0.time) }.first
        }
    }
    private func clockMinute(from raw: String) -> Int? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        // Some logistics backends return Unix timestamps rather than text.
        if let epoch = Double(text), epoch > 1_000_000_000 {
            let seconds = epoch > 1_000_000_000_000 ? epoch / 1000 : epoch
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
            let parts = calendar.dateComponents([.hour, .minute],
                from: Date(timeIntervalSince1970: seconds))
            if let hour = parts.hour, let minute = parts.minute {
                return hour * 60 + minute
            }
        }
        // Accept 2026-11-16 17:41:53, 2026/11/16 17:41 or ISO 8601
        // but never dates without a time of day.
        guard let expression = try? NSRegularExpression(
            pattern: #"(?<!\d)([01]?\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?(?!\d)"#),
              let match = expression.firstMatch(in: text, range:
                NSRange(text.startIndex..., in: text)),
              let hoursRange = Range(match.range(at: 1), in: text),
              let minutesRange = Range(match.range(at: 2), in: text),
              let hour = Int(text[hoursRange]), let minute = Int(text[minutesRange])
        else { return nil }
        return hour * 60 + minute
    }
    private var averageArrivalMinute: Int? {
        let values = arrivalSamples
        guard !values.isEmpty else { return nil }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .firstTextBaseline) {
                    Text("统计")
                        .font(.system(size: 32, weight: .bold))
                    Spacer()
                    Text("取件报告")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 9),
                    GridItem(.flexible(), spacing: 9)
                ], spacing: 9) {
                    metricTile("累计取件", value: "\(picked.count)",
                               symbol: "checkmark.circle.fill", color: accent)
                    metricTile("本月取件", value: "\(monthCount)",
                               symbol: "calendar", color: PH.orange)
                    metricTile("当前待取", value: "\(pending)",
                               symbol: "clock.badge.checkmark", color: PH.green)
                    metricTile("月均取件", value: monthAverage,
                               symbol: "chart.line.uptrend.xyaxis", color: accent)
                }

                DashboardSection("取件趋势", subtitle: "最近 5 个月")
                trendPanel

                DashboardSection("常用驿站", subtitle: "按已取件数量")
                rankingPanel

                DashboardSection("平均到站时间", subtitle: "基于真实物流轨迹")
                arrivalPanel
            }
            .padding(.horizontal, 18)
            .padding(.top, 15)
            .padding(.bottom, 118)
        }
        .background(PH.page)
    }

    private func metricTile(
        _ title: String, value: String, symbol: String, color: Color
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(PH.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var trendPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("每月完成件数")
                        .font(.system(size: 14, weight: .semibold))
                    Text("按标记已取时间统计")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text("\(months.reduce(0) { $0 + $1.1 }) 件")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
            }
            let ceiling = max(1, months.map { $0.1 }.max() ?? 0)
            HStack(alignment: .bottom, spacing: 14) {
                ForEach(Array(months.enumerated()), id: \.offset) { _, month in
                    VStack(spacing: 6) {
                        Text("\(month.1)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(height: 16)
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LinearGradient(
                                colors: month.1 == 0 ?
                                    [accent.opacity(0.13), accent.opacity(0.13)] :
                                    [accent, accent.opacity(0.55)],
                                startPoint: .top, endPoint: .bottom))
                            .frame(height: CGFloat(max(8, month.1 * 80 / ceiling)))
                            .frame(height: 84, alignment: .bottom)
                        Text(month.0)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(height: 17)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 129, alignment: .bottom)
        }
        .padding(18)
        .background(PH.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private var rankingPanel: some View {
        VStack(spacing: 12) {
            if ranking.isEmpty {
                DashboardEmpty(
                    title: "还没有驿站排行",
                    subtitle: "完成取件后这里会自动统计常用驿站",
                    symbol: "mappin.and.ellipse"
                )
            } else {
                ForEach(Array(ranking.enumerated()), id: \.offset) { rank, item in
                    HStack(spacing: 12) {
                        Text("\(rank + 1)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(rank == 0 ? accent : .secondary)
                            .frame(width: 32, height: 32)
                            .background(accent.opacity(rank == 0 ? 0.13 : 0.06),
                                        in: RoundedRectangle(cornerRadius: 10))
                        Text(item.0)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text("\(item.1) 件")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    if rank != ranking.count - 1 { Divider().opacity(0.5) }
                }
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PH.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private var arrivalPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let minutes = averageArrivalMinute {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "%02d:%02d", minutes / 60, minutes % 60))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Spacer()
                    Text("\(arrivalSamples.count) 件有效记录")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(accent)
                                .frame(width: geo.size.width * CGFloat(
                                    max(0, min(14 * 60, minutes - 8 * 60))) /
                                       CGFloat(14 * 60))
                        }
                }
                .frame(height: 8)
                HStack {
                    Text("08:00")
                    Spacer()
                    Text("15:00")
                    Spacer()
                    Text("22:00")
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                Text("取物流记录中首次有效的到站时间计算平均值，不使用取件码生成时间。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 25))
                        .foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("暂无有效到站时间")
                            .font(.system(size: 15, weight: .semibold))
                        Text("需要真实物流轨迹中的到站或入库时间才能计算。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PH.card, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct SettingsHome: View {
    @EnvironmentObject private var store: ParcelStore
    @State private var githubVersion: String?
    private var nickname: String {
        let value = store.snapshot.preferences.nickName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "包裹助手" : value
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BigHeading(text: "设置")
                NavigationLink { ProfileSettingsPage() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: UserDefaults.standard.string(forKey: "native.profile.avatar") ?? "person.crop.circle.fill")
                            .font(.system(size: 52)).foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(nickname).font(.system(size: 17, weight: .semibold)).foregroundStyle(.primary)
                            Text("尚未授权平台 · 本地数据").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }.padding(16)
                        .background(PH.card, in: RoundedRectangle(cornerRadius: 22))
                }.buttonStyle(.plain)
                settingsGroup {
                    nativeRow("账号授权", "checkmark.shield.fill", PH.orange) { PlatformAccountsPage() }
                }
                settingsGroup {
                    nativeRow("快捷指令与自动化", "bolt.fill", PH.orange) { ShortcutsSettingsPage() }
                    Divider().padding(.leading, 58)
                    nativeRow("驿站管理", "building.2.fill", .cyan) { StationsHome() }
                    Divider().padding(.leading, 58)
                    nativeRow("身份码", "qrcode", .blue) { IdentitySettingsPage() }
                    Divider().padding(.leading, 58)
                    nativeRow("取件提醒", "bell.fill", .blue) { ReminderSettingsPage() }
                }
                settingsGroup {
                    nativeRow("外观与显示", "circle.lefthalf.filled", .purple) { AppearanceSettingsPage() }
                    Divider().padding(.leading, 58)
                    nativeRow("实时活动（灵动岛）", "iphone.gen3", .blue) { LiveSettingsPage() }
                    Divider().padding(.leading, 58)
                    nativeRow("刷新频率", "arrow.triangle.2.circlepath", .red) { RefreshSettingsPage() }
                }
                settingsGroup {
                    nativeRow("常见问题", "questionmark.circle.fill", .blue) { FAQSettingsPage() }
                    Divider().padding(.leading, 58)
                    nativeRow("清除缓存", "trash.fill", .gray) { CacheSettingsPage() }
                }
                Text("版本 \(githubVersion ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"))")
                    .font(.system(size: 12)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity).padding(.top, 27)
            }.padding(.horizontal, 20).padding(.bottom, 130)
        }
        .background(PH.page)
        .task {
            githubVersion = await GitHubReleaseVersion.latest() 
        }
    }
    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(PH.card, in: RoundedRectangle(cornerRadius: 22))
            .padding(.top, 26)
    }
    private func settingsLabel(_ title: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white).frame(width: 30, height: 30)
                .background(color, in: RoundedRectangle(cornerRadius: 9))
            Text(title).font(.system(size: 15)).foregroundStyle(.primary)
            Spacer(minLength: 5)
            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(.tertiary)
        }.padding(.horizontal, 16).frame(minHeight: 49)
            .contentShape(Rectangle())
    }
    private func nativeRow<Destination: View>(_ title: String, _ icon: String, _ color: Color, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination) { settingsLabel(title, icon, color) }.buttonStyle(.plain)
    }
}
struct StationsHome: View {
    @EnvironmentObject private var store: ParcelStore
    @State private var creating = false
    var body: some View {
        List {
            if store.snapshot.stations.isEmpty {
                Text("还没有驿站记录，有包裹到站后会自动建档，也可以点右上角加号手动添加。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(store.snapshot.stations) { s in NavigationLink { StationEditor(station: s) } label: {
            VStack(alignment: .leading) { Text(s.courierStationName).bold(); Text(s.address).font(.caption).foregroundStyle(.secondary) }
        } }.onDelete { offsets in for i in offsets { store.removeStation(store.snapshot.stations[i].id) } } }
        .navigationTitle("驿站管理")
        .onAppear { store.persist() }
        .toolbar { Button { creating = true } label: { Image(systemName: "plus") } }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Text("根据物流中明确的驿站名称自动建档；信息不准确时可点开修改。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)
        }
        .sheet(isPresented: $creating) { NavigationStack { StationEditor(station: Station()) } }
    }
}
struct StationEditor: View {
    @EnvironmentObject private var store: ParcelStore
    @Environment(\.dismiss) private var dismiss
    @State var station: Station
    @State private var keywordText = ""
    @State private var errorMessage = ""
    private var name: String { station.courierStationName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var address: String { station.address.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var phone: String { station.phone.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        Form {
            Section("驿站信息") {
                TextField("驿站名称（必填）", text: $station.courierStationName)
                    .textInputAutocapitalization(.never)
                TextField("详细地址（可补全）", text: $station.address)
                TextField("联系电话", text: $station.phone)
                    .keyboardType(.phonePad)
                TextField("营业时间", text: $station.businessHours)
            }
            Section("匹配规则") {
                Text("自动识别的驿站可能没有完整地址。请核对名称与位置；修改后不会被物流同步覆盖。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("关键词（逗号分隔）", text: $keywordText)
                TextField("备注", text: $station.notes)
            }
        }
        .navigationTitle("编辑驿站")
        .onAppear { keywordText = station.keywords.joined(separator: ",") }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }.disabled(name.isEmpty)
            }
        }
        .alert("无法保存驿站", isPresented: Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } })) {
            Button("确定", role: .cancel) { errorMessage = "" }
        } message: { Text(errorMessage) }
    }
    private func save() {
        guard !name.isEmpty else { errorMessage = "请填写驿站名称"; return }
        let digits = phone.filter(\.isNumber)
        if !phone.isEmpty && (digits.count < 7 || digits.count > 15 || phone.range(of: "^[+0-9()\\- ]+$", options: .regularExpression) == nil) {
            errorMessage = "请输入有效的联系电话"; return
        }
        let keys = keywordText.components(separatedBy: CharacterSet(charactersIn: ",，"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !keys.contains(where: { $0.count > 50 }) else { errorMessage = "单个匹配关键词不能超过 50 字"; return }
        let duplicate = store.snapshot.stations.contains {
            $0.id != station.id && $0.courierStationName.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(name) == .orderedSame && $0.address.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(address) == .orderedSame
        }
        guard !duplicate else { errorMessage = "相同名称和地址的驿站已存在"; return }
        station.courierStationName = name
        station.address = address
        station.phone = phone
        station.keywords = Array(Set(keys)).sorted()
        store.upsertStation(station)
        dismiss()
    }
}
struct PlatformsHome: View {
    private let platforms: [(String, String, String)] = [
        ("淘宝", "taobao", "bag"),
        ("京东", "jd", "shippingbox"),
        ("拼多多", "pdd", "cart"),
        ("抖音商城", "douyin", "play.rectangle"),
        ("菜鸟", "cainiao", "shippingbox.fill"),
        ("丰巢", "fengchao", "square.grid.2x2"),
        ("小米", "xiaomi", "cube.box")
    ]
    var body: some View {
        List {
            Section {
                Label("抖音提供打开官网、返回自动识别剪贴板的快速导入；其他平台可手动粘贴物流文字。自动读取完整订单需要对应平台开放授权。", systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section("物流导入") {
                ForEach(platforms, id: \.1) { item in
                    NavigationLink {
                        if item.1 == "douyin" {
                            DouyinImportView()
                        } else {
                            PlatformImportView(platformName: item.0, platformID: item.1)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.2).frame(width: 28).foregroundStyle(accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.0)
                                Text("粘贴物流详情 · 识别运单/取件码")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            Section("授权状态") {
                Label("普通网页版登录不等于订单 API 授权", systemImage: "lock.shield")
                    .foregroundStyle(.secondary)
                Text("不会请求账号密码，也不会把账号 Cookie 上传到第三方服务器。官方接口获得授权后，才能增加自动订单同步。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("平台导入")
    }
}
struct CourierSettings: View {
    @State private var businessID = NativeTracking.get("businessID")
    @State private var key = NativeTracking.get("apiKey")
    @State private var configured = NativeTracking.isConfigured
    @State private var notice: String?
    var body: some View {
        Form {
            Section("快递鸟 API · 物流查单") {
                TextField("EBusinessID",text:$businessID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("API Key",text:$key)
                Button("保存 API 配置") {
                    do {
                        try NativeTracking.setCredential(businessID:businessID,apiKey:key)
                        configured=true
                        notice="密钥已安全保存到设备钥匙串"
                    } catch {notice=error.localizedDescription}
                }
                Button("清除 API 配置",role:.destructive) {
                    NativeTracking.clearCredential()
                    businessID="";key="";configured=false
                    notice="API 配置已清除"
                }.disabled(!configured)
            }
            Section("状态") {
                LabeledContent("查询服务",value:configured ? "已配置" : "尚未配置")
                Text("查快递优先复用已授权平台的物流数据；必要时调用你自己的快递鸟查询接口。部分运单可能要求收件手机尾号。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("物流服务")
        .alert("快递鸟",isPresented:Binding(get:{notice != nil},set:{if !$0 {notice=nil}})) {
            Button("确定") {notice=nil}
        } message:{Text(notice ?? "")}
    }
}
