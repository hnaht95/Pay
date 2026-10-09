import SwiftUI

/// Nhóm "Nhà chung": khoản chi chung của cả nhà, ai ứng thì ghi, cuối tháng xem ai chuyển cho ai.
struct HouseView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var house = House.shared
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    @State private var groupName = "Nhà mình"
    @State private var myName = ""
    @State private var newMember = ""
    @State private var confirmLeave = false
    @State private var paying: HouseTransfer?
    @State private var inviteError: String?

    var body: some View {
        NavigationStack {
            Form { content }
                .navigationTitle(house.phase == .ready && !house.name.isEmpty ? house.name : "Nhà chung")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } }
                    if house.phase == .ready && house.me != nil {
                        ToolbarItem(placement: .confirmationAction) {
                            Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Thêm khoản chung")
                        }
                    }
                }
                .refreshable { await house.load() }
                .overlay { if house.busy { ProgressView().controlSize(.large) } }
        }
        .task { await house.load() }
        .sheet(isPresented: $adding) { HouseSpendEditor().environmentObject(store) }
        .confirmationDialog(house.isOwner ? "Xoá nhóm cho cả nhà?" : "Rời nhóm?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button(house.isOwner ? "Xoá nhóm" : "Rời nhóm", role: .destructive) { Task { await house.leave() } }
        } message: {
            Text(house.isOwner ? "Mọi người trong nhóm sẽ mất sổ chung này. Không hoàn tác được." : "Sổ chung vẫn còn ở người tạo nhóm; họ mời lại được.")
        }
        .confirmationDialog("Xác nhận đã chuyển?", isPresented: Binding(get: { paying != nil }, set: { if !$0 { paying = nil } }), titleVisibility: .visible) {
            if let t = paying {
                Button("\(house.memberName(t.from)) đã trả \(fmt(t.amount))đ") { Task { await house.settle(t) } }
            }
        } message: {
            if let t = paying { Text("Ghi nhận \(house.memberName(t.from)) đã chuyển cho \(house.memberName(t.to)). Số dư hai người về 0.") }
        }
        .alert("Không mở được lời mời", isPresented: Binding(get: { inviteError != nil }, set: { if !$0 { inviteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(inviteError ?? "") }
    }

    @ViewBuilder private var content: some View {
        switch house.phase {
        case .loading:
            Section { HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 30) }
        case .noAccount:
            Section {
                Text("Nhà chung lưu trên iCloud. Đăng nhập iCloud trong Cài đặt của iPhone rồi mở lại.").foregroundStyle(.secondary)
            }
        case .failed(let why):
            Section {
                Text(why).foregroundStyle(.secondary)
                Button("Thử lại") { Task { await house.load() } }
            }
        case .none:
            createForm
        case .ready:
            if house.me == nil { pickMe } else { ready }
        }
    }

    // MARK: Chưa có nhóm

    @ViewBuilder private var createForm: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "house.fill").font(.system(size: 30)).foregroundStyle(.orange)
                Text("Sổ chi tiêu chung của cả nhà").font(.system(size: 20, weight: .bold))
                Text("Ai đi chợ, trả điện nước thì ghi vào đây. Cuối tháng Pay tính ai phải chuyển cho ai bao nhiêu, ít lần chuyển nhất.")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
        Section {
            TextField("Tên nhóm", text: $groupName)
            TextField("Tên của bạn", text: $myName)
        } footer: {
            Text("Tạo xong, bấm Mời để gửi lời mời qua Tin nhắn hoặc Zalo. Người được mời cần cài Pay và đăng nhập iCloud. Muốn vào nhóm người khác đã tạo thì bấm vào lời mời họ gửi.")
        }
        Section {
            Button("Tạo nhóm") {
                Task { await house.create(name: groupName.trimmingCharacters(in: .whitespaces), me: myName.trimmingCharacters(in: .whitespaces)) }
            }
            .disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty || myName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: Chọn "tôi là ai"

    @ViewBuilder private var pickMe: some View {
        Section {
            ForEach(house.members) { m in
                Button { house.me = m.id } label: { Text(m.name).foregroundStyle(.primary) }
            }
        } header: {
            Text("Bạn là ai trong nhóm?")
        } footer: {
            Text("Chỉ để biết phần nào là của bạn trên máy này.")
        }
        Section {
            TextField("Tên của bạn", text: $newMember)
            Button("Thêm tôi vào nhóm") {
                let n = newMember.trimmingCharacters(in: .whitespaces)
                Task { if let id = await house.addMember(n) { house.me = id; newMember = "" } }
            }
            .disabled(newMember.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: Nhóm

    @ViewBuilder private var ready: some View {
        let net = Settle.balances(house.spends, house.settles)
        let transfers = Settle.transfers(net)
        let name = house.memberName

        Section {
            let mine = net[house.me ?? ""] ?? 0
            VStack(alignment: .leading, spacing: 6) {
                Text(mine > 0 ? "Cả nhà còn nợ bạn" : mine < 0 ? "Bạn còn phải trả" : "Bạn không nợ ai")
                    .font(.system(size: 15)).foregroundStyle(.secondary)
                Text(mine == 0 ? "0" : fmt(abs(mine)))
                    .font(.system(size: 40, weight: .bold)).kerning(-1)
                    .foregroundStyle(mine < 0 ? Palette.danger : .primary)
            }
            .padding(.vertical, 6)
            Button {
                Task {
                    do { HouseInvite.present(share: try await house.share(), container: house.cloud) }
                    catch { inviteError = House.describe(error) }
                }
            } label: {
                Label(house.isOwner ? "Mời thành viên" : "Xem thành viên", systemImage: "person.badge.plus")
            }
        }

        Section {
            if transfers.isEmpty {
                Text("Mọi người đã cân bằng.").foregroundStyle(.secondary)
            }
            ForEach(transfers, id: \.self) { t in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(name(t.from)) → \(name(t.to))").fontWeight(.medium)
                        Text(fmt(t.amount)).font(.system(size: 15)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Đã trả") { paying = t }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule)
                }
            }
        } header: {
            Text("Ai chuyển cho ai")
        } footer: {
            if !transfers.isEmpty { Text("Đã gộp để số lần chuyển ít nhất. Chuyển xong bấm Đã trả.") }
        }

        Section("Khoản chung") {
            if house.spends.isEmpty {
                Button { adding = true } label: { Label("Thêm khoản chung đầu tiên", systemImage: "plus") }
            }
            ForEach(house.spends) { e in
                let c = Category.get(e.cat)
                HStack(spacing: 12) {
                    CategoryIcon(c: c, size: 20).frame(width: 36, height: 36).background(c.color, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.note.isEmpty ? c.name : e.note).lineLimit(1)
                        Text("\(name(e.payer)) ứng · chia \(Set(e.shares).count) người · \(day(e.date))")
                            .font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(fmt(e.amount)).fontWeight(.semibold)
                }
                .swipeActions { Button(role: .destructive) { Task { await house.delete(e.id) } } label: { Image(systemName: "trash.fill") } }
            }
            ForEach(house.settles) { s in
                HStack {
                    Image(systemName: "arrow.left.arrow.right.circle.fill").font(.system(size: 22)).foregroundStyle(.green)
                    Text("\(name(s.from)) đã trả \(name(s.to))").lineLimit(1)
                    Spacer()
                    Text(fmt(s.amount)).foregroundStyle(.secondary)
                }
                .swipeActions { Button(role: .destructive) { Task { await house.delete(s.id) } } label: { Image(systemName: "trash.fill") } }
            }
        }

        Section {
            ForEach(house.members) { m in
                HStack {
                    Text(m.name)
                    if m.id == house.me { Text("bạn").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary) }
                    Spacer()
                    let v = net[m.id] ?? 0
                    Text(v == 0 ? "0" : (v > 0 ? "+" : "−") + fmt(abs(v)))
                        .foregroundStyle(v < 0 ? Palette.danger : v > 0 ? Palette.goodInk : .secondary)
                }
            }
            HStack {
                TextField("Thêm người", text: $newMember)
                Button("Thêm") {
                    let n = newMember.trimmingCharacters(in: .whitespaces)
                    Task { _ = await house.addMember(n); newMember = "" }
                }
                .disabled(newMember.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Thành viên")
        } footer: {
            Text("+ là được nhận lại, − là còn phải trả. Thêm được cả người không dùng Pay.")
        }

        Section {
            Button(house.isOwner ? "Xoá nhóm" : "Rời nhóm", role: .destructive) { confirmLeave = true }
        }
    }

    private func day(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.day, .month], from: d)
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
    private var myShare: Int? {
        guard let me = house.me, shares.contains(me) else { return nil }
        return Settle.split(amount, Array(shares), seed: "")[me]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Số tiền", text: Binding(get: { amount > 0 ? fmt(amount) : amountText }, set: { amountText = $0 }))
                        .keyboardType(.numberPad)
                        .font(.system(size: 28, weight: .bold))
                        .focused($amountFocused)
                    TextField("Ghi chú, ví dụ: đi chợ", text: $note)
                        .onChange(of: note) { _, v in let g = store.guessCategory(v); if g != "khac" { cat = g } }
                    Picker("Danh mục", selection: $cat) {
                        ForEach(Category.all) { c in Text("\(c.icon) \(c.name)").tag(c.k) }
                    }
                }
                Section("Ai ứng tiền") {
                    Picker("Người trả", selection: $payer) {
                        ForEach(house.members) { m in Text(m.id == house.me ? "\(m.name) · bạn" : m.name).tag(m.id) }
                    }
                }
                Section {
                    ForEach(house.members) { m in
                        Button {
                            if shares.contains(m.id) { shares.remove(m.id) } else { shares.insert(m.id) }
                        } label: {
                            HStack {
                                Text(m.name).foregroundStyle(.primary)
                                Spacer()
                                if shares.contains(m.id), amount > 0 {
                                    Text(fmt(Settle.split(amount, Array(shares), seed: "")[m.id] ?? 0)).foregroundStyle(.secondary)
                                }
                                Image(systemName: shares.contains(m.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(shares.contains(m.id) ? Color.accentColor : .secondary)
                            }
                        }
                    }
                } header: {
                    Text("Chia cho")
                } footer: {
                    Text("Chia đều cho những người được chọn.")
                }
                if let mine = myShare, mine > 0 {
                    Section {
                        Toggle("Ghi \(fmt(mine))đ vào chi tiêu của tôi", isOn: $logMine)
                    } footer: {
                        Text("Phần của bạn vào thống kê và ngân sách cá nhân, không tính cả khoản.")
                    }
                }
            }
            .navigationTitle("Khoản chung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { save() }.disabled(amount == 0 || shares.isEmpty || payer.isEmpty)
                }
            }
            .onAppear {
                payer = house.me ?? house.members.first?.id ?? ""
                shares = Set(house.members.map(\.id))
                amountFocused = true
            }
        }
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
