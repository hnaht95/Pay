import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Vào nhóm chung bằng mã QR, hai chiều:
/// - Chủ nhóm mở "Mã QR vào nhóm": người kia quét bằng camera iPhone hoặc máy quét Payso là vào. Mỗi mã là một link mời
///   dùng một lần, có người vào thì tự đổi mã mới cho người sau.
/// - Người muốn vào mở "Vào nhóm bằng mã" (danh sách nhóm): hiện mã của mình, chủ nhóm quét bằng Payso là máy này tự vào.
enum HouseJoinCode {
    static let prefix = "PAYSO-JOIN:"

    /// Mã của người đang chờ vào nhóm (chủ nhóm quét được), nil nếu không phải
    static func nonce(_ s: String) -> String? {
        guard s.hasPrefix(prefix) else { return nil }
        let n = String(s.dropFirst(prefix.count))
        return n.count >= 16 && n.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) ? n : nil
    }

    /// Link mời vào nhóm của iCloud (mã QR nhóm), nil nếu không phải
    static func shareURL(_ s: String) -> URL? {
        guard let u = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)), u.scheme == "https",
              let h = u.host?.lowercased(), h == "www.icloud.com" || h == "icloud.com", u.path.hasPrefix("/share/") else { return nil }
        return u
    }
}

/// Mã QR của một chuỗi bất kỳ, không nền: các ô tô theo màu chữ (trắng trên nền tối, đen trên nền sáng), ô vuông sắc nét khi phóng to
struct PlainQR: View {
    let text: String

    var body: some View {
        if let img = Self.image(text) {
            Image(decorative: img, scale: 1).renderingMode(.template).interpolation(.none).resizable().scaledToFit()
        } else {
            Color.clear
        }
    }

    static func image(_ text: String) -> CGImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage else { return nil }
        // Chỉ giữ các ô của mã, nền trắng thành trong suốt (để tô bằng màu chữ)
        let c = CIFilter.falseColor()
        c.inputImage = out
        c.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
        c.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let t = c.outputImage else { return nil }
        return CIContext().createCGImage(t, from: t.extent)
    }
}

/// Sáng màn hình tối đa trong lúc hiện mã (dễ quét), đóng hoặc rời app thì trả lại độ sáng cũ
private struct BrightWhileShown: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var old: CGFloat?

    func body(content: Content) -> some View {
        content
            .onAppear { set(true) }
            .onDisappear { set(false) }
            .onChange(of: scenePhase) { _, p in set(p == .active) }
    }

    private func set(_ on: Bool) {
        guard let scene = (UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive }
                           ?? UIApplication.shared.connectedScenes.first) as? UIWindowScene else { return }
        if on {
            guard old == nil else { return }
            old = scene.screen.brightness
            scene.screen.brightness = 1
        } else if let o = old {
            scene.screen.brightness = o
            old = nil
        }
    }
}

/// Mã và dòng chữ bên dưới, đặt thẳng trên nền của tấm (không thẻ nền)
private struct QRCard<Footer: View>: View {
    let text: String?
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                if let text { PlainQR(text: text) } else { ProgressView() }
            }
            .frame(width: 240, height: 240)
            footer
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
    }
}

/// Nút phụ mở máy quét (nền xám, chữ và biểu tượng giữa nút), nằm trên nút đóng
private struct ScanPill: View {
    let title: String
    let run: () -> Void

    var body: some View {
        Button(action: run) {
            Label(title, systemImage: "qrcode.viewfinder")
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Palette.card, in: Capsule())
                .foregroundStyle(.primary)
        }
        .buttonStyle(Pressable())
    }
}

// MARK: Chủ nhóm: mã QR vào nhóm

@available(iOS 18.0, *)
struct GroupQRSheet: View {
    @ObservedObject private var house = House.shared
    @Environment(\.dismiss) private var dismiss
    @State private var url: URL?
    @State private var pid: String?
    /// Các link một lần đã tạo trong lần mở này: đóng thì gỡ những link chưa ai dùng
    @State private var made: [String] = []
    @State private var joined = 0
    @State private var error: String?
    @State private var scanning = false
    @State private var scannedCode: String?

    var body: some View {
        VStack(spacing: 0) {
            Text(L("Mã QR vào nhóm")).font(.system(size: 21, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 46).padding(.top, 8)
            Spacer(minLength: 8)
            QRCard(text: url?.absoluteString) {
                Text(house.name.isEmpty ? L("Nhóm chung") : house.name).font(.system(size: 19, weight: .bold)).lineLimit(1)
                Text(L("Mỗi mã cho một người")).font(.system(size: 14)).foregroundStyle(.secondary)
            }
            if let error {
                Text(error).font(.system(size: 15)).foregroundStyle(Palette.danger).multilineTextAlignment(.center).padding(.top, 12)
                Button(L("Thử lại")) { Task { await next() } }.font(.system(size: 17, weight: .semibold)).padding(.top, 6)
            } else if joined > 0 {
                Label(joined == 1 ? L("1 người đã vào nhóm. Mã mới cho người tiếp theo") : L("%d người đã vào nhóm. Mã mới cho người tiếp theo", joined),
                      systemImage: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.goodInk)
                    .multilineTextAlignment(.center).padding(.top, 14)
            }
            Text(L("Người kia mở camera iPhone hoặc nút Quét QR của Payso, đưa vào mã này là vào nhóm. Cần cài Payso và đăng nhập iCloud."))
                .font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .padding(.top, 14).padding(.horizontal, 8)
            Spacer(minLength: 8)
            ScanPill(title: L("Quét mã của họ")) { scanning = true }
            BigButton(title: L("Xong"), icon: "", primary: true) { dismiss() }
                .padding(.top, 10).padding(.bottom, -18)
        }
        .padding(.horizontal, 16)
        .background(Palette.surface.ignoresSafeArea())
        .modifier(BrightWhileShown())
        .task { await next() }
        // Hỏi iCloud vài giây một lần: người đang giữ mã đã vào chưa; vào rồi thì đổi mã mới
        .task(id: pid) {
            guard let p = pid else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                if await house.inviteAccepted(p) {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(.snappy) { joined += 1 }
                    await next()
                    return
                }
            }
        }
        .onDisappear {
            let unused = made
            Task { await house.dropInvites(unused) }
            if joined > 0 { Task { await house.load(prompt: false) } }
        }
        .fullScreenCover(isPresented: $scanning, onDismiss: {
            guard let s = scannedCode else { return }
            scannedCode = nil
            if let n = HouseJoinCode.nonce(s) { Task { await house.inviteByCode(n) } }
            else { Store.shared.showError(L("Đây không phải mã vào nhóm của Payso. Người kia mở Nhóm chung › Vào nhóm bằng mã.")) }
        }) {
            ScannerView(hint: L("Đưa mã vào nhóm của người kia vào khung")) { code in scannedCode = code; scanning = false }
        }
    }

    private func next() async {
        error = nil
        url = nil
        do {
            let r = try await house.oneTimeInvite()
            made.append(r.pid)
            url = r.url; pid = r.pid
        } catch {
            self.error = L("Không tạo được mã") + ". " + House.describe(error)
        }
    }
}

// MARK: Người muốn vào: mã của mình

struct JoinByCodeSheet: View {
    @ObservedObject private var house = House.shared
    @Environment(\.dismiss) private var dismiss
    /// Mã ngẫu nhiên của lần mở này: chủ nhóm quét được thì gửi link mời vào đúng chỗ này
    @State private var nonce = UUID().uuidString
    @State private var joining = false
    @State private var scanning = false
    @State private var scannedCode: String?

    var body: some View {
        VStack(spacing: 0) {
            Text(L("Vào nhóm bằng mã")).font(.system(size: 21, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 46).padding(.top, 8)
            Spacer(minLength: 8)
            QRCard(text: HouseJoinCode.prefix + nonce) {
                Text(L("Mã của bạn")).font(.system(size: 19, weight: .bold))
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(joining ? L("Đang vào nhóm…") : L("Đang chờ chủ nhóm quét…")).font(.system(size: 14)).foregroundStyle(.secondary)
                }
            }
            Text(L("Đưa mã này cho chủ nhóm. Họ mở nhóm, chọn Thêm người › Quét mã của họ. Quét xong máy bạn tự vào nhóm."))
                .font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .padding(.top, 14).padding(.horizontal, 8)
            Spacer(minLength: 8)
            ScanPill(title: L("Quét mã nhóm")) { scanning = true }
            BigButton(title: L("Đóng"), icon: "", primary: true) { dismiss() }
                .padding(.top, 10).padding(.bottom, -18)
        }
        .padding(.horizontal, 16)
        .background(Palette.surface.ignoresSafeArea())
        .modifier(BrightWhileShown())
        // Chờ chủ nhóm quét: hỏi iCloud vài giây một lần xem đã có link mời gửi tới mã này chưa
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.5))
                guard !Task.isCancelled, !joining else { continue }
                if let u = await house.relayedInvite(nonce) {
                    joining = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    await house.join(u)
                    dismiss()
                    return
                }
            }
        }
        .fullScreenCover(isPresented: $scanning, onDismiss: {
            guard let s = scannedCode else { return }
            scannedCode = nil
            if let u = HouseJoinCode.shareURL(s) {
                joining = true
                Task { await house.join(u); dismiss() }
            } else {
                Store.shared.showError(L("Đây không phải mã nhóm. Nhờ chủ nhóm mở nhóm, chọn Thêm người › Mã QR vào nhóm."))
            }
        }) {
            ScannerView(hint: L("Đưa mã QR của nhóm vào khung")) { code in scannedCode = code; scanning = false }
        }
    }
}
