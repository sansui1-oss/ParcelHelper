import Foundation
@main struct Tests {
  static func main() {
    let samples = [
        ("抖音商城\n商品名称：保温杯\n物流公司：中通快递\n运单号：78451234567890\n最新物流：快件运输中\n订单号：987654321", "78451234567890", "中通快递", ""),
        ("抖音物流详情\n快递公司：极兔速递\n物流单号：JT1234567890123\n取件码：8-1234\n取件地点：菜鸟驿站幸福路店", "JT1234567890123", "极兔速递", "8-1234"),
        ("订单号：123456789123456789\n收件人手机号：13812345678", "", "", "")
    ]
    for (text, no, company, code) in samples {
       let p = DouyinTextParser.parse(text)
       precondition(p.trackingNumber == no, "tracking number failure: \(p.trackingNumber)")
       precondition(p.company == company, "company failure: \(p.company)")
       precondition(p.pickupCode == code, "code failure: \(p.pickupCode)")
    }
    print("PASS 3 Douyin parser tests")
    ParcelStatusTests.runAll()
    MiErrorTests.runAll()
    DedupeTests.runAll()
    NeedsClaimTests.runAll()
    LooseOrderTests.runAll()
  }
}
