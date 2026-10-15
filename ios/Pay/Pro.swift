import StoreKit
import SwiftUI
import UIKit

/// Pay Pro: mua một lần (trọn đời) hoặc gói năm, qua StoreKit 2.
///
/// Ghi chép (quét QR, nhập, nói để ghi) luôn miễn phí. Pro mở những thứ người dùng lâu mới cần: xem lịch sử xa hơn hai tháng,
/// đồng bộ iCloud, khoản định kỳ, ảnh hoá đơn / ảnh danh mục, danh mục tự tạo không giới hạn, tự ghi khi trả
/// Apple Pay, xuất CSV. Giá đặt trong App Store Connect (trọn đời 299.000đ, giá ra mắt 149.000đ; gói năm 99.000đ).
@MainActor
final class Pro: ObservableObject {
    static let shared = Pro()
    static let lifetimeID = "com.hnaht95.sochipay.pro.forever"
    static let yearlyID = "com.hnaht95.sochipay.pro.yearly"
    /// Số danh mục tự tạo được dùng miễn phí
    static let freeCategories = 2

    /// Đã mua Pro (nhớ lần kiểm tra gần nhất, để mở app không có mạng vẫn đúng)
    @Published private(set) var active: Bool
    /// Gói bán: gói năm trước, trọn đời sau
    @Published private(set) var products: [Product] = []
    /// Không tải được giá từ App Store (mất mạng…): màn mua hiện nút Thử lại thay vì vòng xoay mãi
    @Published private(set) var loadFailed = false
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
        Task { await checkTestBuild(); await load(); await refresh() }
    }

    /// Bản thử (TestFlight / chạy từ Xcode), không phải bản tải từ App Store: hiện công tắc "mở Pro" trong Cài đặt
    @Published private(set) var isTestBuild = false
    /// Công tắc mở Pro của bản thử (chỉ có tác dụng khi isTestBuild)
    @Published var testerUnlock: Bool = UserDefaults.standard.bool(forKey: "testerPro") {
        didSet { UserDefaults.standard.set(testerUnlock, forKey: "testerPro"); Task { await refresh() } }
    }

    private func checkTestBuild() async {
        #if DEBUG
        isTestBuild = true
        #else
        // Bản phát hành (TestFlight, App Store) không có công tắc này: người duyệt của App Store cũng chạy bằng hoá đơn thử
        // ("sandboxReceipt", môi trường .sandbox) như TestFlight, nên không phân biệt được — họ sẽ thấy công tắc mở Pro miễn phí
        // và từ chối app. Trên TestFlight mua Pro là mua thử, không mất tiền, nên người thử cứ mua như thật
        isTestBuild = false
        #endif
    }

    func load() async {
        guard products.isEmpty else { return }
        loadFailed = false
        guard let list = try? await Product.products(for: [Self.yearlyID, Self.lifetimeID]), !list.isEmpty else { loadFailed = true; return }
        products = list.sorted { a, _ in a.id == Self.yearlyID }
    }

    /// Gói đang dùng (hiện trong Cài đặt): trọn đời, hoặc gói năm kèm ngày gia hạn / hết hạn
    struct Plan: Equatable {
        var lifetime: Bool
        var expires: Date?
        /// Gói năm còn tự gia hạn không (nil: chưa đọc được)
        var renews: Bool?
    }
    /// nil: chưa mua (hoặc chỉ mở bằng công tắc bản thử)
    @Published private(set) var plan: Plan?

    /// Đọc lại quyền Pro từ các giao dịch còn hiệu lực
    func refresh() async {
        var on = false
        var plan: Plan?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil,
                  t.productID == Self.lifetimeID || t.productID == Self.yearlyID else { continue }
            on = true
            if t.productID == Self.lifetimeID { plan = Plan(lifetime: true) }
            else if plan?.lifetime != true { plan = Plan(lifetime: false, expires: t.expirationDate, renews: await Self.renews(t)) }
        }
        self.plan = plan
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "proOn") { on = true }
        #endif
        if isTestBuild && testerUnlock { on = true }
        set(on)
    }

    /// Gói năm còn tự gia hạn không: đọc trạng thái gói đăng ký của nhóm gói
    private static func renews(_ t: StoreKit.Transaction) async -> Bool? {
        guard let group = t.subscriptionGroupID,
              let statuses = try? await Product.SubscriptionInfo.status(for: group) else { return nil }
        for s in statuses {
            if case .verified(let r) = s.renewalInfo, r.currentProductID == yearlyID { return r.willAutoRenew }
        }
        return nil
    }

    /// Mở màn quản lý gói đăng ký của iOS (huỷ, đổi gói) ngay trong app
    func manage() async {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        try? await AppStore.showManageSubscriptions(in: scene)
        await refresh()
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
    case history, cloud, recurring, photos, categories, cardAuto, csv
    var id: String { rawValue }

    var title: String {
        switch self {
        case .history: L("Xem toàn bộ lịch sử")
        case .cloud: L("Đồng bộ iCloud")
        case .recurring: L("Khoản định kỳ")
        case .photos: L("Ảnh hoá đơn & ảnh danh mục")
        case .categories: L("Danh mục không giới hạn")
        case .cardAuto: L("Tự ghi khi trả Apple Pay")
        case .csv: L("Xuất CSV")
        }
    }

    var detail: String {
        switch self {
        case .history: L("Thống kê từ khoản chi đầu tiên")
        case .cloud: L("Dữ liệu trên mọi iPhone, iPad của bạn")
        case .recurring: L("Tiền nhà, điện, internet tự ghi mỗi tháng")
        case .photos: L("Đính kèm hoá đơn, ảnh cho danh mục")
        case .categories: L("Tạo bao nhiêu danh mục tuỳ ý")
        case .cardAuto: L("Quẹt thẻ là có khoản chi, không mở app")
        case .csv: L("Mở bằng Excel, Numbers")
        }
    }

    var icon: String {
        switch self {
        case .history: "chart.bar.fill"
        case .cloud: "icloud.fill"
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
        vc.sheetPresentationController?.prefersGrabberVisible = false   // như các bảng khác của app: không có vạch kéo
        if #unavailable(iOS 26.0) { vc.sheetPresentationController?.preferredCornerRadius = 38 }
        top.present(vc, animated: true)
    }

    private var lifetime: Product? { pro.products.first { $0.id == Pro.lifetimeID } }
    private var yearly: Product? { pro.products.first { $0.id == Pro.yearlyID } }
    private var chosen: Product? { pro.products.first { $0.id == pick } }

    /// Nền khung nhạt (nhạt hơn nền thẻ ở màn chính)
    private static let cardBG = Color(light: 0xF5F6F9, dark: 0x1D1D22)

    private var ordered: [ProFeature] {
        guard let feature else { return ProFeature.allCases }
        return [feature] + ProFeature.allCases.filter { $0 != feature }
    }

    var body: some View {
        ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        // "Payso Pro" viết tay như tiêu đề peakapp.vn: "Payso" màu chữ, "Pro" xanh lá
                        ZStack {
                            HandPayPro(word: 0).fill(Color.primary)
                            HandPayPro(word: 1).fill(Color(hex: 0x61BE6E))
                        }
                        .frame(width: 64 * HandPayPro.aspect, height: 64)
                        .accessibilityElement().accessibilityLabel("Payso Pro")
                        Text(L("Ghi chép luôn miễn phí. Pro dành cho khi bạn dùng Payso lâu dài."))
                            .font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(.top, 30).padding(.horizontal, 24)

                    // Mỗi tính năng một khung riêng: tiêu đề và mô tả.
                    // Mở từ tính năng nào thì khung đó lên đầu, viền xanh
                    VStack(spacing: 10) {
                        ForEach(ordered) { f in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(f.title).font(.system(size: 17, weight: .semibold))
                                Text(f.detail).font(.system(size: 15)).foregroundStyle(.secondary)
                                    .lineLimit(1).minimumScaleFactor(0.85)
                            }
                            // Khung nào cũng cao bằng nhau, chữ nằm giữa theo chiều dọc, lề trái phải bằng nhau
                            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                            .padding(.horizontal, 20)
                            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Self.cardBG))
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(f == feature ? Color(hex: 0x61BE6E) : .clear, lineWidth: 2))
                        }
                    }
                    .padding(.horizontal, 16)

                    if pro.products.isEmpty && pro.loadFailed {
                        Button { Task { await pro.load() } } label: {
                            VStack(spacing: 6) {
                                Text(L("Chưa tải được giá từ App Store")).font(.system(size: 15)).foregroundStyle(.secondary)
                                Text(L("Thử lại")).font(.system(size: 17, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity).frame(height: 96).contentShape(Rectangle())
                        }
                        .buttonStyle(Pressable()).foregroundStyle(.primary)
                    } else if pro.products.isEmpty {
                        ProgressView().frame(height: 96)
                    } else {
                        HStack(spacing: 10) {
                            if let lifetime { plan(lifetime, title: L("Trọn đời"), note: L("Trả một lần, dùng mãi")) }
                            if let yearly { plan(yearly, title: L("Gói năm"), note: L("Tự gia hạn, huỷ bất cứ lúc nào")) }
                        }
                        .padding(.horizontal, 16)
                    }
                    // Khôi phục / Điều khoản / Quyền riêng tư: cuối danh sách, dưới các gói
                    HStack(spacing: 18) {
                        Button(L("Khôi phục giao dịch")) { Task { await pro.restore(); if pro.active { dismiss() } } }
                        Link(L("Điều khoản"), destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        Link(L("Quyền riêng tư"), destination: URL(string: "https://peakapp.vn/pay/privacy.html")!)
                    }
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.top, 6)
                }
                .padding(.bottom, 16)
            }
        // Nút Mua luôn nằm trên thanh đáy, cùng kiểu Huỷ / Lưu của các màn khác: phía sau mờ dần như thanh tiêu đề
        .bottomBar {
            Button {
                if pro.active { dismiss(); return }
                guard let p = chosen, !pro.buying else { return }
                Task { if await pro.buy(p) { Haptic.tap(.medium); dismiss() } }
            } label: {
                Group {
                    if pro.buying || (chosen == nil && !pro.active && !pro.loadFailed) {
                        ProgressView().tint(.white)
                    } else {
                        Text(pro.active ? L("Đã mở Pro, cảm ơn bạn!") : chosen.map { L("Mua %@", $0.displayPrice) } ?? L("Mua"))
                            .font(.system(size: 21, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                // Cùng cỡ nút to của app (BigButton: cao 56 + lề 11 hai phía)
                .frame(maxWidth: .infinity).frame(height: 56 + BigButton.inset * 2)
                .background(Capsule().fill(Color(hex: 0x61BE6E)))
                .contentShape(Capsule())
            }
            .buttonStyle(Pressable())
            // Không tải được giá: nút mờ, không bấm được (bấm Thử lại ở trên)
            .disabled(chosen == nil && !pro.active)
            .opacity(chosen == nil && !pro.active && pro.loadFailed ? 0.45 : 1)
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, -18)
        }
        .background(Palette.surface.ignoresSafeArea())
        .task { await pro.load() }
    }

    private func plan(_ p: Product, title: String, note: String) -> some View {
        let on = pick == p.id
        return Button { if !on { Haptic.select() }; pick = p.id } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title).font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 20))
                        .foregroundStyle(on ? Color(hex: 0x61BE6E) : Color.primary.opacity(0.25))
                }
                Text(p.id == Pro.yearlyID ? L("%@/năm", p.displayPrice) : p.displayPrice)
                    .font(.system(size: 24, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                Text(note).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Self.cardBG))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(on ? Color(hex: 0x61BE6E) : .clear, lineWidth: 2.5))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(Pressable())
    }
}

extension ProFeature {
    /// Một dòng giới thiệu, từ khoá trong **…** được tô dạ quang
    var line: String {
        switch self {
        case .history: L("Xem **toàn bộ lịch sử**, từ khoản chi đầu tiên")
        case .cloud: L("**Đồng bộ iCloud** trên mọi iPhone, iPad")
        case .recurring: L("**Khoản định kỳ** tự ghi mỗi tháng")
        case .photos: L("**Ảnh hoá đơn** và ảnh riêng cho danh mục")
        case .categories: L("Tạo **danh mục không giới hạn**")
        case .cardAuto: L("**Tự ghi khi trả Apple Pay**, không cần mở app")
        case .csv: L("**Xuất CSV** mở bằng Excel, Numbers")
        }
    }

    /// Màu bút dạ quang của dòng (bảng màu danh mục của app)
    var marker: UInt32 {
        switch self {
        case .history: 0x5FB875
        case .cloud: 0x4FA6DB
        case .recurring: 0xB993FF
        case .photos: 0xF07B3F
        case .categories: 0x4FD1C5
        case .cardAuto: 0xEA5455
        case .csv: 0xFF8CC6
        }
    }
}

/// Nhãn "Pro" nhỏ cạnh tính năng cần Pro (chỉ hiện khi chưa mua): chữ Pro viết tay xanh lá như peakapp.vn
struct ProBadge: View {
    var height: CGFloat = 22
    var body: some View {
        HandPro().fill(Color(hex: 0x61BE6E))
            .frame(width: height * HandPro.aspect, height: height)
            .accessibilityLabel("Pro")
    }
}

/// Chữ "Payso Pro" viết tay, cùng nét chữ tiêu đề trên peakapp.vn (phông 1K Awesome Quote). Theo giấy phép phông chỉ được
/// dùng hình vẽ của cả từ, không nhúng phông: đây là hình của cụm "Payso Pro" (đường nét lấy từ phông bằng HarfBuzz, như
/// tools/hand-heading.py của trang web), vẽ lại bằng Path. `word`: 0 = "Payso", 1 = "Pro" (cùng hệ toạ độ, để tô hai màu)
struct HandPayPro: Shape {
    static let aspect: CGFloat = 2.1927
    var word: Int

    func path(in r: CGRect) -> Path {
        var path = Path()
        let k = r.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * k, y: r.minY + y * k) }
        func m(to a: CGPoint) { path.move(to: a) }
        func l(to a: CGPoint) { path.addLine(to: a) }
        func q(to a: CGPoint, control c: CGPoint) { path.addQuadCurve(to: a, control: c) }
        func c(to a: CGPoint, control1 c1: CGPoint, control2 c2: CGPoint) { path.addCurve(to: a, control1: c1, control2: c2) }
        func z() { path.closeSubpath() }
        if word == 0 {
            m(to: p(0.0954, 0.7974))
            q(to: p(0.0787, 0.7931), control: p(0.0861, 0.7974))
            q(to: p(0.0545, 0.7200), control: p(0.0626, 0.7844))
            q(to: p(0.0409, 0.4610), control: p(0.0446, 0.6437))
            q(to: p(0.0155, 0.4250), control: p(0.0155, 0.4535))
            q(to: p(0.0403, 0.3922), control: p(0.0155, 0.4002))
            q(to: p(0.0428, 0.2528), control: p(0.0403, 0.3209))
            q(to: p(0.0545, 0.0756), control: p(0.0483, 0.0948))
            q(to: p(0.0366, 0.0768), control: p(0.0458, 0.0768))
            q(to: p(0.0087, 0.0641), control: p(0.0173, 0.0768))
            q(to: p(0.0000, 0.0415), control: p(0.0000, 0.0514))
            q(to: p(0.0099, 0.0155), control: p(0.0000, 0.0248))
            q(to: p(0.0849, 0.0000), control: p(0.0273, 0.0000))
            q(to: p(0.1679, 0.0223), control: p(0.1301, 0.0000))
            q(to: p(0.2280, 0.0877), control: p(0.2057, 0.0446))
            q(to: p(0.2503, 0.1939), control: p(0.2503, 0.1307))
            q(to: p(0.2376, 0.2996), control: p(0.2503, 0.2447))
            q(to: p(0.1949, 0.3975), control: p(0.2249, 0.3544))
            q(to: p(0.1140, 0.4579), control: p(0.1648, 0.4405))
            q(to: p(0.1332, 0.7627), control: p(0.1177, 0.5861))
            q(to: p(0.1205, 0.7878), control: p(0.1332, 0.7782))
            q(to: p(0.0954, 0.7974), control: p(0.1078, 0.7974))
            z()
            m(to: p(0.1134, 0.3773))
            l(to: p(0.1146, 0.3767))
            q(to: p(0.1490, 0.3333), control: p(0.1344, 0.3606))
            q(to: p(0.1747, 0.2342), control: p(0.1636, 0.3061))
            q(to: p(0.1778, 0.1945), control: p(0.1778, 0.2144))
            q(to: p(0.1252, 0.0818), control: p(0.1778, 0.1128))
            l(to: p(0.1196, 0.1704))
            q(to: p(0.1134, 0.3773), control: p(0.1140, 0.2596))
            z()
            m(to: p(0.3178, 0.7695))
            q(to: p(0.2556, 0.7460), control: p(0.2807, 0.7695))
            q(to: p(0.2305, 0.6914), control: p(0.2305, 0.7224))
            q(to: p(0.2652, 0.6301), control: p(0.2305, 0.6524))
            q(to: p(0.3470, 0.6078), control: p(0.2999, 0.6078))
            q(to: p(0.4411, 0.6320), control: p(0.3934, 0.6078))
            l(to: p(0.4418, 0.5613))
            q(to: p(0.4170, 0.4603), control: p(0.4418, 0.4771))
            q(to: p(0.4139, 0.4572), control: p(0.4145, 0.4585))
            q(to: p(0.3748, 0.4473), control: p(0.3971, 0.4473))
            q(to: p(0.3082, 0.4616), control: p(0.3439, 0.4473))
            q(to: p(0.2472, 0.4957), control: p(0.2726, 0.4758))
            q(to: p(0.2277, 0.5108), control: p(0.2354, 0.5056))
            q(to: p(0.2094, 0.5161), control: p(0.2200, 0.5161))
            q(to: p(0.1843, 0.5062), control: p(0.1952, 0.5161))
            q(to: p(0.1735, 0.4796), control: p(0.1735, 0.4963))
            q(to: p(0.2063, 0.4343), control: p(0.1735, 0.4591))
            q(to: p(0.2862, 0.3919), control: p(0.2392, 0.4095))
            q(to: p(0.3742, 0.3742), control: p(0.3333, 0.3742))
            q(to: p(0.5143, 0.5576), control: p(0.5143, 0.3742))
            l(to: p(0.5155, 0.6691))
            q(to: p(0.5090, 0.7364), control: p(0.5155, 0.7169))
            q(to: p(0.4777, 0.7559), control: p(0.5025, 0.7559))
            q(to: p(0.4542, 0.7472), control: p(0.4616, 0.7559))
            q(to: p(0.4356, 0.7218), control: p(0.4498, 0.7429))
            q(to: p(0.3470, 0.6809), control: p(0.3996, 0.6809))
            q(to: p(0.3048, 0.6914), control: p(0.3154, 0.6809))
            q(to: p(0.3197, 0.6964), control: p(0.3067, 0.6964))
            q(to: p(0.3482, 0.6908), control: p(0.3333, 0.6964))
            q(to: p(0.3668, 0.6871), control: p(0.3594, 0.6871))
            q(to: p(0.3928, 0.6986), control: p(0.3823, 0.6871))
            q(to: p(0.4033, 0.7237), control: p(0.4033, 0.7100))
            q(to: p(0.3894, 0.7509), control: p(0.4033, 0.7410))
            q(to: p(0.3556, 0.7652), control: p(0.3755, 0.7608))
            q(to: p(0.3178, 0.7695), control: p(0.3358, 0.7695))
            z()
            m(to: p(0.5446, 1.0000))
            q(to: p(0.4610, 0.9823), control: p(0.4957, 1.0000))
            q(to: p(0.4080, 0.9421), control: p(0.4263, 0.9647))
            q(to: p(0.3897, 0.9033), control: p(0.3897, 0.9195))
            q(to: p(0.3999, 0.8779), control: p(0.3897, 0.8891))
            q(to: p(0.4250, 0.8668), control: p(0.4102, 0.8668))
            q(to: p(0.4610, 0.8903), control: p(0.4492, 0.8668))
            q(to: p(0.4752, 0.9058), control: p(0.4659, 0.9002))
            q(to: p(0.5428, 0.9269), control: p(0.5081, 0.9269))
            q(to: p(0.6084, 0.9126), control: p(0.5750, 0.9269))
            q(to: p(0.6543, 0.8860), control: p(0.6276, 0.9040))
            l(to: p(0.6524, 0.8866))
            q(to: p(0.7128, 0.8030), control: p(0.6970, 0.8494))
            q(to: p(0.7286, 0.7069), control: p(0.7286, 0.7565))
            q(to: p(0.7230, 0.6406), control: p(0.7286, 0.6735))
            q(to: p(0.6865, 0.6691), control: p(0.7057, 0.6580))
            q(to: p(0.6413, 0.6803), control: p(0.6673, 0.6803))
            q(to: p(0.5871, 0.6651), control: p(0.6121, 0.6803))
            q(to: p(0.5465, 0.6211), control: p(0.5620, 0.6499))
            q(to: p(0.5310, 0.5514), control: p(0.5310, 0.5923))
            q(to: p(0.5527, 0.4641), control: p(0.5310, 0.4783))
            q(to: p(0.5750, 0.4572), control: p(0.5632, 0.4572))
            q(to: p(0.5998, 0.4665), control: p(0.5886, 0.4572))
            q(to: p(0.6109, 0.4950), control: p(0.6109, 0.4758))
            q(to: p(0.6084, 0.5105), control: p(0.6109, 0.5012))
            q(to: p(0.6035, 0.5514), control: p(0.6035, 0.5235))
            q(to: p(0.6227, 0.6010), control: p(0.6035, 0.5849))
            q(to: p(0.6406, 0.6072), control: p(0.6332, 0.6072))
            q(to: p(0.6710, 0.5898), control: p(0.6537, 0.6072))
            q(to: p(0.6958, 0.5700), control: p(0.6815, 0.5793))
            q(to: p(0.7323, 0.5607), control: p(0.7100, 0.5607))
            q(to: p(0.7788, 0.5846), control: p(0.7639, 0.5607))
            q(to: p(0.7977, 0.6434), control: p(0.7937, 0.6084))
            q(to: p(0.8017, 0.7119), control: p(0.8017, 0.6784))
            q(to: p(0.7776, 0.8386), control: p(0.8017, 0.7844))
            q(to: p(0.7153, 0.9284), control: p(0.7534, 0.8928))
            q(to: p(0.6320, 0.9820), control: p(0.6772, 0.9641))
            q(to: p(0.5446, 1.0000), control: p(0.5867, 1.0000))
            z()
            m(to: p(0.8625, 0.7980))
            q(to: p(0.8374, 0.7859), control: p(0.8470, 0.7980))
            q(to: p(0.8278, 0.7602), control: p(0.8278, 0.7739))
            q(to: p(0.8377, 0.7373), control: p(0.8278, 0.7478))
            q(to: p(0.8656, 0.7249), control: p(0.8476, 0.7268))
            q(to: p(0.8993, 0.7029), control: p(0.8885, 0.7200))
            q(to: p(0.9102, 0.6667), control: p(0.9102, 0.6859))
            q(to: p(0.8897, 0.5929), control: p(0.9102, 0.6431))
            q(to: p(0.8656, 0.4969), control: p(0.8656, 0.5347))
            q(to: p(0.8798, 0.4368), control: p(0.8656, 0.4622))
            q(to: p(0.9160, 0.3975), control: p(0.8941, 0.4114))
            q(to: p(0.9622, 0.3835), control: p(0.9380, 0.3835))
            q(to: p(0.9867, 0.3959), control: p(0.9771, 0.3835))
            q(to: p(0.9963, 0.4213), control: p(0.9963, 0.4083))
            q(to: p(0.9876, 0.4439), control: p(0.9963, 0.4337))
            q(to: p(0.9628, 0.4566), control: p(0.9789, 0.4542))
            q(to: p(0.9387, 0.4969), control: p(0.9387, 0.4634))
            q(to: p(0.9572, 0.5651), control: p(0.9387, 0.5186))
            q(to: p(0.9827, 0.6667), control: p(0.9827, 0.6239))
            q(to: p(0.9464, 0.7590), control: p(0.9827, 0.7200))
            q(to: p(0.8625, 0.7980), control: p(0.9102, 0.7980))
            z()
            m(to: p(1.1029, 0.7416))
            q(to: p(1.0483, 0.7234), control: p(1.0706, 0.7416))
            q(to: p(1.0143, 0.6750), control: p(1.0260, 0.7051))
            q(to: p(1.0025, 0.6090), control: p(1.0025, 0.6450))
            q(to: p(1.0180, 0.5248), control: p(1.0025, 0.5626))
            q(to: p(1.0555, 0.4597), control: p(1.0335, 0.4870))
            q(to: p(1.0991, 0.4176), control: p(1.0774, 0.4325))
            q(to: p(1.1326, 0.4027), control: p(1.1208, 0.4027))
            q(to: p(1.1580, 0.4129), control: p(1.1462, 0.4027))
            q(to: p(1.1698, 0.4380), control: p(1.1698, 0.4232))
            q(to: p(1.1617, 0.4631), control: p(1.1698, 0.4548))
            q(to: p(1.1437, 0.4765), control: p(1.1537, 0.4715))
            l(to: p(1.1332, 0.4839))
            l(to: p(1.1400, 0.4833))
            q(to: p(1.1729, 0.4994), control: p(1.1549, 0.4833))
            q(to: p(1.2042, 0.5431), control: p(1.1908, 0.5155))
            q(to: p(1.2175, 0.6059), control: p(1.2175, 0.5706))
            q(to: p(1.2011, 0.6775), control: p(1.2175, 0.6468))
            q(to: p(1.1586, 0.7249), control: p(1.1846, 0.7082))
            q(to: p(1.1029, 0.7416), control: p(1.1326, 0.7416))
            z()
            m(to: p(1.1022, 0.6679))
            q(to: p(1.1310, 0.6530), control: p(1.1177, 0.6679))
            q(to: p(1.1444, 0.6059), control: p(1.1444, 0.6382))
            q(to: p(1.1366, 0.5703), control: p(1.1444, 0.5824))
            q(to: p(1.1202, 0.5502), control: p(1.1289, 0.5582))
            q(to: p(1.1087, 0.5375), control: p(1.1134, 0.5440))
            q(to: p(1.1041, 0.5167), control: p(1.1041, 0.5310))
            q(to: p(1.0756, 0.6084), control: p(1.0756, 0.5613))
            q(to: p(1.0905, 0.6636), control: p(1.0756, 0.6406))
            q(to: p(1.0911, 0.6642), control: p(1.0911, 0.6636))
            l(to: p(1.0929, 0.6648))
            q(to: p(1.1022, 0.6679), control: p(1.0973, 0.6679))
            z()
        } else {
            m(to: p(1.6592, 0.7974))
            q(to: p(1.6425, 0.7931), control: p(1.6499, 0.7974))
            q(to: p(1.6183, 0.7200), control: p(1.6264, 0.7844))
            q(to: p(1.6047, 0.4610), control: p(1.6084, 0.6437))
            q(to: p(1.5793, 0.4250), control: p(1.5793, 0.4535))
            q(to: p(1.6041, 0.3922), control: p(1.5793, 0.4002))
            q(to: p(1.6066, 0.2528), control: p(1.6041, 0.3209))
            q(to: p(1.6183, 0.0756), control: p(1.6121, 0.0948))
            q(to: p(1.6004, 0.0768), control: p(1.6097, 0.0768))
            q(to: p(1.5725, 0.0641), control: p(1.5812, 0.0768))
            q(to: p(1.5638, 0.0415), control: p(1.5638, 0.0514))
            q(to: p(1.5737, 0.0155), control: p(1.5638, 0.0248))
            q(to: p(1.6487, 0.0000), control: p(1.5911, 0.0000))
            q(to: p(1.7317, 0.0223), control: p(1.6939, 0.0000))
            q(to: p(1.7918, 0.0877), control: p(1.7695, 0.0446))
            q(to: p(1.8141, 0.1939), control: p(1.8141, 0.1307))
            q(to: p(1.8014, 0.2996), control: p(1.8141, 0.2447))
            q(to: p(1.7587, 0.3975), control: p(1.7887, 0.3544))
            q(to: p(1.6778, 0.4579), control: p(1.7286, 0.4405))
            q(to: p(1.6970, 0.7627), control: p(1.6815, 0.5861))
            q(to: p(1.6843, 0.7878), control: p(1.6970, 0.7782))
            q(to: p(1.6592, 0.7974), control: p(1.6716, 0.7974))
            z()
            m(to: p(1.6772, 0.3773))
            l(to: p(1.6784, 0.3767))
            q(to: p(1.7128, 0.3333), control: p(1.6983, 0.3606))
            q(to: p(1.7385, 0.2342), control: p(1.7274, 0.3061))
            q(to: p(1.7416, 0.1945), control: p(1.7416, 0.2144))
            q(to: p(1.6890, 0.0818), control: p(1.7416, 0.1128))
            l(to: p(1.6834, 0.1704))
            q(to: p(1.6772, 0.3773), control: p(1.6778, 0.2596))
            z()
            m(to: p(1.8030, 0.7497))
            q(to: p(1.7788, 0.7388), control: p(1.7900, 0.7497))
            q(to: p(1.7677, 0.7144), control: p(1.7677, 0.7280))
            l(to: p(1.7819, 0.4393))
            q(to: p(1.7940, 0.4126), control: p(1.7831, 0.4226))
            q(to: p(1.8197, 0.4027), control: p(1.8048, 0.4027))
            q(to: p(1.8442, 0.4133), control: p(1.8340, 0.4027))
            q(to: p(1.8550, 0.4380), control: p(1.8544, 0.4238))
            l(to: p(1.8513, 0.5087))
            q(to: p(1.9260, 0.4486), control: p(1.8879, 0.4690))
            q(to: p(1.9746, 0.4281), control: p(1.9641, 0.4281))
            q(to: p(2.0000, 0.4399), control: p(1.9888, 0.4281))
            q(to: p(2.0112, 0.4659), control: p(2.0112, 0.4517))
            q(to: p(1.9808, 0.5025), control: p(2.0112, 0.4895))
            q(to: p(1.9374, 0.5279), control: p(1.9591, 0.5124))
            q(to: p(1.8984, 0.5663), control: p(1.9263, 0.5341))
            q(to: p(1.8686, 0.6165), control: p(1.8786, 0.5936))
            q(to: p(1.8519, 0.7057), control: p(1.8519, 0.6549))
            q(to: p(1.8321, 0.7367), control: p(1.8519, 0.7261))
            q(to: p(1.8030, 0.7497), control: p(1.8191, 0.7497))
            z()
            m(to: p(2.0781, 0.7416))
            q(to: p(2.0235, 0.7234), control: p(2.0458, 0.7416))
            q(to: p(1.9895, 0.6750), control: p(2.0012, 0.7051))
            q(to: p(1.9777, 0.6090), control: p(1.9777, 0.6450))
            q(to: p(1.9932, 0.5248), control: p(1.9777, 0.5626))
            q(to: p(2.0307, 0.4597), control: p(2.0087, 0.4870))
            q(to: p(2.0743, 0.4176), control: p(2.0527, 0.4325))
            q(to: p(2.1078, 0.4027), control: p(2.0960, 0.4027))
            q(to: p(2.1332, 0.4129), control: p(2.1214, 0.4027))
            q(to: p(2.1450, 0.4380), control: p(2.1450, 0.4232))
            q(to: p(2.1369, 0.4631), control: p(2.1450, 0.4548))
            q(to: p(2.1190, 0.4765), control: p(2.1289, 0.4715))
            l(to: p(2.1084, 0.4839))
            l(to: p(2.1152, 0.4833))
            q(to: p(2.1481, 0.4994), control: p(2.1301, 0.4833))
            q(to: p(2.1794, 0.5431), control: p(2.1660, 0.5155))
            q(to: p(2.1927, 0.6059), control: p(2.1927, 0.5706))
            q(to: p(2.1763, 0.6775), control: p(2.1927, 0.6468))
            q(to: p(2.1338, 0.7249), control: p(2.1599, 0.7082))
            q(to: p(2.0781, 0.7416), control: p(2.1078, 0.7416))
            z()
            m(to: p(2.0774, 0.6679))
            q(to: p(2.1063, 0.6530), control: p(2.0929, 0.6679))
            q(to: p(2.1196, 0.6059), control: p(2.1196, 0.6382))
            q(to: p(2.1118, 0.5703), control: p(2.1196, 0.5824))
            q(to: p(2.0954, 0.5502), control: p(2.1041, 0.5582))
            q(to: p(2.0840, 0.5375), control: p(2.0886, 0.5440))
            q(to: p(2.0793, 0.5167), control: p(2.0793, 0.5310))
            q(to: p(2.0508, 0.6084), control: p(2.0508, 0.5613))
            q(to: p(2.0657, 0.6636), control: p(2.0508, 0.6406))
            q(to: p(2.0663, 0.6642), control: p(2.0663, 0.6636))
            l(to: p(2.0682, 0.6648))
            q(to: p(2.0774, 0.6679), control: p(2.0725, 0.6679))
            z()
        }
        return path
    }
}

/// Chữ "Pro" viết tay (cùng nét tiêu đề peakapp.vn, hình vẽ của cả từ, xem HandPayPro) cho nhãn Pro nhỏ
struct HandPro: Shape {
    static let aspect: CGFloat = 0.7887

    func path(in r: CGRect) -> Path {
        var path = Path()
        let k = r.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * k, y: r.minY + y * k) }
        func m(to a: CGPoint) { path.move(to: a) }
        func l(to a: CGPoint) { path.addLine(to: a) }
        func q(to a: CGPoint, control c: CGPoint) { path.addQuadCurve(to: a, control: c) }
        func c(to a: CGPoint, control1 c1: CGPoint, control2 c2: CGPoint) { path.addCurve(to: a, control1: c1, control2: c2) }
        func z() { path.closeSubpath() }
        m(to: p(0.1197, 1.0000))
        q(to: p(0.0987, 0.9946), control: p(0.1080, 1.0000))
        q(to: p(0.0684, 0.9029), control: p(0.0785, 0.9837))
        q(to: p(0.0513, 0.5781), control: p(0.0559, 0.8073))
        q(to: p(0.0194, 0.5330), control: p(0.0194, 0.5688))
        q(to: p(0.0505, 0.4918), control: p(0.0194, 0.5019))
        q(to: p(0.0536, 0.3170), control: p(0.0505, 0.4025))
        q(to: p(0.0684, 0.0948), control: p(0.0606, 0.1189))
        q(to: p(0.0458, 0.0963), control: p(0.0575, 0.0963))
        q(to: p(0.0109, 0.0804), control: p(0.0218, 0.0963))
        q(to: p(0.0000, 0.0521), control: p(0.0000, 0.0645))
        q(to: p(0.0124, 0.0194), control: p(0.0000, 0.0311))
        q(to: p(0.1064, 0.0000), control: p(0.0342, 0.0000))
        q(to: p(0.2106, 0.0280), control: p(0.1632, 0.0000))
        q(to: p(0.2859, 0.1099), control: p(0.2580, 0.0559))
        q(to: p(0.3139, 0.2432), control: p(0.3139, 0.1639))
        q(to: p(0.2980, 0.3757), control: p(0.3139, 0.3069))
        q(to: p(0.2444, 0.4984), control: p(0.2821, 0.4444))
        q(to: p(0.1430, 0.5742), control: p(0.2067, 0.5524))
        q(to: p(0.1671, 0.9565), control: p(0.1476, 0.7350))
        q(to: p(0.1511, 0.9880), control: p(0.1671, 0.9759))
        q(to: p(0.1197, 1.0000), control: p(0.1352, 1.0000))
        z()
        m(to: p(0.1422, 0.4732))
        l(to: p(0.1437, 0.4724))
        q(to: p(0.1869, 0.4180), control: p(0.1686, 0.4522))
        q(to: p(0.2191, 0.2937), control: p(0.2051, 0.3838))
        q(to: p(0.2230, 0.2440), control: p(0.2230, 0.2688))
        q(to: p(0.1570, 0.1026), control: p(0.2230, 0.1414))
        l(to: p(0.1500, 0.2137))
        q(to: p(0.1422, 0.4732), control: p(0.1430, 0.3256))
        z()
        m(to: p(0.2999, 0.9402))
        q(to: p(0.2696, 0.9266), control: p(0.2836, 0.9402))
        q(to: p(0.2556, 0.8959), control: p(0.2556, 0.9130))
        l(to: p(0.2735, 0.5509))
        q(to: p(0.2887, 0.5175), control: p(0.2751, 0.5299))
        q(to: p(0.3209, 0.5051), control: p(0.3023, 0.5051))
        q(to: p(0.3516, 0.5183), control: p(0.3388, 0.5051))
        q(to: p(0.3652, 0.5493), control: p(0.3644, 0.5315))
        l(to: p(0.3605, 0.6379))
        q(to: p(0.4542, 0.5625), control: p(0.4064, 0.5882))
        q(to: p(0.5152, 0.5369), control: p(0.5019, 0.5369))
        q(to: p(0.5470, 0.5517), control: p(0.5330, 0.5369))
        q(to: p(0.5610, 0.5843), control: p(0.5610, 0.5664))
        q(to: p(0.5229, 0.6301), control: p(0.5610, 0.6138))
        q(to: p(0.4685, 0.6620), control: p(0.4957, 0.6426))
        q(to: p(0.4196, 0.7102), control: p(0.4545, 0.6698))
        q(to: p(0.3823, 0.7731), control: p(0.3947, 0.7444))
        q(to: p(0.3613, 0.8850), control: p(0.3613, 0.8213))
        q(to: p(0.3364, 0.9239), control: p(0.3613, 0.9106))
        q(to: p(0.2999, 0.9402), control: p(0.3201, 0.9402))
        z()
        m(to: p(0.6449, 0.9301))
        q(to: p(0.5765, 0.9071), control: p(0.6045, 0.9301))
        q(to: p(0.5338, 0.8465), control: p(0.5486, 0.8842))
        q(to: p(0.5190, 0.7638), control: p(0.5190, 0.8089))
        q(to: p(0.5385, 0.6581), control: p(0.5190, 0.7055))
        q(to: p(0.5855, 0.5765), control: p(0.5579, 0.6107))
        q(to: p(0.6402, 0.5237), control: p(0.6131, 0.5423))
        q(to: p(0.6822, 0.5051), control: p(0.6674, 0.5051))
        q(to: p(0.7141, 0.5179), control: p(0.6993, 0.5051))
        q(to: p(0.7288, 0.5493), control: p(0.7288, 0.5307))
        q(to: p(0.7187, 0.5808), control: p(0.7288, 0.5703))
        q(to: p(0.6962, 0.5975), control: p(0.7086, 0.5913))
        l(to: p(0.6830, 0.6068))
        l(to: p(0.6915, 0.6061))
        q(to: p(0.7327, 0.6263), control: p(0.7102, 0.6061))
        q(to: p(0.7720, 0.6810), control: p(0.7552, 0.6465))
        q(to: p(0.7887, 0.7599), control: p(0.7887, 0.7156))
        q(to: p(0.7681, 0.8497), control: p(0.7887, 0.8112))
        q(to: p(0.7148, 0.9091), control: p(0.7475, 0.8881))
        q(to: p(0.6449, 0.9301), control: p(0.6822, 0.9301))
        z()
        m(to: p(0.6441, 0.8376))
        q(to: p(0.6803, 0.8190), control: p(0.6636, 0.8376))
        q(to: p(0.6970, 0.7599), control: p(0.6970, 0.8003))
        q(to: p(0.6873, 0.7152), control: p(0.6970, 0.7304))
        q(to: p(0.6667, 0.6900), control: p(0.6775, 0.7001))
        q(to: p(0.6523, 0.6740), control: p(0.6581, 0.6822))
        q(to: p(0.6465, 0.6480), control: p(0.6465, 0.6659))
        q(to: p(0.6107, 0.7630), control: p(0.6107, 0.7040))
        q(to: p(0.6294, 0.8322), control: p(0.6107, 0.8034))
        q(to: p(0.6301, 0.8329), control: p(0.6301, 0.8322))
        l(to: p(0.6325, 0.8337))
        q(to: p(0.6441, 0.8376), control: p(0.6379, 0.8376))
        z()
        return path
    }
}
