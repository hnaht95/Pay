import SwiftUI

/// Đặt / điều chỉnh số dư hiện có: nhập số tiền đang có thật (gộp tiền mặt, tài khoản…). Lần đầu là số dư ban đầu;
/// các lần sau app ghi phần chênh thành một khoản "Điều chỉnh số dư" (xem Store.setBalance)
struct BalanceSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var digits = ""

    private var amount: Int { Int(digits) ?? 0 }

    var body: some View {
        let current = store.balance
        VStack(alignment: .leading, spacing: 0) {
            Text(current == nil ? L("Số dư hiện có") : L("Điều chỉnh số dư")).font(.system(size: 21, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .padding(.top, 8)
            Text(current.map { L("App đang tính: %@. Nhập số bạn đang có thật, phần chênh được ghi vào Lịch sử.", fmt($0)) }
                 ?? L("Tổng tiền bạn đang có (tiền mặt, tài khoản…). Từ giờ app tự cộng khoản thu, trừ khoản chi."))
                .font(.system(size: 15)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                .padding(.top, 4)
            Text(digits.isEmpty ? "0" : fmt(amount))
                .font(.system(size: 40, weight: .bold)).kerning(-1)
                .foregroundStyle(digits.isEmpty ? .tertiary : .primary)
                .lineLimit(1).minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .padding(.horizontal, 18).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1) }
                .padding(.top, 24)
            NumberPad(digits: $digits)
                .frame(maxHeight: 320)
                .frame(maxHeight: .infinity)
                .padding(.vertical, 8)
            HStack(spacing: 12) {
                BigButton(title: L("Huỷ"), icon: "", primary: false, tint: BigButton.cancelTint) { dismiss() }
                BigButton(title: L("Lưu"), icon: "", primary: true) {
                    guard !digits.isEmpty else { return }
                    store.setBalance(amount)
                    dismiss()
                }
                .opacity(digits.isEmpty ? 0.55 : 1)
                .animation(.easeInOut(duration: 0.25), value: digits.isEmpty)
            }
            .padding(.bottom, -18)
        }
        .padding(.horizontal, 16)
        .background(Palette.surface.ignoresSafeArea())
        .onAppear { if let current, current > 0 { digits = String(current) } }
    }
}
