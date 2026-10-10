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

    var date: Date { Date(timeIntervalSince1970: t / 1000) }
    var stamp: Double { u ?? t }
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

    /// tone < 0: giữ màu gốc của danh mục có sẵn
    var category: Category {
        if let base = Category.builtin.first(where: { $0.k == k }) {
            // Danh mục có sẵn đã chỉnh: giữ từ khoá gốc, thêm tên mới làm từ khoá
            let kw = base.kw + [Store.noteKey(name)].filter { !$0.isEmpty && !base.kw.contains($0) }
            var c = Category(k: k, icon: icon, name: name, color: tone < 0 ? base.color : CategoryTone.bg(tone),
                             art: base.art && icon == base.icon, kw: kw, customChart: tone < 0 ? nil : CategoryTone.chart(tone))
            c.onDark = CategoryTone.dark(tone)
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
        return "\(x.a)|\(x.c)|\(x.n ?? "")|\(x.acct ?? "")|\(x.t)" > "\(y.a)|\(y.c)|\(y.n ?? "")|\(y.acct ?? "")|\(y.t)"
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
    case on(last: Date?)     // đang đồng bộ; lần đọc/ghi gần nhất
}

extension String {
    /// Viết hoa chữ đầu để hiển thị ("cà phê" -> "Cà phê"); dữ liệu lưu giữ nguyên như người dùng nhập / nói
    var capFirst: String { prefix(1).uppercased() + dropFirst() }
}

struct Toast: Identifiable {
    let id = UUID()
    let message: String
    let undo: (() -> Void)?
}

@MainActor
final class Store: ObservableObject {
    /// Dùng chung cho app và lệnh Siri (Siri có thể ghi khi app chưa mở giao diện).
    static let shared = Store()

    @Published private(set) var items: [Expense] = []
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
    /// Danh mục tự tạo theo mã
    @Published private(set) var cats: [String: CustomCat] = [:] {
        didSet {
            let on = cats.values.filter(\.on)
            Category.custom = on.filter { !Category.isBuiltin($0.k) }.sorted { $0.u < $1.u }.map(\.category)
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
        if UserDefaults.standard.bool(forKey: "filmSeed") { items = Self.filmSeed(); cats = [:];
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
        guard cloudOn else { cloud.stop(); cloudState = .off; return }
        if cloud.active { return }
        cloudState = .connecting
        let ok = await cloud.start { [weak self] remote in self?.absorb(remote) }
        if !cloudOn { cloud.stop(); cloudState = .off; return }   // vừa tắt trong lúc đang kết nối
        cloudState = ok ? .on(last: nil) : .unavailable
    }

    /// Nút "Đồng bộ ngay": đẩy bản máy này lên rồi đọc lại bản trên iCloud.
    func syncNow() async {
        guard cloud.active else { await applyCloud(); return }
        cloud.push(snapshot)
        await cloud.pull()
    }

    private var snapshot: Backup { Backup(items: items, memo: memo, deleted: deleted, rules: rules, cats: cats) }
    private var now: Double { Date().timeIntervalSince1970 * 1000 }

    private func apply(_ b: Backup) {
        items = b.items
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
            if runRecurring() { merged = snapshot }   // khoản định kỳ máy khác vừa thêm
            writeLocal()
        }
        if !merged.same(as: remote) { cloud.push(merged) }
    }

    var bankApp: BankApp { BankData.apps.first { $0.id == appId } ?? BankData.apps[0] }
    var sorted: [Expense] { items.sorted { $0.t > $1.t } }

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
        Summary(today: total(on: now), month: monthItems(now).reduce(0) { $0 + $1.a }, count: count(on: now), day: now, budget: budget).save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// toast: false khi màn hình tự có nút Hoàn tác (thẻ giọng nói)
    func add(amount: Int, note: String, cat: String, acct: String? = nil, toast: Bool = true) {
        let e = Expense(id: UUID().uuidString, t: Date().timeIntervalSince1970 * 1000, a: amount, n: note, c: cat, acct: acct)
        items.append(e)
        persist()
        if toast { show(L("Đã lưu %@đ", fmt(amount))) { [weak self] in self?.remove(id: e.id, toast: false) } }
    }

    /// Ghi từ một câu "35k cafe": tự đoán danh mục theo ghi chú. Không đọc được số tiền thì nil.
    /// spoken: câu từ giọng nói, hiểu thêm số bằng chữ ("ba lăm nghìn") và số dưới 1.000 là nghìn.
    @discardableResult
    func quickAdd(_ text: String, spoken: Bool = false, toast: Bool = true) -> Expense? {
        guard let q = spoken ? (QuickParse.spoken(text) ?? QuickParse.expense(text)) : QuickParse.expense(text) else { return nil }
        add(amount: q.amount, note: q.note, cat: guessCategory(q.note), toast: toast)
        return items.last
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
        guard let i = items.firstIndex(where: { $0.id == e.id }) else { return }
        var e = e
        e.u = now
        items[i] = e
        persist()
    }

    func remove(id: String, toast: Bool = true) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        var e = items.remove(at: i)
        deleted[id] = now
        persist()
        if toast {
            show(L("Đã xoá")) { [weak self] in
                guard let self else { return }
                e.u = self.now
                self.deleted[id] = nil
                self.items.insert(e, at: min(i, self.items.count))
                self.persist()
            }
        }
    }

    /// Xoá mọi khoản chi (có dấu xoá nên các máy đồng bộ iCloud cũng xoá theo). Giữ ghi nhớ người nhận.
    func eraseAll() {
        let t = now
        for e in items { deleted[e.id] = t }
        items = []
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

    // MARK: Sao lưu

    func exportJSON() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pay-\(stamp()).json")
        guard let data = try? JSONEncoder().encode(Backup(items: items, memo: memo, rules: rules, cats: cats)), (try? data.write(to: url)) != nil else { return nil }
        return url
    }

    func exportCSV() -> URL? {
        let df = DateFormatter(); df.dateFormat = "dd/MM/yyyy"
        let tf = DateFormatter(); tf.dateFormat = "HH:mm"
        let q = { (s: String) in "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var rows = [[L("Ngày"), L("Giờ"), L("Số tiền"), L("Danh mục"), L("Ghi chú")].map(q).joined(separator: ",")]
        for e in items.sorted(by: { $0.t < $1.t }) {
            rows.append([df.string(from: e.date), tf.string(from: e.date), String(e.a), Category.get(e.c).name, e.n ?? ""].map(q).joined(separator: ","))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pay-\(stamp()).csv")
        guard (try? ("\u{FEFF}" + rows.joined(separator: "\n")).write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        return url
    }

    func importBackup(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let b = try? JSONDecoder().decode(Backup.self, from: data) else {
            show(L("File sao lưu không hợp lệ")); return
        }
        let ids = Set(items.map(\.id))
        let t = now
        // Khoản được khôi phục mang dấu sửa mới và bỏ dấu xoá cũ (vd sau "Xoá tất cả"),
        // nếu không lần gộp iCloud kế tiếp sẽ xoá chúng lần nữa
        let add = b.items.filter { !ids.contains($0.id) && $0.a > 0 }.map { e -> Expense in
            var e = e
            e.u = t
            return e
        }
        for e in add { deleted[e.id] = nil }
        items += add
        memo = (b.memo ?? [:]).merging(memo) { _, mine in mine }
        // Khoản định kỳ trong file: thêm cái còn thiếu, bật lại cái đã bỏ (như khoản chi đã xoá cũng được khôi phục)
        for (k, var r) in b.rules ?? [:] where r.on && rules[k]?.on != true {
            r.u = t
            rules[k] = r
        }
        for (k, c) in b.cats ?? [:] where c.on && cats[k]?.on != true { var c = c; c.u = t; cats[k] = c }
        runRecurring()
        persist()
        show(L("Đã khôi phục %ld khoản", add.count))
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
        if let c = memo["note:" + k]?.c { return c }
        // Ghi chú dài hơn có chứa tên đã học: "phuc long sang nay" dùng danh mục đã học cho "phuc long"
        let padded = " \(k) "
        let hit = memo.keys.filter { $0.hasPrefix("note:") && padded.contains(" \($0.dropFirst(5)) ") }.max { $0.count < $1.count }
        return hit.flatMap { memo[$0]?.c } ?? Category.guess(note)
    }

    /// Nhớ danh mục đã tự chọn cho ghi chú này, chỉ khi khác với cách app đang đoán (đồng bộ iCloud cùng ghi nhớ người nhận).
    func learnCategory(_ note: String, _ cat: String) {
        let k = Self.noteKey(note)
        guard !k.isEmpty, guessCategory(note) != cat else { return }
        remember("note:" + k, Memo(c: cat, n: nil))
    }

    // MARK: Danh mục tự tạo

    /// Thêm danh mục mới, trả về mã để chọn luôn.
    @discardableResult
    func addCategory(name: String, icon: String, tone: Int) -> String {
        let k = "u-" + UUID().uuidString.prefix(8).lowercased()
        cats[k] = CustomCat(k: k, name: name, icon: icon, tone: tone, on: true, u: now)
        persist()
        return k
    }

    /// Sửa danh mục; danh mục có sẵn thì lưu thành bản chỉnh (đổi lại được về mặc định).
    func updateCategory(_ k: String, name: String, icon: String, tone: Int) {
        var c = cats[k] ?? CustomCat(k: k, name: name, icon: icon, tone: tone, on: true, u: now)
        c.name = name; c.icon = icon; c.tone = tone; c.on = true; c.u = now
        cats[k] = c
        persist()
    }

    /// Ô danh mục ở màn hình chính dài cả hàng hay nửa hàng
    func isWide(_ k: String) -> Bool { cats[k]?.wide == true }

    func setWide(_ k: String, _ wide: Bool) {
        let base = Category.get(k)
        var c = cats[k] ?? CustomCat(k: k, name: base.rawName, icon: base.icon, tone: -1, on: false, u: now)
        c.wide = wide; c.u = now
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
        c.on = false; c.u = now
        cats[k] = c
        persist()
        show(L("Đã xoá danh mục %@", c.name)) { [weak self] in
            guard let self, var c = self.cats[k] else { return }
            c.on = true; c.u = self.now
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
        let k = Self.noteKey(e.n ?? "")
        return on.first { $0.src == e.id } ?? on.first { $0.a == e.a && $0.c == e.c && Self.noteKey($0.n ?? "") == k }
    }

    /// "Lặp hằng tháng": cứ đến ngày đó (giờ đó) mỗi tháng, app tự ghi một khoản giống hệt.
    /// Bắt đầu từ lần tới hạn kế tiếp, không ghi bù các tháng trước.
    func repeatMonthly(_ e: Expense) {
        let cal = Calendar.current
        let c = cal.dateComponents([.day, .hour, .minute], from: e.date)
        var r = Rule(id: UUID().uuidString, a: e.a, n: e.n, c: e.c, day: c.day!, minute: c.hour! * 60 + c.minute!,
                     start: "", src: e.id, on: true, u: now)
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
        show(L("Đã bỏ lặp %@", r.n?.isEmpty == false ? r.n! : Category.get(r.c).name))
    }

    /// Ghi các kỳ đã tới hạn. Mã khoản cố định theo (khoản định kỳ, tháng) nên nhiều máy cùng ghi vẫn không trùng;
    /// kỳ đã xoá thì không ghi lại; tháng đã có khoản giống hệt (ghi tay, hoặc chính khoản gốc) thì bỏ qua.
    @discardableResult
    private func runRecurring() -> Bool {
        let cal = Calendar.current, today = Date()
        var ids = Set(items.map(\.id))
        var added = false
        for r in rules.values where r.on {
            let parts = r.start.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 2, var m = cal.date(from: DateComponents(year: parts[0], month: parts[1], day: 1)) else { continue }
            while m <= today {
                let id = "r-\(r.id)-\(Self.monthKey(m))"
                let at = due(r, in: m)
                if at <= today, !ids.contains(id), deleted[id] == nil, !hasSame(r, inMonthOf: m) {
                    items.append(Expense(id: id, t: at.timeIntervalSince1970 * 1000, a: r.a, n: r.n, c: r.c, acct: nil))
                    ids.insert(id)
                    added = true
                }
                m = cal.date(byAdding: .month, value: 1, to: m)!
            }
        }
        return added
    }

    /// Mở lại app (vd sáng ngày mùng 5): ghi các khoản định kỳ vừa tới hạn.
    func catchUpRecurring() {
        if runRecurring() { persist() }
    }

    private func hasSame(_ r: Rule, inMonthOf m: Date) -> Bool {
        let k = Self.noteKey(r.n ?? "")
        return monthItems(m).contains { $0.a == r.a && $0.c == r.c && Self.noteKey($0.n ?? "") == k }
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
