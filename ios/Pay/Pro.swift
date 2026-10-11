import StoreKit
import SwiftUI
import UIKit

/// Pay Pro: mua một lần (trọn đời) hoặc gói năm, qua StoreKit 2.
///
/// Ghi chép (quét QR, nhập, nói để ghi) luôn miễn phí. Pro mở những thứ người dùng lâu mới cần: xem lịch sử xa hơn hai tháng,
/// đồng bộ iCloud, khoản định kỳ, ảnh hoá đơn / ảnh danh mục, danh mục tự tạo không giới hạn, tự ghi khi trả
/// Apple Pay, xuất CSV. Giá đặt trong App Store Connect (trọn đời 299.000đ, giá ra mắt 149.000đ; gói năm 79.000đ).
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
                        // "Pay Pro" viết tay như tiêu đề peakapp.vn: "Pay" màu chữ, "Pro" xanh lá
                        ZStack {
                            HandPayPro(word: 0).fill(Color.primary)
                            HandPayPro(word: 1).fill(Color(hex: 0x61BE6E))
                        }
                        .frame(width: 64 * HandPayPro.aspect, height: 64)
                        .accessibilityElement().accessibilityLabel("Pay Pro")
                        Text(L("Ghi chép luôn miễn phí. Pro dành cho khi bạn dùng Pay lâu dài."))
                            .font(.system(size: 16)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(.top, 30).padding(.horizontal, 24)

                    // Mỗi tính năng một khung riêng: tiêu đề và mô tả.
                    // Mở từ tính năng nào thì khung đó lên đầu, viền xanh
                    VStack(spacing: 10) {
                        ForEach(ordered) { f in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(f.title).font(.system(size: 18, weight: .semibold))
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

                    if pro.products.isEmpty {
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
                    if pro.buying || (chosen == nil && !pro.active) {
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

/// Chữ "Pay Pro" viết tay, cùng nét chữ tiêu đề trên peakapp.vn (phông 1K Awesome Quote). Theo giấy phép phông chỉ được
/// dùng hình vẽ của cả từ, không nhúng phông: đây là hình của cụm "Pay Pro" (đường nét lấy từ phông bằng HarfBuzz, như
/// tools/hand-heading.py của trang web), vẽ lại bằng Path. `word`: 0 = "Pay", 1 = "Pro" (cùng hệ toạ độ, để tô hai màu)
struct HandPayPro: Shape {
    static let aspect: CGFloat = 1.7689
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
        } else {
            m(to: p(1.2354, 0.7974))
            q(to: p(1.2187, 0.7931), control: p(1.2261, 0.7974))
            q(to: p(1.1945, 0.7200), control: p(1.2026, 0.7844))
            q(to: p(1.1809, 0.4610), control: p(1.1846, 0.6437))
            q(to: p(1.1555, 0.4250), control: p(1.1555, 0.4535))
            q(to: p(1.1803, 0.3922), control: p(1.1555, 0.4002))
            q(to: p(1.1828, 0.2528), control: p(1.1803, 0.3209))
            q(to: p(1.1945, 0.0756), control: p(1.1884, 0.0948))
            q(to: p(1.1766, 0.0768), control: p(1.1859, 0.0768))
            q(to: p(1.1487, 0.0641), control: p(1.1574, 0.0768))
            q(to: p(1.1400, 0.0415), control: p(1.1400, 0.0514))
            q(to: p(1.1499, 0.0155), control: p(1.1400, 0.0248))
            q(to: p(1.2249, 0.0000), control: p(1.1673, 0.0000))
            q(to: p(1.3079, 0.0223), control: p(1.2701, 0.0000))
            q(to: p(1.3680, 0.0877), control: p(1.3457, 0.0446))
            q(to: p(1.3903, 0.1939), control: p(1.3903, 0.1307))
            q(to: p(1.3776, 0.2996), control: p(1.3903, 0.2447))
            q(to: p(1.3349, 0.3975), control: p(1.3649, 0.3544))
            q(to: p(1.2540, 0.4579), control: p(1.3048, 0.4405))
            q(to: p(1.2732, 0.7627), control: p(1.2577, 0.5861))
            q(to: p(1.2605, 0.7878), control: p(1.2732, 0.7782))
            q(to: p(1.2354, 0.7974), control: p(1.2478, 0.7974))
            z()
            m(to: p(1.2534, 0.3773))
            l(to: p(1.2546, 0.3767))
            q(to: p(1.2890, 0.3333), control: p(1.2745, 0.3606))
            q(to: p(1.3147, 0.2342), control: p(1.3036, 0.3061))
            q(to: p(1.3178, 0.1945), control: p(1.3178, 0.2144))
            q(to: p(1.2652, 0.0818), control: p(1.3178, 0.1128))
            l(to: p(1.2596, 0.1704))
            q(to: p(1.2534, 0.3773), control: p(1.2540, 0.2596))
            z()
            m(to: p(1.3792, 0.7497))
            q(to: p(1.3550, 0.7388), control: p(1.3662, 0.7497))
            q(to: p(1.3439, 0.7144), control: p(1.3439, 0.7280))
            l(to: p(1.3581, 0.4393))
            q(to: p(1.3702, 0.4126), control: p(1.3594, 0.4226))
            q(to: p(1.3959, 0.4027), control: p(1.3810, 0.4027))
            q(to: p(1.4204, 0.4133), control: p(1.4102, 0.4027))
            q(to: p(1.4312, 0.4380), control: p(1.4306, 0.4238))
            l(to: p(1.4275, 0.5087))
            q(to: p(1.5022, 0.4486), control: p(1.4641, 0.4690))
            q(to: p(1.5508, 0.4281), control: p(1.5403, 0.4281))
            q(to: p(1.5762, 0.4399), control: p(1.5651, 0.4281))
            q(to: p(1.5874, 0.4659), control: p(1.5874, 0.4517))
            q(to: p(1.5570, 0.5025), control: p(1.5874, 0.4895))
            q(to: p(1.5136, 0.5279), control: p(1.5353, 0.5124))
            q(to: p(1.4746, 0.5663), control: p(1.5025, 0.5341))
            q(to: p(1.4449, 0.6165), control: p(1.4548, 0.5936))
            q(to: p(1.4281, 0.7057), control: p(1.4281, 0.6549))
            q(to: p(1.4083, 0.7367), control: p(1.4281, 0.7261))
            q(to: p(1.3792, 0.7497), control: p(1.3953, 0.7497))
            z()
            m(to: p(1.6543, 0.7416))
            q(to: p(1.5998, 0.7234), control: p(1.6221, 0.7416))
            q(to: p(1.5657, 0.6750), control: p(1.5774, 0.7051))
            q(to: p(1.5539, 0.6090), control: p(1.5539, 0.6450))
            q(to: p(1.5694, 0.5248), control: p(1.5539, 0.5626))
            q(to: p(1.6069, 0.4597), control: p(1.5849, 0.4870))
            q(to: p(1.6506, 0.4176), control: p(1.6289, 0.4325))
            q(to: p(1.6840, 0.4027), control: p(1.6722, 0.4027))
            q(to: p(1.7094, 0.4129), control: p(1.6976, 0.4027))
            q(to: p(1.7212, 0.4380), control: p(1.7212, 0.4232))
            q(to: p(1.7131, 0.4631), control: p(1.7212, 0.4548))
            q(to: p(1.6952, 0.4765), control: p(1.7051, 0.4715))
            l(to: p(1.6846, 0.4839))
            l(to: p(1.6914, 0.4833))
            q(to: p(1.7243, 0.4994), control: p(1.7063, 0.4833))
            q(to: p(1.7556, 0.5431), control: p(1.7423, 0.5155))
            q(to: p(1.7689, 0.6059), control: p(1.7689, 0.5706))
            q(to: p(1.7525, 0.6775), control: p(1.7689, 0.6468))
            q(to: p(1.7100, 0.7249), control: p(1.7361, 0.7082))
            q(to: p(1.6543, 0.7416), control: p(1.6840, 0.7416))
            z()
            m(to: p(1.6537, 0.6679))
            q(to: p(1.6825, 0.6530), control: p(1.6691, 0.6679))
            q(to: p(1.6958, 0.6059), control: p(1.6958, 0.6382))
            q(to: p(1.6880, 0.5703), control: p(1.6958, 0.5824))
            q(to: p(1.6716, 0.5502), control: p(1.6803, 0.5582))
            q(to: p(1.6602, 0.5375), control: p(1.6648, 0.5440))
            q(to: p(1.6555, 0.5167), control: p(1.6555, 0.5310))
            q(to: p(1.6270, 0.6084), control: p(1.6270, 0.5613))
            q(to: p(1.6419, 0.6636), control: p(1.6270, 0.6406))
            q(to: p(1.6425, 0.6642), control: p(1.6425, 0.6636))
            l(to: p(1.6444, 0.6648))
            q(to: p(1.6537, 0.6679), control: p(1.6487, 0.6679))
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
