import StoreKit
import SwiftUI
import UIKit

/// Pay Pro: mua một lần (trọn đời) hoặc gói năm, qua StoreKit 2.
///
/// Ghi chép (quét QR, nhập, nói để ghi) luôn miễn phí. Pro mở những thứ người dùng lâu mới cần: xem lịch sử xa hơn hai tháng,
/// đồng bộ iCloud, nhóm chung, khoản định kỳ, ảnh hoá đơn / ảnh danh mục, danh mục tự tạo không giới hạn, tự ghi khi trả
/// Apple Pay, xuất CSV. Giá đặt trong App Store Connect (trọn đời 199.000đ, giá ra mắt 99.000đ; gói năm 79.000đ).
@MainActor
final class Pro: ObservableObject {
    static let shared = Pro()
    static let lifetimeID = "com.hnaht95.sochipay.pro.lifetime"
    static let yearlyID = "com.hnaht95.sochipay.pro.yearly"
    /// Số danh mục tự tạo được dùng miễn phí
    static let freeCategories = 2

    /// Đã mua Pro (nhớ lần kiểm tra gần nhất, để mở app không có mạng vẫn đúng)
    @Published private(set) var active: Bool
    /// Gói bán: gói năm trước, trọn đời sau
    @Published private(set) var products: [Product] = []
    @Published private(set) var buying = false

    private var updates: Task<Void, Never>?

    private init() {
        active = UserDefaults.standard.bool(forKey: "proActive")
        #if DEBUG
        // "-proOn YES": xem app như đã mua (quay phim, thử giao diện)
        if UserDefaults.standard.bool(forKey: "proOn") { active = true }
        #endif
        // Giao dịch đến từ ngoài app (mua trên máy khác, gia hạn, hoàn tiền, Ask to Buy được duyệt)
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refresh()
            }
        }
        Task { await load(); await refresh() }
    }

    func load() async {
        guard products.isEmpty, let list = try? await Product.products(for: [Self.yearlyID, Self.lifetimeID]) else { return }
        products = list.sorted { a, _ in a.id == Self.yearlyID }
    }

    /// Đọc lại quyền Pro từ các giao dịch còn hiệu lực
    func refresh() async {
        var on = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil,
                  t.productID == Self.lifetimeID || t.productID == Self.yearlyID else { continue }
            on = true
        }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "proOn") { on = true }
        #endif
        set(on)
    }

    private func set(_ on: Bool) {
        guard on != active else { return }
        active = on
        UserDefaults.standard.set(on, forKey: "proActive")
        Store.shared.proChanged()
    }

    /// Mua một gói. Trả về true khi đã mở Pro.
    func buy(_ p: Product) async -> Bool {
        buying = true
        defer { buying = false }
        guard let result = try? await p.purchase() else { return false }
        switch result {
        case .success(let v):
            guard case .verified(let t) = v else { return false }
            await t.finish()
            await refresh()
            return active
        default:
            return false   // huỷ, hoặc đang chờ phụ huynh duyệt (Ask to Buy): Transaction.updates sẽ báo sau
        }
    }

    func restore() async {
        buying = true
        defer { buying = false }
        try? await AppStore.sync()
        await refresh()
    }

    /// Dùng được tính năng Pro chưa; chưa mua thì mở màn mua Pro (nói rõ đang mở khoá tính năng nào) và trả về false.
    @discardableResult
    func allow(_ f: ProFeature) -> Bool {
        if active { return true }
        Haptic.tap()
        ProPaywall.present(f)
        return false
    }
}

/// Tính năng Pro: tên hiện ở đầu màn mua khi người dùng chạm vào đúng tính năng đó
enum ProFeature: String, CaseIterable, Identifiable {
    case history, cloud, house, recurring, photos, categories, cardAuto, csv
    var id: String { rawValue }

    var title: String {
        switch self {
        case .history: L("Xem toàn bộ lịch sử")
        case .cloud: L("Đồng bộ iCloud")
        case .house: L("Nhóm chung")
        case .recurring: L("Khoản định kỳ")
        case .photos: L("Ảnh hoá đơn & ảnh danh mục")
        case .categories: L("Danh mục không giới hạn")
        case .cardAuto: L("Tự ghi khi trả Apple Pay")
        case .csv: L("Xuất CSV")
        }
    }

    var detail: String {
        switch self {
        case .history: L("Thống kê theo ngày, theo tháng từ khoản đầu tiên")
        case .cloud: L("Dữ liệu trên mọi iPhone, iPad của bạn")
        case .house: L("Chia tiền với gia đình, bạn bè")
        case .recurring: L("Tiền nhà, điện, internet tự ghi mỗi tháng")
        case .photos: L("Đính kèm hoá đơn, ảnh riêng cho danh mục")
        case .categories: L("Tạo bao nhiêu danh mục tuỳ ý")
        case .cardAuto: L("Quẹt thẻ là có khoản chi, không mở app")
        case .csv: L("Mở bằng Excel, Numbers")
        }
    }

    var icon: String {
        switch self {
        case .history: "chart.bar.fill"
        case .cloud: "icloud.fill"
        case .house: "person.2.fill"
        case .recurring: "repeat"
        case .photos: "photo.fill"
        case .categories: "square.grid.2x2.fill"
        case .cardAuto: "creditcard.fill"
        case .csv: "tablecells.fill"
        }
    }
}

/// Màn mua Pro: danh sách quyền lợi, hai gói (năm / trọn đời), nút mua, khôi phục, điều khoản.
struct ProPaywall: View {
    var feature: ProFeature?
    @ObservedObject private var pro = Pro.shared
    @Environment(\.dismiss) private var dismiss
    @State private var pick = Pro.lifetimeID

    /// Mở màn mua từ bất kỳ đâu (kể cả khi đang có một tấm khác mở): đặt lên trên cùng bằng UIKit
    static func present(_ f: ProFeature? = nil) {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
                ?? UIApplication.shared.connectedScenes.first as? UIWindowScene,
              var top = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        if top is UIHostingController<ProPaywall> { return }
        let vc = UIHostingController(rootView: ProPaywall(feature: f))
        vc.modalPresentationStyle = .pageSheet
        vc.sheetPresentationController?.prefersGrabberVisible = true
        top.present(vc, animated: true)
    }

    private var lifetime: Product? { pro.products.first { $0.id == Pro.lifetimeID } }
    private var yearly: Product? { pro.products.first { $0.id == Pro.yearlyID } }
    private var chosen: Product? { pro.products.first { $0.id == pick } }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pay Pro").font(.system(size: 34, weight: .bold))
                        Text(feature.map { L("Mở khoá %@ và mọi tính năng Pro.", $0.title) }
                             ?? L("Ghi chép luôn miễn phí. Pro dành cho khi bạn dùng Pay lâu dài."))
                            .font(.system(size: 17)).foregroundStyle(.secondary)
                    }
                    .padding(.top, 28)

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(ProFeature.allCases) { f in
                            HStack(spacing: 14) {
                                Image(systemName: f.icon).font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(f == feature ? .white : Color.primary)
                                    .frame(width: 40, height: 40)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(f == feature ? Color(hex: 0x61BE6E) : Palette.card))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.title).font(.system(size: 16, weight: .semibold))
                                    Text(f.detail).font(.system(size: 14)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if pro.products.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
                    } else {
                        VStack(spacing: 10) {
                            if let lifetime {
                                plan(lifetime, title: L("Trọn đời"), note: L("Trả một lần, dùng mãi"))
                            }
                            if let yearly {
                                plan(yearly, title: L("Gói năm"), note: L("Tự gia hạn, huỷ bất cứ lúc nào"))
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }

            VStack(spacing: 12) {
                if pro.active {
                    BigButton(title: L("Đã mở Pro, cảm ơn bạn!"), icon: "", primary: true) { dismiss() }
                } else {
                    BigButton(title: chosen.map { L("Mua %@", $0.displayPrice) } ?? L("Mua"), icon: "", primary: true) {
                        guard let p = chosen, !pro.buying else { return }
                        Task { if await pro.buy(p) { Haptic.tap(.medium); dismiss() } }
                    }
                    .opacity(chosen == nil || pro.buying ? 0.5 : 1)
                }
                HStack(spacing: 18) {
                    Button(L("Khôi phục giao dịch")) { Task { await pro.restore(); if pro.active { dismiss() } } }
                    Link(L("Điều khoản"), destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    Link(L("Quyền riêng tư"), destination: URL(string: "https://peakapp.vn/pay/privacy.html")!)
                }
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
        }
        .background(Palette.surface.ignoresSafeArea())
        .task { await pro.load() }
    }

    private func plan(_ p: Product, title: String, note: String) -> some View {
        let on = pick == p.id
        return Button { if !on { Haptic.select() }; pick = p.id } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 22))
                    .foregroundStyle(on ? Color(hex: 0x61BE6E) : Color.primary.opacity(0.3))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 17, weight: .semibold))
                    Text(note).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(p.id == Pro.yearlyID ? L("%@/năm", p.displayPrice) : p.displayPrice)
                    .font(.system(size: 17, weight: .bold))
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(on ? Color(hex: 0x61BE6E) : .clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(Pressable())
    }
}

/// Nhãn "Pro" nhỏ cạnh tính năng cần Pro (chỉ hiện khi chưa mua)
struct ProBadge: View {
    var body: some View {
        Text("PRO").font(.system(size: 10, weight: .heavy)).tracking(0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 2.5)
            .background(Capsule().fill(Color(hex: 0x61BE6E)))
    }
}
