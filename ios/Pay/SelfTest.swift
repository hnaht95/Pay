#if DEBUG
import CloudKit
import Foundation

/// Bộ kiểm tra logic chạy ngay trong app (chỉ bản Debug): "-selfTest YES" khi mở app trên máy ảo. Dùng đúng Store, CSVImport,
/// Settle của app trên dữ liệu thật của máy ảo (xoá sạch trước khi chạy). Kết quả ghi ra Documents/selftest.txt và log.
@MainActor
enum SelfTest {
    private static var out: [String] = []
    private static var failed = 0

    private static func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        if !ok { failed += 1 }
        out.append((ok ? "✓ " : "✗ ") + name + (ok ? "" : "  — " + detail()))
    }

    static func runIfAsked(store: Store) {
        guard UserDefaults.standard.bool(forKey: "selfTest") else { return }
        out = []; failed = 0
        store.eraseAll()

        // MARK: Đoán chi / thu
        let notIncome = ["trả lương giúp việc", "lì xì cho cháu", "gift for mom", "pay loan interest", "đóng tiền lương hưu cho mẹ"]
        for s in notIncome { check("chi, không phải thu: \(s)", !Category.isIncome(store.guessEntry(s)), store.guessEntry(s)) }
        let income = ["nhận lương", "lương tháng 10", "được chuyển", "tiền thưởng tết", "hoàn tiền"]
        for s in income { check("khoản thu: \(s)", Category.isIncome(store.guessEntry(s)), store.guessEntry(s)) }
        check("giao dịch thẻ luôn là chi: Phở Lương Sơn", !Category.isIncome(store.guessCategory("Phở Lương Sơn")))

        // Dán số tài khoản (màn quét › Dán STK): ngân hàng, số tài khoản, số tiền
        let pastes: [(String, String?, String, Int?)] = [
            ("MB 0123456789 200k", "970422", "0123456789", 200_000),
            ("STK 1903 4567 8901 Techcombank NGUYEN VAN A", "970407", "190345678901", nil),
            ("vcb 1012345678 - 1.500.000", "970436", "1012345678", 1_500_000),
            ("Vietinbank: 107-8765-4321, 350k tiền ăn", "970415", "10787654321", 350_000),
            ("MB Bank 9999888877", "970422", "9999888877", nil),
            ("0987654321 1tr2", nil, "0987654321", 1_200_000),
        ]
        for (t, bin, acct, amt) in pastes {
            let q = VietQR.fromText(t)
            check("dán STK: \(t)", q?.bin == bin && q?.acct == acct && q?.amount == amt,
                  "\(q?.bin ?? "nil") \(q?.acct ?? "nil") \(q?.amount.map(String.init) ?? "nil")")
        }
        check("dán chữ không có STK → nil", VietQR.fromText("ăn trưa 35k") == nil)
        // Học danh mục cho đúng câu
        store.learnCategory("trả lương giúp việc", "hd")
        check("đã học: trả lương giúp việc → hd", store.guessEntry("trả lương giúp việc") == "hd", store.guessEntry("trả lương giúp việc"))
        store.learnCategory("mẹ cho", "in-nhan")
        check("đã học: mẹ cho → in-nhan", store.guessEntry("mẹ cho") == "in-nhan", store.guessEntry("mẹ cho"))

        // MARK: Số dư, thẻ tín dụng
        check("chưa đặt số dư thì nil", store.balance == nil)
        store.setBalance(1_000_000)
        check("đặt số dư 1.000.000", store.balance == 1_000_000, "\(store.balance ?? -1)")
        store.add(amount: 100_000, note: "an trua", cat: "an", toast: false)
        check("chi 100k → 900k", store.balance == 900_000, "\(store.balance ?? -1)")
        store.add(amount: 200_000, note: "uniqlo", cat: "mua", credit: true, toast: false)
        check("quẹt thẻ 200k: số dư giữ 900k", store.balance == 900_000, "\(store.balance ?? -1)")
        check("chi tiêu thẻ 200k", store.cardDebt == 200_000, "\(store.cardDebt)")
        check("quẹt thẻ vẫn là chi tiêu tháng", store.monthItems(Date()).contains { $0.isCredit && $0.a == 200_000 })
        store.payCard(300_000)
        check("trả thẻ 300k: chi tiêu thẻ về 0", store.cardDebt == 0, "\(store.cardDebt)")
        check("trả thẻ 300k: số dư 600k", store.balance == 600_000, "\(store.balance ?? -1)")
        check("trả thẻ không tính là chi", !store.items.contains { $0.isCardPay })
        store.add(amount: 50_000, note: "grab", cat: "di", credit: true, toast: false)
        check("trả dư không bù cho lần quẹt sau: chi tiêu thẻ 50k", store.cardDebt == 50_000, "\(store.cardDebt)")
        store.add(amount: 5_000_000, note: "nhận lương", cat: "in-luong", toast: false)
        check("khoản thu cộng số dư: 5.600.000", store.balance == 5_600_000, "\(store.balance ?? -1)")
        store.add(amount: 70_000, note: "x", cat: "in-luong", credit: true, toast: false)
        check("khoản thu không mang dấu thẻ tín dụng", store.all.last?.cr == nil)
        // Bỏ / đánh dấu thẻ tín dụng
        if let e = store.items.first(where: { $0.n == "grab" }) {
            store.setCredit(e, false)
            check("bỏ dấu thẻ: chi tiêu thẻ 0, số dư trừ 50k", store.cardDebt == 0 && store.balance == 5_620_000, "debt \(store.cardDebt) bal \(store.balance ?? -1)")
            if let e2 = store.items.first(where: { $0.n == "grab" }) { store.setCredit(e2, true) }
            check("đánh dấu lại: chi tiêu thẻ 50k", store.cardDebt == 50_000, "\(store.cardDebt)")
        }
        // Điều chỉnh số dư
        let before = store.balance ?? 0
        store.setBalance(before - 20_000)
        check("điều chỉnh số dư giảm 20k", store.balance == before - 20_000, "\(store.balance ?? -1)")
        check("2 lần điều chỉnh, trả thẻ không nằm trong đó", store.adjusts.count == 2 && store.cardPays.count == 1,
              "adjusts \(store.adjusts.count) pays \(store.cardPays.count)")

        // MARK: Lặp hằng tháng giữ dấu thẻ
        if let e = store.items.first(where: { $0.n == "uniqlo" }) {
            store.repeatMonthly(e)
            check("lặp hằng tháng giữ dấu thẻ tín dụng", store.rules.values.contains { $0.src == e.id && $0.cr == true })
        }

        // MARK: CSV xuất rồi nhập lại
        if let url = store.exportCSV() {
            if case .success(let r) = CSVImport.read(url, store: store) {
                check("nhập lại file vừa xuất: không có khoản mới", r.items.isEmpty, "\(r.items.count) khoản mới")
                check("nhập lại: các dòng trả thẻ / điều chỉnh bị bỏ qua (không thành khoản chi)", !r.items.contains { $0.a == 300_000 })
            } else { check("đọc file CSV vừa xuất", false) }
            // Nhập vào sổ trống: dấu thẻ giữ nguyên, trả thẻ không thành khoản chi
            let saved = store.all
            store.eraseAll()
            if case .success(let r) = CSVImport.read(url, store: store) {
                check("sổ trống: quẹt thẻ giữ dấu thẻ tín dụng", r.items.contains { $0.isCredit && $0.a == 200_000 })
                check("sổ trống: trả thẻ 300k không thành khoản chi", !r.items.contains { $0.a == 300_000 })
                check("sổ trống: khoản thu 5tr là khoản thu", r.items.contains { $0.isIncome && $0.a == 5_000_000 })
            } else { check("đọc CSV vào sổ trống", false) }
            _ = saved
        }
        func csv(_ text: String) -> CSVImport.Result? {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-\(UUID().uuidString).csv")
            try? text.write(to: url, atomically: true, encoding: .utf8)
            if case .success(let r) = CSVImport.read(url, store: store) { return r }
            return nil
        }
        let r1 = csv("Ngày,Tiền vào,Tiền ra,Ghi chú\n01/10/2026,15000000,,Lương\n02/10/2026,,35000,cà phê\n")
        check("CSV Tiền vào / Tiền ra: lương là khoản thu", r1?.items.contains { $0.isIncome && $0.a == 15_000_000 } == true, "\(r1?.items.map { "\($0.a) \($0.c)" } ?? [])")
        check("CSV Tiền vào / Tiền ra: cà phê là khoản chi", r1?.items.contains { !$0.isIncome && $0.a == 35_000 } == true)
        let r2 = csv("Ngày,Giờ,Số tiền,Ghi chú\n12/10/2026,08:00,35000,cà phê\n12/10/2026,15:00,35000,cà phê\n")
        check("CSV hai dòng giống nhau cùng ngày: nhập cả hai", r2?.items.count == 2, "\(r2?.items.count ?? -1)")
        let r3 = csv("Ngày,Số tiền,Ghi chú\n15/07/26,50000,test\n")
        let y = r3?.items.first.map { Calendar.current.component(.year, from: $0.date) }
        check("CSV năm hai chữ số 15/07/26 → 2026", y == 2026, "\(y ?? -1)")

        // MARK: Số tiền giao dịch thẻ (Phím tắt Ví)
        let amounts: [(String, Int?)] = [("₫35.000", 35_000), ("35,000.00 VND", 35_000), ("35000", 35_000), ("1.234.567 ₫", 1_234_567),
                                         ("VND 1,234,567.89", 1_234_567), ("35.000,00 ₫", 35_000), ("-35.000 ₫", -35_000),
                                         ("−120,000 VND", -120_000), ("(50.000 ₫)", -50_000), ("₫ -1 000 000", -1_000_000), ("VND", nil), ("", nil)]
        for (s, v) in amounts { check("số tiền thẻ \"\(s)\" → \(v.map(String.init) ?? "nil")", CardPaymentIntent.parse(s) == v, "\(CardPaymentIntent.parse(s) ?? -1)") }
        for s in ["Refund", "Hoàn tiền", "hoàn", "Shopee - hoàn tiền", "REFUND Apple"] { check("hoàn tiền: \(s)", CardPaymentIntent.isRefund(s)) }
        for s in ["Hoàn Kiếm Coffee", "Highlands", ""] { check("không phải hoàn tiền: \(s)", !CardPaymentIntent.isRefund(s)) }

        // MARK: Chia tiền nhóm
        for (amt, n) in [(100_000, 3), (1, 3), (999_999, 7), (50_000, 4)] {
            let ids = (0..<n).map { "m\($0)" }
            let parts = Settle.parts(amt, ids, fixed: [:], seed: "seed")
            check("chia \(amt) cho \(n) người cộng đủ", parts.values.reduce(0, +) == amt, "\(parts.values.reduce(0, +))")
        }
        let fixedParts = Settle.parts(300_000, ["a", "b", "c"], fixed: ["a": 200_000], seed: "s")
        check("số riêng: a 200k, b và c chia 100k", fixedParts["a"] == 200_000 && fixedParts.values.reduce(0, +) == 300_000, "\(fixedParts)")
        let over = Settle.parts(100_000, ["a", "b"], fixed: ["a": 200_000], seed: "s")
        check("số riêng lớn hơn tổng: chia đều", over.values.reduce(0, +) == 100_000, "\(over)")
        let net = Settle.balances([HouseSpend(id: "s1", amount: 300_000, note: "", payer: "a", shares: ["a", "b", "c"], date: Date(), cat: "an", fixed: [:])],
                                  [HouseSettle(id: "p1", from: "b", to: "a", amount: 100_000, date: Date(), status: "ok"),
                                   HouseSettle(id: "p2", from: "c", to: "a", amount: 100_000, date: Date(), status: "no")])
        check("số dư nhóm: a +100k, b 0, c −100k (lần trả bị báo chưa nhận không tính)", net["a"] == 100_000 && net["b"] == 0 && net["c"] == -100_000, "\(net)")
        let tr = Settle.transfers(net)
        check("gợi ý trả: c → a 100k", tr.count == 1 && tr[0].from == "c" && tr[0].to == "a" && tr[0].amount == 100_000, "\(tr)")

        // MARK: Nói vào nhóm: ai trả, chia cho ai
        var g = HouseGroup(zone: CKRecordZone.ID(zoneName: "selftest"), scope: .private, isOwner: true, name: "Tùng của")
        g.members = [HouseMember(id: "c", name: "Minh"), HouseMember(id: "h", name: "Hạnh"), HouseMember(id: "v", name: "Vy"),
                     HouseMember(id: "x", name: "Khoa")]
        g.me = "c"
        func roles(_ t: String) -> String {
            let r = House.speechRoles(t, in: g)
            return "\(r.rest)|\(r.payer ?? "-")|\((r.shares ?? []).joined(separator: ","))"
        }
        for (t, want) in [("ăn lẩu 500k Hạnh trả", "ăn lẩu 500k|h|"),
                          ("500k lẩu chia cho tôi với Hạnh", "500k lẩu|-|c,h"),
                          ("chia đôi với Vy 200k cafe", "200k cafe|-|c,v"),
                          ("do khoa trả 300k taxi chia Khoa, Vy và mình", "300k taxi|x|x,v,c"),
                          ("Minh trả 100k", "100k|c|"),
                          ("chia đều 300k", "300k|-|"),
                          ("ăn lẩu 500k", "ăn lẩu 500k|-|")] {
            check("nhóm, câu nói: \(t)", roles(t) == want, roles(t))
        }
        for (t, want, off) in [("ăn trưa 315 nghìn, giảm giá 82 nghìn", "ăn trưa 315 nghìn", 82_000),
                               ("cơm 200k mã giảm 30k", "cơm 200k", 30_000),
                               ("ăn trưa 315 nghìn", "ăn trưa 315 nghìn", 0)] {
            let d = House.speechDiscount(t)
            check("giảm giá trong câu: \(t)", d.rest == want && d.discount == off, "\(d.rest) | \(d.discount)")
        }

        store.eraseAll()
        let report = "SELFTEST \(failed == 0 ? "PASS" : "FAIL \(failed)")\n" + out.joined(separator: "\n")
        print(report)
        let url = URL.documentsDirectory.appending(path: "selftest.txt")
        try? report.write(to: url, atomically: true, encoding: .utf8)
    }
}
#endif
