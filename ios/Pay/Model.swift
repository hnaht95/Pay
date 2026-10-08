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

struct Backup: Codable {
    var items: [Expense]
    var memo: [String: Memo]?
    var deleted: [String: Double]? = nil   // id -> lúc xoá (ms), để xoá cũng đồng bộ sang máy khác

    func same(as o: Backup) -> Bool {
        Set(items) == Set(o.items) && (memo ?? [:]) == (o.memo ?? [:]) && (deleted ?? [:]) == (o.deleted ?? [:])
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
        return Backup(items: items, memo: memo, deleted: deleted)
    }

    private static func wins(_ x: Expense, over y: Expense) -> Bool {
        if x.stamp != y.stamp { return x.stamp > y.stamp }
        return "\(x.a)|\(x.c)|\(x.n ?? "")|\(x.acct ?? "")|\(x.t)" > "\(y.a)|\(y.c)|\(y.n ?? "")|\(y.acct ?? "")|\(y.t)"
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

struct Toast: Identifiable {
    let id = UUID()
    let message: String
    let undo: (() -> Void)?
}

@MainActor
final class Store: ObservableObject {
    @Published private(set) var items: [Expense] = []
    @Published var memo: [String: Memo] = [:]
    @Published var appId: String = UserDefaults.standard.string(forKey: "bankApp") ?? "acb" {
        didSet { UserDefaults.standard.set(appId, forKey: "bankApp") }
    }
    @Published var toast: Toast?
    private var deleted: [String: Double] = [:]
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

    private var snapshot: Backup { Backup(items: items, memo: memo, deleted: deleted) }
    private var now: Double { Date().timeIntervalSince1970 * 1000 }

    private func apply(_ b: Backup) {
        items = b.items
        memo = b.memo ?? [:]
        deleted = b.deleted ?? [:]
    }

    /// Có bản mới trên iCloud (từ máy khác): gộp vào máy này, máy này có gì mới hơn thì đẩy ngược lên.
    private func absorb(_ remote: Backup?) {
        guard let remote else { cloud.push(snapshot); return }
        let merged = Backup.merge(snapshot, remote)
        if !merged.same(as: snapshot) { apply(merged); writeLocal() }
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
        Summary(today: total(on: now), month: monthItems(now).reduce(0) { $0 + $1.a }, count: count(on: now), day: now).save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func add(amount: Int, note: String, cat: String, acct: String? = nil) {
        let e = Expense(id: UUID().uuidString, t: Date().timeIntervalSince1970 * 1000, a: amount, n: note, c: cat, acct: acct)
        items.append(e)
        persist()
        show("Đã lưu \(fmt(amount))đ") { [weak self] in self?.remove(id: e.id, toast: false) }
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
            show("Đã xoá") { [weak self] in
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
        persist()
        show("Đã xoá tất cả khoản chi")
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
        guard let data = try? JSONEncoder().encode(Backup(items: items, memo: memo)), (try? data.write(to: url)) != nil else { return nil }
        return url
    }

    func exportCSV() -> URL? {
        let df = DateFormatter(); df.dateFormat = "dd/MM/yyyy"
        let tf = DateFormatter(); tf.dateFormat = "HH:mm"
        let q = { (s: String) in "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var rows = [["Ngày", "Giờ", "Số tiền", "Danh mục", "Ghi chú"].map(q).joined(separator: ",")]
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
            show("File sao lưu không hợp lệ"); return
        }
        let ids = Set(items.map(\.id))
        let add = b.items.filter { !ids.contains($0.id) && $0.a > 0 }
        items += add
        memo = (b.memo ?? [:]).merging(memo) { _, mine in mine }
        persist()
        show("Đã khôi phục \(add.count) khoản")
    }

    private func stamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
