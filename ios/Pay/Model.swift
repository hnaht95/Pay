import Foundation
import SwiftUI

/// Một khoản chi. Cùng định dạng với file sao lưu của bản web (t = mili giây).
struct Expense: Codable, Identifiable, Equatable {
    var id: String
    var t: Double
    var a: Int
    var n: String?
    var c: String
    var acct: String?

    var date: Date { Date(timeIntervalSince1970: t / 1000) }
}

/// Ghi nhớ theo số tài khoản để lần sau quét lại tự điền tên + danh mục.
struct Memo: Codable, Equatable {
    var c: String?
    var n: String?
}

struct Backup: Codable {
    var items: [Expense]
    var memo: [String: Memo]?
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

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pay.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fileURL), let b = try? JSONDecoder().decode(Backup.self, from: data) {
            items = b.items
            memo = b.memo ?? [:]
        }
    }

    var bankApp: BankApp { BankData.apps.first { $0.id == appId } ?? BankData.apps[0] }
    var sorted: [Expense] { items.sorted { $0.t > $1.t } }

    private func persist() {
        guard let data = try? JSONEncoder().encode(Backup(items: items, memo: memo)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func add(amount: Int, note: String, cat: String, acct: String? = nil) {
        let e = Expense(id: UUID().uuidString, t: Date().timeIntervalSince1970 * 1000, a: amount, n: note, c: cat, acct: acct)
        items.append(e)
        persist()
        show("Đã lưu \(fmt(amount))đ") { [weak self] in self?.remove(id: e.id, toast: false) }
    }

    func update(_ e: Expense) {
        guard let i = items.firstIndex(where: { $0.id == e.id }) else { return }
        items[i] = e
        persist()
    }

    func remove(id: String, toast: Bool = true) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let e = items.remove(at: i)
        persist()
        if toast {
            show("Đã xoá") { [weak self] in
                guard let self else { return }
                self.items.insert(e, at: min(i, self.items.count))
                self.persist()
            }
        }
    }

    func remember(_ key: String, _ m: Memo) {
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

/// 45000 -> "45.000"
func fmt(_ n: Int) -> String {
    let s = String(abs(n))
    var out = ""
    for (i, ch) in s.enumerated() {
        if i > 0 && (s.count - i) % 3 == 0 { out += "." }
        out.append(ch)
    }
    return (n < 0 ? "-" : "") + out
}
