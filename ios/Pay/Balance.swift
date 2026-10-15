import SwiftUI

/// Đặt / điều chỉnh số dư hiện có: nhập số tiền đang có thật (gộp tiền mặt, tài khoản…). Lần đầu là số dư ban đầu;
/// các lần sau app ghi phần chênh thành một khoản "Điều chỉnh số dư" (xem Store.setBalance)
/// card: bảng trả thẻ tín dụng (cùng khung): nhập số đã trả cho thẻ, số dư và nợ thẻ cùng giảm (xem Store.payCard)
struct BalanceSheet: View {
    var card = false
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var digits = ""
    @State private var showLog = false

    private var amount: Int { Int(digits) ?? 0 }

    var body: some View {
        let current = store.balance
        let log = card ? store.cardPays : store.adjusts
        VStack(alignment: .leading, spacing: 0) {
            Text(card ? L("Trả thẻ tín dụng") : current == nil ? L("Số dư hiện có") : L("Điều chỉnh số dư")).font(.system(size: 21, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .padding(.top, 8)
            Text(card ? L("Chi tiêu thẻ chưa trả: %@. Nhập số tiền bạn đã trả cho thẻ: số dư giảm theo, không tính là chi tiêu lần nữa (đã tính lúc quẹt thẻ).", fmt(store.cardDebt))
                 : current.map { L("App đang tính: %@. Nhập số bạn đang có thật, phần chênh được ghi vào Các lần điều chỉnh.", fmt($0)) }
                 ?? L("Tổng tiền bạn đang có (tiền mặt, tài khoản…). Từ giờ app tự cộng khoản thu, trừ khoản chi."))
                .font(.system(size: 15)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                .padding(.top, 4)
            // Các lần đặt / điều chỉnh số dư (không hiện ở Gần đây, Lịch sử chi tiêu: không phải tiêu tiền)
            if !log.isEmpty {
                Button { showLog = true } label: {
                    HStack(spacing: 8) {
                        Text(card ? L("Các lần trả thẻ") : L("Các lần điều chỉnh"))
                        // Số lần trong vòng tròn xám, cách mép viên đều 5 trên, dưới, phải: vòng tròn đồng tâm với đầu viên (bo viên
                        // = bo vòng tròn + 5)
                        Text("\(log.count)").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                            .frame(minWidth: 26, minHeight: 26)
                            .background(Color.primary.opacity(0.12), in: Capsule())
                    }
                    .font(.system(size: 15, weight: .medium))
                    .padding(.leading, 14).padding(.trailing, 5).padding(.vertical, 5)
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
                    if card { store.payCard(amount) } else { store.setBalance(amount) }
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
            if card { if store.cardDebt > 0 { digits = String(store.cardDebt) } }
            else if let current, current > 0 { digits = String(current) }
            #if DEBUG
            if UserDefaults.standard.string(forKey: "shotOpen") == (card ? "cardlog" : "balancelog") { showLog = true }
            #endif
        }
        .sheet(isPresented: $showLog) { BalanceLog(card: card).environmentObject(store).sheetGrabber() }
    }
}

/// Trả thẻ tín dụng: bảng Số dư ở chế độ trả thẻ
struct CardPaySheet: View {
    var body: some View { BalanceSheet(card: true) }
}

/// Các lần đặt / điều chỉnh số dư: ngày giờ, số tiền chênh, số dư sau lần đó. Vuốt để xoá (lỡ nhập sai)
/// card: các lần trả thẻ tín dụng, dòng phụ là nợ thẻ còn lại sau lần đó
struct BalanceLog: View {
    var card = false
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            List {
                let log = card ? store.cardPays.sorted { $0.t > $1.t } : store.adjustLog
                if log.isEmpty {
                    Text(card ? L("Chưa trả thẻ lần nào.") : L("Chưa điều chỉnh số dư lần nào.")).font(.system(size: 15)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(40)
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                ForEach(log) { e in
                    // Dòng phụ bên trái (ngang hàng ngày giờ bên phải): số dư ngay sau lần này
                    let row = ExpenseRow(e: e, showDay: true, sub: card ? L("Chi tiêu thẻ còn lại: %@", fmt(store.cardDebt(before: e.t + 1)))
                                                                        : store.balance(before: e.t + 1).map { L("Số dư sau: %@", fmt($0)) })
                    // Số dư ban đầu (lần đặt đầu tiên) là mốc của mọi lần điều chỉnh sau (chúng chỉ ghi phần chênh): còn lần sau thì
                    // không cho xoá nó, xoá thì mốc nhảy sang một lần chênh và số dư sai hẳn. Xoá các lần sau trước, hoặc điều chỉnh lại
                    if !card && e.id == log.last?.id && log.count > 1 {
                        row
                    } else {
                        row.expenseSwipe(delete: { withAnimation(.snappy(duration: 0.3)) { store.remove(id: e.id) } })
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // Thẻ đầu cách vạch dưới tiêu đề 16 (bằng lề hai bên), không dính sát vạch
            .contentMargins(.top, 16, for: .scrollContent)
            .padding(.leading, -16).padding(.trailing, -8)
            .padding(.horizontal, 16)
            .background(Palette.surface.ignoresSafeArea())
            .softTopEdge(fade: Palette.surface)
            .screenTitle(card ? L("Các lần trả thẻ") : L("Các lần điều chỉnh"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .overlay(alignment: .bottom) { ToastView().padding(.bottom, 24) }
    }
}
