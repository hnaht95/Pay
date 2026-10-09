import SwiftUI

/// Ảnh đại diện tròn: chữ cái đầu của tên gọi (chữ cuối trong tên), màu riêng theo người.
struct HouseAvatar: View {
    let id: String
    let name: String
    var size: CGFloat = 40

    var body: some View {
        let initial = (name.split(separator: " ").last.map(String.init) ?? name).prefix(1).uppercased()
        Text(initial.isEmpty ? "?" : initial)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(Color(hex: 0x111114))
            .frame(width: size, height: size)
            .background(CategoryTone.bg(House.shared.tone(id)), in: Circle())
    }
}

/// Nhóm "Nhà chung": khoản chi chung của cả nhà, ai ứng thì ghi, cuối tháng xem ai chuyển cho ai.
struct HouseView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var house = House.shared
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    @State private var groupName = "Nhà mình"
    @State private var myName = ""
    @State private var newMember = ""
    @State private var addingMember = false
    @State private var confirmLeave = false
    @State private var paying: HouseTransfer?
    @State private var inviteError: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
            .refreshable { await house.load() }
            .withDock(dock: dock, fallbackBlur: bottomFade)

            ToastView().padding(.bottom, 100)
        }
        .overlay { if house.busy { ProgressView().controlSize(.large) } }
        .task {
            await house.load()
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "houseDemoAdd") { adding = true }   // máy ảo không bấm được nút nổi
            #endif
        }
        .sheet(isPresented: $adding) { HouseSpendEditor().environmentObject(store) }
        .alert("Thêm người vào nhóm", isPresented: $addingMember) {
            TextField("Tên", text: $newMember)
            Button("Huỷ", role: .cancel) { newMember = "" }
            Button("Thêm") {
                let n = newMember.trimmingCharacters(in: .whitespaces)
                newMember = ""
                if !n.isEmpty { Task { _ = await house.addMember(n) } }
            }
        } message: {
            Text("Thêm được cả người không dùng Pay; bạn ghi giúp phần của họ.")
        }
        .confirmationDialog(house.isOwner ? "Xoá nhóm cho cả nhà?" : "Rời nhóm?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button(house.isOwner ? "Xoá nhóm" : "Rời nhóm", role: .destructive) { Task { await house.leave() } }
        } message: {
            Text(house.isOwner ? "Mọi người trong nhóm sẽ mất sổ chung này. Không hoàn tác được." : "Sổ chung vẫn còn ở người tạo nhóm, họ mời lại được.")
        }
        .confirmationDialog("Xác nhận đã chuyển?", isPresented: Binding(get: { paying != nil }, set: { if !$0 { paying = nil } }), titleVisibility: .visible) {
            if let t = paying {
                Button("\(house.memberName(t.from)) đã trả \(fmt(t.amount))đ") { Task { await house.settle(t) } }
            }
        } message: {
            if let t = paying { Text("Ghi nhận \(house.memberName(t.from)) đã chuyển cho \(house.memberName(t.to)).") }
        }
        .alert("Không mở được lời mời", isPresented: Binding(get: { inviteError != nil }, set: { if !$0 { inviteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(inviteError ?? "") }
    }

    /// Nút "Thêm khoản chung" nổi ở đáy (chỉ khi đã vào nhóm)
    @ViewBuilder private var dock: some View {
        if house.phase == .ready && house.me != nil {
            GlassGroup {
                BigButton(title: "Thêm khoản chung", icon: "plus", primary: true) { adding = true }
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
    }

    /// Nền dưới nút chuyển dần sang màu nền, giống màn hình chính
    private var bottomFade: some View {
        Color.clear
            .overlay(alignment: .bottom) {
                LinearGradient(stops: [.init(color: Palette.bg, location: 0), .init(color: Palette.bg, location: 0.3),
                                       .init(color: Palette.bg.opacity(0.6), location: 0.6), .init(color: Palette.bg.opacity(0), location: 1)],
                               startPoint: .bottom, endPoint: .top)
                    .frame(height: 170)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    // MARK: Đầu trang

    private var header: some View {
        HStack(spacing: 8) {
            circleButton("chevron.down", "Đóng") { dismiss() }
            Spacer()
            Text(house.phase == .ready && !house.name.isEmpty ? house.name : "Nhà chung")
                .font(.system(size: 19, weight: .bold)).lineLimit(1)
            Spacer()
            if house.phase == .ready {
                Menu {
                    Button(house.isOwner ? "Mời thành viên" : "Người trong nhóm", systemImage: "person.badge.plus") { invite() }
                    Button("Thêm người", systemImage: "plus") { addingMember = true }
                    Button(house.isOwner ? "Xoá nhóm" : "Rời nhóm", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { confirmLeave = true }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 18, weight: .bold))
                        .frame(width: 42, height: 42).background(Palette.pill, in: Circle())
                }
                .foregroundStyle(.primary)
            } else {
                Color.clear.frame(width: 42, height: 42)
            }
        }
        .padding(.top, 14).padding(.bottom, 14)
    }

    private func circleButton(_ symbol: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol).font(.system(size: 17, weight: .bold))
                .frame(width: 42, height: 42).background(Palette.pill, in: Circle())
        }
        .foregroundStyle(.primary)
        .accessibilityLabel(label)
    }

    private func sectionTitle(_ title: String, trailing: String? = nil) -> some View {
        HStack {
            Text(title).font(.system(size: 21, weight: .bold))
            Spacer()
            if let trailing {
                Text(trailing).font(.system(size: 15)).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Palette.pill, in: Capsule())
            }
        }
        .padding(.top, 26).padding(.bottom, 12)
    }

    @ViewBuilder private var content: some View {
        switch house.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).padding(.top, 120)
        case .noAccount:
            message("icloud.slash", "Chưa đăng nhập iCloud", "Nhà chung lưu trên iCloud. Đăng nhập iCloud trong Cài đặt của iPhone rồi mở lại.")
        case .failed(let why):
            message("exclamationmark.triangle", "Chưa tải được nhóm", why)
            primaryButton("Thử lại") { Task { await house.load() } }.padding(.top, 16)
        case .none:
            createForm
        case .ready:
            if house.me == nil { pickMe } else { ready }
        }
    }

    private func message(_ symbol: String, _ title: String, _ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 34)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 20, weight: .bold))
            Text(text).font(.system(size: 16)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(28)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.top, 20)
    }

    private func primaryButton(_ title: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title).font(.system(size: 19, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 60)
                .foregroundStyle(Palette.ctaInk)
                .background(Palette.cta, in: Capsule())
        }
        .buttonStyle(Pressable())
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 15)).foregroundStyle(.secondary).padding(.leading, 4)
            TextField(label, text: text)
                .font(.system(size: 18))
                .padding(.horizontal, 18).padding(.vertical, 15)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    // MARK: Chưa có nhóm

    @ViewBuilder private var createForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: -10) {
                ForEach(Array(["Bố", "Mẹ", "Anh", "Em"].enumerated()), id: \.offset) { i, n in
                    HouseAvatar(id: "demo\(i)", name: n, size: 52).overlay(Circle().stroke(Palette.surface, lineWidth: 3))
                }
            }
            Text("Sổ chi tiêu chung của cả nhà").font(.system(size: 26, weight: .bold))
            Text("Ai đi chợ, trả điện nước thì ghi vào đây. Cuối tháng Pay tính ai chuyển cho ai bao nhiêu, ít lần chuyển nhất.")
                .font(.system(size: 16)).foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 32, style: .continuous))

        VStack(spacing: 14) {
            field("Tên nhóm", $groupName)
            field("Tên của bạn", $myName)
        }
        .padding(.top, 20)

        primaryButton("Tạo nhóm") {
            Task { await house.create(name: groupName.trimmingCharacters(in: .whitespaces), me: myName.trimmingCharacters(in: .whitespaces)) }
        }
        .disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty || myName.trimmingCharacters(in: .whitespaces).isEmpty)
        .opacity(groupName.trimmingCharacters(in: .whitespaces).isEmpty || myName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.35 : 1)
        .padding(.top, 20)

        Text("Tạo xong, mời mọi người qua Tin nhắn hoặc Zalo. Người được mời cần cài Pay và đăng nhập iCloud. Muốn vào nhóm người khác đã tạo thì bấm vào lời mời họ gửi.")
            .font(.system(size: 14)).foregroundStyle(.secondary)
            .padding(.top, 12).padding(.horizontal, 4)
    }

    // MARK: Chọn "tôi là ai"

    @ViewBuilder private var pickMe: some View {
        Text("Bạn là ai trong nhóm?").font(.system(size: 26, weight: .bold)).padding(.top, 10)
        Text("Chỉ để biết phần nào là của bạn trên máy này.").font(.system(size: 16)).foregroundStyle(.secondary).padding(.top, 4)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(house.members) { m in
                Button { house.me = m.id } label: {
                    VStack(spacing: 10) {
                        HouseAvatar(id: m.id, name: m.name, size: 56)
                        Text(m.name).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .buttonStyle(Pressable())
            }
            Button { addingMember = true } label: {
                VStack(spacing: 10) {
                    Image(systemName: "plus").font(.system(size: 22, weight: .semibold))
                        .frame(width: 56, height: 56).background(Palette.pill, in: Circle())
                    Text("Tôi chưa có").font(.system(size: 17, weight: .medium)).foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity).padding(.vertical, 20)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            }
            .buttonStyle(Pressable())
        }
        .padding(.top, 20)
    }

    // MARK: Nhóm

    @ViewBuilder private var ready: some View {
        let net = Settle.balances(house.spends, house.settles)
        let transfers = Settle.transfers(net)

        hero(net[house.me ?? ""] ?? 0)

        sectionTitle("Ai chuyển cho ai", trailing: transfers.isEmpty ? nil : "\(transfers.count) lần")
        if transfers.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 26)).foregroundStyle(.green)
                Text("Mọi người đã cân bằng, không ai nợ ai.").font(.system(size: 16)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        VStack(spacing: 10) {
            ForEach(transfers, id: \.self) { transferRow($0) }
        }

        sectionTitle("Thành viên", trailing: "\(house.members.count) người")
        members(net)

        sectionTitle("Khoản chung", trailing: monthTotal)
        timeline
    }

    private var monthTotal: String? {
        let cal = Calendar.current
        let sum = house.spends.filter { cal.isDate($0.date, equalTo: Date(), toGranularity: .month) }.reduce(0) { $0 + $1.amount }
        return sum > 0 ? "Tháng \(cal.component(.month, from: Date())): \(fmt(sum))" : nil
    }

    private func hero(_ mine: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(mine > 0 ? "Cả nhà còn nợ bạn" : mine < 0 ? "Bạn còn phải trả" : "Bạn đã cân bằng")
                .font(.system(size: 16)).foregroundStyle(.secondary)
            Text(fmt(abs(mine)))
                .font(.system(size: 46, weight: .bold)).kerning(-1.5)
                .foregroundStyle(mine < 0 ? Palette.danger : .primary)
                .minimumScaleFactor(0.5).lineLimit(1)
                .padding(.top, 8).padding(.bottom, 16)
            HStack(spacing: 10) {
                HStack(spacing: -10) {
                    ForEach(house.members.prefix(5)) { m in
                        HouseAvatar(id: m.id, name: m.name, size: 36).overlay(Circle().stroke(Palette.surface, lineWidth: 2.5))
                    }
                }
                if house.members.count > 5 {
                    Text("+\(house.members.count - 5)").font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { invite() } label: {
                    Label("Mời", systemImage: "person.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.horizontal, 16).frame(height: 40)
                        .background(Palette.pill, in: Capsule())
                }
                .foregroundStyle(.primary)
                .buttonStyle(Pressable())
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .environment(\.colorScheme, .light)   // giống thẻ "Hôm nay đã chi" ở màn hình chính
    }

    private func transferRow(_ t: HouseTransfer) -> some View {
        let from = house.memberName(t.from), to = house.memberName(t.to)
        let mine = t.from == house.me || t.to == house.me
        return HStack(spacing: 10) {
            HStack(spacing: 4) {
                HouseAvatar(id: t.from, name: from, size: 40)
                Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold)).foregroundStyle(.secondary)
                HouseAvatar(id: t.to, name: to, size: 40)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(t.from == house.me ? "Bạn trả \(to)" : t.to == house.me ? "\(from) trả bạn" : "\(from) trả \(to)")
                    .font(.system(size: 16, weight: .semibold)).lineLimit(1)
                Text(fmt(t.amount)).font(.system(size: 16, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 4)
            Button("Đã trả") { paying = t }
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 14).frame(height: 38)
                .foregroundStyle(mine ? Palette.ctaInk : .primary)
                .background(mine ? Palette.cta : Palette.pill, in: Capsule())
                .buttonStyle(Pressable())
        }
        .padding(12).padding(.trailing, 2)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func members(_ net: [String: Int]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(house.members) { m in
                    let v = net[m.id] ?? 0
                    VStack(spacing: 8) {
                        HouseAvatar(id: m.id, name: m.name, size: 48)
                        Text(m.id == house.me ? "Bạn" : m.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Text(v == 0 ? "0" : (v > 0 ? "+" : "−") + fmt(abs(v)))
                            .font(.system(size: 14, weight: .medium)).monospacedDigit()
                            .foregroundStyle(v < 0 ? Palette.danger : v > 0 ? Palette.goodInk : .secondary)
                    }
                    .frame(width: 96).padding(.vertical, 14)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                Button { addingMember = true } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
                            .frame(width: 48, height: 48).background(Palette.pill, in: Circle())
                        Text("Thêm").font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                        Text(" ").font(.system(size: 14))
                    }
                    .foregroundStyle(.primary)
                    .frame(width: 96).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                }
                .buttonStyle(Pressable())
            }
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
    }

    /// Khoản chung và các lần trả nhau, mới nhất trước.
    @ViewBuilder private var timeline: some View {
        let items: [(Date, AnyView)] = house.spends.map { ($0.date, AnyView(spendRow($0))) } + house.settles.map { ($0.date, AnyView(settleRow($0))) }
        if items.isEmpty {
            Text("Chưa có khoản chung nào. Bấm Thêm khoản chung khi bạn ứng tiền cho cả nhà.")
                .font(.system(size: 16)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(24)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        VStack(spacing: 10) {
            ForEach(Array(items.sorted { $0.0 > $1.0 }.enumerated()), id: \.offset) { $0.element.1 }
        }
    }

    private func spendRow(_ e: HouseSpend) -> some View {
        let c = Category.get(e.cat)
        let payer = house.memberName(e.payer)
        return HStack(spacing: 14) {
            CategoryIcon(c: c, size: 28)
                .frame(width: 52, height: 52)
                .background(c.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(e.note.isEmpty ? c.name : e.note).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                Text("\(e.payer == house.me ? "Bạn" : payer) ứng · chia \(Set(e.shares).count) người · \(day(e.date))")
                    .font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(fmt(e.amount)).font(.system(size: 17, weight: .bold))
                if let me = house.me, e.shares.contains(me) {
                    Text("bạn \(fmt(Settle.split(e.amount, e.shares, seed: e.id)[me] ?? 0))")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.leading, 12).padding(.trailing, 16).padding(.vertical, 12)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contextMenu {
            Button("Xoá khoản này", systemImage: "trash", role: .destructive) { Task { await house.delete(e.id) } }
        }
    }

    private func settleRow(_ s: HouseSettle) -> some View {
        let from = s.from == house.me ? "Bạn" : house.memberName(s.from)
        let to = s.to == house.me ? "bạn" : house.memberName(s.to)
        return HStack(spacing: 14) {
            Image(systemName: "checkmark").font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.goodInk)
                .frame(width: 52, height: 52)
                .background(Palette.good, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(from) đã trả \(to)").font(.system(size: 17, weight: .semibold)).lineLimit(1)
                Text(day(s.date)).font(.system(size: 14)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(fmt(s.amount)).font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.goodInk)
        }
        .padding(.leading, 12).padding(.trailing, 16).padding(.vertical, 12)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contextMenu {
            Button("Xoá lần trả này", systemImage: "trash", role: .destructive) { Task { await house.delete(s.id) } }
        }
    }

    private func invite() {
        Task {
            do { HouseInvite.present(share: try await house.share(), container: house.cloud) }
            catch { inviteError = House.describe(error) }
        }
    }

    private func day(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Hôm nay" }
        if cal.isDateInYesterday(d) { return "Hôm qua" }
        let c = cal.dateComponents([.day, .month], from: d)
        return "\(c.day!)/\(c.month!)"
    }
}

/// Thêm khoản chung: số tiền, ghi chú, ai ứng, chia cho ai; ghi luôn phần của mình vào chi tiêu cá nhân.
struct HouseSpendEditor: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var house = House.shared
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var note = ""
    @State private var cat = "an"
    @State private var payer = ""
    @State private var shares: Set<String> = []
    @State private var logMine = true
    @FocusState private var amountFocused: Bool

    private var amount: Int { Int(amountText.filter(\.isNumber).prefix(12)) ?? 0 }
    private var parts: [String: Int] { Settle.split(amount, Array(shares), seed: "") }
    private var myShare: Int? { house.me.flatMap { shares.contains($0) ? parts[$0] : nil } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                        .frame(width: 46, height: 46).background(Palette.pill, in: Circle())
                }
                .foregroundStyle(.primary)
                Text("Khoản chung").font(.system(size: 21, weight: .bold))
                Spacer()
            }
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Số tiền").font(.system(size: 15)).foregroundStyle(.secondary).padding(.top, 16)
                    // Ô nhập ẩn giữ các chữ số, phía trên hiện số đã chia dấu chấm; con trỏ luôn ở cuối, không nhảy giữa số
                    HStack(alignment: .firstTextBaseline) {
                        Text(amount > 0 ? fmt(amount) : "0")
                            .font(.system(size: 46, weight: .bold)).kerning(-1.5)
                            .foregroundStyle(amount > 0 ? .primary : .tertiary)
                            .contentTransition(.numericText())
                            .lineLimit(1).minimumScaleFactor(0.5)
                        Spacer()
                        Text("đ").font(.system(size: 22, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    .background {
                        TextField("", text: Binding(get: { amountText }, set: { amountText = String($0.filter(\.isNumber).prefix(12)) }))
                            .keyboardType(.numberPad)
                            .focused($amountFocused)
                            .foregroundStyle(.clear).tint(.clear)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { amountFocused = true }
                    .animation(.snappy(duration: 0.15), value: amount)
                    Rectangle().fill(.primary).frame(height: 2).padding(.top, 4)

                    TextField("Ghi chú, ví dụ: đi chợ", text: $note)
                        .font(.system(size: 18))
                        .padding(.horizontal, 18).padding(.vertical, 15)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.top, 16)
                        .onChange(of: note) { _, v in let g = store.guessCategory(v); if g != "khac" { cat = g } }

                    categories.padding(.top, 12)

                    label("Ai ứng tiền")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(house.members) { m in
                                personChip(m, on: payer == m.id, sub: nil) { payer = m.id }
                            }
                        }
                        .padding(.horizontal, 18)
                    }
                    .padding(.horizontal, -18)

                    HStack {
                        label("Chia đều cho")
                        Spacer()
                        Button(shares.count == house.members.count ? "Bỏ chọn" : "Cả nhà") {
                            shares = shares.count == house.members.count ? [] : Set(house.members.map(\.id))
                        }
                        .font(.system(size: 15, weight: .semibold)).padding(.top, 22)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(house.members) { m in
                            let on = shares.contains(m.id)
                            personChip(m, on: on, sub: on && amount > 0 ? fmt(parts[m.id] ?? 0) : nil, wide: true) {
                                if on { shares.remove(m.id) } else { shares.insert(m.id) }
                            }
                        }
                    }

                    if let mine = myShare, mine > 0 {
                        Toggle(isOn: $logMine) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ghi \(fmt(mine))đ vào chi tiêu của tôi").font(.system(size: 16, weight: .semibold))
                                Text("Thống kê và ngân sách chỉ tính phần của bạn.").font(.system(size: 14)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(16)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.top, 18)
                    }
                }
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)

            Button { save() } label: {
                Text("Lưu").font(.system(size: 19, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .foregroundStyle(Palette.ctaInk)
                    .background(Palette.cta, in: Capsule())
            }
            .buttonStyle(Pressable())
            .disabled(!valid).opacity(valid ? 1 : 0.35)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 18)
        .background(Palette.surface.ignoresSafeArea())
        .onAppear {
            payer = house.me ?? house.members.first?.id ?? ""
            shares = Set(house.members.map(\.id))
            amountFocused = true
        }
    }

    private var valid: Bool { amount > 0 && !shares.isEmpty && !payer.isEmpty }

    private func label(_ t: String) -> some View {
        Text(t).font(.system(size: 15)).foregroundStyle(.secondary).padding(.top, 22).padding(.bottom, 10)
    }

    private var categories: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Category.all) { c in
                    let on = cat == c.k
                    Button { cat = c.k } label: {
                        HStack(spacing: 8) {
                            CategoryIcon(c: c, size: 20).frame(width: 32, height: 32)
                                .background(on ? Color.white.opacity(0.7) : c.color, in: Circle())
                            Text(c.name).font(.system(size: 16, weight: on ? .semibold : .medium))
                        }
                        .padding(.leading, 5).padding(.trailing, 14).padding(.vertical, 5)
                        .foregroundStyle(on ? Color.black : Color.primary)
                        .background(on ? c.color : Color.primary.opacity(0.05), in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 18)
        }
        .padding(.horizontal, -18)
    }

    private func personChip(_ m: HouseMember, on: Bool, sub: String?, wide: Bool = false, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 10) {
                HouseAvatar(id: m.id, name: m.name, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.id == house.me ? "Bạn" : m.name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    if let line = sub { Text(line).font(.system(size: 13)).foregroundStyle(on ? Palette.ctaInk.opacity(0.7) : .secondary).lineLimit(1) }
                }
                if wide { Spacer(minLength: 0) }
                if wide {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 20))
                        .foregroundStyle(on ? Palette.ctaInk : .secondary)
                }
            }
            .padding(.leading, 6).padding(.trailing, 14).padding(.vertical, 6)
            .frame(maxWidth: wide ? .infinity : nil, alignment: .leading)
            .foregroundStyle(on ? Palette.ctaInk : .primary)
            .background(on ? Palette.cta : Color.primary.opacity(0.05), in: Capsule())
        }
        .buttonStyle(Pressable())
    }

    private func save() {
        let a = amount, n = note.trimmingCharacters(in: .whitespaces), c = cat, p = payer, s = Array(shares), mine = myShare
        let log = logMine
        Task {
            guard await house.addSpend(amount: a, note: n, payer: p, shares: s, cat: c) else { return }
            if log, let mine, mine > 0 { store.add(amount: mine, note: n.isEmpty ? "Nhà chung" : n, cat: c) }
            dismiss()
        }
    }
}
