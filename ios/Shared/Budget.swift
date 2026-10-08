import SwiftUI

/// Ngân sách tháng: còn bao nhiêu, đã dùng bao nhiêu phần, mỗi ngày còn tiêu được bao nhiêu.
struct BudgetStatus {
    let budget: Int
    let spent: Int

    enum Level { case ok, warn, over }

    var remaining: Int { budget - spent }
    var ratio: Double { budget > 0 ? Double(spent) / Double(budget) : 0 }
    var level: Level { ratio > 1 ? .over : ratio >= 0.8 ? .warn : .ok }

    /// Số còn lại chia cho số ngày còn lại trong tháng (tính cả hôm nay).
    func perDay(at date: Date) -> Int {
        let cal = Calendar.current
        let days = cal.range(of: .day, in: .month, for: date)!.count - cal.component(.day, from: date) + 1
        return max(remaining, 0) / max(days, 1) / 1000 * 1000   // làm tròn xuống hàng nghìn
    }

    var color: Color {
        switch level {
        case .ok: Color(red: 0.18, green: 0.62, blue: 0.32)
        case .warn: .orange
        case .over: Color(red: 0.85, green: 0.18, blue: 0.13)
        }
    }

    /// "Còn 1.200.000đ" hoặc "Vượt 300.000đ"
    var label: String { remaining >= 0 ? "Còn \(fmt(remaining))đ" : "Vượt \(fmt(-remaining))đ" }
}

/// Thanh tiến độ ngân sách.
struct BudgetBar: View {
    let s: BudgetStatus
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(s.color).frame(width: max(height, g.size.width * min(s.ratio, 1)))
            }
        }
        .frame(height: height)
    }
}
