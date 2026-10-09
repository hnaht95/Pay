import Foundation

/// Số liệu app ghi ra cho widget đọc (qua App Group, vì widget chạy riêng, không đọc được file của app).
struct Summary: Codable {
    var today: Int
    var month: Int
    var count: Int
    var day: Date   // ngày tính số liệu, để widget tự về 0 khi sang ngày/tháng mới
    var budget: Int? = nil   // ngân sách tháng, nil/0 = không đặt

    var budgetStatus: BudgetStatus? { (budget ?? 0) > 0 ? BudgetStatus(budget: budget!, spent: month) : nil }

    static let group = "group.com.hnaht95.sochipay"
    private static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("summary.json")
    }

    static func load() -> Summary {
        guard let url, let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Summary.self, from: d) else {
            return Summary(today: 0, month: 0, count: 0, day: Date())
        }
        return s
    }

    func save() {
        guard let url = Summary.url, let d = try? JSONEncoder().encode(self) else { return }
        try? d.write(to: url, options: .atomic)
    }

    /// Số liệu như nhìn vào lúc `date`: qua ngày thì hôm nay = 0, qua tháng thì cả tháng = 0.
    func at(_ date: Date) -> Summary {
        let cal = Calendar.current
        if cal.isDate(day, inSameDayAs: date) { return self }
        let sameMonth = cal.isDate(day, equalTo: date, toGranularity: .month)
        return Summary(today: 0, month: sameMonth ? month : 0, count: 0, day: date, budget: budget)
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
