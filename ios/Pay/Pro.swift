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

    private var ordered: [ProFeature] {
        guard let feature else { return ProFeature.allCases }
        return [feature] + ProFeature.allCases.filter { $0 != feature }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        // "Pay" chữ đậm của app, "Pro" viết tay như tiêu đề peakapp.vn
                        HStack(alignment: .lastTextBaseline, spacing: 6) {
                            Text("Pay").font(.system(size: 40, weight: .bold))
                            HandPro().fill(Color(hex: 0x61BE6E))
                                .frame(width: 58 * HandPro.aspect, height: 58)
                                .alignmentGuide(.lastTextBaseline) { $0.height * 0.86 }
                        }
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
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.card))
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
    /// Một dòng giới thiệu, từ khoá trong **…** được tô dạ quang
    var line: String {
        switch self {
        case .history: L("Xem **toàn bộ lịch sử**, từ khoản chi đầu tiên")
        case .cloud: L("**Đồng bộ iCloud** trên mọi iPhone, iPad")
        case .house: L("**Nhóm chung**: chia tiền với gia đình, bạn bè")
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
        case .house: 0xFFC800
        case .recurring: 0xB993FF
        case .photos: 0xF07B3F
        case .categories: 0x4FD1C5
        case .cardAuto: 0xEA5455
        case .csv: 0xFF8CC6
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

/// Chữ "Pro" viết tay, cùng nét chữ tiêu đề trên peakapp.vn (phông 1K Awesome Quote). Theo giấy phép phông chỉ được dùng
/// hình vẽ của cả từ, không nhúng phông: đây là hình của từ "Pro" (đường nét lấy từ phông bằng HarfBuzz, như
/// tools/hand-heading.py của trang web), vẽ lại bằng Path. Tỉ lệ rộng / cao: 0.7887
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
