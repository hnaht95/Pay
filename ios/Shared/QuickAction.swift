import AppIntents
import SwiftUI

/// Việc cần làm ngay khi app được mở từ widget, nút Tác vụ hoặc Phím tắt.
enum QuickKind: String {
    case scan, add

    init?(url: URL) {
        guard url.scheme == "sochipay", let k = url.host.flatMap(QuickKind.init(rawValue:)) else { return nil }
        self = k
    }

    var url: URL { URL(string: "sochipay://\(rawValue)")! }
}

@MainActor
final class QuickAction: ObservableObject {
    static let shared = QuickAction()
    @Published var pending: QuickKind?
}

/// Mở app và vào thẳng màn hình quét QR. Dùng cho nút Tác vụ, Trung tâm điều khiển, Phím tắt và Siri.
/// File này nằm ở cả app lẫn widget: hệ thống cần thấy intent ở cả hai thì nút trong Trung tâm điều khiển mới mở được app.
struct ScanIntent: AppIntent {
    static let title: LocalizedStringResource = "Quét QR"
    static let description = IntentDescription("Mở Pay và quét mã QR thanh toán ngay.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickAction.shared.pending = .scan
        return .result()
    }
}

struct AddIntent: AppIntent {
    static let title: LocalizedStringResource = "Ghi khoản chi"
    static let description = IntentDescription("Mở Pay và nhập ngay một khoản chi.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickAction.shared.pending = .add
        return .result()
    }
}
