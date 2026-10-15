import SwiftUI
import UIKit

/// Bảng "Nhận tiền": mã VietQR có sẵn số tiền và nội dung, để nhờ bạn bè trả lại (vd sau bữa ăn chia tiền).
/// Mã đổi ngay theo số đang nhập; màn hình sáng tối đa trong lúc mở để dễ quét, đóng thì trả lại độ sáng cũ.
struct RequestQRSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var digits = ""
    @State private var note = ""
    /// Đang nhập số (hiện bàn phím số); chạm vào mã thì thu bàn phím lại cho mã to ra
    @State private var typing = true
    @FocusState private var noteFocused: Bool
    /// Độ sáng trước khi mở bảng, để trả lại
    @State private var oldBrightness: CGFloat?

    private let base = MyQR.load()
    private var amount: Int { Int(digits) ?? 0 }

    /// Mã đang hiện: tài khoản của mình + số tiền + nội dung không dấu
    private var qr: MyQR {
        var q = base
        q.amount = amount
        q.note = Self.plainNote(note)
        return q
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(L("Nhận tiền")).font(.system(size: 21, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .padding(.top, 8)
            if base.ready { content } else { missing }
        }
        .padding(.horizontal, 16)
        .background(Palette.surface.ignoresSafeArea())
        .onAppear { brighten(true) }
        .onDisappear { brighten(false) }
        // Rời app thì trả độ sáng (iOS không tự trả), quay lại thì sáng lại
        .onChange(of: scenePhase) { _, p in brighten(p == .active) }
    }

    // MARK: Chưa có tài khoản

    private var missing: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "qrcode").font(.system(size: 54, weight: .medium)).foregroundStyle(.secondary)
            Text(L("Chưa có tài khoản nhận tiền")).font(.system(size: 19, weight: .semibold))
            Text(L("Vào Cài đặt › Mã QR nhận tiền, chọn ngân hàng và nhập số tài khoản. Sau đó tạo được mã có sẵn số tiền để bạn bè quét là chuyển."))
                .font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            BigButton(title: L("Đóng"), icon: "", primary: true) { dismiss() }
                .padding(.bottom, -18)
        }
    }

    // MARK: Mã và ô nhập

    private var content: some View {
        VStack(spacing: 0) {
            RequestQRCard(qr: qr, note: note)
                .onTapGesture { withAnimation(.snappy) { typing.toggle(); noteFocused = false } }
                .padding(.top, 10)
                .frame(maxHeight: .infinity)

            Button { withAnimation(.snappy) { typing = true; noteFocused = false } } label: {
                Text(digits.isEmpty ? L("Số tiền") : fmt(amount))
                    .font(.system(size: 34, weight: .bold)).kerning(-1)
                    .foregroundStyle(digits.isEmpty ? .tertiary : .primary)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(typing && !noteFocused ? 0.3 : 0.14), lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .padding(.top, 12)

            TextField(L("Nội dung (vd Tiền ăn tối)"), text: $note)
                .focused($noteFocused)
                .submitLabel(.done)
                .font(.system(size: 17))
                .padding(.horizontal, 18).frame(height: 48)
                .background(Palette.pill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.top, 8)
                .onChange(of: note) { _, v in if v.count > 40 { note = String(v.prefix(40)) } }

            if typing && !noteFocused {
                NumberPad(digits: $digits)
                    .frame(minHeight: 180, maxHeight: 250)
                    .padding(.top, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            BigButton(title: L("Chia sẻ"), icon: "square.and.arrow.up", primary: true) { share() }
                .padding(.top, 8)
                .padding(.bottom, -18)
        }
        .animation(.snappy, value: noteFocused)
    }

    // MARK: Việc

    private func brighten(_ on: Bool) {
        guard let screen = (UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive }
                            ?? UIApplication.shared.connectedScenes.first) as? UIWindowScene else { return }
        if on {
            guard oldBrightness == nil else { return }
            oldBrightness = screen.screen.brightness
            screen.screen.brightness = 1
        } else if let old = oldBrightness {
            screen.screen.brightness = old
            oldBrightness = nil
        }
    }

    /// Ảnh thẻ mã + một dòng chữ "Chuyển cho <tên> <số tiền> – <nội dung>"
    private func share() {
        Haptic.tap()
        noteFocused = false
        let r = ImageRenderer(content: RequestQRCard(qr: qr, note: note).frame(width: 360).padding(16).background(Color.white))
        r.scale = 3
        var line = L("Chuyển cho %@", base.name.isEmpty ? base.acct : base.name)
        if amount > 0 { line += " " + fmt(amount) + "đ" }
        let n = note.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { line += " – " + n }
        line += "\n\(base.bank) · \(base.acct)"
        var items: [Any] = [line]
        if let img = r.uiImage { items.insert(img, at: 0) }
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              var top = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        top.present(UIActivityViewController(activityItems: items, applicationActivities: nil), animated: true)
    }

    /// Nội dung chuyển khoản cho mã: bỏ dấu, chỉ chữ và số, tối đa 25 ký tự (app ngân hàng nhiều nơi chỉ nhận chừng đó,
    /// và độ dài trường tính theo ký tự nên chữ có dấu làm lệch mã)
    static func plainNote(_ s: String) -> String {
        let folded = s.replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "D")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "vi"))
        let kept = String(folded.unicodeScalars.map { $0.isASCII && (CharacterSet.alphanumerics.contains($0)) ? Character($0) : " " })
        return String(kept.split(separator: " ").joined(separator: " ").prefix(25)).trimmingCharacters(in: .whitespaces)
    }
}

/// Thẻ trắng của bảng Nhận tiền: mã to, số tiền, nội dung, ngân hàng · số tài khoản · tên
struct RequestQRCard: View {
    let qr: MyQR
    let note: String

    var body: some View {
        VStack(spacing: 6) {
            MyQRCode(qr: qr)
                .padding(4)
                .frame(maxWidth: 280, maxHeight: 280)
                .layoutPriority(-1)
            if qr.amount > 0 {
                Text(fmt(qr.amount) + "đ").font(.system(size: 24, weight: .bold)).kerning(-0.5)
                    .contentTransition(.numericText())
            }
            let n = note.trimmingCharacters(in: .whitespaces)
            if !n.isEmpty { Text(n).font(.system(size: 15, weight: .medium)).lineLimit(1) }
            Text([qr.bank, qr.acct].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 14)).opacity(0.6).lineLimit(1).minimumScaleFactor(0.7)
            if !qr.name.isEmpty { Text(qr.name).font(.system(size: 14, weight: .semibold)).opacity(0.75).lineLimit(1) }
        }
        .foregroundStyle(.black)   // thẻ luôn trắng (dễ quét), chữ luôn đen kể cả chế độ tối
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.black.opacity(0.06), lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}
