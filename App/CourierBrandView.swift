import SwiftUI
import UIKit

// Prefer packaged high-resolution carrier artwork. Missing logos use sharp
// SwiftUI text/SF Symbols instead of enlarging the tiny legacy sprite atlas.
struct CourierBrandView: View {
    let company: String
    let shipperCode: String
    var source: String? = nil
    var size: CGFloat = 52

    private var name: String { (company + " " + shipperCode).lowercased() }
    private func has(_ values: [String]) -> Bool { values.contains { name.contains($0) } }

    private var carrier: (label: String, color: Color, asset: String?) {
        if has(["中通", "zto"]) { return ("ZTO", .blue, "carrier_zto") }
        if has(["邮政", "ems", "yzpy"]) { return ("EMS", .green, "carrier_ems") }
        if has(["圆通", "yto"]) { return ("YTO", .purple, "carrier_yto") }
        if has(["极兔", "j&t", "jtexpress"]) { return ("J&T", .red, nil) }
        if has(["申通", "sto"]) { return ("申通", .orange, "carrier_sto") }
        if has(["百世", "best"]) { return ("BEST", .orange, nil) }
        if has(["德邦", "deppon", "dbwl"]) { return ("德邦", .blue, "carrier_debon") }
        if has(["京东", "jdl", "jd logistics"]) { return ("京东", .red, "brand_jd") }
        if has(["韵达", "yunda"]) { return ("韵达", Color(red: 0.96, green: 0.71, blue: 0.05), nil) }
        if has(["丰巢", "fcbox"]) { return ("丰巢", .yellow, "carrier_fengchao") }
        if has(["菜鸟", "cainiao"]) { return ("菜鸟", .blue, "carrier_cainiao") }
        if has(["顺丰", "sf express"]) || shipperCode.lowercased() == "sf" {
            return ("SF", .red, "carrier_sf")
        }
        if has(["dhl"]) { return ("DHL", .yellow, "carrier_dhl") }
        if has(["fedex"]) { return ("FedEx", .purple, "carrier_fedex") }
        if has(["ups"]) { return ("UPS", .brown, "carrier_ups") }
        if has(["闪送"]) { return ("闪送", .orange, nil) }
        return ("", .blue, nil)
    }

    private var sourceMark: (text: String, color: Color)? {
        guard let source else { return nil }
        if source == "jd" && carrier.asset == "brand_jd" { return nil }
        if source == "cainiao" && carrier.asset == "carrier_cainiao" { return nil }
        if source == "fengchao" && carrier.asset == "carrier_fengchao" { return nil }
        switch source {
        case "taobao": return ("淘", Color(red: 1.0, green: 0.35, blue: 0.04))
        case "jd": return ("京", Color(red: 0.86, green: 0.13, blue: 0.12))
        case "pdd": return ("拼", Color(red: 0.90, green: 0.10, blue: 0.13))
        case "cainiao": return ("菜", Color(red: 0.17, green: 0.48, blue: 0.95))
        case "fengchao": return ("丰", Color(red: 0.93, green: 0.58, blue: 0.06))
        case "mi": return ("米", Color(red: 1.0, green: 0.42, blue: 0.06))
        case "vip": return ("唯", Color(red: 0.85, green: 0.10, blue: 0.20))
        case "dewu": return ("得", .black)
        case "douyin": return ("抖", .black)
        case "kdniao": return ("快", .blue)
        default: return nil
        }
    }

    var body: some View {
        let mark = carrier
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let asset = mark.asset, UIImage(named: asset) != nil {
                    Image(asset)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .background(Color.white)
                } else {
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .fill(mark.color)
                        .overlay {
                            if mark.label.isEmpty {
                                Image(systemName: "shippingbox.fill")
                                    .font(.system(size: size * 0.46, weight: .semibold))
                                    .foregroundStyle(.white)
                            } else {
                                Text(mark.label)
                                    .font(.system(
                                        size: size * (mark.label.count > 4 ? 0.22 :
                                                      mark.label.count > 2 ? 0.30 : 0.36),
                                        weight: .heavy, design: .rounded
                                    ))
                                    .minimumScaleFactor(0.72)
                                    .lineLimit(1)
                                    .foregroundStyle(mark.label == "韵达" ? Color.black : Color.white)
                                    .padding(.horizontal, 2)
                            }
                        }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))

            if let badge = sourceMark {
                Text(badge.text)
                    .font(.system(size: size * 0.22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.34, height: size * 0.34)
                    .background(badge.color,
                                in: RoundedRectangle(cornerRadius: size * 0.10,
                                                     style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.10, style: .continuous)
                            .strokeBorder(Color(uiColor: .systemBackground), lineWidth: 1.5)
                    }
                    .offset(x: size * 0.09, y: size * 0.09)
            }
        }
        .frame(width: size + 4, height: size + 4)
        .accessibilityLabel(company.isEmpty ? "快递包裹" : company)
    }
}
