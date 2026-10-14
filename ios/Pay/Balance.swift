import SwiftUI

/// Đặt / điều chỉnh số dư hiện có: nhập số tiền đang có thật (gộp tiền mặt, tài khoản…). Lần đầu là số dư ban đầu;
/// các lần sau app ghi phần chênh thành một khoản "Điều chỉnh số dư" (xem Store.setBalance)
struct BalanceSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var digits = ""
    @State private var showLog = false

    private var amount: Int { Int(digits) ?? 0 }

    var body: some View {
        let current = store.balance
        VStack(alignment: .leading, spacing: 0) {
            Text(current == nil ? L("Số dư hiện có") : L("Điều chỉnh số dư")).font(.system(size: 21, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .padding(.top, 8)
            Text(current.map { L("App đang tính: %@. Nhập số bạn đang có thật, phần chênh được ghi vào Các lần điều chỉnh.", fmt($0)) }
                 ?? L("Tổng tiền bạn đang có (tiền mặt, tài khoản…). Từ giờ app tự cộng khoản thu, trừ khoản chi."))
                .font(.system(size: 15)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                .padding(.top, 4)
            // Các lần đặt / điều chỉnh số dư (không hiện ở Gần đây, Lịch sử chi tiêu: không phải tiêu tiền)
            if !store.adjusts.isEmpty {
                Button { showLog = true } label: {
                    HStack(spacing: 6) {
                        Text(L("Các lần điều chỉnh"))
                        // Số lần trong vòng tròn xám
                        Text("\(store.adjusts.count)").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                            .frame(minWidth: 22, minHeight: 22)
                            .background(Color.primary.opacity(0.12), in: Circle())
                    }
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Palette.pill, in: Capsule())
                }
                .buttonStyle(Pressable()).foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
            }
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
        .onAppear {
            if let current, current > 0 { digits = String(current) }
            #if DEBUG
            if UserDefaults.standard.string(forKey: "shotOpen") == "balancelog" { showLog = true }
            #endif
        }
        .sheet(isPresented: $showLog) { BalanceLog().environmentObject(store).sheetGrabber() }
    }
}

/// Các lần đặt / điều chỉnh số dư: ngày giờ, số tiền chênh, số dư sau lần đó. Vuốt để xoá (lỡ nhập sai)
struct BalanceLog: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            List {
                let log = store.adjustLog
                if log.isEmpty {
                    Text(L("Chưa điều chỉnh số dư lần nào.")).font(.system(size: 15)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(40)
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                ForEach(log) { e in
                    VStack(alignment: .leading, spacing: 6) {
                        ExpenseRow(e: e, showDay: true)
                        // Số dư ngay sau lần này
                        if let before = store.balance(before: e.t + 1) {
                            Text(L("Số dư sau đó: %@", fmt(before))).font(.system(size: 13)).foregroundStyle(.secondary)
                                .padding(.leading, 12)
                        }
                    }
                    .expenseSwipe(delete: { withAnimation(.snappy(duration: 0.3)) { store.remove(id: e.id) } })
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .padding(.leading, -16).padding(.trailing, -8)
            .padding(.horizontal, 16)
            .background(Palette.surface.ignoresSafeArea())
            .softTopEdge(fade: Palette.surface)
            .screenTitle(L("Các lần điều chỉnh"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .overlay(alignment: .bottom) { ToastView().padding(.bottom, 24) }
    }
}
