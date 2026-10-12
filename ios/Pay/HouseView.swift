import PhotosUI
import UserNotifications
import SwiftUI

/// Ảnh đại diện tròn: chữ cái đầu của tên gọi (chữ cuối trong tên), màu riêng theo người.
struct HouseAvatar: View {
    let id: String
    let name: String
    var size: CGFloat = 40
    /// Xem trước khi đang sửa: ảnh đang chọn (nil = đã bỏ ảnh) thay cho ảnh đã lưu của thành viên
    var photo: Data?? = nil
    // Theo dõi House để ảnh đổi là vẽ lại: id, tên, cỡ vẫn như cũ thì SwiftUI không chạy lại body
    @ObservedObject private var house = House.shared

    var body: some View {
        let initial = (name.split(separator: " ").last.map(String.init) ?? name).prefix(1).uppercased()
        // Tìm ở nhóm đang mở trước, rồi mọi nhóm: ở danh sách nhóm chưa có nhóm nào đang mở
        let member: HouseMember? = house.members.first(where: { $0.id == id })
            ?? house.groups.lazy.flatMap { $0.members }.first(where: { $0.id == id })
        let saved: Data? = member?.photo
        if let data = photo ?? saved, let img = UIImage(data: data) {
            Image(uiImage: img).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
        } else {
            Text(initial.isEmpty ? "?" : initial)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(Color(hex: 0x111114))
                .frame(width: size, height: size)
                .background(CategoryTone.bg(house.tone(id)), in: Circle())
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
    /// Nhóm đang sửa ảnh đại diện / tên
    @State private var editingGroup: HouseGroup?
    @State private var showInbox = false
    /// Đang tạo nhóm mới (từ danh sách nhóm)
    @State private var creating = false
    @State private var showArchived = false
    @State private var menu: AppMenuSpec?
    @State private var notifyOn: Bool?
    /// Khoản chung đang sửa
    @State private var editingSpend: HouseSpend?
    /// Lần trả người khác báo đã chuyển cho mình, đang hỏi đã nhận chưa
    @State private var confirming: HouseSettle?
    @Environment(\.scenePhase) private var scenePhase
    /// Đang dựng phim giới thiệu (xem Film.swift)
    @Environment(\.film) private var film

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.bg.ignoresSafeArea()
            FilmScroll {
                VStack(alignment: .leading, spacing: 0) {
                    if !Self.nativeTop { header.hidden() }   // iOS cũ: giữ chỗ cho đầu trang phủ bên trên
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
            // Đầu trang (‹, chuông, ⋯) cố định. iOS 26: thanh của hệ thống, nội dung cuộn lên nhoè dưới nó (cạnh cuộn mềm như
            // Ghi chú, Cài đặt). iOS cũ: phủ dải màu nền mờ dần
            .modifier(PinnedHeader(header: header.padding(.horizontal, 16), film: film != nil))
            // Không có kéo-để-tải-lại: nó giành mất cử chỉ vuốt xuống để ẩn bảng. Sổ tự tải khi mở, khi app quay lại và khi có thông báo
            .withDock(dock: dock, fallbackBlur: bottomFade, film: film != nil)

            ToastView().padding(.bottom, 100)
        }
        .overlay { if house.busy { ProgressView().controlSize(.large) } }
        .sheetGrabber()
        // Vuốt từ mép trái: đang trong nhóm (hoặc đang tạo nhóm) thì về danh sách nhóm, như nút mũi tên ở góc trái.
        // Ở danh sách nhóm thì không làm gì: bảng có vạch ngang, đóng bằng vuốt xuống
        .edgeBack {
            if inGroup { withAnimation(.snappy) { house.open(nil) } }
            else if creating && !house.groups.isEmpty && !house.busy { withAnimation(.snappy) { creating = false } }   // đang lưu nhóm vừa tạo thì chờ xong
        }
        .task {
            await house.load()
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "houseDemoAdd") { adding = true }   // máy ảo không bấm được nút nổi
            #endif
        }
        .sheet(isPresented: $adding) { HouseSpendEditor().environmentObject(store).sheetGrabber() }
        .confirmationDialog(confirming.map { L("%@ báo đã chuyển %@ cho bạn", house.memberName($0.from), fmt($0.amount)) } ?? "",
                            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), titleVisibility: .visible,
                            presenting: confirming) { c in
            Button(L("Đã nhận")) { Task { await house.respond(c.id, received: true) } }
            Button(L("Chưa nhận được"), role: .destructive) { Task { await house.respond(c.id, received: false) } }
            Button(L("Huỷ"), role: .cancel) {}
        } message: { _ in Text(L("Kiểm tra tài khoản rồi xác nhận.")) }
        .sheet(item: $editingSpend) { HouseSpendEditor(editing: $0).environmentObject(store).sheetGrabber() }
        .alert(L("Thêm người vào nhóm"), isPresented: $addingMember) {
            TextField(L("Tên"), text: $newMember)
            Button(L("Huỷ"), role: .cancel) { newMember = ""; claimAfterAdd = false }
            Button(L("Thêm")) {
                let n = newMember.trimmingCharacters(in: .whitespaces)
                newMember = ""
                let claim = claimAfterAdd
                claimAfterAdd = false
                // Chỉ nhận người vừa thêm là mình khi chưa chọn "tôi là ai": không bao giờ đè lên lựa chọn đã có
                if !n.isEmpty { Task { if let id = await house.addMember(n), claim, house.me == nil { await house.claim(id) } } }
            }
        } message: {
            Text(L("Thêm được cả người không dùng Pay; bạn ghi giúp phần của họ."))
        }
        .confirmationDialog(house.isOwner ? L("Xoá nhóm cho cả nhà?") : L("Rời nhóm?"), isPresented: $confirmLeave, titleVisibility: .visible) {
            Button(house.isOwner ? L("Xoá nhóm") : L("Rời nhóm"), role: .destructive) { Task { await house.leave() } }
        } message: {
            Text(house.isOwner ? L("Mọi người trong nhóm sẽ mất sổ chung này. Không hoàn tác được.") : L("Sổ chung vẫn còn ở người tạo nhóm, họ mời lại được."))
        }
        // Bảng Thông báo đang mở thì hộp này hiện trên bảng đó (xem `inbox`): gắn ở đây sẽ không bật lên được vì bảng đang che
        .confirmationDialog(L("Xác nhận đã chuyển?"), isPresented: payAsked(!showInbox), titleVisibility: .visible) { payActions } message: { payMessage }
        .sheet(item: $editingMember) { HouseMemberEditor(member: $0).environmentObject(store).sheetGrabber() }
        .onDisappear { if film == nil { house.open(nil) } }   // (phim vẽ lại màn hình mỗi khung: không tính là đóng)
        .appMenu($menu)   // mở lại thì về danh sách nhóm
        // Trả qua app ngân hàng xong quay lại Pay: hỏi đã chuyển xong chưa
        .onChange(of: scenePhase) { _, p in
            if p == .active, let t = house.pendingPay { house.pendingPay = nil; paying = t }
        }
        // App quay lại từ nền: tải lại sổ (người khác có thể vừa thêm khoản hay xác nhận; đẩy im lặng của iCloud không bảo đảm tới).
        // Vừa đi trả ở app ngân hàng về thì không tải: sắp ghi lần trả ở hộp hỏi trên, không để lần ghi đó phải đua với một lần tải đang chạy
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            if house.pendingPay == nil { Task { await house.load(prompt: false) } }
        }
        .alert(L("Không mở được lời mời"), isPresented: Binding(get: { inviteError != nil }, set: { if !$0 { inviteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(inviteError ?? "") }
    }

    // MARK: Hộp "Xác nhận đã chuyển?" (gắn ở màn nhóm và ở bảng Thông báo; `on` chọn nơi đang hiện để hai hộp không tranh nhau)

    private func payAsked(_ on: Bool) -> Binding<Bool> {
        Binding(get: { paying != nil && on }, set: { if !$0 { paying = nil } })
    }

    @ViewBuilder private var payActions: some View {
        if let t = paying {
            if t.from == house.me {
                Button(L("Đã chuyển %@", fmt(t.amount))) { Task { await house.settle(t) } }
                Button(L("Chưa chuyển"), role: .cancel) {}
            } else {
                Button(L("Đã nhận %@", fmt(t.amount))) { Task { await house.settle(t) } }
            }
        }
    }

    @ViewBuilder private var payMessage: some View {
        if let t = paying {
            Text(t.from == house.me ? L("%@ sẽ nhận thông báo để xác nhận đã nhận tiền.", house.memberName(t.to))
                                    : L("Ghi nhận bạn đã nhận tiền từ %@.", house.memberName(t.from)))
        }
    }

    /// iOS 26: đầu trang là thanh của hệ thống (safeAreaBar), không cần chừa chỗ trong nội dung
    static var nativeTop: Bool { if #available(iOS 26.0, *) { true } else { false } }

    /// Nút "Thêm khoản chung" nổi ở đáy (chỉ khi đã vào nhóm)
    private var inGroup: Bool { house.phase == .ready && house.current != nil && !creating }

    @ViewBuilder private var dock: some View {
        if inGroup && house.me != nil {
            GlassGroup {
                BigButton(title: L("Thêm khoản chung"), icon: "plus", primary: true) { adding = true }
            }
            .padding(.horizontal, 16)
            // Sát vạch Home hơn (cách mép dưới 16 điểm, bằng lề hai bên): để nguyên vùng an toàn 34 điểm + 8 thì
            // dưới hai nút trống một khoảng lớn
            .padding(.bottom, HomeView.nativeEdge ? -18 : 8)
        }
    }

    /// Nền dưới nút chuyển dần sang màu nền, giống màn hình chính
    private var bottomFade: some View {
        Color.clear
            .overlay(alignment: .bottom) {
                if film != nil {
                    // Phim: cùng các mốc ấy, bằng dải màu đặc (xem FilmFade)
                    FilmFade(color: Palette.bg, stops: [(0, 1), (0.3, 1), (0.6, 0.6), (1, 0)], height: 170)
                } else {
                    LinearGradient(stops: [.init(color: Palette.bg, location: 0), .init(color: Palette.bg, location: 0.3),
                                           .init(color: Palette.bg.opacity(0.6), location: 0.6), .init(color: Palette.bg.opacity(0), location: 1)],
                                   startPoint: .bottom, endPoint: .top)
                        .frame(height: 170)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    // MARK: Đầu trang

    private var header: some View {
        HStack(spacing: 8) {
            if inGroup {
                circleButton("arrow.left", L("Các nhóm")) { withAnimation(.snappy) { house.open(nil) } }
            } else if creating && !house.groups.isEmpty {
                // (đang lưu nhóm vừa tạo thì chờ xong: lùi ra lúc này sẽ gặp màn "Bạn là ai" của nhóm chưa có ai)
                circleButton("arrow.left", L("Các nhóm")) { if !house.busy { withAnimation(.snappy) { creating = false } } }
            } else {
                // Ở danh sách nhóm không có nút đóng (vạch ngang trên cùng cho biết kéo xuống là đóng); giữ chỗ để tên vẫn ở giữa
                Color.clear.frame(width: 36, height: 36)
            }
            Spacer()
            if inGroup && house.me != nil {
                // Chuông: việc cần mình xác nhận + hoạt động gần đây
                Button { showInbox = true } label: {
                    Image(systemName: "bell.fill").font(.system(size: 15, weight: .semibold))
                        .frame(width: 36, height: 36).background(Palette.pill, in: Circle())
                        .overlay(alignment: .topTrailing) {
                            if !pending.isEmpty {
                                Text("\(pending.count)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                    .frame(minWidth: 18, minHeight: 18).background(Palette.danger, in: Circle())
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
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 36).background(Palette.pill, in: Circle())
            } else if inGroup {
                Menu {
                    Button(house.isOwner ? L("Mời thành viên") : L("Người trong nhóm"), systemImage: "person.badge.plus") { invite() }
                    Button(L("Thêm người"), systemImage: "plus") { claimAfterAdd = false; addingMember = true }
                    Button(L("Đổi ảnh, màu, tên nhóm"), systemImage: "paintpalette") { editingGroup = house.current }
                    Button(house.isOwner ? L("Xoá nhóm") : L("Rời nhóm"), systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { confirmLeave = true }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold))
                        .frame(width: 36, height: 36).background(Palette.pill, in: Circle())
                }
                .foregroundStyle(.primary)
            } else {
                Color.clear.frame(width: 36, height: 36)
            }
        }
        // Tên ở chính giữa màn hình, không theo khoảng trống giữa các nút (bên phải có hai nút, bên trái một nút)
        .overlay {
            // Trong nhóm: tên nhóm nằm ngay trên số tiền (xem youCard), đầu trang chỉ còn các nút
            if !inGroup {
                Text(creating ? L("Nhóm mới") : L("Nhóm chung"))
                    .font(.system(size: 19, weight: .bold)).lineLimit(1)
                    .padding(.horizontal, 100)
            }
        }
        .padding(.top, 14).padding(.bottom, 14)
        .sheet(isPresented: $showInbox) { inbox }
        .sheet(item: $editingGroup) { HouseGroupEditor(group: $0).sheetGrabber() }
    }

    private func circleButton(_ symbol: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            // Nút back: chỉ có mũi tên, không nền
            Image(systemName: symbol).font(.system(size: symbol == "arrow.left" ? 18 : 15, weight: .bold))
                .frame(width: 36, height: 36, alignment: symbol == "arrow.left" ? .leading : .center)
                .background { if symbol != "arrow.left" { Circle().fill(Palette.pill) } }
                .contentShape(Rectangle())
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
                guard !house.busy else { return }   // bấm hai lần liền nhau: lần đầu đang lưu
                // Giữ màn này tới khi lưu xong: House.create đưa nhóm vào danh sách trước rồi mới lưu thành viên đầu tiên,
                // giữa chừng nhóm chưa có ai và chưa biết "tôi là ai" nên màn hình sẽ nhảy sang "Bạn là ai trong nhóm?" trống
                creating = true
                await house.create(name: groupName.trimmingCharacters(in: .whitespaces), me: myName.trimmingCharacters(in: .whitespaces))
                creating = false
            }
        }
        .disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty || myName.trimmingCharacters(in: .whitespaces).isEmpty || house.busy)
        .opacity(groupName.trimmingCharacters(in: .whitespaces).isEmpty || myName.trimmingCharacters(in: .whitespaces).isEmpty || house.busy ? 0.35 : 1)
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
                // Biểu tượng + chữ đứng giữa nút (dồn trái thì bên phải trống một khoảng lớn)
                HStack(spacing: 10) {
                    Image(systemName: "plus").font(.system(size: 16, weight: .bold))
                    Text(L("Tạo nhóm mới")).font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 64)
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
                groupIcon(g)
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

    private func groupIcon(_ g: HouseGroup, size: CGFloat = 56) -> some View { HouseGroupIcon(group: g, size: size) }

    private func groupMenu(_ g: HouseGroup) -> AppMenuSpec {
        let archived = house.archived.contains(g.id)
        return AppMenuSpec(icon: AnyView(groupIcon(g)), title: g.name.isEmpty ? L("Nhóm chung") : g.name,
                           subtitle: L("%d người · %d khoản chung", g.members.count, g.spends.count), items: [
            AppMenuItem(icon: "arrow.right", title: L("Mở nhóm")) { house.open(g.id) },
            AppMenuItem(icon: "person.badge.plus", title: g.isOwner ? L("Mời thành viên") : L("Người trong nhóm")) { house.open(g.id); invite() },
            AppMenuItem(icon: "paintpalette.fill", title: L("Đổi ảnh, màu, tên nhóm")) { editingGroup = g },
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
        let me = house.me ?? ""
        let mine = net[me] ?? 0

        // 1. Việc của bạn: phải trả ai / ai trả bạn, mỗi người một dòng kèm nút
        youCard(mine, transfers.filter { $0.from == me || $0.to == me })

        // Chỉ nhắc thêm tài khoản khi mình là người được nhận tiền (để người khác bấm Trả ngay)
        if mine > 0, let m = house.members.first(where: { $0.id == me }), !m.hasBank {
            Button { editingMember = m } label: {
                HStack(spacing: 10) {
                    Image(systemName: "creditcard.fill").font(.system(size: 15))
                    Text(L("Thêm tài khoản nhận tiền")).font(.system(size: 16, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 18).frame(height: 58)
                .background(Palette.card, in: Capsule())
            }
            .buttonStyle(Pressable())
            .padding(.top, 10)
        }

        // 2. Cần xác nhận (chỉ khi có)
        pendingSection

        // 3. Khoản chi chung
        sectionTitle(L("Khoản chi"), trailing: monthTotal)
        spendList

        // 4. Cả nhóm (thu gọn)
        groupSection(net, transfers.filter { $0.from != me && $0.to != me })
    }

    private var monthTotal: String? {
        let cal = Calendar.current
        let sum = house.spends.filter { cal.isDate($0.date, equalTo: Date(), toGranularity: .month) }.reduce(0) { $0 + $1.amount }
        guard sum > 0 else { return nil }
        if Lang.isEnglish { return "\(Date().formatted(.dateTime.month(.wide).locale(Lang.locale))): \(fmt(sum))" }
        return "Tháng \(cal.component(.month, from: Date())): \(fmt(sum))"
    }

    /// Thẻ trên cùng: số tiền của riêng bạn, bên dưới là từng người bạn cần trả / sẽ trả bạn.
    private func youCard(_ mine: Int, _ mineTransfers: [HouseTransfer]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(house.name).font(.system(size: 28, weight: .bold)).lineLimit(2).padding(.bottom, 14)
            // Màu đỏ / xanh chỉ ở dòng chữ nhỏ; số tiền to màu chữ thường cho dễ đọc trên nền xám
            Text(mine > 0 ? L("Bạn sẽ nhận") : mine < 0 ? L("Bạn cần trả") : L("Bạn không nợ ai"))
                .font(.system(size: 16, weight: mine == 0 ? .regular : .semibold))
                .foregroundStyle(mine < 0 ? Palette.danger : mine > 0 ? Palette.goodInk : .secondary)
            if mine != 0 {
                Text(fmt(abs(mine)))
                    .font(.system(size: 46, weight: .bold)).kerning(-1.5)
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.5).lineLimit(1)
                    .padding(.top, 6)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(.green)
                    Text(L("Đã cân bằng")).font(.system(size: 22, weight: .bold))
                }
                .padding(.top, 6)
            }
            if !mineTransfers.isEmpty {
                VStack(spacing: 8) {
                    ForEach(mineTransfers, id: \.self) { personRow($0) }
                }
                .padding(.top, 16)
            }
        }
        // Không bọc nền: nằm thẳng trên nền màn hình, chỉ các dòng từng người có nền (tránh lồng nhiều lớp nền)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Một người trong thẻ "Việc của bạn": bạn trả họ, hoặc họ trả bạn.
    private func personRow(_ t: HouseTransfer) -> some View {
        let outgoing = t.from == house.me
        let other = outgoing ? t.to : t.from
        let name = house.memberName(other)
        let canPay = outgoing && house.members.first { $0.id == t.to }?.hasBank == true
        return HStack(spacing: 12) {
            HouseAvatar(id: other, name: name, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(outgoing ? L("Trả %@", name) : L("%@ trả bạn", name)).font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(1)
                Text(fmt(t.amount)).font(.system(size: 18, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 4)
            Button {
                if canPay { Task { await house.payNow(t, app: store.bankApp) } } else { paying = t }
            } label: {
                // Có tài khoản: Trả ngay (mở app ngân hàng). Không có: báo đã trả bằng cách khác. Người nhận: xác nhận đã nhận
                Text(canPay ? L("Trả ngay") : outgoing ? L("Báo đã trả") : L("Đã nhận"))
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 14).frame(height: 38)
                    .foregroundStyle(canPay ? Palette.ctaInk : .primary)
                    .background(canPay ? Palette.cta : Palette.surface, in: Capsule())
            }
            .buttonStyle(Pressable())
        }
        .padding(10).padding(.trailing, 2)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onHold {
            guard outgoing else { return }
            menu = AppMenuSpec(icon: AnyView(HouseAvatar(id: t.to, name: name, size: 56)), title: L("Bạn trả %@", name) + " · \(fmt(t.amount))",
                               subtitle: house.members.first { $0.id == t.to }?.hasBank == true ? L("Đã có tài khoản nhận tiền") : L("Chưa có tài khoản nhận tiền"),
                               items: [
                AppMenuItem(icon: "creditcard.fill", title: L("Trả qua app ngân hàng")) { Task { await house.payNow(t, app: store.bankApp) } },
                AppMenuItem(icon: "checkmark", title: L("Đã chuyển bằng cách khác"), subtitle: L("Tiền mặt, ví điện tử…")) { paying = t },
            ].filter { $0.icon != "creditcard.fill" || house.members.first { $0.id == t.to }?.hasBank == true })
        }
    }

    /// Mục "Cả nhóm" (luôn hiện). Số dư từng người bằng chữ, các lần trả giữa người khác, lịch sử trả tiền.
    private var addMemberLabel: some View {
        Label(L("Thêm người"), systemImage: "plus")
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Palette.card, in: Capsule())
            .foregroundStyle(.primary)
    }

    @ViewBuilder private func groupSection(_ net: [String: Int], _ others: [HouseTransfer]) -> some View {
        sectionTitle(L("Cả nhóm"), trailing: L("%d người", house.members.count))
        do {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(house.members) { m in memberRow(m, net[m.id] ?? 0) }
                // Một nút, hai cách: mời người có dùng Pay (họ tự vào nhóm), hoặc chỉ thêm tên người không dùng Pay (mình ghi giúp)
                // Phim: chỉ vẽ nhãn nút (Menu là của UIKit, ảnh xuất ra chỉ thấy ô vàng có dấu cấm)
                if film != nil { addMemberLabel } else {
                Menu {
                    Button { invite() } label: {
                        Text(L("Gửi lời mời")); Text(L("Người này có dùng Pay")); Image(systemName: "paperplane")
                    }
                    Button { claimAfterAdd = false; addingMember = true } label: {
                        Text(L("Chỉ thêm tên")); Text(L("Không dùng Pay, bạn ghi giúp")); Image(systemName: "person.text.rectangle")
                    }
                } label: { addMemberLabel }
                .tint(.primary)
                }

                if !others.isEmpty {
                    Text(L("Giữa những người khác")).font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 10)
                    ForEach(others, id: \.self) { t in
                        HStack(spacing: 8) {
                            HouseAvatar(id: t.from, name: house.memberName(t.from), size: 32)
                            Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                            HouseAvatar(id: t.to, name: house.memberName(t.to), size: 32)
                            Text(L("%@ trả %@", house.memberName(t.from), house.memberName(t.to))).font(.system(size: 15)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(fmt(t.amount)).font(.system(size: 15, weight: .semibold))
                        }
                        .padding(10)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }

                if !house.settles.isEmpty {
                    Text(L("Lịch sử trả tiền")).font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 10)
                    ForEach(house.settles.sorted { $0.date > $1.date }) { settleRow($0) }
                }
            }
        }
    }

    /// Một người trong "Cả nhóm": số dư viết bằng chữ, chạm để sửa tên / tài khoản.
    private func memberRow(_ m: HouseMember, _ v: Int) -> some View {
        let isMe = m.id == house.me
        let name = isMe ? L("Bạn") : m.name
        return HStack(spacing: 12) {
            HouseAvatar(id: m.id, name: m.name, size: 40)
            HStack(spacing: 6) {
                Text(name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                if m.hasBank { Image(systemName: "creditcard.fill").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 4)
            Text(v > 0 ? L("sẽ nhận %@", fmt(v)) : v < 0 ? L("cần trả %@", fmt(-v)) : L("không nợ"))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(v < 0 ? Palette.danger : v > 0 ? Palette.goodInk : .secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture { editingMember = m }
    }

    /// Các khoản chi chung, mới nhất trước.
    @ViewBuilder private var spendList: some View {
        if house.spends.isEmpty {
            Text(L("Chưa có khoản chung nào. Bấm Thêm khoản chung khi bạn ứng tiền cho cả nhà."))
                .font(.system(size: 16)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(24)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        VStack(spacing: 10) {
            ForEach(house.spends.sorted { $0.date > $1.date }) { spendRow($0) }
        }
    }

    private func spendRow(_ e: HouseSpend) -> some View {
        let c = Category.get(e.cat)
        let payer = house.memberName(e.payer)
        return HStack(spacing: 14) {
            CategoryBadge(c: c, side: 52, radius: 16, iconSize: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(e.note.isEmpty ? c.name : e.note.capFirst).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                Text(L("%@ trả · %@", e.payer == house.me ? L("Bạn") : payer, day(e.date)))
                    .font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(fmt(e.amount)).font(.system(size: 17, weight: .bold))
                if let me = house.me, e.shares.contains(me) {
                    Text(L("bạn chịu %@", fmt(Settle.split(e.amount, e.shares, seed: e.id)[me] ?? 0)))
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.leading, 12).padding(.trailing, 16).padding(.vertical, 12)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture { editingSpend = e }   // chạm để xem / sửa ai trả, chia cho ai
        .onHold {
            let c = Category.get(e.cat)
            menu = AppMenuSpec(icon: AnyView(CategoryBadge(c: c, side: 56, radius: 18, iconSize: 30)),
                               title: "\(e.note.isEmpty ? c.name : e.note.capFirst) · \(fmt(e.amount))",
                               subtitle: L("%@ ứng · chia %d người · %@", house.memberName(e.payer), Set(e.shares).count, day(e.date)),
                               items: [AppMenuItem(icon: "pencil", title: L("Sửa khoản này")) { editingSpend = e },
                                       AppMenuItem(icon: "trash.fill", title: L("Xoá khoản này"), subtitle: L("Cả nhóm sẽ không thấy khoản này nữa"), danger: true) {
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
            // Biểu tượng tròn đặc cùng một khung (clock / checkmark / xmark .circle.fill) để to nhỏ đều nhau
            Image(systemName: icon + ".circle.fill").font(.system(size: 24)).foregroundStyle(tint)
                .frame(width: 52, height: 52)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(L("%@ chuyển %@", from, to)).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                Text("\(note) · \(day(s.date))").font(.system(size: 14)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            // Số tiền màu chữ thường cho dễ đọc; trạng thái đã có ở biểu tượng màu bên trái
            Text(fmt(s.amount)).font(.system(size: 17, weight: .bold)).foregroundStyle(s.status == "no" ? .secondary : .primary)
                .strikethrough(s.status == "no")
        }
        .padding(.leading, 12).padding(.trailing, 16).padding(.vertical, 12)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        // Người khác báo đã chuyển cho mình, đang chờ: chạm để xác nhận đã nhận hay chưa
        .onTapGesture { if s.to == house.me && s.status == "wait" { confirming = s } }
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
            .screenTitle(L("Thông báo"))
            .navigationBarTitleDisplayMode(.inline)
            .task {
                let s = await UNUserNotificationCenter.current().notificationSettings()
                notifyOn = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
            }
        }
        // Bảng này che màn nhóm bên dưới, nên thanh báo lỗi, vòng xoay và hộp "Xác nhận đã chuyển?" của các thẻ
        // "Cần xác nhận" phải có ngay trên bảng (ở màn nhóm thì bấm xong không thấy gì)
        .overlay(alignment: .bottom) { ToastView().padding(.bottom, 24) }
        .overlay { if house.busy { ProgressView().controlSize(.large) } }
        .confirmationDialog(L("Xác nhận đã chuyển?"), isPresented: payAsked(showInbox), titleVisibility: .visible) { payActions } message: { payMessage }
        .environmentObject(store)
        .sheetGrabber()   // không có nút Xong: kéo xuống là đóng
    }

    private struct Activity { let id: String; let who: String; let text: String; let date: Date }

    /// Khoản chung người khác vừa thêm và các lần trả liên quan tới mình, mới nhất trước.
    private var activity: [Activity] {
        let me = house.me, name = house.memberName
        var out: [Activity] = []
        for e in house.spends where e.payer != me {
            let part = me.flatMap { e.shares.contains($0) ? Settle.split(e.amount, e.shares, seed: e.id)[$0] : nil }
            out.append(Activity(id: e.id, who: e.payer, text: L("%@ thêm %@ %@", name(e.payer), e.note.isEmpty ? L("một khoản") : "\"\(e.note)\"", fmt(e.amount))
                                + (part.map { L(", phần bạn %@", fmt($0)) } ?? ""), date: e.date))
        }
        for s in house.settles where s.from == me || s.to == me {
            let other = s.from == me ? s.to : s.from
            let text: String = switch (s.from == me, s.status) {
            case (true, "wait"): L("Đã báo chuyển %@ cho %@, chờ xác nhận", fmt(s.amount), name(s.to))
            case (true, "no"): L("%@ chưa nhận được %@ bạn chuyển", name(s.to), fmt(s.amount))
            case (true, _): L("%@ đã nhận %@ của bạn", name(s.to), fmt(s.amount))
            case (false, "wait"): L("%@ báo đã chuyển cho bạn %@", name(s.from), fmt(s.amount))
            case (false, "no"): L("Bạn báo chưa nhận được %@ từ %@", fmt(s.amount), name(s.from))
            case (false, _): L("Bạn đã nhận %@ từ %@", fmt(s.amount), name(s.from))
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
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))   // phẳng: chỉ nền, không viền
    }

    private func pill(_ title: String, primary: Bool, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title).font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(primary ? Palette.ctaInk : .primary)
                .background(primary ? Palette.cta : Palette.surface, in: Capsule())   // nút phụ nền trắng trên thẻ xám
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

/// Ảnh đại diện của nhóm: ảnh đã chọn, không thì biểu tượng nhóm trên nền màu (màu đã chọn, không thì màu theo mã nhóm).
struct HouseGroupIcon: View {
    let group: HouseGroup
    var size: CGFloat = 56
    /// Xem trước khi đang sửa: ảnh / màu đang chọn thay cho của nhóm
    var photo: Data?? = nil
    var tone: Int?? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
        let t = (tone ?? group.tone) ?? House.shared.tone(group.id)
        if let data = photo ?? group.photo, let img = UIImage(data: data) {
            Image(uiImage: img).resizable().scaledToFill().frame(width: size, height: size).clipShape(shape)
        } else {
            Image(systemName: "person.2.crop.square.stack.fill")
                .font(.system(size: size * 0.43))
                .foregroundStyle(CategoryTone.dark(t) ? .white : Color(hex: 0x111114))
                .frame(width: size, height: size)
                .background(CategoryTone.bg(t), in: shape)
        }
    }
}

/// Sửa nhóm: ảnh đại diện (ảnh tự chọn hoặc một màu) và tên. Cả nhóm cùng thấy.
struct HouseGroupEditor: View {
    @ObservedObject private var house = House.shared
    @Environment(\.dismiss) private var dismiss
    let group: HouseGroup
    @State private var name = ""
    @State private var tone: Int?
    @State private var photo: Data?
    @State private var photoChanged = false
    @State private var pick: PhotosPickerItem?
    @State private var loaded = false
    /// Đang lưu lên iCloud: nút Lưu mờ đi cho biết đã nhận (vòng xoay ở màn nhóm bị bảng này che)
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        HouseGroupIcon(group: group, size: 96, photo: .some(photo), tone: .some(tone))
                        HStack(spacing: 16) {
                            PhotosPicker(selection: $pick, matching: .images) { Text(photo == nil ? L("Chọn ảnh") : L("Đổi ảnh")) }
                            if photo != nil { Button(L("Bỏ ảnh"), role: .destructive) { photo = nil; photoChanged = true } }
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .buttonStyle(.borderless)   // trong Form: mỗi nút tự nhận chạm, không phải cả hàng
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Section(L("Tên")) { TextField(L("Tên nhóm"), text: $name) }
                Section {
                    VStack(spacing: 10) {
                        swatchRow(CategoryTone.light)
                        swatchRow(CategoryTone.strong)
                        swatchRow(CategoryTone.flat)
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text(L("Màu"))
                } footer: {
                    if photo != nil { Text(L("Đang dùng ảnh. Bỏ ảnh để hiện màu.")) }
                }
            }
            .screenTitle(L("Sửa nhóm"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Huỷ")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Lưu")) {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        let p: Data? = photoChanged ? (photo ?? Data()) : nil
                        saving = true
                        Task {
                            await house.updateGroup(group.id, name: n.isEmpty ? group.name : n, tone: tone, photo: p)
                            dismiss()
                        }
                    }
                    .disabled(saving)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                name = group.name; tone = group.tone; photo = group.photo
            }
            .onChange(of: pick) { _, item in
                Task {
                    guard let d = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: d) else { return }
                    photo = HouseMemberEditor.thumbnail(img)
                    photoChanged = true
                }
            }
        }
    }

    private func swatchRow(_ range: Range<Int>) -> some View {
        let now = tone ?? house.tone(group.id)
        return HStack(spacing: 0) {
            ForEach(Array(range), id: \.self) { i in
                Button { tone = i } label: {
                    Circle().fill(CategoryTone.bg(i)).frame(width: 30, height: 30)
                        .overlay { Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1) }
                        .overlay {
                            if i == now && photo == nil {
                                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(CategoryTone.dark(i) ? .white : Color(hex: 0x111114))
                            }
                        }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(Pressable())
                .accessibilityLabel(L("Màu %d", i + 1))
            }
        }
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
    /// Đang lưu lên iCloud: nút Lưu mờ đi cho biết đã nhận (vòng xoay ở màn nhóm bị bảng này che)
    @State private var saving = false

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
                                // .some(nil): chỉ chữ cái — vừa bấm "Bỏ ảnh" thì không hiện lại ảnh đã lưu
                                HouseAvatar(id: member.id, name: name.isEmpty ? member.name : name, size: 96, photo: .some(nil))
                            }
                        }
                        HStack(spacing: 16) {
                            PhotosPicker(selection: $pick, matching: .images) { Text(photo == nil ? L("Chọn ảnh") : L("Đổi ảnh")) }
                            if photo != nil { Button(L("Bỏ ảnh"), role: .destructive) { photo = nil; photoChanged = true } }
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .buttonStyle(.borderless)   // trong Form: mỗi nút tự nhận chạm, không phải cả hàng (thiếu thì chạm "Đổi ảnh" là "Bỏ ảnh" cũng chạy)
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
            .screenTitle(member.id == house.me ? L("Bạn") : member.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Huỷ")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Lưu")) {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        let a = acct.filter(\.isNumber)
                        let p: Data? = photoChanged ? (photo ?? Data()) : nil
                        saving = true
                        Task {
                            await house.updateMember(member.id, name: n.isEmpty ? member.name : n,
                                                     bin: bin.isEmpty ? nil : bin, acct: a.isEmpty ? nil : a, photo: p)
                            dismiss()
                        }
                    }
                    .disabled(saving)
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
    /// Đang sửa khoản có sẵn (nil: thêm khoản mới)
    var editing: HouseSpend? = nil
    @EnvironmentObject var store: Store
    @ObservedObject private var house = House.shared
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var note = ""
    @State private var cat = "an"
    /// Đã tự chọn danh mục: gõ tiếp ghi chú không đoán lại nữa (như màn nhập khoản chi)
    @State private var catPicked = false
    @State private var payer = ""
    @State private var shares: Set<String> = []
    @State private var logMine = true
    /// Đang lưu lên iCloud: khoá nút Lưu, bấm lần nữa sẽ thành hai khoản giống nhau
    @State private var saving = false
    /// Lần lưu vừa rồi không thành: hiện thanh báo lỗi ngay trên bảng này (thanh ở màn nhóm bị bảng che)
    @State private var failed = false
    /// Bàn phím số của app đang hiện (ẩn khi gõ ghi chú, chạm số tiền thì hiện lại)
    @State private var padShown = true
    @FocusState private var noteFocused: Bool

    private var amount: Int { Int(amountText.filter(\.isNumber).prefix(12)) ?? 0 }
    private var parts: [String: Int] { Settle.split(amount, Array(shares), seed: "") }
    private var myShare: Int? { house.me.flatMap { shares.contains($0) ? parts[$0] : nil } }

    var body: some View {
        VStack(spacing: 0) {
            // Bảng có vạch ngang, vuốt xuống là đóng: không cần nút quay lại
            Text(editing == nil ? L("Khoản chung") : L("Sửa khoản chung")).font(.system(size: 21, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 26)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L("Số tiền")).font(.system(size: 15)).foregroundStyle(.secondary).padding(.top, 16)
                    // Số tiền nhập bằng bàn phím số của app (bên dưới), chạm vào đây để hiện lại bàn phím
                    // Cùng kiểu ô số tiền của màn nhập khoản chi: khung viền mảnh, vạch nhấp nháy sau số khi đang nhập
                    HStack(spacing: 4) {
                        Text(amount > 0 ? fmt(amount) : "0")
                            .font(.system(size: 40, weight: .bold)).kerning(-1)
                            .foregroundStyle(amount > 0 ? .primary : .tertiary)
                            .contentTransition(.numericText())
                            .lineLimit(1).minimumScaleFactor(0.5)
                        if padShown && !noteFocused {
                            TimelineView(.periodic(from: .now, by: 0.55)) { t in
                                let on = Int(t.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0
                                Capsule().fill(Palette.goodInk).frame(width: 3, height: 36).opacity(on ? 1 : 0)
                                    .animation(.easeInOut(duration: 0.18), value: on)
                            }
                            .accessibilityHidden(true)
                        }
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1) }
                    .contentShape(Rectangle())
                    .onTapGesture { noteFocused = false; withAnimation(.snappy(duration: 0.25)) { padShown = true } }
                    .animation(.snappy(duration: 0.15), value: amount)
                    .padding(.top, 8)

                    TextField(L("Ghi chú, ví dụ: đi chợ"), text: $note)
                        .focused($noteFocused)
                        .font(.system(size: 18))
                        .padding(.horizontal, 18).padding(.vertical, 15)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.top, 16)
                        .onChange(of: note) { _, v in
                            guard !catPicked else { return }
                            let g = store.guessCategory(v); if g != "khac" { cat = g }
                        }

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
                    // Cùng kiểu viên thuốc với "Ai ứng tiền": chọn thì nền đậm, không chọn nền nhạt; xếp ngang, hết chỗ thì xuống dòng
                    ChipFlow(spacing: 8) {
                        ForEach(house.members) { m in
                            let on = shares.contains(m.id)
                            personChip(m, on: on, sub: on && amount > 0 ? fmt(parts[m.id] ?? 0) : nil) {
                                if on { shares.remove(m.id) } else { shares.insert(m.id) }
                            }
                        }
                    }

                    if editing == nil, let mine = myShare, mine > 0 {   // sửa khoản cũ: không ghi thêm vào chi tiêu cá nhân
                        Toggle(isOn: $logMine) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("Ghi %@ vào chi tiêu của tôi", fmt(mine))).font(.system(size: 16, weight: .semibold))
                                Text(L("Thống kê và ngân sách chỉ tính phần của bạn.")).font(.system(size: 14)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(16)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.top, 18)
                    }
                }
                .padding(.bottom, 20)
                .padding(.horizontal, 18)
                // Chạm vào chỗ trống ngoài bàn phím số: bàn phím ẩn đi (chạm ô số tiền để hiện lại)
                .contentShape(Rectangle())
                .onTapGesture { if padShown { withAnimation(.snappy(duration: 0.25)) { padShown = false } } }
            }
            // Vùng cuộn tràn ra sát hai mép bảng (nội dung tự lùi vào 18pt) để thanh cuộn nằm sát mép phải
            .padding(.horizontal, -18)
            // Kéo nội dung lên để xem phần bên dưới: bàn phím số tự ẩn nhường chỗ (chạm số tiền để hiện lại)
            .simultaneousGesture(DragGesture(minimumDistance: 16).onChanged { v in
                if padShown, v.translation.height < -16, abs(v.translation.width) < 30 {
                    withAnimation(.snappy(duration: 0.25)) { padShown = false }
                }
            })
            .scrollDismissesKeyboard(.interactively)
            // Gõ ghi chú thì bàn phím chữ của iOS lên, bàn phím số của app nhường chỗ
            .onChange(of: noteFocused) { _, f in if f { withAnimation(.snappy(duration: 0.25)) { padShown = false } } }
            // Bàn phím số và hàng nút nổi trên vùng cuộn: nội dung cuộn chui xuống dưới, mép trên của tấm này làm mờ (blur) dần
            // nội dung đang trôi qua, từ đó trở xuống là nền đục
            .softBottomPanel {
                VStack(spacing: 0) {

                if padShown {
                    VStack(spacing: 0) {
                        NumberPad(digits: $amountText) { noteFocused = false }
                            .frame(height: 248)
                    }
                    .padding(.bottom, 6)
                    .transition(.opacity)   // chỉ mờ đi: trượt xuống thì các phím số chạy ngang qua hàng nút Huỷ / Lưu
                }

                // Huỷ và Lưu cùng một hàng sát đáy, như màn nhập khoản chi (vùng an toàn dưới 34 điểm, lùi xuống 18)
                HStack(spacing: 12) {
                    BigButton(title: L("Huỷ"), icon: "", primary: false) { dismiss() }
                    // Đang lưu: nút mờ và không nhận bấm (bấm lần nữa sẽ thành hai khoản giống nhau)
                    BigButton(title: L("Lưu"), icon: "", primary: true) { if valid && !saving { save() } }
                        .overlay { if saving { ProgressView().tint(Palette.ctaInk) } }
                        .opacity(valid && !saving ? 1 : 0.35)
                        .animation(.easeInOut(duration: 0.25), value: valid && !saving)
                }
                .padding(.bottom, -18)
                }
                .padding(.top, PanelEdge.gap)   // khoảng trống phía trên phím: nội dung cuộn chui vào đây và bị nhoè dần
                .background {
                    VStack(spacing: 0) {
                        PanelEdge()
                        Palette.surface
                    }
                    .padding(.top, -PanelEdge.rise)   // dải mờ vươn lên trên tấm, phủ lên phần nội dung đang cuộn
                    .padding(.horizontal, -18)   // nền tràn ra sát hai mép bảng, nút và phím vẫn thẳng lề nội dung
                    .ignoresSafeArea(edges: .bottom)
                }
            }
        }
        .padding(.horizontal, 18)
        .background(Palette.surface.ignoresSafeArea())
        .overlay(alignment: .bottom) { if failed { ToastView().padding(.bottom, 84) } }   // ngay trên nút Lưu
        .onAppear {
            if let e = editing {
                amountText = String(e.amount); note = e.note; cat = e.cat; catPicked = true
                payer = e.payer; shares = Set(e.shares)
                padShown = false
            } else {
                payer = house.me ?? house.members.first?.id ?? ""
                shares = Set(house.members.map(\.id))
            }
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
                    Button { cat = c.k; catPicked = true } label: {
                        HStack(spacing: 8) {
                            CategoryBadge(c: c, side: 32, radius: 9, iconSize: 20)
                            Text(c.name).font(.system(size: 16, weight: on ? .semibold : .medium))
                        }
                        .padding(.leading, 5).padding(.trailing, 14).padding(.vertical, 5)
                        .foregroundStyle(on ? c.ink : Color.primary)
                        .background(on ? c.color : Color.primary.opacity(0.05), in: Capsule())
                    }
                    .buttonStyle(Pressable())
                }
            }
            .padding(.horizontal, 18)
        }
        .padding(.horizontal, -18)
    }

    private func personChip(_ m: HouseMember, on: Bool, sub: String?, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 10) {
                HouseAvatar(id: m.id, name: m.name, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.id == house.me ? L("Bạn") : m.name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    if let line = sub { Text(line).font(.system(size: 13)).foregroundStyle(on ? Palette.ctaInk.opacity(0.7) : .secondary).lineLimit(1) }
                }
            }
            .padding(.leading, 6).padding(.trailing, 14).padding(.vertical, 6)
            .foregroundStyle(on ? Palette.ctaInk : .primary)
            .background(on ? Palette.cta : Color.primary.opacity(0.05), in: Capsule())
        }
        .buttonStyle(Pressable())
    }

    private func save() {
        guard !saving else { return }
        saving = true; failed = false
        let a = amount, n = note.trimmingCharacters(in: .whitespaces), c = cat, p = payer, s = Array(shares), mine = myShare
        let log = logMine
        Task {
            if var e = editing {
                e.amount = a; e.note = n; e.cat = c; e.payer = p; e.shares = s
                guard await house.updateSpend(e) else { saving = false; failed = true; return }
                dismiss(); return
            }
            // Không lưu được: ở lại bảng, mở lại nút Lưu, House đã đưa lỗi lên thanh báo
            guard await house.addSpend(amount: a, note: n, payer: p, shares: s, cat: c) else { saving = false; failed = true; return }
            if log, let mine, mine > 0 { store.add(amount: mine, note: n.isEmpty ? L("Nhà chung") : n, cat: c) }
            dismiss()
        }
    }
}

/// Xếp các viên thuốc theo hàng ngang, hết bề ngang thì xuống dòng.
struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(width: CGFloat, _ subviews: Subviews) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + size.width <= width {
                rows[rows.count - 1].items.append(i)
                rows[rows.count - 1].width += spacing + size.width
                rows[rows.count - 1].height = max(last.height, size.height)
            } else {
                rows.append(([i], size.width, size.height))
            }
        }
        return rows
    }
}

/// Đầu trang cố định của màn Nhóm chung; iOS 26 dùng cạnh cuộn nhoè của hệ thống.
private struct PinnedHeader<H: View>: ViewModifier {
    let header: H
    let film: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !film {
            // Cạnh nhoè của hệ thống quá nhẹ: nội dung vẫn lộ ở khoảng trên các nút rồi bị cắt ở mép bảng. Phủ thêm màu nền đặc
            // ở trên cùng, nhạt dần xuống ngang các nút (như dải nút dưới đáy màn hình chính)
            content
                .safeAreaBar(edge: .top) {
                    header.background(alignment: .bottom) {
                        LinearGradient(stops: [.init(color: Palette.bg, location: 0), .init(color: Palette.bg, location: 0.45),
                                               .init(color: Palette.bg.opacity(0.7), location: 0.7), .init(color: Palette.bg.opacity(0), location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                            .padding(.bottom, -24).padding(.top, -40)
                            .allowsHitTesting(false)
                    }
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content.overlay(alignment: .top) {
                header.background(alignment: .top) {
                    LinearGradient(stops: [.init(color: Palette.bg, location: 0), .init(color: Palette.bg, location: 0.55),
                                           .init(color: Palette.bg.opacity(0), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .padding(.bottom, -28)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

/// Mép trên của tấm bàn phím số: nội dung cuộn tới đây bị làm nhoè dần rồi mới chìm vào nền đục bên dưới.
/// iOS 26: nhoè bằng mép cuộn mềm của hệ thống (cùng hiệu ứng với thanh nút ở trang chủ), dải này chỉ để trống phần trên
/// cho thấy lớp nhoè và ngả sang nền đục ở cuối. iOS cũ: tự làm bằng lớp kính mờ.
private struct PanelEdge: View {
    static let gap: CGFloat = 22      // đệm trên của tấm: vùng nhoè chỉ nhô lên trên hàng phím đầu một chút (hệ thống nhoè nội dung cuộn nằm dưới tấm)
    static let rise: CGFloat = 0
    static let height: CGFloat = rise + gap + 155   // trong suốt qua hai hàng phím đầu, tới hàng 7 8 9 mới đục hẳn
    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                // Đục dần đều từ mép trên xuống tới hàng 7 8 9
                LinearGradient(colors: [Palette.surface.opacity(0), Palette.surface],
                               startPoint: .top, endPoint: .bottom)
            } else {
                Rectangle().fill(.ultraThinMaterial)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.4), .init(color: .black, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(LinearGradient(stops: [.init(color: Palette.surface.opacity(0), location: 0.55), .init(color: Palette.surface, location: 1)],
                                            startPoint: .top, endPoint: .bottom))
            }
        }
        .frame(height: Self.height)
        .allowsHitTesting(false)
    }
}

private extension View {
    /// Gắn tấm ở đáy vùng cuộn. iOS 26: safeAreaBar để hệ thống tự nhoè nội dung cuộn chui xuống dưới tấm.
    @ViewBuilder func softBottomPanel<P: View>(@ViewBuilder _ panel: () -> P) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .bottom, spacing: 0) { panel() }.scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            safeAreaInset(edge: .bottom, spacing: 0) { panel() }
        }
    }
}
