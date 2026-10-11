import Foundation
import UserNotifications

/// Nhắc ghi chi tiêu mỗi tối: tới giờ đã chọn mà hôm ấy chưa ghi khoản nào thì báo một câu.
///
/// Thông báo cục bộ không biết được "hôm nay đã ghi chưa" lúc nó nổ, nên đặt sẵn cho 7 ngày tới rồi đặt lại mỗi khi dữ liệu đổi
/// (thêm / xoá / đồng bộ, kể cả ghi qua Siri hay Phím tắt — đều chạy trong app): hôm nay đã có khoản thì bỏ lịch của hôm nay.
enum DailyReminder {
    private static let onKey = "remindOn", minuteKey = "remindMinute"
    private static let prefix = "remind-"

    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: onKey) }
        set { UserDefaults.standard.set(newValue, forKey: onKey) }
    }

    /// Giờ nhắc, tính bằng phút trong ngày (mặc định 21:00)
    static var minute: Int {
        get { UserDefaults.standard.object(forKey: minuteKey) as? Int ?? 21 * 60 }
        set { UserDefaults.standard.set(newValue, forKey: minuteKey) }
    }

    /// Xin quyền thông báo khi bật; từ chối thì tắt lại
    @MainActor
    static func enable(_ on: Bool, store: Store) async {
        if on {
            let ok = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
            isOn = ok
        } else {
            isOn = false
        }
        reschedule(loggedToday: store.count(on: Date()) > 0)
    }

    static func reschedule(loggedToday: Bool) {
        let center = UNUserNotificationCenter.current()
        let ids = (0..<8).map { prefix + String($0) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard isOn else { return }
        let cal = Calendar.current, now = Date()
        for d in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: d, to: cal.startOfDay(for: now)),
                  let at = cal.date(byAdding: .minute, value: minute, to: day), at > now else { continue }
            if d == 0 && loggedToday { continue }
            let c = UNMutableNotificationContent()
            c.title = L("Hôm nay chi gì chưa?")
            c.body = L("Chưa ghi khoản nào hôm nay. Nói một câu hoặc nhập nhanh để không quên.")
            c.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: at)
            center.add(UNNotificationRequest(identifier: prefix + String(d), content: c,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }
}
