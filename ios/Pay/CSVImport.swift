import SwiftUI
import UniformTypeIdentifiers

/// Nhập khoản chi / thu từ file CSV: file CSV do Pay xuất ra, hoặc của app khác (Money Lover, Wallet, YNAB…) và bảng Excel tự làm.
/// Tự đoán cột theo tên tiêu đề (ngày, giờ, số tiền, thu / chi, loại, danh mục, ghi chú), đọc nhiều kiểu ngày và kiểu số,
/// bỏ qua khoản đã có (cùng ngày, cùng số tiền, cùng ghi chú). Xem trước rồi mới nhập
struct CSVImport {
    /// Kết quả đọc file: các khoản đọc được (chưa có trong app), số dòng trùng và số dòng không đọc được
    struct Result: Identifiable {
        let id = UUID()
        let name: String
        let items: [Expense]
        let duplicates: Int
        let skipped: Int
        var spends: Int { items.filter { !$0.isIncome }.count }
        var incomes: Int { items.filter(\.isIncome).count }
    }

    enum Failure: Error { case unreadable, noColumns }

    // MARK: Đọc file

    @MainActor
    static func read(_ url: URL, store: Store) -> Swift.Result<Result, Failure> {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? String(data: data, encoding: .windowsCP1252)
        else { return .failure(.unreadable) }
        let rows = parse(text)
        guard let header = rows.first, rows.count > 1 else { return .failure(.noColumns) }
        let cols = Columns(header)
        guard cols.date != nil, cols.amount != nil || cols.inflow != nil || cols.outflow != nil else { return .failure(.noColumns) }

        // Không có cột thu / chi: số âm là chi, số dương là thu — chỉ khi file có cả âm lẫn dương (Money Lover);
        // toàn số dương thì đều là khoản chi
        let body = rows.dropFirst().filter { $0.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        let signed = cols.kind == nil && cols.amount != nil
            && body.contains { (amount(cols.value($0, cols.amount)) ?? 0) < 0 }
            && body.contains { (amount(cols.value($0, cols.amount)) ?? 0) > 0 }

        let cal = Calendar.current
        // Khoản đã có: theo ngày + số tiền + ghi chú + thu / chi
        func key(_ d: Date, _ a: Int, _ n: String, _ inc: Bool) -> String {
            "\(cal.startOfDay(for: d).timeIntervalSince1970)|\(a)|\(Store.noteKey(n))|\(inc)"
        }
        var seen = Set(store.all.filter { !$0.isAdjust }.map { key($0.date, $0.a, $0.n ?? "", $0.isIncome) })
        var out: [Expense] = [], dup = 0, bad = 0
        let now = Date().timeIntervalSince1970 * 1000
        for row in body {
            guard let date = date(cols.value(row, cols.date), time: cols.value(row, cols.time)) else { bad += 1; continue }
            // Số tiền và thu / chi
            var value: Int?, income = false
            if let raw = amount(cols.value(row, cols.amount)) {
                value = abs(raw)
                if let k = kind(cols.value(row, cols.kind)) {
                    if k == .skip { bad += 1; continue }
                    income = k == .income
                } else {
                    income = signed && raw > 0
                }
            } else {
                // Hai cột riêng: tiền vào / tiền ra (YNAB Inflow / Outflow)
                let i = amount(cols.value(row, cols.inflow)).map(abs) ?? 0, o = amount(cols.value(row, cols.outflow)).map(abs) ?? 0
                if i > 0 { value = i; income = true } else if o > 0 { value = o }
            }
            guard let a = value, a > 0 else { bad += 1; continue }
            let note = cols.value(row, cols.note).trimmingCharacters(in: .whitespaces)
            let catName = cols.value(row, cols.category).trimmingCharacters(in: .whitespaces)
            let k = key(date, a, note, income)
            if seen.contains(k) { dup += 1; continue }
            seen.insert(k)
            let c = category(catName, note: note, income: income, store: store)
            // Ghi chú trống: lấy tên danh mục trong file làm ghi chú (danh mục lạ không mất thông tin)
            let n = note.isEmpty && !catName.isEmpty && strip(Category.get(c).name) != strip(catName) ? catName : note
            let t = date.timeIntervalSince1970 * 1000
            out.append(Expense(id: UUID().uuidString, t: t, a: a, n: n.isEmpty ? nil : n, c: c, acct: nil, u: now))
        }
        out.sort { $0.t > $1.t }
        return .success(Result(name: url.deletingPathExtension().lastPathComponent, items: out, duplicates: dup, skipped: bad))
    }

    // MARK: Cột

    /// Vị trí các cột, đoán theo chữ tiêu đề (bỏ dấu, chữ thường)
    struct Columns {
        var date, time, amount, inflow, outflow, kind, category, note: Int?

        init(_ header: [String]) {
            let h = header.map { strip($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            func find(_ names: [String], exact: Bool = false) -> Int? {
                for n in names {
                    if let i = h.firstIndex(where: { $0 == n }) { return i }
                }
                guard !exact else { return nil }
                for n in names {
                    if let i = h.firstIndex(where: { $0.contains(n) }) { return i }
                }
                return nil
            }
            date = find(["ngay", "date", "ngay giao dich", "transaction date", "thoi gian", "datetime"])
            time = find(["gio", "time"], exact: true)
            if time == date { time = nil }
            amount = find(["so tien", "amount", "gia tri", "money", "value", "tien", "sum"])
            inflow = find(["inflow", "tien vao", "income", "credit", "co"], exact: true)
            outflow = find(["outflow", "tien ra", "expense", "debit", "no"], exact: true)
            kind = find(["loai", "type", "thu chi", "thu/chi", "kind"], exact: true)
            category = find(["danh muc", "category", "nhom", "hang muc", "category name"])
            note = find(["ghi chu", "note", "mo ta", "description", "memo", "dien giai", "noi dung", "payee", "ten"])
            if note == category { note = nil }
        }

        func value(_ row: [String], _ i: Int?) -> String {
            guard let i, i < row.count else { return "" }
            return row[i]
        }
    }

    // MARK: Ô dữ liệu

    enum Kind { case income, spend, skip }

    /// "Thu" / "Income" / "Vào" là khoản thu; "Chi" / "Expense" là khoản chi; "Điều chỉnh" / "Transfer" bỏ qua
    static func kind(_ s: String) -> Kind? {
        let k = strip(s).trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return nil }
        if ["thu", "income", "vao", "in", "tien vao", "khoan thu", "credit"].contains(k) || k.hasPrefix("thu ") { return .income }
        if ["chi", "expense", "ra", "out", "tien ra", "khoan chi", "debit"].contains(k) || k.hasPrefix("chi ") { return .spend }
        if k.contains("dieu chinh") || k.contains("transfer") || k.contains("chuyen vi") { return .skip }
        return nil
    }

    /// Số tiền: "1.234.567", "1,234,567", "-50,000 ₫", "(50.000)", "50000.00", "35k", "1tr2"
    static func amount(_ s: String) -> Int? {
        var t = s.lowercased().trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let negative = t.hasPrefix("-") || t.hasPrefix("−") || (t.hasPrefix("(") && t.hasSuffix(")"))
        // Viết tắt kiểu nói: 35k, 1tr2
        if t.range(of: #"^[\d.,]+\s*(k|tr|trieu|m)\s*\d*$"#, options: .regularExpression) != nil, let q = QuickParse.expense(t) {
            return negative ? -q.amount : q.amount
        }
        t = String(t.filter { $0.isNumber || $0 == "." || $0 == "," })
        guard !t.isEmpty else { return nil }
        // Dấu ngăn cuối cùng: theo sau đúng 3 chữ số là ngăn hàng nghìn, 1–2 chữ số là phần lẻ (bỏ đi)
        if let last = t.lastIndex(where: { $0 == "." || $0 == "," }) {
            let tail = t[t.index(after: last)...]
            if tail.count != 3 { t = String(t[..<last]) }
        }
        guard let v = Int(t.filter(\.isNumber)) else { return nil }
        return negative ? -v : v
    }

    /// Ngày (và giờ nếu có): dd/MM/yyyy (kiểu Việt), yyyy-MM-dd, cả kiểu có giờ đi kèm; giờ ở cột riêng thì ghép vào
    static func date(_ s: String, time: String) -> Date? {
        let d = s.trimmingCharacters(in: .whitespaces)
        guard !d.isEmpty else { return nil }
        let full = time.trimmingCharacters(in: .whitespaces).isEmpty ? d : d + " " + time.trimmingCharacters(in: .whitespaces)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        for p in ["dd/MM/yyyy HH:mm:ss", "dd/MM/yyyy HH:mm", "d/M/yyyy HH:mm", "dd/MM/yyyy", "d/M/yyyy", "dd-MM-yyyy HH:mm", "dd-MM-yyyy",
                  "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd", "yyyy/MM/dd",
                  "dd/MM/yy", "d/M/yy", "MMM d, yyyy", "d MMM yyyy"] {
            f.dateFormat = p
            if let r = f.date(from: full) ?? f.date(from: d) {
                // Chỉ có ngày: đặt 12:00 để đổi múi giờ không nhảy sang ngày bên cạnh
                if !p.contains("HH") && full == d { return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: r) }
                return r
            }
        }
        return nil
    }

    /// Danh mục: trùng tên danh mục đang có (cùng loại thu / chi) thì dùng luôn; không thì đoán theo tên danh mục trong file
    /// rồi theo ghi chú như khi nhập tay; vẫn không ra thì "Khác"
    @MainActor
    static func category(_ name: String, note: String, income: Bool, store: Store) -> String {
        let n = strip(name)
        let list = income ? Category.income : Category.all
        // Tên danh mục (hoặc cả ghi chú) trùng tên danh mục đang có
        for t in [n, strip(note)] where !t.isEmpty {
            if let c = list.first(where: { strip($0.name) == t || strip($0.rawName) == t }) { return c.k }
        }
        if income {
            return Category.guessIncome(name) ?? store.guessIncome(note)
        }
        let byName = Category.guess(name)
        return byName != "khac" ? byName : store.guessCategory(note)
    }

    // MARK: Tách CSV

    /// Tách dòng / ô theo chuẩn CSV (ô trong ngoặc kép có dấu phẩy, xuống dòng, "" là một dấu ngoặc kép).
    /// Tự nhận dấu ngăn: phẩy, chấm phẩy (Excel bản tiếng Việt) hoặc tab
    static func parse(_ raw: String) -> [[String]] {
        let text = raw.hasPrefix("\u{FEFF}") ? String(raw.dropFirst()) : raw
        let firstLine = text.prefix { $0 != "\n" && $0 != "\r" }
        let sep: Character = [";", "\t", ","].max { a, b in firstLine.filter { $0 == a }.count < firstLine.filter { $0 == b }.count } ?? ","
        var rows: [[String]] = [], row: [String] = [], cell = "", quoted = false
        var it = text.makeIterator()
        var pending: Character? = nil
        while let ch = pending ?? it.next() {
            pending = nil
            if quoted {
                if ch == "\"" {
                    if let next = it.next() {
                        if next == "\"" { cell.append("\"") } else { quoted = false; pending = next }
                    } else { quoted = false }
                } else { cell.append(ch) }
            } else if ch == "\"" {
                quoted = true
            } else if ch == sep {
                row.append(cell); cell = ""
            } else if ch == "\n" || ch == "\r" || ch == "\r\n" {
                row.append(cell); cell = ""
                if row.count > 1 || !(row.first ?? "").isEmpty { rows.append(row) }
                row = []
            } else {
                cell.append(ch)
            }
        }
        row.append(cell)
        if row.count > 1 || !(row.first ?? "").isEmpty { rows.append(row) }
        return rows
    }
}

/// Xem trước trước khi nhập: số khoản chi / thu đọc được, số dòng trùng / không đọc được, vài khoản đầu
struct CSVImportSheet: View {
    let result: CSVImport.Result
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Nhập từ CSV")).font(.system(size: 21, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 46).padding(.top, 8)
            Text(result.name).font(.system(size: 15)).foregroundStyle(.secondary)
                .lineLimit(1).frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 6) {
                Text(L("%ld khoản chi · %ld khoản thu", result.spends, result.incomes)).font(.system(size: 17, weight: .semibold))
                if let range { Text(range).font(.system(size: 15)).foregroundStyle(.secondary) }
                if result.duplicates > 0 { Text(L("%ld khoản đã có, bỏ qua", result.duplicates)).font(.system(size: 15)).foregroundStyle(.secondary) }
                if result.skipped > 0 { Text(L("%ld dòng không đọc được", result.skipped)).font(.system(size: 15)).foregroundStyle(.secondary) }
            }
            .padding(.top, 20)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(result.items.prefix(30)) { ExpenseRow(e: $0, showDay: true) }
                    if result.items.count > 30 {
                        Text(L("và %ld khoản khác", result.items.count - 30)).font(.system(size: 15)).foregroundStyle(.secondary).padding(.top, 4)
                    }
                }
                .padding(.vertical, 16)
            }
            HStack(spacing: 12) {
                BigButton(title: L("Huỷ"), icon: "", primary: false, tint: BigButton.cancelTint) { dismiss() }
                BigButton(title: result.items.isEmpty ? L("Không có gì để nhập") : L("Nhập %ld khoản", result.items.count), icon: "", primary: true) {
                    guard !result.items.isEmpty else { return }
                    store.importItems(result.items)
                    dismiss()
                }
                .opacity(result.items.isEmpty ? 0.55 : 1)
            }
            .padding(.bottom, -18)
        }
        .padding(.horizontal, 16)
        .background(Palette.surface.ignoresSafeArea())
    }

    /// "Từ 15/7/2026 đến 13/10/2026"
    private var range: String? {
        guard let first = result.items.last?.date, let last = result.items.first?.date else { return nil }
        let f = DateFormatter(); f.dateFormat = "d/M/yyyy"
        if Lang.isEnglish { f.locale = Lang.locale; f.dateFormat = "MMM d, yyyy" }
        return L("Từ %1$@ đến %2$@", f.string(from: first), f.string(from: last))
    }
}
