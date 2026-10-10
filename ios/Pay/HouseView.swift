import PhotosUI
import UserNotifications
import SwiftUI

/// Ảnh đại diện tròn: chữ cái đầu của tên gọi (chữ cuối trong tên), màu riêng theo người.
struct HouseAvatar: View {
    let id: String
    let name: String
    var size: CGFloat = 40

    var body: some View {
        let initial = (name.split(separator: " ").last.map(String.init) ?? name).prefix(1).uppercased()
        if let data = House.shared.members.first(where: { $0.id == id })?.photo, let img = UIImage(data: data) {
            Image(uiImage: img).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
        } else {
            Text(initial.isEmpty ? "?" : initial)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(Color(hex: 0x111114))
                .frame(width: size, height: size)
                .background(CategoryTone.bg(House.shared.tone(id)), in: Circle())
        }
    }
}

/// Nhóm "Nhà chung": khoản chi chung của cả nhà, ai ứng thì ghi, cuối tháng xem ai chuyển cho ai.
struct HouseView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var house = House.shared
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    @State private var groupName = ""
    @State private var myName = ""
    @State private var newMember = ""
    @State private var addingMember = false
    @State private var confirmLeave = false
    @State private var paying: HouseTransfer?
    @State private var inviteError: String?
    /// Thêm người từ màn "Bạn là ai": thêm xong nhận luôn là mình
    @State private var claimAfterAdd = false
    @State private var editingMember: HouseMember?
    @State private var showInbox = false
    /// Đang tạo nhóm mới (từ danh sách nhóm)
    @State private var creating = false
    @State private var showArchived = false
    @State private var menu: AppMenuSpec?
    @State private var notifyOn: Bool?
    @Environment(\.scenePhase) private var scenePhase
    /// Đang dựng phim giới thiệu (xem Film.swift)
    @Environment(\.film) private var film

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.bg.ignoresSafeArea()
            FilmScroll {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
            .refreshable { await house.load() }
            .withDock(dock: dock, fallbackBlur: bottomFade, film: film != nil)

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
        .alert(L("Thêm người vào nhóm"), isPresented: $addingMember) {
            TextField(L("Tên"), text: $newMember)
            Button(L("Huỷ"), role: .cancel) { newMember = "" }
            Button(L("Thêm")) {
                let n = newMember.trimmingCharacters(in: .whitespaces)
                newMember = ""
                let claim = claimAfterAdd
                claimAfterAdd = false
                if !n.isEmpty { Task { if let id = await house.addMember(n), claim { await house.claim(id) } } }
            }
        } message: {
            Text(L("Thêm được cả người không dùng Pay; bạn ghi giúp phần của họ."))
        }
        .confirmationDialog(house.isOwner ? L("Xoá nhóm cho cả nhà?") : L("Rời nhóm?"), isPresented: $confirmLeave, titleVisibility: .visible) {
            Button(house.isOwner ? L("Xoá nhóm") : L("Rời nhóm"), role: .destructive) { Task { await house.leave() } }
        } message: {
            Text(house.isOwner ? L("Mọi người trong nhóm sẽ mất sổ chung này. Không hoàn tác được.") : L("Sổ chung vẫn còn ở người tạo nhóm, họ mời lại được."))
        }
        .confirmationDialog(L("Xác nhận đã chuyển?"), isPresented: Binding(get: { paying != nil }, set: { if !$0 { paying = nil } }), titleVisibility: .visible) {
            if let t = paying {
                if t.from == house.me {
                    Button(L("Đã chuyển %@đ", fmt(t.amount))) { Task { await house.settle(t) } }
                    Button(L("Chưa chuyển"), role: .cancel) {}
                } else {
                    Button(L("Đã nhận %@đ", fmt(t.amount))) { Task { await house.settle(t) } }
                }
            }
        } message: {
            if let t = paying {
                Text(t.from == house.me ? L("%@ sẽ nhận thông báo để xác nhận đã nhận tiền.", house.memberName(t.to))
                                        : L("Ghi nhận bạn đã nhận tiền từ %@.", house.memberName(t.from)))
            }
        }
        .sheet(item: $editingMember) { HouseMemberEditor(member: $0).environmentObject(store) }
        .onDisappear { if film == nil { house.open(nil) } }   // (phim vẽ lại màn hình mỗi khung: không tính là đóng)
        .appMenu($menu)   // mở lại thì về danh sách nhóm
        // Trả qua app ngân hàng xong quay lại Pay: hỏi đã chuyển xong chưa
        .onChange(of: scenePhase) { _, p in
            if p == .active, let t = house.pendingPay { house.pendingPay = nil; paying = t }
        }
        .alert(L("Không mở được lời mời"), isPresented: Binding(get: { inviteError != nil }, set: { if !$0 { inviteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(inviteError ?? "") }
    }

    /// Nút "Thêm khoản chung" nổi ở đáy (chỉ khi đã vào nhóm)
    private var inGroup: Bool { house.phase == .ready && house.current != nil && !creating }

    @ViewBuilder private var dock: some View {
        if inGroup && house.me != nil {
            GlassGroup {
                BigButton(title: L("Thêm khoản chung"), icon: "plus", primary: true) { adding = true }
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
            if inGroup {
                circleButton("chevron.left", L("Các nhóm")) { withAnimation(.snappy) { house.open(nil) } }
            } else if creating && !house.groups.isEmpty {
                circleButton("chevron.left", L("Các nhóm")) { withAnimation(.snappy) { creating = false } }
            } else {
                circleButton("chevron.down", L("Đóng")) { dismiss() }
            }
            Spacer()
            Text(inGroup && !house.name.isEmpty ? house.name : creating ? L("Nhóm mới") : L("Nhóm chung"))
                .font(.system(size: 19, weight: .bold)).lineLimit(1)
            Spacer()
            if inGroup && house.me != nil {
                // Chuông: việc cần mình xác nhận + hoạt động gần đây
                Button { showInbox = true } label: {
                    Image(systemName: "bell.fill").font(.system(size: 17, weight: .semibold))
                        .frame(width: 42, height: 42).background(Palette.pill, in: Circle())
                        .overlay(alignment: .topTrailing) {
                            if !pending.isEmpty {
                                Text("\(pending.count)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                    .frame(minWidth: 20, minHeight: 20).background(Palette.danger, in: Circle())
                                    .offset(x: 4, y: -4)
                            }
                        }
                }
                .buttonStyle(Pressable())
                .foregroundStyle(.primary)
                .accessibilityLabel(pending.isEmpty ? L("Thông báo") : L("Thông báo, %d việc cần xác nhận", pending.count))
            }
            if inGroup, film != nil {
                // Phim: menu của hệ thống không vẽ ra PDF được, chỉ cần hình nút
                Image(systemName: "ellipsis").font(.system(size: 18, weight: .bold))
                    .frame(width: 42, height: 42).background(Palette.pill, in: Circle())
            } else if inGroup {
                Menu {
                    Button(house.isOwner ? L("Mời thành viên") : L("Người trong nhóm"), systemImage: "person.badge.plus") { invite() }
                    Button(L("Thêm người"), systemImage: "plus") { addingMember = true }
                    Button(house.isOwner ? L("Xoá nhóm") : L("Rời nhóm"), systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { confirmLeave = true }
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
        .sheet(isPresented: $showInbox) { inbox }
    }

    private func circleButton(_ symbol: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol).font(.system(size: 17, weight: .bold))
                .frame(width: 42, height: 42).background(Palette.pill, in: Circle())
        }
        .buttonStyle(Pressable())
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
            message("icloud.slash", L("Chưa đăng nhập iCloud"), L("Nhóm chung lưu trên iCloud. Đăng nhập iCloud trong Cài đặt của iPhone rồi mở lại."))
        case .failed(let why):
            message("exclamationmark.triangle", L("Chưa tải được nhóm"), why)
            primaryButton(L("Thử lại")) { Task { await house.load() } }.padding(.top, 16)
        case .ready:
            if creating || house.groups.isEmpty { createForm }
            else if house.current == nil { groupList }
            else if house.me == nil { pickMe } else { ready }
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
            Text(L("Sổ chi tiêu chung")).font(.system(size: 26, weight: .bold))
            Text(L("Cho nhà chung, phòng trọ, chuyến đi… Ai ứng tiền thì ghi vào đây, Pay tính ai chuyển cho ai bao nhiêu, ít lần chuyển nhất."))
                .font(.system(size: 16)).foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 32, style: .continuous))

        VStack(spacing: 14) {
            field(L("Tên nhóm, ví dụ: Nhà mình, Đi Đà Lạt"), $groupName)
            field(L("Tên của bạn"), $myName)
        }
        .padding(.top, 20)

        primaryButton(L("Tạo nhóm")) {
            Task {
                await house.create(name: groupName.trimmingCharacters(in: .whitespaces), me: myName.trimmingCharacters(in: .whitespaces))
                creating = false
            }
        }
        .disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty || myName.trimmingCharacters(in: .whitespaces).isEmpty)
        .opacity(groupName.trimmingCharacters(in: .whitespaces).isEmpty || myName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.35 : 1)
        .padding(.top, 20)

        Text(L("Tạo xong, mời mọi người qua Tin nhắn hoặc Zalo. Người được mời cần cài Pay và đăng nhập iCloud. Muốn vào nhóm người khác đã tạo thì bấm vào lời mời họ gửi."))
            .font(.system(size: 14)).foregroundStyle(.secondary)
            .padding(.top, 12).padding(.horizontal, 4)
    }

    // MARK: Danh sách nhóm

    @ViewBuilder private var groupList: some View {
        let active = house.groups.filter { !house.archived.contains($0.id) }
        let old = house.groups.filter { house.archived.contains($0.id) }
        VStack(spacing: 10) {
            ForEach(active) { g in groupCard(g).filmPressed(film?.pressed["group-" + g.id] ?? 0) }
            Button { groupName = ""; creating = true } label: {
                Image(systemName: "plus").font(.system(size: 22, weight: .semibold))
                    .frame(width: 52, height: 52).background(Palette.surface, in: Circle())
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .buttonStyle(Pressable())
            .accessibilityLabel(L("Tạo nhóm mới"))
        }
        if !old.isEmpty {
            Button { withAnimation(.snappy) { showArchived.toggle() } } label: {
                HStack {
                    Text(L("Đã lưu trữ")).font(.system(size: 21, weight: .bold))
                    Text("\(old.count)").font(.system(size: 15)).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: showArchived ? "chevron.up" : "chevron.down").font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
            }
            .buttonStyle(Pressable())
            .padding(.top, 26).padding(.bottom, 12)
            if showArchived {
                VStack(spacing: 10) { ForEach(old) { groupCard($0).opacity(0.6) } }
            }
        }
    }

    private func groupCard(_ g: HouseGroup) -> some View {
        let net = g.myNet
        let pend = g.pending.count
        return TapHold(tap: { withAnimation(.snappy) { house.open(g.id) } }, hold: { menu = groupMenu(g) }) {
            HStack(spacing: 14) {
                groupIcon(g.id)
                VStack(alignment: .leading, spacing: 4) {
                    Text(g.name.isEmpty ? L("Nhóm chung") : g.name).font(.system(size: 18, weight: .semibold)).lineLimit(1)
                    HStack(spacing: -6) {
                        ForEach(g.members.prefix(5)) { m in
                            HouseAvatar(id: m.id, name: m.name, size: 22).overlay(Circle().stroke(Palette.card, lineWidth: 1.5))
                        }
                        Text("  " + L("%d người", g.members.count)).font(.system(size: 14)).foregroundStyle(.secondary)
                            .lineLimit(1).fixedSize()
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(net > 0 ? L("Được nhận") : net < 0 ? L("Còn phải trả") : L("Đã cân bằng"))
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    if net != 0 {
                        Text(fmt(abs(net))).font(.system(size: 17, weight: .bold))
                            .foregroundStyle(net < 0 ? Palette.danger : Palette.goodInk).lineLimit(1)
                    }
                }
            }
            .foregroundStyle(.primary)
            .padding(.leading, 12).padding(.trailing, 16).padding(.vertical, 12)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(alignment: .topLeading) {
                if pend > 0 {
                    Text("\(pend)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .frame(minWidth: 20, minHeight: 20).background(Palette.danger, in: Circle())
                        .offset(x: 56, y: 6)
                }
            }
        }
    }

    private func groupIcon(_ id: String, size: CGFloat = 56) -> some View {
        Image(systemName: "person.2.crop.square.stack.fill")
            .font(.system(size: size * 0.43))
            .foregroundStyle(Color(hex: 0x111114))
            .frame(width: size, height: size)
            .background(CategoryTone.bg(house.tone(id)), in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
    }

    private func groupMenu(_ g: HouseGroup) -> AppMenuSpec {
        let archived = house.archived.contains(g.id)
        return AppMenuSpec(icon: AnyView(groupIcon(g.id)), title: g.name.isEmpty ? L("Nhóm chung") : g.name,
                           subtitle: L("%d người · %d khoản chung", g.members.count, g.spends.count), items: [
            AppMenuItem(icon: "arrow.right", title: L("Mở nhóm")) { house.open(g.id) },
            AppMenuItem(icon: "person.badge.plus", title: g.isOwner ? L("Mời thành viên") : L("Người trong nhóm")) { house.open(g.id); invite() },
            archived ? AppMenuItem(icon: "tray.and.arrow.up", title: L("Bỏ lưu trữ")) { house.setArchived(g.id, false) }
                     : AppMenuItem(icon: "archivebox", title: L("Lưu trữ"), subtitle: L("Ẩn khỏi danh sách, chỉ trên máy này")) { house.setArchived(g.id, true) },
        ])
    }

    // MARK: Chọn "tôi là ai"

    @ViewBuilder private var pickMe: some View {
        Text(L("Bạn là ai trong nhóm?")).font(.system(size: 26, weight: .bold)).padding(.top, 10)
        Text(L("Chỉ để biết phần nào là của bạn trên máy này.")).font(.system(size: 16)).foregroundStyle(.secondary).padding(.top, 4)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(house.members) { m in
                Button { Task { await house.claim(m.id) } } label: {
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
            Button { claimAfterAdd = true; addingMember = true } label: {
                Image(systemName: "plus").font(.system(size: 22, weight: .semibold))
                    .frame(width: 56, height: 56).background(Palette.surface, in: Circle())
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.vertical, 20)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(Pressable())
            .accessibilityLabel(L("Thêm tôi vào nhóm"))
        }
        .padding(.top, 20)
    }

    // MARK: Nhóm

    @ViewBuilder private var ready: some View {
        let net = Settle.balances(house.spends, house.settles)
        let transfers = Settle.transfers(net)

        hero(net[house.me ?? ""] ?? 0)
        if let me = house.members.first(where: { $0.id == house.me }), !me.hasBank {
            Button { editingMember = me } label: {
                HStack(spacing: 12) {
                    Image(systemName: "building.columns.fill").font(.system(size: 18))
                        .frame(width: 40, height: 40).background(Palette.pill, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Thêm tài khoản nhận tiền")).font(.system(size: 16, weight: .semibold))
                        Text(L("Mọi người bấm Trả ngay là app ngân hàng điền sẵn cho bạn.")).font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
                }
                .foregroundStyle(.primary)
                .padding(14)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(Pressable())
            .padding(.top, 12)
        }

        pendingSection

        sectionTitle(L("Ai chuyển cho ai"), trailing: transfers.isEmpty ? nil : L("%d lần", transfers.count))
        if transfers.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 26)).foregroundStyle(.green)
                Text(L("Mọi người đã cân bằng, không ai nợ ai.")).font(.system(size: 16)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        VStack(spacing: 10) {
            ForEach(transfers, id: \.self) { transferRow($0) }
        }

        sectionTitle(L("Thành viên"), trailing: L("%d người", house.members.count))
        members(net)

        sectionTitle(L("Khoản chung"), trailing: monthTotal)
        timeline
    }

    private var monthTotal: String? {
        let cal = Calendar.current
        let sum = house.spends.filter { cal.isDate($0.date, equalTo: Date(), toGranularity: .month) }.reduce(0) { $0 + $1.amount }
        guard sum > 0 else { return nil }
        if Lang.isEnglish { return "\(Date().formatted(.dateTime.month(.wide).locale(Lang.locale))): \(fmt(sum))" }
        return "Tháng \(cal.component(.month, from: Date())): \(fmt(sum))"
    }

    private func hero(_ mine: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(mine > 0 ? L("Cả nhà còn nợ bạn") : mine < 0 ? L("Bạn còn phải trả") : L("Bạn đã cân bằng"))
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
                    Label(L("Mời"), systemImage: "person.badge.plus")
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
                Text(t.from == house.me ? L("Bạn trả %@", to) : t.to == house.me ? L("%@ trả bạn", from) : L("%@ trả %@", from, to))
                    .font(.system(size: 16, weight: .semibold)).lineLimit(1)
                Text(fmt(t.amount)).font(.system(size: 16, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 4)
            // Mình là người trả và người nhận đã thêm tài khoản: mở app ngân hàng điền sẵn
            // Chỉ người trả và người nhận mới có nút; người khác chỉ xem
            let canPay = t.from == house.me && house.members.first { $0.id == t.to }?.hasBank == true
            if mine {
                Button {
                    if canPay { Task { await house.payNow(t, app: store.bankApp) } } else { paying = t }
                } label: {
                    // nền nằm trong nhãn để cả viên thuốc cùng thu nhỏ khi nhấn (để ngoài thì chỉ chữ động)
                    Text(canPay ? L("Trả ngay") : t.to == house.me ? L("Đã nhận") : L("Đã chuyển"))
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 14).frame(height: 38)
                        .foregroundStyle(Palette.ctaInk)
                        .background(Palette.cta, in: Capsule())
                }
                .buttonStyle(Pressable())

            }
        }
        .padding(12).padding(.trailing, 2)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onHold {
            guard t.from == house.me else { return }
            menu = AppMenuSpec(icon: AnyView(HouseAvatar(id: t.to, name: to, size: 56)), title: L("Bạn trả %@", to) + " · \(fmt(t.amount))",
                               subtitle: house.members.first { $0.id == t.to }?.hasBank == true ? L("Đã có tài khoản nhận tiền") : L("Chưa có tài khoản nhận tiền"),
                               items: [
                AppMenuItem(icon: "building.columns.fill", title: L("Trả qua app ngân hàng")) { Task { await house.payNow(t, app: store.bankApp) } },
                AppMenuItem(icon: "checkmark", title: L("Đã chuyển bằng cách khác"), subtitle: L("Tiền mặt, ví điện tử…")) { paying = t },
            ].filter { $0.icon != "building.columns.fill" || house.members.first { $0.id == t.to }?.hasBank == true })
        }
    }

    private func members(_ net: [String: Int]) -> some View {
        FilmScroll(axes: .horizontal) {
            HStack(spacing: 10) {
                ForEach(house.members) { m in
                    let v = net[m.id] ?? 0
                    VStack(spacing: 8) {
                        HouseAvatar(id: m.id, name: m.name, size: 48)
                        Text(m.id == house.me ? L("Bạn") : m.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Text(v == 0 ? "0" : (v > 0 ? "+" : "−") + fmt(abs(v)))
                            .font(.system(size: 14, weight: .medium)).monospacedDigit()
                            .foregroundStyle(v < 0 ? Palette.danger : v > 0 ? Palette.goodInk : .secondary)
                    }
                    .frame(width: 96).padding(.vertical, 14)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if m.hasBank { Image(systemName: "building.columns.fill").font(.system(size: 11)).foregroundStyle(.secondary).padding(10) }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .onTapGesture { editingMember = m }
                }
                Button { addingMember = true } label: {
                    Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
                        .frame(width: 48, height: 48).background(Palette.surface, in: Circle())
                        .foregroundStyle(.primary)
                        .frame(width: 96).frame(maxHeight: .infinity)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(Pressable())
                .accessibilityLabel(L("Thêm người"))
            }
            .fixedSize(horizontal: false, vertical: true)   // ô dấu + cao bằng các ô thành viên
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
    }

    /// Khoản chung và các lần trả nhau, mới nhất trước.
    @ViewBuilder private var timeline: some View {
        let items: [(Date, AnyView)] = house.spends.map { ($0.date, AnyView(spendRow($0))) } + house.settles.map { ($0.date, AnyView(settleRow($0))) }
        if items.isEmpty {
            Text(L("Chưa có khoản chung nào. Bấm Thêm khoản chung khi bạn ứng tiền cho cả nhà."))
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
                Text(e.note.isEmpty ? c.name : e.note.capFirst).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                Text(L("%@ ứng · chia %d người · %@", e.payer == house.me ? L("Bạn") : payer, Set(e.shares).count, day(e.date)))
                    .font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(fmt(e.amount)).font(.system(size: 17, weight: .bold))
                if let me = house.me, e.shares.contains(me) {
                    Text(L("bạn %@", fmt(Settle.split(e.amount, e.shares, seed: e.id)[me] ?? 0)))
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.leading, 12).padding(.trailing, 16).padding(.vertical, 12)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onHold {
            let c = Category.get(e.cat)
            menu = AppMenuSpec(icon: AnyView(CategoryIcon(c: c, size: 30).frame(width: 56, height: 56)
                                .background(c.color, in: RoundedRectangle(cornerRadius: 18, style: .continuous))),
                               title: "\(e.note.isEmpty ? c.name : e.note.capFirst) · \(fmt(e.amount))",
                               subtitle: L("%@ ứng · chia %d người · %@", house.memberName(e.payer), Set(e.shares).count, day(e.date)),
                               items: [AppMenuItem(icon: "trash.fill", title: L("Xoá khoản này"), subtitle: L("Cả nhóm sẽ không thấy khoản này nữa"), danger: true) {
                                   Task { await house.delete(e.id) }
                               }])
        }
    }

    private func settleRow(_ s: HouseSettle) -> some View {
        let from = s.from == house.me ? L("Bạn") : house.memberName(s.from)
        let to = s.to == house.me ? L("bạn") : house.memberName(s.to)
        let (icon, tint, note): (String, Color, String) = switch s.status {
        case "wait": ("clock", .orange, L("Chờ xác nhận"))
        case "no": ("xmark", Palette.danger, L("Chưa nhận được"))
        default: ("checkmark", Palette.goodInk, L("Đã xác nhận"))
        }
        return HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 20, weight: .bold)).foregroundStyle(tint)
                .frame(width: 52, height: 52)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(L("%@ chuyển %@", from, to)).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                Text("\(note) · \(day(s.date))").font(.system(size: 14)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(fmt(s.amount)).font(.system(size: 17, weight: .bold)).foregroundStyle(s.status == "no" ? .secondary : tint)
                .strikethrough(s.status == "no")
        }
        .padding(.leading, 12).padding(.trailing, 16).padding(.vertical, 12)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onHold {
            menu = AppMenuSpec(icon: AnyView(Image(systemName: icon).font(.system(size: 22, weight: .bold)).foregroundStyle(tint)
                                .frame(width: 56, height: 56).background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 18, style: .continuous))),
                               title: L("%@ chuyển %@", from, to) + " · \(fmt(s.amount))", subtitle: "\(note) · \(day(s.date))",
                               items: [AppMenuItem(icon: "trash.fill", title: L("Xoá lần trả này"), subtitle: L("Số nợ sẽ tính lại như chưa trả"), danger: true) {
                                   Task { await house.delete(s.id) }
                               }])
        }
    }

    /// Lần trả cần mình làm gì: xác nhận đã nhận, chờ người kia xác nhận, hoặc bị báo chưa nhận được.
    /// Lần trả cần mình để ý: có người báo đã chuyển cho mình, hoặc mình chuyển mà đang chờ / bị báo chưa nhận.
    private var pending: [HouseSettle] {
        let me = house.me
        return house.settles.filter { ($0.to == me && $0.status == "wait") || ($0.from == me && $0.status != "ok") }
    }

    // MARK: Thông báo

    private var inbox: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if notifyOn == false {
                        Button {
                            if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "bell.slash.fill").font(.system(size: 18)).foregroundStyle(.orange)
                                    .frame(width: 40, height: 40).background(Palette.pill, in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L("Đang tắt thông báo")).font(.system(size: 16, weight: .semibold))
                                    Text(L("Bật để biết ngay khi có người báo đã chuyển tiền.")).font(.system(size: 14)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Text(L("Bật")).font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(.primary).padding(14)
                            .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        }
                        .buttonStyle(Pressable())
                    }
                    if !pending.isEmpty {
                        Text(L("Cần xác nhận")).font(.system(size: 21, weight: .bold)).padding(.top, 8)
                        ForEach(pending) { pendingCard($0) }
                    }
                    Text(L("Gần đây")).font(.system(size: 21, weight: .bold)).padding(.top, 16)
                    let recent = activity
                    if recent.isEmpty {
                        Text(L("Chưa có gì mới.")).font(.system(size: 16)).foregroundStyle(.secondary).padding(.vertical, 20)
                    }
                    ForEach(recent, id: \.id) { a in
                        HStack(alignment: .top, spacing: 12) {
                            HouseAvatar(id: a.who, name: house.memberName(a.who), size: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(a.text).font(.system(size: 16)).fixedSize(horizontal: false, vertical: true)
                                Text(ago(a.date)).font(.system(size: 13)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)   // trải hết bề ngang, không co thành cột giữa
                .padding(.horizontal, 16).padding(.bottom, 30)
            }
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle(L("Thông báo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Xong")) { showInbox = false } } }
            .task {
                let s = await UNUserNotificationCenter.current().notificationSettings()
                notifyOn = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
            }
        }
    }

    private struct Activity { let id: String; let who: String; let text: String; let date: Date }

    /// Khoản chung người khác vừa thêm và các lần trả liên quan tới mình, mới nhất trước.
    private var activity: [Activity] {
        let me = house.me, name = house.memberName
        var out: [Activity] = []
        for e in house.spends where e.payer != me {
            let part = me.flatMap { e.shares.contains($0) ? Settle.split(e.amount, e.shares, seed: e.id)[$0] : nil }
            out.append(Activity(id: e.id, who: e.payer, text: L("%@ thêm %@ %@đ", name(e.payer), e.note.isEmpty ? L("một khoản") : "\"\(e.note)\"", fmt(e.amount))
                                + (part.map { L(", phần bạn %@đ", fmt($0)) } ?? ""), date: e.date))
        }
        for s in house.settles where s.from == me || s.to == me {
            let other = s.from == me ? s.to : s.from
            let text: String = switch (s.from == me, s.status) {
            case (true, "wait"): L("Đã báo chuyển %@đ cho %@, chờ xác nhận", fmt(s.amount), name(s.to))
            case (true, "no"): L("%@ chưa nhận được %@đ bạn chuyển", name(s.to), fmt(s.amount))
            case (true, _): L("%@ đã nhận %@đ của bạn", name(s.to), fmt(s.amount))
            case (false, "wait"): L("%@ báo đã chuyển cho bạn %@đ", name(s.from), fmt(s.amount))
            case (false, "no"): L("Bạn báo chưa nhận được %@đ từ %@", fmt(s.amount), name(s.from))
            case (false, _): L("Bạn đã nhận %@đ từ %@", fmt(s.amount), name(s.from))
            }
            out.append(Activity(id: s.id, who: other, text: text, date: s.date))
        }
        return Array(out.sorted { $0.date > $1.date }.prefix(30))
    }

    private func ago(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Lang.locale
        return f.localizedString(for: d, relativeTo: Date())
    }

    @ViewBuilder private var pendingSection: some View {
        let mine = pending
        if !mine.isEmpty {
            sectionTitle(L("Cần xác nhận"))
            VStack(spacing: 10) {
                ForEach(mine) { s in pendingCard(s) }
            }
        }
    }

    private func pendingCard(_ s: HouseSettle) -> some View {
        let from = house.memberName(s.from), to = house.memberName(s.to)
        let incoming = s.to == house.me
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                HouseAvatar(id: incoming ? s.from : s.to, name: incoming ? from : to, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(incoming ? L("%@ báo đã chuyển cho bạn", from) : s.status == "no" ? L("%@ chưa nhận được", to) : L("Chờ %@ xác nhận", to))
                        .font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Text(fmt(s.amount)).font(.system(size: 20, weight: .bold))
                        .foregroundStyle(s.status == "no" ? Palette.danger : .primary)
                }
                Spacer(minLength: 0)
                if !incoming && s.status == "wait" {
                    Image(systemName: "clock").font(.system(size: 18, weight: .semibold)).foregroundStyle(.orange)
                }
            }
            if incoming {
                HStack(spacing: 8) {
                    pill(L("Chưa nhận được"), primary: false) { Task { await house.respond(s.id, received: false) } }
                    pill(L("Đã nhận"), primary: true) { Task { await house.respond(s.id, received: true) } }
                        .filmPressed(film?.pressed["received"] ?? 0)
                }
            } else if s.status == "no" {
                Text(L("Kiểm tra lại giao dịch trong app ngân hàng. Nếu chưa chuyển được thì chuyển lại."))
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    pill(L("Bỏ"), primary: false) { Task { await house.delete(s.id) } }
                    pill(L("Chuyển lại"), primary: true) {
                        Task {
                            await house.delete(s.id)
                            let t = HouseTransfer(from: s.from, to: s.to, amount: s.amount)
                            if house.members.first(where: { $0.id == s.to })?.hasBank == true { await house.payNow(t, app: store.bankApp) }
                            else { paying = t }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(incoming ? Palette.hero : Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func pill(_ title: String, primary: Bool, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title).font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(primary ? Palette.ctaInk : .primary)
                .background(primary ? Palette.cta : Palette.pill, in: Capsule())
        }
        .buttonStyle(Pressable())
    }

    private func invite() {
        Task {
            do { HouseInvite.present(share: try await house.share(), container: house.cloud) }
            catch { inviteError = House.describe(error) }
        }
    }

    private func day(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return L("Hôm nay") }
        if cal.isDateInYesterday(d) { return L("Hôm qua") }
        if Lang.isEnglish { return d.formatted(.dateTime.month(.abbreviated).day().locale(Lang.locale)) }
        let c = cal.dateComponents([.day, .month], from: d)
        return "\(c.day!)/\(c.month!)"
    }
}

/// Sửa thành viên: ảnh, tên, tài khoản nhận tiền.
struct HouseMemberEditor: View {
    @ObservedObject private var house = House.shared
    @Environment(\.dismiss) private var dismiss
    let member: HouseMember
    @State private var name = ""
    @State private var bin = ""
    @State private var acct = ""
    @State private var photo: Data?
    @State private var photoChanged = false
    @State private var pick: PhotosPickerItem?
    /// Đã nạp thông tin của thành viên vào các ô chưa (chỉ nạp một lần)
    @State private var loaded = false

    private static let banks = BankData.names.sorted { $0.value.lowercased() < $1.value.lowercased() }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Group {
                            if let photo, let img = UIImage(data: photo) {
                                Image(uiImage: img).resizable().scaledToFill().frame(width: 96, height: 96).clipShape(Circle())
                            } else {
                                HouseAvatar(id: member.id, name: name.isEmpty ? member.name : name, size: 96)
                            }
                        }
                        HStack(spacing: 16) {
                            PhotosPicker(selection: $pick, matching: .images) { Text(photo == nil ? L("Chọn ảnh") : L("Đổi ảnh")) }
                            if photo != nil { Button(L("Bỏ ảnh"), role: .destructive) { photo = nil; photoChanged = true } }
                        }
                        .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Section(L("Tên")) { TextField(L("Tên"), text: $name) }
                Section {
                    Picker(L("Ngân hàng"), selection: $bin) {
                        Text(L("Chưa chọn")).tag("")
                        ForEach(Self.banks, id: \.key) { Text($0.value).tag($0.key) }
                    }
                    .pickerStyle(.navigationLink)   // danh sách dài: mở trang riêng để cuộn
                    TextField(L("Số tài khoản"), text: $acct).keyboardType(.numberPad)
                } header: {
                    Text(L("Tài khoản nhận tiền"))
                } footer: {
                    Text(L("Ai nợ người này bấm Trả ngay là mở app ngân hàng với sẵn số tài khoản, số tiền, nội dung."))
                }
            }
            .navigationTitle(member.id == house.me ? L("Bạn") : member.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Huỷ")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Lưu")) {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        let a = acct.filter(\.isNumber)
                        let p: Data? = photoChanged ? (photo ?? Data()) : nil
                        Task {
                            await house.updateMember(member.id, name: n.isEmpty ? member.name : n,
                                                     bin: bin.isEmpty ? nil : bin, acct: a.isEmpty ? nil : a, photo: p)
                            dismiss()
                        }
                    }
                }
            }
            // Chỉ nạp lần đầu: chọn ngân hàng mở trang riêng, lúc quay lại onAppear chạy lần nữa — nạp lại thì
            // ngân hàng vừa chọn (và tên, số tài khoản đang gõ) bị trả về giá trị cũ
            .onAppear {
                guard !loaded else { return }
                loaded = true
                name = member.name; bin = member.bin ?? ""; acct = member.acct ?? ""; photo = member.photo
            }
            .onChange(of: pick) { _, item in
                Task {
                    guard let d = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: d) else { return }
                    photo = Self.thumbnail(img)
                    photoChanged = true
                }
            }
        }
    }

    /// Ảnh vuông 256px, JPEG: nhỏ gọn để đồng bộ nhanh
    static func thumbnail(_ img: UIImage) -> Data? {
        let side = min(img.size.width, img.size.height)
        let crop = CGRect(x: (img.size.width - side) / 2, y: (img.size.height - side) / 2, width: side, height: side)
        let r = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256))
        return r.image { _ in img.draw(in: CGRect(x: -crop.minX * 256 / side, y: -crop.minY * 256 / side,
                                                  width: img.size.width * 256 / side, height: img.size.height * 256 / side)) }
            .jpegData(compressionQuality: 0.8)
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
                .buttonStyle(Pressable())
                .foregroundStyle(.primary)
                Text(L("Khoản chung")).font(.system(size: 21, weight: .bold))
                Spacer()
            }
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L("Số tiền")).font(.system(size: 15)).foregroundStyle(.secondary).padding(.top, 16)
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

                    TextField(L("Ghi chú, ví dụ: đi chợ"), text: $note)
                        .font(.system(size: 18))
                        .padding(.horizontal, 18).padding(.vertical, 15)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.top, 16)
                        .onChange(of: note) { _, v in let g = store.guessCategory(v); if g != "khac" { cat = g } }

                    categories.padding(.top, 12)

                    label(L("Ai ứng tiền"))
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
                        label(L("Chia đều cho"))
                        Spacer()
                        Button(shares.count == house.members.count ? L("Bỏ chọn") : L("Cả nhà")) {
                            shares = shares.count == house.members.count ? [] : Set(house.members.map(\.id))
                        }
                        .buttonStyle(Pressable())
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
                                Text(L("Ghi %@đ vào chi tiêu của tôi", fmt(mine))).font(.system(size: 16, weight: .semibold))
                                Text(L("Thống kê và ngân sách chỉ tính phần của bạn.")).font(.system(size: 14)).foregroundStyle(.secondary)
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
                Text(L("Lưu")).font(.system(size: 19, weight: .semibold))
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
                    .buttonStyle(Pressable())
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
                    Text(m.id == house.me ? L("Bạn") : m.name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
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
            if log, let mine, mine > 0 { store.add(amount: mine, note: n.isEmpty ? L("Nhà chung") : n, cat: c) }
            dismiss()
        }
    }
}
