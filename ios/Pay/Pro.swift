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
                    .frame(height: 330)
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
            ProArt(feature: f)
                .frame(maxWidth: .infinity).frame(height: 220)
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

/// Hình minh hoạ từng tính năng, vẽ bằng SwiftUI theo đúng các thành phần của app (viên tháng, ô danh mục, hàng khoản chi…)
struct ProArt: View {
    let feature: ProFeature
    private let ink = Color(hex: 0x111114)

    var body: some View {
        switch feature {
        case .history: history
        case .cloud: cloud
        case .house: house
        case .recurring: recurring
        case .photos: photos
        case .categories: categories
        case .cardAuto: cardAuto
        case .csv: csv
        }
    }

    /// Dải viên tháng như Thống kê: tháng cũ mờ có ổ khoá, mở Pro là sáng hết
    private var history: some View {
        let levels: [CGFloat] = [0.45, 0.7, 0.55, 0.9, 0.6, 0.8, 0.5]
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<7, id: \.self) { i in
                VStack(spacing: 0) {
                    Text("\(4 + i)").font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(i == 6 ? .white : ink.opacity(0.8)).padding(.top, 7)
                    Spacer(minLength: 0)
                    UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7, style: .continuous)
                        .fill(i == 6 ? Color.white.opacity(0.3) : ink.opacity(0.12))
                        .frame(height: 96 * levels[i]).padding(3)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .frame(width: 32, height: 132)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(i == 6 ? ink : .white))
            }
        }
        .overlay(alignment: .topLeading) {
            Image(systemName: "lock.open.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(width: 34, height: 34).background(Circle().fill(Color(hex: 0x61BE6E)))
                .offset(x: -22, y: -24)
        }
    }

    /// iPhone và iPad cùng một dữ liệu, đám mây ở giữa
    private var cloud: some View {
        HStack(spacing: 18) {
            device(w: 62, h: 118, r: 14)
            Image(systemName: "icloud.fill").font(.system(size: 40)).foregroundStyle(.white)
                .overlay(Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: 0x3E9BD6)).offset(y: 3))
            device(w: 104, h: 136, r: 16)
        }
    }

    private func device(w: CGFloat, h: CGFloat, r: CGFloat) -> some View {
        VStack(spacing: 5) {
            ForEach(0..<4, id: \.self) { i in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill([Color(hex: 0xF07B3F), Color(hex: 0xFFD43B), Color(hex: 0xEA5455), Color(hex: 0x61BE6E)][i])
                        .frame(width: 10, height: 10)
                    Capsule().fill(ink.opacity(0.15)).frame(height: 5)
                }
            }
        }
        .padding(10)
        .frame(width: w, height: h)
        .background(RoundedRectangle(cornerRadius: r, style: .continuous).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(ink, lineWidth: 3))
    }

    /// Ba người, một hoá đơn chia ba
    private var house: some View {
        VStack(spacing: 14) {
            HStack(spacing: -12) {
                ForEach(Array(["A", "B", "C"].enumerated()), id: \.offset) { i, n in
                    Text(n).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(Circle().fill([Color(hex: 0xF07B3F), Color(hex: 0xEA5455), Color(hex: 0x3E9BD6)][i]))
                        .overlay(Circle().strokeBorder(Color(hex: 0xFFD43B), lineWidth: 4))
                }
            }
            HStack(spacing: 10) {
                Text("🍲").font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Lẩu cuối tuần")).font(.system(size: 14, weight: .semibold)).foregroundStyle(ink).lineLimit(1).fixedSize()
                    Text("÷ 3").font(.system(size: 12, weight: .medium)).foregroundStyle(ink.opacity(0.5))
                }
                Spacer()
                Text("420.000").font(.system(size: 15, weight: .bold)).foregroundStyle(ink)
            }
            .padding(.horizontal, 14).frame(width: 230, height: 54)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
        }
    }

    /// Lịch tháng có ngày 5 được đánh dấu lặp lại
    private var recurring: some View {
        VStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { c in
                        let n = r * 7 + c + 1
                        let mark = n == 5 || n == 19
                        Text("\(n)").font(.system(size: 12, weight: mark ? .bold : .medium, design: .rounded))
                            .foregroundStyle(mark ? .white : ink.opacity(0.55))
                            .frame(width: 26, height: 26)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(mark ? Color(hex: 0x7A3FD6) : .white.opacity(0.7)))
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "repeat").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                .frame(width: 36, height: 36).background(Circle().fill(ink)).offset(x: 14, y: -16)
        }
    }

    /// Hoá đơn giấy cạnh ô khoản chi có chấm xanh (có ảnh đính kèm)
    private var photos: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("HOÁ ĐƠN").font(.system(size: 10, weight: .heavy)).foregroundStyle(ink.opacity(0.6))
                ForEach(0..<5, id: \.self) { i in
                    HStack { Capsule().fill(ink.opacity(0.15)).frame(width: CGFloat(40 + i * 7 % 20), height: 5); Spacer(); Capsule().fill(ink.opacity(0.25)).frame(width: 18, height: 5) }
                }
                Rectangle().fill(ink.opacity(0.2)).frame(height: 1)
                HStack { Text("TỔNG").font(.system(size: 10, weight: .heavy)); Spacer(); Text("85k").font(.system(size: 11, weight: .bold)) }.foregroundStyle(ink)
            }
            .padding(12).frame(width: 110, height: 150)
            .background(Rectangle().fill(.white))
            .rotationEffect(.degrees(-6))
            ZStack(alignment: .topTrailing) {
                Text("☕️").font(.system(size: 32)).frame(width: 64, height: 64)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
                Circle().fill(Color(hex: 0xF07B3F)).frame(width: 18, height: 18)
                    .overlay(Circle().fill(Color(hex: 0x61BE6E)).frame(width: 11, height: 11)).offset(x: 5, y: -5)
            }
        }
    }

    /// Lưới ô danh mục đủ màu, ô cuối là dấu cộng
    private var categories: some View {
        let tiles: [(String, UInt32)] = [("🍕", 0xF07B3F), ("🥤", 0xFFD43B), ("🚕", 0xEA5455), ("🛒", 0xA2D5F2),
                                         ("🐶", 0xB993FF), ("🎮", 0x4FD1C5), ("✈️", 0xFF8CC6), ("", 0)]
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(54), spacing: 10), count: 4), spacing: 10) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, t in
                Group {
                    if t.0.isEmpty {
                        Image(systemName: "plus").font(.system(size: 20, weight: .bold)).foregroundStyle(ink)
                            .frame(width: 54, height: 54)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(ink.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
                    } else {
                        Text(t.0).font(.system(size: 22))
                            .frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white))
                            .frame(width: 54, height: 54)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: t.1)))
                    }
                }
            }
        }
    }

    /// Thẻ ngân hàng, mũi tên, hàng khoản chi vừa tự ghi
    private var cardAuto: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ink).frame(width: 170, height: 104)
                RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0xFFD43B)).frame(width: 26, height: 20).offset(x: 16, y: 18)
                Image(systemName: "wave.3.right").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                    .offset(x: 130, y: 18)
                Text("•••• 4821").font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(.white.opacity(0.85))
                    .offset(x: 16, y: 70)
            }
            HStack(spacing: 10) {
                Text("🛒").font(.system(size: 20)).frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: 0xF4F5F8)))
                Text("WinMart").font(.system(size: 15, weight: .semibold)).foregroundStyle(ink)
                Spacer()
                Text("128.000").font(.system(size: 15, weight: .bold)).foregroundStyle(ink)
            }
            .padding(.horizontal, 12).frame(width: 230, height: 52)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
        }
    }

    /// Bảng tính: hàng tiêu đề xanh, các dòng số liệu
    private var csv: some View {
        let rows = [["Ngày", "Ghi chú", "Số tiền"], ["09/10", "Grab", "55.000"], ["08/10", "Cafe", "35.000"], ["08/10", "Ăn trưa", "45.000"], ["07/10", "Trà sữa", "46.000"]]
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { c, cell in
                        Text(cell).font(.system(size: 12, weight: r == 0 ? .bold : .medium, design: c == 2 ? .rounded : .default))
                            .foregroundStyle(r == 0 ? .white : ink.opacity(0.8))
                            .frame(width: c == 1 ? 90 : 70, height: 26, alignment: c == 2 ? .trailing : .leading)
                            .padding(.horizontal, 6)
                            .overlay(alignment: .trailing) { Rectangle().fill(ink.opacity(0.08)).frame(width: 1) }
                    }
                }
                .background(r == 0 ? Color(hex: 0x2E8B1F) : (r % 2 == 0 ? Color.white : Color(hex: 0xF7F7F7)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ink.opacity(0.12), lineWidth: 1))
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
