import LocalAuthentication
import SwiftUI

/// Khoá app bằng Face ID / Touch ID (không có thì mật mã máy). Bật trong Cài đặt › Bảo mật.
/// Màn khoá là một cửa sổ riêng nằm trên mọi thứ (cả các tấm và màn toàn phần như camera), nên che được hết.
/// - Rời app (vào nền): khoá; quay lại thì hỏi Face ID.
/// - Kéo Trung tâm điều khiển / xem màn đa nhiệm (app chưa vào nền): chỉ che nội dung, quay lại không phải mở khoá.
@MainActor
final class AppLock: ObservableObject {
    static let shared = AppLock()
    static let key = "appLock"

    var enabled: Bool { UserDefaults.standard.bool(forKey: Self.key) }
    /// Đã vào nền: lần quay lại phải mở khoá (không chỉ bỏ lớp che)
    @Published private(set) var needsAuth = false
    /// Đã hỏi Face ID mà không mở được (huỷ, sai): lúc đó mới hiện chữ "đang khoá" và nút mở khoá. Bình thường màn khoá chỉ là
    /// nền trơn có logo, hộp Face ID bật lên ngay trên đó, nhận mặt xong là vào thẳng app
    @Published private(set) var failed = false
    private var window: UIWindow?
    private var authenticating = false

    /// Tên phương thức của máy: "Face ID", "Touch ID", hoặc "mật mã" khi máy không có sinh trắc học
    static var methodName: String {
        let c = LAContext()
        _ = c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch c.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return L("mật mã")
        }
    }

    /// Máy có đặt mật mã (điều kiện tối thiểu để khoá)
    static var available: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }

    /// Mở app lần đầu: khoá luôn
    func launch() {
        #if DEBUG
        // "-lockPreview YES": chỉ hiện lớp che (không hỏi Face ID) để xem trên máy ảo, nơi màn nhập mật mã che kín cả màn
        if UserDefaults.standard.bool(forKey: "lockPreview") {
            Task { try? await Task.sleep(for: .seconds(1.5)); show() }
            return
        }
        #endif
        guard enabled else { return }
        needsAuth = true
        failed = false
        show()
    }

    func phaseChanged(_ p: ScenePhase) {
        guard enabled else { hide(); return }
        switch p {
        case .background:
            needsAuth = true
            failed = false
            show()
        case .inactive:
            show()   // che khi ở màn đa nhiệm; hộp Face ID cũng làm app sang inactive: đã che sẵn nên không sao
        case .active:
            if needsAuth { Task { await unlock() } } else if !authenticating { hide() }
        @unknown default: break
        }
    }

    /// Hỏi Face ID. Thành công thì bỏ màn khoá; huỷ thì giữ màn khoá với nút Mở khoá
    func unlock() async {
        guard !authenticating else { return }
        authenticating = true
        defer { authenticating = false }
        let ok = (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: L("Mở khoá Payso"))) ?? false
        failed = !ok
        if ok { needsAuth = false; hide() }
    }

    /// Bật khoá trong Cài đặt: hỏi Face ID một lần để chắc người bật là chủ máy và máy dùng được
    func enable() async -> Bool {
        guard Self.available else { return false }
        let ok = (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: L("Bật khoá Payso"))) ?? false
        if ok { UserDefaults.standard.set(true, forKey: Self.key) }
        return ok
    }

    func disable() {
        UserDefaults.standard.set(false, forKey: Self.key)
        needsAuth = false
        hide()
    }

    private func show() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        let host = UIHostingController(rootView: AppLockView().environmentObject(self))
        host.view.backgroundColor = .clear
        w.rootViewController = host
        w.isHidden = false
        window = w
    }

    private func hide() {
        window?.isHidden = true
        window = nil
    }
}

/// Màn khoá: làm mờ đậm nội dung app phía sau (nhìn ra màn mình đang dùng nhưng không đọc được số), hộp Face ID của iOS
/// bật lên ngay trên đó. Chỉ khi Face ID không mở được (huỷ, sai) mới hiện chữ "đang khoá" và nút mở khoá để thử lại
private struct AppLockView: View {
    @EnvironmentObject var lock: AppLock

    var body: some View {
        ZStack {
            LockBlur().ignoresSafeArea()
            if lock.needsAuth && lock.failed {
                VStack(spacing: 14) {
                    Spacer().frame(maxHeight: 160)
                    Image(systemName: "lock.fill").font(.system(size: 28, weight: .semibold))
                    Text(L("Payso đang khoá")).font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Button { Task { await lock.unlock() } } label: {
                        Label(L("Mở khoá bằng %@", AppLock.methodName), systemImage: "faceid")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .foregroundStyle(Palette.ctaInk)
                            .background(Palette.cta, in: Capsule())
                    }
                    .buttonStyle(Pressable())
                    .padding(.horizontal, 16).padding(.bottom, 8)
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// Lớp mờ vừa phải: vẫn thấy hình các khối phía sau (thẻ, ô danh mục, nút) nhưng chữ và số không đọc được.
/// Độ mờ của UIBlurEffect cố định (rất đậm): chạy hiệu ứng làm mờ bằng UIViewPropertyAnimator rồi dừng ở `amount` để lấy mức nhẹ hơn
private struct LockBlur: UIViewRepresentable {
    var amount: CGFloat = 0.3

    func makeUIView(context: Context) -> BlurView { BlurView(amount: amount) }
    func updateUIView(_ v: BlurView, context: Context) {}

    final class BlurView: UIView {
        private let effect = UIVisualEffectView(effect: nil)
        private var animator: UIViewPropertyAnimator?
        private let amount: CGFloat

        init(amount: CGFloat) {
            self.amount = amount
            super.init(frame: .zero)
            effect.frame = bounds
            effect.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(effect)
        }
        required init?(coder: NSCoder) { fatalError() }

        // Dựng lại hiệu ứng mỗi khi vào cửa sổ (đổi sáng / tối, quay lại từ nền): animator đã dừng thì không tự áp lại
        override func didMoveToWindow() {
            super.didMoveToWindow()
            animator?.stopAnimation(true)
            effect.effect = nil
            guard window != nil else { return }
            let a = UIViewPropertyAnimator(duration: 1, curve: .linear) { [effect] in effect.effect = UIBlurEffect(style: .regular) }
            a.pausesOnCompletion = true
            a.fractionComplete = amount
            animator = a
        }
        deinit { animator?.stopAnimation(true) }
    }
}
