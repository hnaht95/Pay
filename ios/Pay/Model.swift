import Foundation
import SwiftUI
import WidgetKit

/// Một khoản chi. Cùng định dạng với file sao lưu của bản web (t = mili giây).
struct Expense: Codable, Identifiable, Hashable {
    var id: String
    var t: Double
    var a: Int
    var n: String?
    var c: String
    var acct: String?
    var u: Double?   // lần sửa cuối (ms), để gộp dữ liệu giữa các máy qua iCloud
    /// Khoản chi trả bằng thẻ tín dụng: vẫn là chi tiêu (ngân sách, thống kê), nhưng chưa trừ vào số dư — cộng vào nợ thẻ,
    /// tới lúc trả thẻ (khoản "adj-card") mới trừ. nil / false: trả bằng tiền đang có
    var cr: Bool? = nil

    var date: Date { Date(timeIntervalSince1970: t / 1000) }
    var stamp: Double { u ?? t }
    /// Khoản thu (danh mục thu), không phải khoản chi
    var isIncome: Bool { Category.isIncome(c) }
    /// Điều chỉnh số dư: không phải thu cũng không phải chi
    var isAdjust: Bool { Category.isAdjust(c) }
    /// Trả nợ thẻ tín dụng: trừ số dư và nợ thẻ, không phải chi tiêu (đã tính lúc quẹt thẻ). Cùng nhóm với điều chỉnh số dư
    /// (mã bắt đầu bằng "adj") nên mọi chỗ đã bỏ qua điều chỉnh cũng bỏ qua khoản này
    var isCardPay: Bool { c == Category.cardPay }
    /// Trả bằng thẻ tín dụng
    var isCredit: Bool { cr == true && !isIncome && !isAdjust }
    /// Ảnh hưởng tới số dư: khoản thu và điều chỉnh cộng thêm cộng, khoản chi và điều chỉnh trừ thì trừ
    var signed: Int { isIncome || c == "adj+" ? a : -a }
    /// Phần làm đổi số dư: khoản quẹt thẻ tín dụng chưa đụng tới tiền đang có (trừ lúc trả thẻ)
    var balanceEffect: Int { isCredit ? 0 : signed }
}

/// Ghi nhớ theo số tài khoản để lần sau quét lại tự điền tên + danh mục.
struct Memo: Codable, Hashable {
    var c: String?
    var n: String?
    var u: Double? = nil
}

/// Danh mục người dùng tự tạo. Không xoá hẳn (on = false) để xoá cũng đồng bộ được sang máy khác.
struct CustomCat: Codable, Hashable {
    var k: String
    var name: String
    var icon: String     // emoji
    var tone: Int        // chỉ số trong CategoryTone
    var on: Bool
    var u: Double
    /// Ô ở màn hình chính chiếm cả hàng (nil / false: nửa hàng). Giữ cả khi `on` = false (danh mục có sẵn chưa sửa gì khác)
    var wide: Bool? = nil
    /// Lúc tạo (ms), để xếp thứ tự ô. Tách khỏi `u` vì `u` đổi theo mỗi lần sửa (đổi tên, kéo dài ô là ô nhảy xuống cuối).
    /// nil: chưa sửa lần nào từ khi có trường này, lúc đó `u` vẫn là mốc xếp thứ tự
    var made: Double? = nil
    /// Hạn mức chi mỗi tháng (đồng); nil: không đặt. Giữ cả khi `on` = false (danh mục có sẵn chưa sửa gì khác), như `wide`
    var limit: Int? = nil

    /// Đánh dấu vừa sửa. Chốt mốc xếp thứ tự trước khi `u` đổi, để ô không đổi chỗ
    mutating func touch(_ t: Double) { made = made ?? u; u = t }

    /// tone < 0: giữ màu gốc của danh mục có sẵn
    var category: Category {
        if let base = Category.base(k) {
            // Danh mục có sẵn đã chỉnh: giữ từ khoá gốc, thêm tên mới làm từ khoá
            let kw = base.kw + [Store.noteKey(name)].filter { !$0.isEmpty && !base.kw.contains($0) }
            var c = Category(k: k, icon: icon, name: name, color: tone < 0 ? base.color : CategoryTone.bg(tone),
                             art: base.art && icon == base.icon, kw: kw, customChart: tone < 0 ? nil : CategoryTone.chart(tone))
            c.onDark = tone < 0 ? base.onDark : CategoryTone.dark(tone)
            return c
        }
        var c = Category(k: k, icon: icon, name: name, color: CategoryTone.bg(tone), kw: [Store.noteKey(name)].filter { !$0.isEmpty },
                         customChart: CategoryTone.chart(tone))
        c.onDark = CategoryTone.dark(tone)
        return c
    }
}

/// Khoản định kỳ: app tự ghi mỗi tháng vào ngày `day` (tiền nhà, điện, internet…).
struct Rule: Codable, Hashable, Identifiable {
    var id: String
    var a: Int
    var n: String?
    var c: String
    var day: Int          // ngày trong tháng; tháng ngắn hơn thì ghi vào ngày cuối tháng
    var minute: Int       // giờ ghi, tính bằng phút từ 0:00
    var start: String     // "yyyy-MM": tháng đầu tiên được tự ghi
    var src: String?      // khoản chi gốc đã chọn "Lặp hằng tháng"
    var on: Bool          // false = đã bỏ lặp
    var u: Double         // lần sửa cuối (ms), để gộp giữa các máy
    var cr: Bool? = nil   // khoản gốc trả bằng thẻ tín dụng: các bản tự ghi cũng vậy (xem Expense.cr)
}

struct Backup: Codable {
    var items: [Expense]
    var memo: [String: Memo]?
    var deleted: [String: Double]? = nil   // id -> lúc xoá (ms), để xoá cũng đồng bộ sang máy khác
    var rules: [String: Rule]? = nil       // khoản định kỳ
    var cats: [String: CustomCat]? = nil   // danh mục tự tạo

    func same(as o: Backup) -> Bool {
        Set(items) == Set(o.items) && (memo ?? [:]) == (o.memo ?? [:]) && (deleted ?? [:]) == (o.deleted ?? [:])
            && (rules ?? [:]) == (o.rules ?? [:]) && (cats ?? [:]) == (o.cats ?? [:])
    }

    /// Gộp hai bản (máy này + iCloud). Bản sửa sau thắng; khoản đã xoá bị bỏ trừ khi được sửa/khôi phục sau lúc xoá.
    /// Kết quả không phụ thuộc thứ tự a, b nên hai máy luôn gộp ra cùng một bản, không ghi qua ghi lại mãi.
    static func merge(_ a: Backup, _ b: Backup) -> Backup {
        var deleted = a.deleted ?? [:]
        for (k, v) in b.deleted ?? [:] { deleted[k] = max(deleted[k] ?? 0, v) }

        var byId: [String: Expense] = [:]
        for e in a.items + b.items {
            if let old = byId[e.id], !wins(e, over: old) { continue }
            byId[e.id] = e
        }
        var items: [Expense] = []
        for e in byId.values {
            if let d = deleted[e.id] {
                if e.stamp > d { deleted[e.id] = nil } else { continue }
            }
            items.append(e)
        }
        items.sort { $0.t < $1.t }

        var memo = a.memo ?? [:]
        for (k, m) in b.memo ?? [:] {
            if let old = memo[k], !wins(m, over: old) { continue }
            memo[k] = m
        }
        var rules = a.rules ?? [:]
        for (k, r) in b.rules ?? [:] {
            if let old = rules[k], !wins(r, over: old) { continue }
            rules[k] = r
        }
        var cats = a.cats ?? [:]
        for (k, c) in b.cats ?? [:] {
            if let old = cats[k], old.u > c.u || (old.u == c.u && "\(old.on)\(old.name)" >= "\(c.on)\(c.name)") { continue }
            cats[k] = c
        }
        return Backup(items: items, memo: memo, deleted: deleted, rules: rules, cats: cats)
    }

    private static func wins(_ x: Expense, over y: Expense) -> Bool {
        if x.stamp != y.stamp { return x.stamp > y.stamp }
        return "\(x.a)|\(x.c)|\(x.n ?? "")|\(x.acct ?? "")|\(x.t)|\(x.cr == true)" > "\(y.a)|\(y.c)|\(y.n ?? "")|\(y.acct ?? "")|\(y.t)|\(y.cr == true)"
    }

    private static func wins(_ x: Rule, over y: Rule) -> Bool {
        if x.u != y.u { return x.u > y.u }
        return "\(x.on)|\(x.a)|\(x.day)|\(x.c)" > "\(y.on)|\(y.a)|\(y.day)|\(y.c)"
    }

    private static func wins(_ x: Memo, over y: Memo) -> Bool {
        if (x.u ?? 0) != (y.u ?? 0) { return (x.u ?? 0) > (y.u ?? 0) }
        return "\(x.c ?? "")|\(x.n ?? "")" > "\(y.c ?? "")|\(y.n ?? "")"
    }
}

/// Trạng thái đồng bộ iCloud để hiện trong Cài đặt.
enum CloudState: Equatable {
    case off                 // người dùng tắt
    case connecting
    case unavailable         // máy chưa đăng nhập iCloud / bản build không có quyền iCloud
    case on(last: Date?)     // đang đồng bộ; lần gần nhất iCloud đã nhận đủ bản trên máy
}

extension String {
    /// Viết hoa chữ đầu để hiển thị ("cà phê" -> "Cà phê"); dữ liệu lưu giữ nguyên như người dùng nhập / nói
    var capFirst: String { prefix(1).uppercased() + dropFirst() }
}

struct Toast: Identifiable {
    let id = UUID()
    let message: String
    let undo: (() -> Void)?
    /// Báo lỗi: hiện biểu tượng cảnh báo thay cho dấu tích
    var error = false
}

@MainActor
final class Store: ObservableObject {
    /// Dùng chung cho app và lệnh Siri (Siri có thể ghi khi app chưa mở giao diện).
    static let shared = Store()

    /// Mọi khoản đã ghi: khoản chi và tiền vào (lưu, đồng bộ, sửa, xoá đều trên đây)
    @Published private(set) var all: [Expense] = [] {
        didSet {
            items = all.filter { !$0.isIncome && !$0.isAdjust }
            incomes = all.filter(\.isIncome)
            adjusts = all.filter { $0.isAdjust && !$0.isCardPay }
            cardPays = all.filter(\.isCardPay)
        }
    }
    /// Chỉ khoản chi: mọi tổng chi, ngân sách, thống kê tính trên đây
    @Published private(set) var items: [Expense] = []
    /// Chỉ khoản thu
    @Published private(set) var incomes: [Expense] = []
    /// Các lần đặt / điều chỉnh số dư
    @Published private(set) var adjusts: [Expense] = []
    /// Các lần trả thẻ tín dụng
    @Published private(set) var cardPays: [Expense] = []
    @Published var memo: [String: Memo] = [:]
    @Published var appId: String = UserDefaults.standard.string(forKey: "bankApp") ?? "acb" {
        didSet { UserDefaults.standard.set(appId, forKey: "bankApp") }
    }
    @Published var toast: Toast?
    /// Ngân sách tháng (đồng), 0 = không đặt.
    @Published var budget: Int = UserDefaults.standard.integer(forKey: "budget") {
        didSet {
            UserDefaults.standard.set(budget, forKey: "budget")
            rememberBudget()
            refreshWidget()
        }
    }
    /// Mức ngân sách theo tháng đặt ("2026-10" -> 8.000.000), để xem tháng cũ không bị so với mức hiện tại
    private var budgetHistory: [String: Int] = UserDefaults.standard.dictionary(forKey: "budgetHistory") as? [String: Int] ?? [:]
    private var deleted: [String: Double] = [:]
    /// Khoản định kỳ theo mã
    @Published private(set) var rules: [String: Rule] = [:]
    /// Các kỳ máy này tự ghi từ lúc mở app. Lúc ghi, dữ liệu trên máy có thể cũ hơn iCloud (máy khác đã bỏ lặp mà chưa gộp về),
    /// nên gộp xong phải xem lại riêng các khoản này: xem `retractStale`
    private var autoWritten: Set<String> = []
    /// Danh mục tự tạo theo mã
    @Published private(set) var cats: [String: CustomCat] = [:] {
        didSet {
            let on = cats.values.filter(\.on)
            // Theo lúc tạo; trùng mốc (vd cùng khôi phục từ một file) thì theo mã, không thì thứ tự đổi theo từng lần mở app
            let mine = on.filter { !Category.isBuiltin($0.k) }.sorted { ($0.made ?? $0.u, $0.k) < ($1.made ?? $1.u, $1.k) }
            Category.custom = mine.filter { !Category.isIncome($0.k) }.map(\.category)
            Category.incomeCustom = mine.filter { Category.isIncome($0.k) }.map(\.category)
            Category.edited = Dictionary(uniqueKeysWithValues: on.filter { Category.isBuiltin($0.k) }.map { ($0.k, $0.category) })
        }
    }
    private let cloud = Cloud()
    @Published private(set) var cloudState: CloudState = .connecting
    @Published var cloudOn: Bool = UserDefaults.standard.object(forKey: "cloudSync") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(cloudOn, forKey: "cloudSync")
            Task { await applyCloud() }
        }
    }

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pay.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fileURL), let b = try? JSONDecoder().decode(Backup.self, from: data) {
            apply(b)
        }
        #if DEBUG
        // "-filmSeed YES": sáu tháng chi tiêu mẫu, không đồng bộ iCloud (để quay phim giới thiệu)
        if UserDefaults.standard.bool(forKey: "filmSeed") { all = Self.filmSeed(); cats = [:];
            // "-filmFlat YES": xem thử bộ màu phẳng trên các danh mục có sẵn
            if UserDefaults.standard.bool(forKey: "filmFlat") {
                for (i, c) in Category.builtin.enumerated() { cats[c.k] = CustomCat(k: c.k, name: c.rawName, icon: c.icon, tone: [16, 17, 19, 18, 20, 22][i], on: true, u: 1, wide: i == 0) }
            }
            budget = 9_000_000; cloudOn = false; return }   // danh mục gốc, không sửa gì
        #endif
        if budget > 0 && budgetHistory.isEmpty { rememberBudget() }   // máy đã đặt ngân sách từ trước khi có ghi nhớ theo tháng
        if runRecurring() { writeLocal() }   // ghi các khoản định kỳ đã tới hạn khi app tắt
        refreshWidget()
        cloud.onSynced = { [weak self] in self?.cloudState = .on(last: Date()) }
        Task { await applyCloud() }
    }

    /// Bật / tắt đồng bộ theo công tắc trong Cài đặt.
    private func applyCloud() async {
        // Đồng bộ iCloud là tính năng Pro: chưa mua thì coi như tắt (công tắc vẫn nhớ, mua xong là chạy)
        guard cloudOn, Pro.shared.active else { cloud.stop(); cloudState = .off; return }
        if cloud.active { return }
        cloudState = .connecting
        let ok = await cloud.start { [weak self] remote in self?.absorb(remote) }
        if !cloudOn || !Pro.shared.active { cloud.stop(); cloudState = .off; return }   // vừa tắt trong lúc đang kết nối
        cloudState = ok ? .on(last: nil) : .unavailable
    }

    /// Vừa mua / hết hạn Pro: bật / tắt các phần cần Pro (đồng bộ iCloud)
    func proChanged() { Task { await applyCloud() } }

    /// Nút "Đồng bộ ngay": đẩy bản máy này lên rồi đọc lại bản trên iCloud.
    func syncNow() async {
        guard cloud.active else { await applyCloud(); return }
        cloud.push(snapshot)
        await cloud.pull()
    }

    private var snapshot: Backup { Backup(items: all, memo: memo, deleted: deleted, rules: rules, cats: cats) }
    private var now: Double { Date().timeIntervalSince1970 * 1000 }

    private func apply(_ b: Backup) {
        all = b.items
        memo = b.memo ?? [:]
        deleted = b.deleted ?? [:]
        rules = b.rules ?? [:]
        cats = b.cats ?? [:]
    }

    /// Có bản mới trên iCloud (từ máy khác): gộp vào máy này, máy này có gì mới hơn thì đẩy ngược lên.
    private func absorb(_ remote: Backup?) {
        guard let remote else { cloud.push(snapshot); return }
        var merged = Backup.merge(snapshot, remote)
        if !merged.same(as: snapshot) {
            apply(merged)
            let retracted = retractStale()
            if runRecurring() || retracted { merged = snapshot }   // khoản định kỳ máy khác vừa thêm
            writeLocal()
        }
        if !merged.same(as: remote) { cloud.push(merged) }
    }

    /// Rút lại khoản định kỳ máy này vừa tự ghi theo danh sách cũ: gộp iCloud xong mới biết khoản định kỳ đó đã được bỏ lặp
    /// (hoặc "Xoá tất cả") ở máy khác TRƯỚC lúc tới hạn. Chỉ đụng tới khoản chính máy này ghi từ lúc mở app và chưa ai sửa,
    /// không dọn lại dữ liệu cũ; để lại dấu xoá cho máy nào đã lỡ nhận khoản đó.
    private func retractStale() -> Bool {
        let off = rules.values.filter { !$0.on }
        let stale = Set(all.filter { e in
            e.u == nil && autoWritten.contains(e.id) && off.contains { e.id.hasPrefix("r-\($0.id)-") && e.t > $0.u }
        }.map(\.id))
        guard !stale.isEmpty else { return false }
        let t = now
        for id in stale { deleted[id] = t }
        all.removeAll { stale.contains($0.id) }
        return true
    }

    var bankApp: BankApp { BankData.apps.first { $0.id == appId } ?? BankData.apps[0] }
    var sorted: [Expense] { all.sorted { $0.t > $1.t } }
    /// Khoản chi và khoản thu, mới nhất trước — không có các lần điều chỉnh số dư (chúng không phải tiêu tiền; xem ở bảng Số dư)
    var activity: [Expense] { all.filter { !$0.isAdjust }.sorted { $0.t > $1.t } }
    /// Các lần đặt / điều chỉnh số dư, mới nhất trước
    var adjustLog: [Expense] { adjusts.sorted { $0.t > $1.t } }

    private func persist() {
        writeLocal()
        cloud.push(snapshot)
    }

    private func writeLocal() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
        refreshWidget()
    }

    /// Ghi số liệu cho widget rồi bảo widget vẽ lại.
    private func refreshWidget() {
        let now = Date()
        // Nhắc ghi buổi tối: hôm nay đã có khoản thì bỏ lời nhắc của hôm nay
        // Nhắc buổi tối: hôm nay người dùng đã tự ghi gì chưa — khoản thu cũng tính; khoản tự ghi hằng tháng ("r-…") thì không
        let cal = Calendar.current
        DailyReminder.reschedule(loggedToday: all.contains { !$0.isAdjust && !$0.id.hasPrefix("r-") && cal.isDateInToday($0.date) })
        Summary(today: total(on: now), month: monthItems(now).reduce(0) { $0 + $1.a }, count: count(on: now), day: now, budget: budget).save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// toast: false khi màn hình tự có nút Hoàn tác (thẻ giọng nói)
    /// idPrefix: đánh dấu nguồn ghi trong mã khoản (vd "wallet-" cho khoản tự ghi từ giao dịch thẻ), không thêm trường mới
    func add(amount: Int, note: String, cat: String, acct: String? = nil, credit: Bool = false, toast: Bool = true, idPrefix: String = "") {
        let e = Expense(id: idPrefix + UUID().uuidString, t: Date().timeIntervalSince1970 * 1000, a: amount, n: note, c: cat, acct: acct,
                        cr: credit && !Category.isIncome(cat) ? true : nil)
        let before = catSpent(cat)
        all.append(e)
        persist()
        let undo: () -> Void = { [weak self] in self?.remove(id: e.id, toast: false) }
        if let name = crossedLimit(cat, before: before) {
            // Vừa vượt hạn mức của danh mục: báo thay cho "Đã lưu" (vẫn Hoàn tác được nếu chỗ gọi không tự có nút Hoàn tác)
            self.toast = Toast(message: L("Vượt hạn mức %@", name), undo: toast ? undo : nil, error: true)
        } else if toast { show(L("Đã lưu %@", fmt(amount)), undo: undo) }
        DailyReminder.askOnce(store: self)
    }

    /// Ghi từ một câu "35k cafe": tự đoán danh mục theo ghi chú. Không đọc được số tiền thì nil.
    /// spoken: câu từ giọng nói, hiểu thêm số bằng chữ ("ba lăm nghìn") và số dưới 1.000 là nghìn.
    @discardableResult
    func quickAdd(_ text: String, spoken: Bool = false, toast: Bool = true) -> Expense? {
        guard let q = spoken ? (QuickParse.spoken(text) ?? QuickParse.expense(text)) : QuickParse.expense(text) else { return nil }
        add(amount: q.amount, note: q.note, cat: guessEntry(q.note), toast: toast)
        return all.last
    }

    /// Tình hình ngân sách của tháng chứa `day`, nil nếu tháng đó chưa đặt.
    func budgetStatus(_ day: Date = Date()) -> BudgetStatus? {
        budget(for: day).map { BudgetStatus(budget: $0, spent: monthItems(day).reduce(0) { $0 + $1.a }) }
    }

    /// Ngân sách áp dụng cho tháng chứa `day`: tháng này là mức đang đặt; tháng cũ là mức đặt gần nhất tính đến tháng đó.
    /// Tháng cũ trước lần đặt đầu tiên thì nil (không so).
    func budget(for day: Date) -> Int? {
        let key = Self.monthKey(day)
        if key >= Self.monthKey(Date()) { return budget > 0 ? budget : nil }
        guard let k = budgetHistory.keys.filter({ $0 <= key }).max(), let v = budgetHistory[k], v > 0 else { return nil }
        return v
    }

    private func rememberBudget() {
        budgetHistory[Self.monthKey(Date())] = budget
        UserDefaults.standard.set(budgetHistory, forKey: "budgetHistory")
    }

    static func monthKey(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: d)
        return String(format: "%04d-%02d", c.year!, c.month!)
    }

    func update(_ e: Expense) {
        guard let i = all.firstIndex(where: { $0.id == e.id }) else { return }
        let before = catSpent(e.c)
        var e = e
        e.u = now
        all[i] = e
        persist()
        if let name = crossedLimit(e.c, before: before) { showError(L("Vượt hạn mức %@", name)) }
    }

    // MARK: Hạn mức theo danh mục

    /// Hạn mức tháng của danh mục, nil nếu chưa đặt
    func limit(_ k: String) -> Int? { cats[k]?.limit.flatMap { $0 > 0 ? $0 : nil } }

    /// Đặt / bỏ hạn mức tháng (nil hoặc 0 = bỏ). Danh mục có sẵn chưa sửa thì thêm bản chỉnh `on` = false như `setWide`,
    /// giữ nguyên tên, biểu tượng, màu gốc
    func setLimit(_ k: String, _ v: Int?) {
        let v = v.flatMap { $0 > 0 ? $0 : nil }
        guard v != cats[k]?.limit else { return }
        let base = Category.get(k)
        var c = cats[k] ?? CustomCat(k: k, name: base.rawName, icon: base.icon, tone: -1, on: false, u: now)
        c.limit = v; c.touch(now)
        cats[k] = c
        persist()
    }

    /// Đã chi trong tháng chứa `day` của một danh mục (danh mục đã xoá tính vào Khác, như ô ở màn hình chính)
    func catSpent(_ k: String, _ day: Date = Date()) -> Int {
        let k = Category.get(k).k
        return monthItems(day).filter { Category.get($0.c).k == k }.reduce(0) { $0 + $1.a }
    }

    /// Tình hình hạn mức của danh mục trong tháng chứa `day`, nil nếu chưa đặt hạn mức.
    /// Hạn mức không ghi nhớ theo tháng (khác ngân sách chung) nên chỉ so ở tháng hiện tại
    func catStatus(_ k: String, _ day: Date = Date()) -> BudgetStatus? {
        guard Calendar.current.isDate(day, equalTo: Date(), toGranularity: .month), let lim = limit(Category.get(k).k) else { return nil }
        return BudgetStatus(budget: lim, spent: catSpent(k, day))
    }

    /// Tên danh mục nếu tổng chi tháng này của nó vừa vượt hạn mức (trước còn trong hạn mức, giờ đã quá)
    private func crossedLimit(_ k: String, before: Int) -> String? {
        let c = Category.get(k)
        guard !Category.isIncome(c.k), let lim = limit(c.k), before <= lim, catSpent(c.k) > lim else { return nil }
        return c.name
    }

    func remove(id: String, toast: Bool = true) {
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        var e = all.remove(at: i)
        deleted[id] = now
        persist()
        if toast {
            show(L("Đã xoá")) { [weak self] in
                guard let self else { return }
                e.u = self.now
                self.deleted[id] = nil
                self.all.insert(e, at: min(i, self.all.count))
                self.persist()
            }
        }
    }

    /// Xoá mọi khoản chi (có dấu xoá nên các máy đồng bộ iCloud cũng xoá theo). Giữ ghi nhớ người nhận.
    /// Xoá ảnh hoá đơn của các khoản đã xoá quá một ngày (đã qua lúc còn Hoàn tác được), kẻo ảnh nằm lại mãi trên máy và iCloud
    func pruneReceiptPhotos() {
        let cutoff = now - 86_400_000
        for (id, at) in deleted where at > 0 && at < cutoff && ReceiptPhotos.has(id) { ReceiptPhotos.remove(id) }
    }

    func eraseAll() {
        let t = now
        for e in all { deleted[e.id] = t }
        all = []
        // Không để tháng sau tự hiện lại khoản định kỳ
        for (k, var r) in rules where r.on { r.on = false; r.u = t; rules[k] = r }
        persist()
        show(L("Đã xoá tất cả khoản chi"))
    }

    func remember(_ key: String, _ m: Memo) {
        var m = m
        m.u = now
        memo[key] = m
        persist()
    }

    func show(_ message: String, undo: (() -> Void)? = nil) {
        toast = Toast(message: message, undo: undo)
    }

    /// Báo việc không làm được: thông báo có biểu tượng cảnh báo, không có Hoàn tác
    func showError(_ message: String) {
        toast = Toast(message: message, undo: nil, error: true)
    }

    // MARK: Tổng

    func total(on day: Date) -> Int {
        let cal = Calendar.current
        return items.filter { cal.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.a }
    }

    func count(on day: Date) -> Int {
        let cal = Calendar.current
        return items.filter { cal.isDate($0.date, inSameDayAs: day) }.count
    }

    func monthItems(_ day: Date) -> [Expense] {
        let cal = Calendar.current
        return items.filter { cal.isDate($0.date, equalTo: day, toGranularity: .month) }
    }

    /// Số dư hiện có: lần đặt số dư đầu tiên làm mốc, cộng mọi khoản thu và điều chỉnh, trừ mọi khoản chi từ mốc đó.
    /// Chưa đặt số dư lần nào thì nil (app không biết lúc bắt đầu dùng bạn có bao nhiêu)
    var balance: Int? {
        guard let start = balanceStart else { return nil }
        return all.filter { $0.t >= start }.reduce(0) { $0 + $1.balanceEffect }
    }

    /// Nợ thẻ tín dụng: các khoản quẹt thẻ trừ các lần trả thẻ (không âm: trả cả nợ có từ trước khi dùng app thì về 0)
    var cardDebt: Int { cardDebt(before: .infinity) }

    /// Nợ thẻ ngay trước thời điểm `t` (ms). Tính lần lượt theo thời gian, mỗi lần trả thẻ chỉ trừ tới 0: trả dư (trả cả nợ có từ
    /// trước khi dùng app) không được bù trừ cho các lần quẹt thẻ sau đó
    func cardDebt(before t: Double) -> Int {
        let events = (items.filter { $0.isCredit && $0.t < t } + cardPays.filter { $0.t < t }).sorted { $0.t < $1.t }
        return events.reduce(0) { debt, e in e.isCardPay ? max(0, debt - e.a) : debt + e.a }
    }

    /// Trả thẻ tín dụng: tiền ra khỏi số dư, nợ thẻ giảm; không tính là chi (đã tính lúc quẹt thẻ)
    func payCard(_ amount: Int) {
        guard amount > 0 else { return }
        let e = Expense(id: UUID().uuidString, t: now, a: amount, n: nil, c: Category.cardPay, acct: nil)
        all.append(e)
        persist()
        show(L("Đã trả thẻ %@", fmt(amount))) { [weak self] in self?.remove(id: e.id, toast: false) }
    }

    /// Khoản chi cá nhân ghi từ một khoản chung ("Ghi phần của tôi vào chi tiêu"): nối bằng trường acct = "h:<mã khoản chung>",
    /// để sửa / xoá khoản chung thì phần của mình đổi theo
    static func groupLink(_ spendID: String) -> String { "h:" + spendID }

    /// Khoản chung vừa đổi phần của mình (mine: phần mới; nil hoặc 0 khi xoá khoản / mình không còn chịu): sửa hoặc xoá khoản chi
    /// cá nhân đã ghi từ nó
    func syncGroupShare(_ spendID: String, mine: Int?) {
        guard let e = all.first(where: { $0.acct == Self.groupLink(spendID) }) else { return }
        if let mine, mine > 0 {
            guard e.a != mine else { return }
            var e = e; e.a = mine; update(e)
        } else {
            remove(id: e.id, toast: false)
        }
    }

    /// Đánh dấu / bỏ đánh dấu một khoản chi là trả bằng thẻ tín dụng
    func setCredit(_ e: Expense, _ on: Bool) {
        var e = e
        e.cr = on ? true : nil
        update(e)
    }

    /// Lúc đặt số dư lần đầu (ms): mốc tính số dư
    var balanceStart: Double? { adjusts.map(\.t).min() }

    /// Số dư ngay trước thời điểm `t` (ms); trước lúc đặt số dư lần đầu thì nil
    func balance(before t: Double) -> Int? {
        guard let start = balanceStart, t > start else { return nil }
        return all.filter { $0.t >= start && $0.t < t }.reduce(0) { $0 + $1.balanceEffect }
    }

    /// Đặt số dư hiện có: ghi một khoản "Điều chỉnh số dư" bằng phần chênh với số app đang tính (lần đầu là cả số dư),
    /// để Lịch sử thấy lúc nào đã chỉnh và chỉnh bao nhiêu. Không tính vào chi, thu, ngân sách, thống kê
    func setBalance(_ target: Int) {
        let first = balance == nil
        let diff = target - (balance ?? 0)
        guard first || diff != 0 else { show(L("Số dư đã đúng")); return }
        let e = Expense(id: UUID().uuidString, t: now, a: abs(diff), n: first ? L("Số dư ban đầu") : nil, c: diff >= 0 ? "adj+" : "adj-", acct: nil)
        all.append(e)
        persist()
        show(L("Số dư: %@", fmt(target))) { [weak self] in self?.remove(id: e.id, toast: false) }
    }

    // MARK: Sao lưu

    func exportJSON() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pay-\(stamp()).json")
        // Kèm các kỳ tự ghi đã xoá ("r-…"): khôi phục ở máy khác thì không ghi lại những kỳ người dùng đã xoá
        let skipped = deleted.filter { $0.key.hasPrefix("r-") }
        guard let data = try? JSONEncoder().encode(Backup(items: all, memo: memo, deleted: skipped.isEmpty ? nil : skipped, rules: rules, cats: cats)),
              (try? data.write(to: url)) != nil else { return nil }
        return url
    }

    func exportCSV() -> URL? {
        let df = DateFormatter(); df.dateFormat = "dd/MM/yyyy"
        let tf = DateFormatter(); tf.dateFormat = "HH:mm"
        let q = { (s: String) in "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var rows = [[L("Ngày"), L("Giờ"), L("Loại"), L("Số tiền"), L("Danh mục"), L("Ghi chú")].map(q).joined(separator: ",")]
        for e in all.sorted(by: { $0.t < $1.t }) {
            rows.append([df.string(from: e.date), tf.string(from: e.date), e.isCardPay ? L("Trả thẻ") : e.isAdjust ? L("Điều chỉnh") : e.isIncome ? L("Thu") : e.isCredit ? L("Chi thẻ tín dụng") : L("Chi"), String(e.a), Category.get(e.c).name, e.n ?? ""].map(q).joined(separator: ","))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pay-\(stamp()).csv")
        guard (try? ("\u{FEFF}" + rows.joined(separator: "\n")).write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        return url
    }

    func importBackup(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let b = try? JSONDecoder().decode(Backup.self, from: data) else {
            showError(L("File sao lưu không hợp lệ")); return
        }
        let ids = Set(all.map(\.id))
        let t = now
        // Khoản được khôi phục mang dấu sửa mới và bỏ dấu xoá cũ (vd sau "Xoá tất cả"),
        // nếu không lần gộp iCloud kế tiếp sẽ xoá chúng lần nữa
        let add = b.items.filter { !ids.contains($0.id) && ($0.a > 0 || $0.isAdjust) }.map { e -> Expense in
            var e = e
            e.u = t
            return e
        }
        for e in add { deleted[e.id] = nil }
        all += add
        memo = (b.memo ?? [:]).merging(memo) { _, mine in mine }
        // Khoản định kỳ trong file: thêm cái còn thiếu, bật lại cái đã bỏ (như khoản chi đã xoá cũng được khôi phục)
        let cal = Calendar.current
        let thisMonth = cal.dateInterval(of: .month, for: Date())!.start
        for (k, var r) in b.rules ?? [:] where r.on && rules[k]?.on != true {
            if rules[k] != nil {
                // Đã bỏ lặp trên máy này: bật lại từ kỳ tới (như repeatMonthly). Giữ `start` cũ thì runRecurring
                // ghi bù mọi tháng nó đang tắt, thành một loạt khoản chi không có thật
                let first = due(r, in: thisMonth) > Date() ? thisMonth : cal.date(byAdding: .month, value: 1, to: thisMonth)!
                r.start = max(r.start, Self.monthKey(first))
            }
            r.u = t
            rules[k] = r
        }
        // Danh mục tự tạo là tính năng Pro (miễn phí được Pro.freeCategories cái mỗi loại): khôi phục cũng không vượt giới hạn đó
        var room = (expense: Pro.shared.active ? Int.max : max(0, Pro.freeCategories - Category.custom.count),
                    income: Pro.shared.active ? Int.max : max(0, Pro.freeCategories - Category.incomeCustom.count))
        for (k, c) in (b.cats ?? [:]).sorted(by: { ($0.value.made ?? $0.value.u) < ($1.value.made ?? $1.value.u) }) where c.on && cats[k]?.on != true {
            let builtin = Category.isBuiltin(k), inc = Category.isIncome(k)
            if !builtin {
                if inc { guard room.income > 0 else { continue }; room.income -= 1 } else { guard room.expense > 0 else { continue }; room.expense -= 1 }
            }
            var c = c; c.touch(t); cats[k] = c
        }
        // Kỳ tự ghi đã xoá trong file: giữ là đã xoá (trừ khi máy này đang có khoản đó)
        let have = Set(all.map(\.id))
        for (k, v) in b.deleted ?? [:] where k.hasPrefix("r-") && !have.contains(k) && deleted[k] == nil { deleted[k] = v }
        runRecurring()
        persist()
        show(L("Đã khôi phục %ld khoản", add.count))
    }

    /// Nhập các khoản đọc từ file CSV (đã bỏ khoản trùng); Hoàn tác xoá hết số vừa nhập
    func importItems(_ add: [Expense]) {
        guard !add.isEmpty else { return }
        all += add
        persist()
        let ids = Set(add.map(\.id))
        show(L("Đã nhập %ld khoản", add.count)) { [weak self] in
            guard let self else { return }
            let t = self.now
            for id in ids { self.deleted[id] = t }
            self.all.removeAll { ids.contains($0.id) }
            self.persist()
        }
    }

    // MARK: Tự học danh mục

    /// Ghi chú chuẩn hoá để so khớp: "Phúc Long  (Q1)" -> "phuc long q1"
    nonisolated static func noteKey(_ s: String) -> String {
        strip(s).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }

    /// Danh mục cho một ghi chú: ưu tiên danh mục đã tự chọn trước đây cho tên đó, không có thì đoán theo từ khoá.
    func guessCategory(_ note: String) -> String {
        let k = Self.noteKey(note)
        guard !k.isEmpty else { return Category.guess(note) }
        // Danh mục đã học mà đã xoá thì coi như chưa học, nếu không khoản mới tiếp tục mang mã danh mục không còn dùng.
        // Ghi nhớ vẫn giữ: Hoàn tác xoá danh mục / khôi phục từ file là dùng lại được
        let live = Set(Category.all.map(\.k))
        if let c = memo["note:" + k]?.c, live.contains(c) { return c }
        // Ghi chú dài hơn có chứa tên đã học: "phuc long sang nay" dùng danh mục đã học cho "phuc long"
        let padded = " \(k) "
        let hit = memo.keys.filter { $0.hasPrefix("note:") && padded.contains(" \($0.dropFirst(5)) ") && live.contains(memo[$0]?.c ?? "") }.max { $0.count < $1.count }
        return hit.flatMap { memo[$0]?.c } ?? Category.guess(note)
    }

    /// Danh mục tiền vào cho ghi chú: danh mục đã tự chọn trước đây, không thì đoán theo từ khoá, không khớp thì "Khác" của tiền vào
    func guessIncome(_ note: String) -> String {
        let k = Self.noteKey(note)
        if !k.isEmpty, let c = memo["note:" + k]?.c, Category.income.contains(where: { $0.k == c }) { return c }
        return Category.guessIncome(note) ?? Category.income.last!.k
    }

    /// Câu ghi nhanh (giọng nói, Siri, "35k cafe"): có từ khoá tiền vào ("nhận lương 15tr") thì là tiền vào, không thì khoản chi
    /// Danh mục đã tự chọn cho đúng ghi chú này (chi hay thu đều được) thắng mọi phỏng đoán: sửa "trả lương giúp việc" sang Hoá
    /// đơn, "mẹ cho" sang Được chuyển thì lần sau nói lại câu đó app chọn đúng như vậy
    func guessEntry(_ note: String) -> String {
        let k = Self.noteKey(note)
        if !k.isEmpty, let c = memo["note:" + k]?.c, (Category.all + Category.income).contains(where: { $0.k == c }) { return c }
        return Category.guessIncome(note) != nil && !Category.spendIntent(note) ? guessIncome(note) : guessCategory(note)
    }

    /// Nhớ danh mục đã tự chọn cho ghi chú này, chỉ khi khác với cách app đang đoán (đồng bộ iCloud cùng ghi nhớ người nhận).
    func learnCategory(_ note: String, _ cat: String) {
        let k = Self.noteKey(note)
        guard !k.isEmpty, (Category.isIncome(cat) ? guessIncome(note) : guessCategory(note)) != cat else { return }
        remember("note:" + k, Memo(c: cat, n: nil))
    }

    // MARK: Danh mục tự tạo

    /// Thêm danh mục mới, trả về mã để chọn luôn.
    @discardableResult
    /// income: danh mục tiền vào (mã "in-u-…")
    func addCategory(name: String, icon: String, tone: Int, income: Bool = false) -> String {
        let k = (income ? "in-u-" : "u-") + UUID().uuidString.prefix(8).lowercased()
        cats[k] = CustomCat(k: k, name: name, icon: icon, tone: tone, on: true, u: now)
        persist()
        return k
    }

    /// Sửa danh mục; danh mục có sẵn thì lưu thành bản chỉnh (đổi lại được về mặc định).
    func updateCategory(_ k: String, name: String, icon: String, tone: Int) {
        var c = cats[k] ?? CustomCat(k: k, name: name, icon: icon, tone: tone, on: true, u: now)
        c.name = name; c.icon = icon; c.tone = tone; c.on = true; c.touch(now)
        cats[k] = c
        persist()
    }

    /// Ô danh mục ở màn hình chính dài cả hàng hay nửa hàng
    func isWide(_ k: String) -> Bool { cats[k]?.wide == true }

    func setWide(_ k: String, _ wide: Bool) {
        let base = Category.get(k)
        var c = cats[k] ?? CustomCat(k: k, name: base.rawName, icon: base.icon, tone: -1, on: false, u: now)
        c.wide = wide; c.touch(now)
        cats[k] = c
        persist()
    }

    /// Danh mục có sẵn về lại tên, biểu tượng, màu gốc.
    func resetCategory(_ k: String) {
        guard var c = cats[k], c.on else { return }
        c.on = false; c.u = now
        cats[k] = c
        persist()
    }

    /// Xoá danh mục tự tạo: các khoản đã ghi hiện là "Khác"; khôi phục được bằng cách tạo lại cùng tên thì không, nên có Hoàn tác.
    func removeCategory(_ k: String) {
        guard !Category.isBuiltin(k), var c = cats[k], c.on else { return }
        c.on = false; c.touch(now)
        cats[k] = c
        persist()
        show(L("Đã xoá danh mục %@", c.name)) { [weak self] in
            guard let self, var c = self.cats[k] else { return }
            c.on = true; c.touch(self.now)
            self.cats[k] = c
            self.persist()
        }
    }

    // MARK: Khoản định kỳ

    /// Khoản định kỳ đang bật mà khoản chi này thuộc về: khoản app tự ghi, khoản gốc, hoặc khoản ghi tay giống hệt.
    func rule(for e: Expense) -> Rule? {
        let on = rules.values.filter(\.on)
        if on.isEmpty { return nil }
        if e.id.hasPrefix("r-"), let r = on.first(where: { e.id.hasPrefix("r-\($0.id)-") }) { return r }
        let k = Self.noteKey(e.n ?? ""), c = Category.get(e.c).k   // danh mục đã xoá tính là "Khác", như hasSame
        return on.first { $0.src == e.id } ?? on.first { $0.a == e.a && Category.get($0.c).k == c && Self.noteKey($0.n ?? "") == k }
    }

    /// "Lặp hằng tháng": cứ đến ngày đó (giờ đó) mỗi tháng, app tự ghi một khoản giống hệt.
    /// Bắt đầu từ lần tới hạn kế tiếp, không ghi bù các tháng trước.
    func repeatMonthly(_ e: Expense) {
        let cal = Calendar.current
        let c = cal.dateComponents([.day, .hour, .minute], from: e.date)
        var r = Rule(id: UUID().uuidString, a: e.a, n: e.n, c: e.c, day: c.day!, minute: c.hour! * 60 + c.minute!,
                     start: "", src: e.id, on: true, u: now, cr: e.isCredit ? true : nil)
        let thisMonth = cal.dateInterval(of: .month, for: Date())!.start
        let first = due(r, in: thisMonth) > Date() ? thisMonth : cal.date(byAdding: .month, value: 1, to: thisMonth)!
        r.start = Self.monthKey(first)
        rules[r.id] = r
        persist()
        let d = cal.dateComponents([.day, .month], from: due(r, in: first))
        show(L("Sẽ tự ghi ngày %1$ld hằng tháng, lần tới %2$ld/%3$ld", r.day, d.day!, d.month!))
    }

    /// Lúc tới hạn của khoản định kỳ trong tháng bắt đầu bằng `month`; tháng ngắn hơn thì ngày cuối tháng.
    private func due(_ r: Rule, in month: Date) -> Date {
        let cal = Calendar.current
        let last = cal.range(of: .day, in: .month, for: month)!.count
        let day = cal.date(byAdding: .day, value: min(r.day, last) - 1, to: month)!
        return cal.date(byAdding: .minute, value: r.minute, to: day)!
    }

    func stopRepeating(_ r: Rule) {
        var r = r
        r.on = false
        r.u = now
        rules[r.id] = r
        persist()
        show(L("Đã bỏ lặp %@", r.n?.isEmpty == false ? r.n! : Category.get(r.c).name)) { [weak self] in
            guard let self, var back = self.rules[r.id] else { return }
            back.on = true; back.u = self.now
            self.rules[r.id] = back
            self.persist()
        }
    }

    /// Ghi các kỳ đã tới hạn. Mã khoản cố định theo (khoản định kỳ, tháng) nên nhiều máy cùng ghi vẫn không trùng;
    /// kỳ đã xoá thì không ghi lại; tháng đã có khoản giống hệt (ghi tay, hoặc chính khoản gốc) thì bỏ qua.
    /// Trả về true khi có gì cần lưu (khoản mới ghi, hoặc kỳ vừa được đánh dấu bỏ qua).
    @discardableResult
    private func runRecurring() -> Bool {
        // Lặp hằng tháng là tính năng Pro: hết Pro (hết hạn, hoàn tiền) thì thôi tự ghi; khoản lặp vẫn giữ, có Pro lại thì ghi tiếp
        guard Pro.shared.active else { return false }
        let cal = Calendar.current, today = Date()
        var ids = Set(all.map(\.id))
        var changed = false
        for r in rules.values where r.on {
            let parts = r.start.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 2, var m = cal.date(from: DateComponents(year: parts[0], month: parts[1], day: 1)) else { continue }
            while m <= today {
                let id = "r-\(r.id)-\(Self.monthKey(m))"
                let at = due(r, in: m)
                if at <= today, !ids.contains(id), deleted[id] == nil {
                    if hasSame(r, inMonthOf: m) {
                        // Kỳ này đã có khoản ghi tay thay thế: ghi nhớ lại, nếu không về sau sửa / xoá khoản ghi tay đó
                        // là app ghi bù một khoản vào tháng cũ. Dấu 0 cũ hơn mọi khoản nên chỉ chặn việc tự ghi,
                        // không xoá khoản của kỳ này mà máy khác đã ghi (khi gộp, khoản đó thắng dấu này)
                        deleted[id] = 0
                    } else {
                        all.append(Expense(id: id, t: at.timeIntervalSince1970 * 1000, a: r.a, n: r.n, c: r.c, acct: nil, cr: r.cr))
                        ids.insert(id)
                        autoWritten.insert(id)
                    }
                    changed = true
                } else if ids.contains(id), deleted[id] == 0, hasSame(r, inMonthOf: m, except: id) {
                    // Máy này đã thấy kỳ này có khoản ghi tay thay thế (dấu 0), nhưng máy khác lỡ tự ghi trước khi đồng bộ: gộp về
                    // thì có cả hai, tháng đó tính hai lần. Bỏ khoản tự ghi, giữ khoản ghi tay
                    all.removeAll { $0.id == id }
                    ids.remove(id)
                    deleted[id] = now
                    changed = true
                }
                m = cal.date(byAdding: .month, value: 1, to: m)!
            }
        }
        return changed
    }

    /// Mở lại app (vd sáng ngày mùng 5): ghi các khoản định kỳ vừa tới hạn.
    func catchUpRecurring() {
        if runRecurring() { persist() }
    }

    private func hasSame(_ r: Rule, inMonthOf m: Date, except: String? = nil) -> Bool {
        let k = Self.noteKey(r.n ?? ""), c = Category.get(r.c).k   // danh mục đã xoá tính là "Khác", như mọi chỗ gộp theo danh mục
        let cal = Calendar.current
        return all.filter { $0.id != except && cal.isDate($0.date, equalTo: m, toGranularity: .month) }
            .contains { $0.a == r.a && Category.get($0.c).k == c && Self.noteKey($0.n ?? "") == k }
    }

    private func stamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

#if DEBUG
extension Store {
    /// Chi tiêu mẫu cố định cho phim giới thiệu: 5 tháng trước đủ các danh mục, tháng này tới hôm qua; hôm nay chưa ghi gì.
    static func filmSeed() -> [Expense] {
        var rng = SeedRandom(seed: 7)
        let cal = Calendar.current, now = Date()
        let today = cal.startOfDay(for: now)
        let daily: [(String, String, ClosedRange<Int>)] = [
            ("an", L("ăn trưa"), 45...45), ("cafe", L("cà phê"), 35...35), ("an", L("ăn sáng"), 30...30),
            ("di", "grab", 30...90), ("an", L("ăn tối"), 60...180), ("cafe", L("trà sữa"), 35...60), ("mua", L("đi chợ"), 120...380)]
        var out: [Expense] = []
        func add(_ d: Date, _ c: String, _ n: String, _ a: Int) {
            let t = d.timeIntervalSince1970 * 1000
            out.append(Expense(id: "seed-\(out.count)", t: t, a: a, n: n, c: c, acct: nil, u: t))
        }
        for back in stride(from: 160, through: 1, by: -1) {
            let day = cal.date(byAdding: .day, value: -back, to: today)!
            for (i, item) in daily.enumerated() where rng.next() % 100 < [85, 70, 40, 35, 30, 20, 18][i] {
                add(day.addingTimeInterval(Double(7 + i * 2) * 3600), item.0, item.1, Int(rng.next() % UInt64(item.2.count) + UInt64(item.2.lowerBound)) * 1000)
            }
            if cal.component(.day, from: day) == 5 {
                add(day.addingTimeInterval(9 * 3600), "hd", L("tiền nhà"), 3_500_000)
                add(day.addingTimeInterval(10 * 3600), "hd", L("điện nước"), Int(rng.next() % 300 + 450) * 1000)
                add(day.addingTimeInterval(11 * 3600), "hd", "internet", 220_000)
            }
            if rng.next() % 100 < 6 { add(day.addingTimeInterval(20 * 3600), "mua", "shopee", Int(rng.next() % 600 + 150) * 1000) }
        }
        return out.sorted { $0.t > $1.t }
    }
}

private struct SeedRandom {
    var seed: UInt64
    mutating func next() -> UInt64 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return seed >> 33 }
}
#endif
