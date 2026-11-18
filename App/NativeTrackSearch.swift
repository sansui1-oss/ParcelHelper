import SwiftUI
import UIKit

// Port of the original Scripting ui/trackSearch.tsx search + recent history.
// The page does not manufacture a parcel from an unverified order number.
struct NativeTrackSearchPage: View {
    @EnvironmentObject private var store: ParcelStore
    @Environment(\.dismiss) private var dismiss
    @State private var mailNo = ""
    @State private var shipperCode = ""
    @State private var phoneTail = ""
    @State private var loading = false
    @State private var result: NativeTrackLookup?
    @State private var history: [String] = NativeTracking.history()
    @State private var errorNotice: String?
    @State private var manualAdd = false
    private let blue = Color(red:47/255,green:123/255,blue:246/255)

    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                HStack(spacing:10) {
                    Image(systemName:"magnifyingglass")
                        .font(.system(size:20)).foregroundStyle(.secondary)
                    TextField("搜索运单号",text:$mailNo)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { search() }
                    if !mailNo.isEmpty {
                        Button { mailNo = ""; result = nil } label: {
                            Image(systemName:"xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal,18).frame(height:52)
                .background(Color(uiColor:.tertiarySystemFill),in:Capsule())
                HStack(spacing:12) {
                    Picker("快递公司",selection:$shipperCode) {
                        ForEach(NativeTracking.shippers.indices,id:\.self) { index in
                            Text(NativeTracking.shippers[index].1).tag(NativeTracking.shippers[index].0)
                        }
                    }.tint(blue)
                    TextField("收件手机尾号（可选）",text:$phoneTail)
                        .keyboardType(.numberPad)
                        .onChange(of:phoneTail) { _, next in
                            phoneTail=String(next.filter(\.isNumber).prefix(4))
                        }
                        .multilineTextAlignment(.trailing)
                }
                .font(.subheadline)
                .padding(14)
                .background(Color(uiColor:.secondarySystemGroupedBackground),
                            in:RoundedRectangle(cornerRadius:19))
                Button(action:search) {
                    HStack {
                        Spacer()
                        if loading { ProgressView().tint(.white) }
                        else { Image(systemName:"magnifyingglass") }
                        Text(loading ? "正在查询物流…" : "查快递")
                        Spacer()
                    }
                    .font(.headline)
                    .frame(height:48)
                }
                .buttonStyle(.borderedProminent)
                .tint(blue)
                .disabled(loading || mailNo.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                if let result {
                    resultCard(result)
                } else if !history.isEmpty {
                    HStack {
                        Text("最近查询").font(.headline)
                        Spacer()
                        Button("清空") { NativeTracking.clearHistory();history=[] }
                            .font(.caption)
                    }.padding(.top,14)
                    ForEach(history,id:\.self) { number in
                        HStack {
                            Button {
                                mailNo=number
                                phoneTail=NativeTracking.phone(for:number)
                                search()
                            } label: {
                                HStack {
                                    Image(systemName:"clock.arrow.circlepath")
                                    Text(number).font(.system(.subheadline,design:.monospaced))
                                    Spacer()
                                    Image(systemName:"chevron.right")
                                }
                                .foregroundStyle(.primary)
                            }
                            Button {
                                NativeTracking.forget(number)
                                history=NativeTracking.history()
                            } label: {
                                Image(systemName:"xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(16)
                        .background(Color(uiColor:.secondarySystemGroupedBackground),
                                    in:RoundedRectangle(cornerRadius:16))
                    }
                }
                Button {
                    manualAdd = true
                } label: {
                    Label("无法查询？手动添加包裹",systemImage:"square.and.pencil")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top,15)
            }
            .padding(.horizontal,20)
            .padding(.top,16)
            .padding(.bottom,100)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(uiColor:.systemGroupedBackground))
        .navigationTitle("查快递")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement:.topBarLeading) {
                Button("取消") { dismiss() }
            }
        }
        .sheet(isPresented:$manualAdd) {
            NavigationStack {
                ParcelEditor(parcel:Parcel())
            }
        }
        .alert("查询结果",isPresented:Binding(
            get:{errorNotice != nil},set:{ if !$0 {errorNotice=nil} })) {
            Button("确定") {errorNotice=nil}
        } message: { Text(errorNotice ?? "") }
    }

    @ViewBuilder private func resultCard(_ r:NativeTrackLookup) -> some View {
        VStack(alignment:.leading,spacing:15) {
            HStack(spacing:11) {
                CourierBrandView(company:r.company,shipperCode:r.shipperCode,size:50)
                VStack(alignment:.leading,spacing:4) {
                    Text(r.company.isEmpty ? "物流包裹" : r.company)
                        .font(.headline)
                    Text(r.mailNo)
                        .font(.system(.caption,design:.monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string=r.mailNo
                } label: {
                    Image(systemName:"doc.on.doc").foregroundStyle(blue)
                }
            }
            if !r.latest.isEmpty {
                Text(r.latest).font(.subheadline).fixedSize(horizontal:false,vertical:true)
            }
            Text("数据来源："+r.provider)
                .font(.caption).foregroundStyle(.secondary)
            if !r.nodes.isEmpty {
                Divider()
                ForEach(Array(r.nodes.prefix(10).enumerated()),id:\.offset) { index,node in
                    HStack(alignment:.top,spacing:11) {
                        Circle().fill(index == 0 ? blue : Color.gray)
                            .frame(width:8,height:8).padding(.top,5)
                        VStack(alignment:.leading,spacing:5) {
                            Text(node.text).font(.subheadline)
                            if !node.time.isEmpty {
                                Text(node.time).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Button {
                save(r)
            } label: {
                Label("加入包裹",systemImage:"plus.circle.fill")
                    .frame(maxWidth:.infinity)
            }
            .buttonStyle(.borderedProminent).tint(blue)
        }
        .padding(18)
        .background(Color(uiColor:.secondarySystemGroupedBackground),
                    in:RoundedRectangle(cornerRadius:24))
    }
    private func search() {
        guard !loading else { return }
        let mail=mailNo.trimmingCharacters(in:.whitespacesAndNewlines)
        loading=true
        result=nil
        Task {
            defer { loading=false }
            do {
                result=try await NativeTracking.lookup(mail,shipperCode:shipperCode,phone:phoneTail)
                history=NativeTracking.history()
            } catch {
                errorNotice=error.localizedDescription
            }
        }
    }
    private func save(_ r:NativeTrackLookup) {
        guard !r.nodes.isEmpty || !r.latest.isEmpty else {
            errorNotice="没有取得有效物流数据，不能自动导入"
            return
        }
        var item=store.snapshot.parcels.first {
            ($0.mailNo ?? "").caseInsensitiveCompare(r.mailNo) == .orderedSame
        } ?? Parcel()
        item.mailNo=r.mailNo
        if !r.company.isEmpty { item.trackCompany=r.company }
        if !r.shipperCode.isEmpty { item.shipperCode=r.shipperCode }
        if !r.latest.isEmpty { item.trackLatest=r.latest }
        if !r.nodes.isEmpty { item.trackNodes=r.nodes }
        if !r.receiverCity.isEmpty { item.receiverCity=r.receiverCity }
        if !r.receiverAddress.isEmpty { item.receiverAddress=r.receiverAddress }
        item.trackUpdatedAt=Date().timeIntervalSince1970*1000
        // Manual lookup used to store only the track text and leave
        // status = 1, so a parcel whose latest node already said "已取件"
        // / "本人签收" / "已送达" kept showing "运输中" in the list.
        // Persist the derived state now: latestPickupConfirmed already
        // covers explicit pickup wording and direct delivery with no
        // code and no station, so a picked parcel is stored as done.
        if item.latestPickupConfirmed {
            item.status = 2
            if item.pickedAt == nil { item.pickedAt = Date().timeIntervalSince1970 * 1000 }
        } else if item.isPending, item.arrivedAt == nil {
            item.arrivedAt = Date().timeIntervalSince1970 * 1000
        }
        if item.source == nil {
            item.source="kdniao"
            item.srcApp=SourceApp(id:"kdniao",name:"快递鸟")
        }
        // Manual save: the user explicitly re-added this shipment, so a
        // previous manual delete must not let the next platform sync
        // suppress it again.
        store.removeDeletion(mail: r.mailNo, order: item.orderId ?? "")
        store.upsert(item)
        dismiss()
    }
}
