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

    /// Thẻ minh hoạ đang hiện (băng chuyền tự chạy; mở từ tính năng nào thì bắt đầu ở tính năng đó)
    @State private var page: ProFeature = .history
    /// Người dùng vừa tự vuốt: ngừng tự chạy một lúc
    @State private var touched = Date.distantPast

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            Text("Pay").font(.system(size: 34, weight: .bold))
                            Text("PRO").font(.system(size: 17, weight: .heavy)).tracking(1)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Capsule().fill(Color(hex: 0x61BE6E)))
                        }
                        Text(L("Ghi chép luôn miễn phí. Pro dành cho khi bạn dùng Pay lâu dài."))
                            .font(.system(size: 16)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(.top, 30).padding(.horizontal, 24)

                    // Băng chuyền: mỗi tính năng một thẻ có hình minh hoạ vẽ bằng code, cùng ngôn ngữ hình với app
                    TabView(selection: Binding(get: { page }, set: { page = $0; touched = Date() })) {
                        ForEach(ProFeature.allCases) { f in
                            featureCard(f).tag(f).padding(.horizontal, 16)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 530)
                    .sensoryFeedback(.selection, trigger: page)

                    // Chấm trang, chạm để nhảy
                    HStack(spacing: 6) {
                        ForEach(ProFeature.allCases) { f in
                            Capsule().fill(f == page ? Color.primary : Color.primary.opacity(0.18))
                                .frame(width: f == page ? 18 : 6, height: 6)
                                .onTapGesture { withAnimation(.snappy) { page = f; touched = Date() } }
                        }
                    }
                    .animation(.snappy, value: page)

                    if pro.products.isEmpty {
                        ProgressView().frame(height: 96)
                    } else {
                        HStack(spacing: 10) {
                            if let lifetime { plan(lifetime, title: L("Trọn đời"), note: L("Trả một lần, dùng mãi")) }
                            if let yearly { plan(yearly, title: L("Gói năm"), note: L("Tự gia hạn, huỷ bất cứ lúc nào")) }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 16)
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
        .task {
            if let feature { page = feature }
            // Tự chạy mỗi 3,2 giây; vừa vuốt tay thì đợi 6 giây rồi mới chạy tiếp
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.2))
                guard Date().timeIntervalSince(touched) > 6 else { continue }
                let all = ProFeature.allCases
                let i = all.firstIndex(of: page) ?? 0
                withAnimation(.easeInOut(duration: 0.45)) { page = all[(i + 1) % all.count] }
            }
        }
    }

    /// Một thẻ: khung minh hoạ màu, tên và mô tả tính năng
    private func featureCard(_ f: ProFeature) -> some View {
        VStack(spacing: 14) {
            ProScreen(feature: f)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(f.tint))
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            VStack(spacing: 4) {
                Text(f.title).font(.system(size: 20, weight: .bold))
                Text(f.detail).font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }

    private func plan(_ p: Product, title: String, note: String) -> some View {
        let on = pick == p.id
        return Button { if !on { Haptic.select() }; pick = p.id } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title).font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 20))
                        .foregroundStyle(on ? Color(hex: 0x61BE6E) : Color.primary.opacity(0.25))
                }
                Text(p.id == Pro.yearlyID ? L("%@/năm", p.displayPrice) : p.displayPrice)
                    .font(.system(size: 22, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                Text(note).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(on ? Color(hex: 0x61BE6E) : .clear, lineWidth: 2.5))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(Pressable())
    }
}

extension ProFeature {
    /// Nền thẻ minh hoạ: bảng màu danh mục của app
    var tint: Color {
        switch self {
        case .history: Color(hex: 0xC9D9A4)
        case .cloud: Color(hex: 0xA2D5F2)
        case .house: Color(hex: 0xFFD43B)
        case .recurring: Color(hex: 0xE2DBFF)
        case .photos: Color(hex: 0xF07B3F)
        case .categories: Color(hex: 0xCFEEDD)
        case .cardAuto: Color(hex: 0xEA5455)
        case .csv: Color(hex: 0xF4EDE1)
        }
    }
}

/// Minh hoạ của từng tính năng: chính màn hình thật của Pay (dựng bằng chế độ vẽ tĩnh của phim giới thiệu, xem Film.swift),
/// thu nhỏ trong khung điện thoại, cuộn tới đúng phần của tính năng đó
struct ProScreen: View {
    let feature: ProFeature
    /// Tỉ lệ thu nhỏ màn hình 402 × 874 (iPhone 17)
    var scale: CGFloat = 0.36

    var body: some View {
        let size = FilmScreen<EmptyView>.size
        // Khung iPhone đúng tỉ lệ: màn hình bo 55 pt như máy thật, viền đen 12 pt quanh màn hình
        let r = 55 * scale, bezel = 12 * scale
        FilmScreen { screen }
            .environmentObject(Store.shared)
            .environmentObject(QuickAction.shared)
            .environment(\.stillPreview, true)
            .allowsHitTesting(false)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
            .padding(bezel)
            .background(RoundedRectangle(cornerRadius: r + bezel, style: .continuous).fill(Color(hex: 0x111114)))
            .overlay(RoundedRectangle(cornerRadius: r + bezel, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
    }

    @ViewBuilder private var screen: some View {
        switch feature {
        // Thống kê và Cài đặt dựng bản thật (không qua chế độ phim): giống y màn hình người dùng đang thấy
        case .history: sheet(live: true) { StatsView() }
        case .cloud: home(scroll: 0)
        case .house:
            if House.shared.groups.isEmpty { home(scroll: 0) } else { sheet { HouseView() } }
        case .recurring: sheet(live: true) { HistoryView() }
        case .photos:
            let c = Category.get("an")
            sheet { CategoryEditor(editing: CustomCat(k: c.k, name: c.rawName, icon: c.icon, tone: -1, on: true, u: 0)) }
        case .categories: home(scroll: 250)
        case .cardAuto: home(scroll: 760)
        case .csv: sheet(scroll: 900) { StatsView() }
        }
    }

    private func home(scroll: CGFloat) -> some View {
        var f = FilmFrame(); f.scroll = scroll
        return HomeView().environment(\.film, f)
    }

    private func sheet<C: View>(scroll: CGFloat = 0, live: Bool = false, @ViewBuilder _ content: () -> C) -> some View {
        var f = FilmFrame(); f.scroll = scroll
        return FilmSheet(shown: 1) { HomeView().environment(\.film, FilmFrame()) } content: {
            content().environment(\.film, live ? nil : f)
        }
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
