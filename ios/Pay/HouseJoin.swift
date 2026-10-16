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

/// Mã nhóm dùng lâu dài (kiểu Telegram): ai quét cũng gửi được yêu cầu xin vào, chủ nhóm duyệt từng người. Gửi ảnh mã qua Zalo
/// cũng được. Lộ mã thì Đặt lại mã: mã cũ hết dùng được
@available(iOS 18.0, *)
struct GroupQRSheet: View {
    @ObservedObject private var house = House.shared
    @Environment(\.dismiss) private var dismiss
    @State private var code: String?
    @State private var error: String?
    @State private var scanning = false
    @State private var scannedCode: String?
    @State private var confirmReset = false

    private var group: HouseGroup? { house.current }
    private var requests: [JoinRequest] { group.flatMap { house.joinRequests[$0.id] } ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            Text(L("Mã QR vào nhóm")).font(.system(size: 21, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 46).padding(.top, 8)
            ScrollView {
                VStack(spacing: 0) {
                    QRCard(text: code.map(House.joinLink)) {
                        Text(house.name.isEmpty ? L("Nhóm chung") : house.name).font(.system(size: 19, weight: .bold)).lineLimit(1)
                        Text(L("Quét mã là gửi yêu cầu, bạn duyệt mới vào được")).font(.system(size: 14)).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)
                    if let error {
                        Text(error).font(.system(size: 15)).foregroundStyle(Palette.danger).multilineTextAlignment(.center).padding(.top, 12)
                        Button(L("Thử lại")) { Task { await load() } }.font(.system(size: 17, weight: .semibold)).padding(.top, 6)
                    }
                    if code != nil {
                        HStack(spacing: 16) {
                            if let code, let img = PlainQR.image(House.joinLink(code)) {
                                ShareLink(item: Image(decorative: img, scale: 1).renderingMode(.original), preview: SharePreview(L("Mã QR vào nhóm"),
                                          image: Image(decorative: img, scale: 1))) {
                                    Label(L("Gửi mã"), systemImage: "square.and.arrow.up")
                                }
                            }
                            Button { confirmReset = true } label: { Label(L("Đặt lại mã"), systemImage: "arrow.clockwise") }
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.top, 14)
                    }
                    if !requests.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L("Đang xin vào")).font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                            ForEach(requests) { q in requestRow(q) }
                        }
                        .padding(.top, 20)
                    }
                    Text(L("Người kia mở camera iPhone hoặc nút Quét QR của Payso, quét mã này rồi gửi yêu cầu. Bạn bấm Duyệt là họ vào nhóm."))
                        .font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .padding(.top, 16).padding(.horizontal, 8)
                }
            }
            .scrollIndicators(.hidden)
            ScanPill(title: L("Quét mã của họ")) { scanning = true }
                .padding(.top, 8)
            BigButton(title: L("Xong"), icon: "", primary: true) { dismiss() }
                .padding(.top, 10).padding(.bottom, -18)
        }
        .padding(.horizontal, 16)
        .background(Palette.surface.ignoresSafeArea())
        .modifier(BrightWhileShown())
        .task { await load() }
        // Hỏi iCloud vài giây một lần: có ai vừa quét mã xin vào không
        .task(id: code) {
            guard code != nil, let g = group else { return }
            while !Task.isCancelled {
                await house.refreshJoinRequests(g)
                try? await Task.sleep(for: .seconds(4))
            }
        }
        .onChange(of: requests.count) { old, new in
            if new > old { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        }
        .confirmationDialog(L("Đặt lại mã?"), isPresented: $confirmReset, titleVisibility: .visible) {
            Button(L("Đặt lại mã"), role: .destructive) {
                Task {
                    guard let g = group else { return }
                    do { code = try await house.resetCode(g) } catch { self.error = L("Không tạo được mã") + ". " + House.describe(error) }
                }
            }
            Button(L("Huỷ"), role: .cancel) {}
        } message: {
            Text(L("Mã cũ và ảnh mã đã gửi đi sẽ không dùng được nữa. Người đã vào nhóm vẫn ở trong nhóm."))
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

    private func requestRow(_ q: JoinRequest) -> some View {
        HStack(spacing: 10) {
            HouseAvatar(id: q.nonce, name: q.name, size: 40)
            Text(q.name).font(.system(size: 17, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 4)
            Button(L("Từ chối")) { Task { if let g = group { await house.answer(q, in: g, accept: false) } } }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 12).frame(height: 38).background(Palette.surface, in: Capsule())
            Button(L("Duyệt")) { Task { if let g = group { await house.answer(q, in: g, accept: true) } } }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ctaInk)
                .padding(.horizontal, 14).frame(height: 38).background(Palette.cta, in: Capsule())
        }
        .buttonStyle(Pressable())
        .disabled(house.busy)
        .padding(10)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func load() async {
        error = nil
        guard let g = group else { return }
        do { code = try await house.groupCode(g) } catch { self.error = L("Không tạo được mã") + ". " + House.describe(error) }
    }
}

// MARK: Người quét mã nhóm: xin vào

struct JoinRequestSheet: View {
    @ObservedObject private var house = House.shared
    @Environment(\.dismiss) private var dismiss
    let code: String
    @State private var group: String?
    @State private var missing = false
    @State private var name = UserDefaults.standard.string(forKey: "house.myName") ?? ""
    @State private var sending = false

    /// Đã gửi, đang chờ chủ nhóm duyệt
    private var waiting: MyJoinRequest? { house.myRequests.first { $0.code == code } }

    var body: some View {
        VStack(spacing: 16) {
            Text(L("Xin vào nhóm")).font(.system(size: 21, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 46).padding(.top, 8)
            Spacer(minLength: 0)
            if missing {
                Image(systemName: "qrcode").font(.system(size: 40)).foregroundStyle(.secondary)
                Text(L("Mã này không còn dùng được. Nhờ chủ nhóm gửi mã mới.")).multilineTextAlignment(.center).foregroundStyle(.secondary)
            } else if let group {
                Image(systemName: "person.3.fill").font(.system(size: 34)).foregroundStyle(.secondary)
                Text(group).font(.system(size: 24, weight: .bold)).multilineTextAlignment(.center)
                if let w = waiting {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L("Đang chờ chủ nhóm duyệt…")).foregroundStyle(.secondary)
                    }
                    Text(L("Đóng màn này cũng được: chủ nhóm duyệt rồi thì lần mở Payso tới bạn sẽ tự vào nhóm."))
                        .font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button(L("Huỷ yêu cầu"), role: .destructive) { Task { await house.cancelRequest(w); dismiss() } }
                        .font(.system(size: 15, weight: .semibold))
                } else {
                    TextField(L("Tên của bạn"), text: $name)
                        .font(.system(size: 17)).multilineTextAlignment(.center)
                        .padding(.horizontal, 18).frame(height: 54)
                        .background(Palette.card, in: Capsule())
                    Text(L("Chủ nhóm sẽ thấy tên này khi duyệt.")).font(.system(size: 14)).foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
            }
            Spacer(minLength: 0)
            if group != nil, waiting == nil, !missing {
                let ok = !name.trimmingCharacters(in: .whitespaces).isEmpty && !sending
                BigButton(title: L("Gửi yêu cầu"), icon: "", primary: true) {
                    guard ok, let group else { return }
                    sending = true
                    Task { _ = await house.requestJoin(code: code, group: group, name: name.trimmingCharacters(in: .whitespaces)); sending = false }
                }
                .opacity(ok ? 1 : 0.4)
                .padding(.bottom, -18)
            } else {
                BigButton(title: L("Đóng"), icon: "", primary: true) { dismiss() }.padding(.bottom, -18)
            }
        }
        .padding(.horizontal, 16)
        .background(Palette.surface.ignoresSafeArea())
        .task {
            group = await house.groupName(forCode: code)
            missing = group == nil
        }
        // Đang chờ: hỏi vài giây một lần; được duyệt thì House tự vào nhóm và mở màn nhóm, màn này đóng lại
        .task(id: waiting?.nonce) {
            guard waiting != nil else { return }
            while !Task.isCancelled, waiting != nil {
                try? await Task.sleep(for: .seconds(3))
                await house.checkMyRequests()
            }
            if !Task.isCancelled { dismiss() }
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
            } else if let c = House.code(in: s) {
                dismiss(); QuickAction.shared.joinCode = c
            } else {
                Store.shared.showError(L("Đây không phải mã nhóm. Nhờ chủ nhóm mở nhóm, chọn Thêm người › Mã QR vào nhóm."))
            }
        }) {
            ScannerView(hint: L("Đưa mã QR của nhóm vào khung")) { code in scannedCode = code; scanning = false }
        }
    }
}
