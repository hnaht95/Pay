import CloudKit
import UserNotifications
import SwiftUI
import UIKit

// MARK: Dữ liệu nhóm "Nhà chung"

/// Thành viên trong nhóm. Ai cũng thêm được, kể cả người chưa cài Pay (như sổ Tab).
struct HouseMember: Identifiable, Hashable {
    let id: String
    var name: String
    /// Tài khoản nhận tiền (mã BIN ngân hàng + số tài khoản), để người khác bấm "Trả ngay"
    var bin: String? = nil
    var acct: String? = nil
    /// Apple ID (mã người dùng iCloud) đã nhận thành viên này là mình: mở máy khác tự biết "tôi là ai"
    var user: String? = nil
    /// Ảnh đại diện (JPEG nhỏ) mỗi người tự chọn; lưu trong nhóm nên cả nhà cùng thấy
    var photo: Data? = nil

    var hasBank: Bool { bin != nil && !(acct ?? "").isEmpty }
}

/// Một khoản chi chung: ai ứng tiền, chia cho những ai.
struct HouseSpend: Identifiable, Hashable {
    let id: String
    var amount: Int
    var note: String
    var payer: String
    var shares: [String]
    var date: Date
    var cat: String
}

/// Một lần chuyển trả nhau.
struct HouseSettle: Identifiable, Hashable {
    let id: String
    var from: String
    var to: String
    var amount: Int
    var date: Date
    /// ok: đã xong; wait: người trả báo đã chuyển, chờ người nhận xác nhận; no: người nhận báo chưa nhận được
    var status = "ok"
}

struct HouseTransfer: Hashable {
    let from: String
    let to: String
    let amount: Int
}

/// Cách tính lấy từ Tab (lib/settle.ts): chia đều trên số nguyên, phần dư rải 1đ mỗi người theo mã khoản chi,
/// số dư = đã ứng − phần phải chịu + đã chuyển trả − đã nhận, rồi ghép cặp khớp đúng trước, tham lam sau.
enum Settle {
    static func hash(_ s: String) -> UInt32 {
        var h: UInt32 = 0
        for c in s.utf16 { h = h &* 31 &+ UInt32(c) }
        return h
    }

    static func split(_ amount: Int, _ shareIds: [String], seed: String) -> [String: Int] {
        let ids = Array(Set(shareIds)).sorted()
        guard !ids.isEmpty, amount != 0 else { return [:] }
        let base = amount / ids.count
        let rem = amount - base * ids.count
        var out = Dictionary(uniqueKeysWithValues: ids.map { ($0, base) })
        let offset = Int(hash(seed) % UInt32(ids.count))
        for k in 0..<rem { out[ids[(offset + k) % ids.count], default: 0] += 1 }
        return out
    }

    /// > 0: cả nhóm còn nợ người này; < 0: người này còn nợ nhóm.
    static func balances(_ spends: [HouseSpend], _ settles: [HouseSettle]) -> [String: Int] {
        var net: [String: Int] = [:]
        for e in spends {
            net[e.payer, default: 0] += e.amount
            for (id, part) in split(e.amount, e.shares, seed: e.id) { net[id, default: 0] -= part }
        }
        // Lần trả đang chờ xác nhận vẫn tính (để không gợi ý trả lần nữa); bị báo chưa nhận được thì bỏ
        for s in settles where s.status != "no" {
            net[s.from, default: 0] += s.amount
            net[s.to, default: 0] -= s.amount
        }
        return net
    }

    static func transfers(_ net: [String: Int]) -> [HouseTransfer] {
        var debtors = net.filter { $0.value < 0 }.map { (id: $0.key, amt: -$0.value) }
        var creditors = net.filter { $0.value > 0 }.map { (id: $0.key, amt: $0.value) }
        let desc: ((id: String, amt: Int), (id: String, amt: Int)) -> Bool = { $0.amt != $1.amt ? $0.amt > $1.amt : $0.id < $1.id }
        debtors.sort(by: desc); creditors.sort(by: desc)
        var out: [HouseTransfer] = []
        // Lượt 1: khớp đúng số tiền
        for i in debtors.indices where debtors[i].amt > 0 {
            if let j = creditors.firstIndex(where: { $0.amt == debtors[i].amt }) {
                out.append(HouseTransfer(from: debtors[i].id, to: creditors[j].id, amount: debtors[i].amt))
                debtors[i].amt = 0; creditors[j].amt = 0
            }
        }
        // Lượt 2: tham lam
        var d = debtors.filter { $0.amt > 0 }.sorted(by: desc), c = creditors.filter { $0.amt > 0 }.sorted(by: desc)
        var i = 0, j = 0
        while i < d.count && j < c.count {
            let a = min(d[i].amt, c[j].amt)
            if a > 0 { out.append(HouseTransfer(from: d[i].id, to: c[j].id, amount: a)); d[i].amt -= a; c[j].amt -= a }
            if d[i].amt == 0 { i += 1 }
            if c[j].amt == 0 { j += 1 }
        }
        return out.sorted { $0.amount != $1.amount ? $0.amount > $1.amount : $0.from < $1.from }
    }
}

// MARK: Lưu trên iCloud (CloudKit, chia sẻ cả vùng dữ liệu cho người được mời)

/// Một nhóm chung: một vùng dữ liệu (zone) trong iCloud của người tạo, chia sẻ bằng CKShare cho cả vùng.
struct HouseGroup: Identifiable {
    var id: String { zone.zoneName }
    let zone: CKRecordZone.ID
    let scope: CKDatabase.Scope
    var isOwner: Bool
    var name = ""
    var members: [HouseMember] = []
    var spends: [HouseSpend] = []
    var settles: [HouseSettle] = []
    var me: String?
    /// Ảnh đại diện của nhóm do người dùng chọn: màu (chỉ số trong CategoryTone) hoặc ảnh. Chưa chọn thì màu theo mã nhóm
    var tone: Int?
    var photo: Data?
    var records: [CKRecord.ID: CKRecord] = [:]

    /// > 0: nhóm còn nợ mình; < 0: mình còn phải trả
    var myNet: Int { me.map { Settle.balances(spends, settles)[$0] ?? 0 } ?? 0 }
    /// Lần trả cần mình để ý (xác nhận, chờ, bị báo chưa nhận)
    var pending: [HouseSettle] { settles.filter { ($0.to == me && $0.status == "wait") || ($0.from == me && $0.status != "ok") } }
    var lastActivity: Date { max(spends.first?.date ?? .distantPast, settles.first?.date ?? .distantPast) }
}

/// Người tạo nhóm có vùng dữ liệu trong iCloud của mình; người được mời thấy vùng đó trong cơ sở dữ liệu "được chia sẻ".
/// Ai trong nhóm cũng thêm / sửa / xoá được. Có thể ở nhiều nhóm cùng lúc (nhà, phòng trọ, chuyến đi…).
@MainActor
final class House: ObservableObject {
    static let shared = House()

    enum Phase: Equatable { case loading, ready, noAccount, failed(String) }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var groups: [HouseGroup] = [] { didSet { scheduleSave() } }
    /// Nhóm đang mở; nil = đang xem danh sách nhóm
    @Published var currentID: String?
    @Published private(set) var busy = false
    /// Nhóm đã lưu trữ (xong việc, ẩn khỏi danh sách chính) — chỉ trên máy này
    @Published private(set) var archived: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "house.archived") ?? [])

    private let container = CKContainer(identifier: "iCloud.com.hnaht95.sochipay")
    private static let zonePrefix = "nha-"

    /// Bản Debug chạy với "-houseDemo YES": dữ liệu mẫu, không cần iCloud, sửa gì cũng chỉ trên máy (để xem giao diện trên máy ảo)
    private var demo = false

    /// Số lần máy này tự đổi `groups` (lưu, xoá, tạo, rời nhóm, chọn "tôi là ai"). Sổ hiện ngay từ bản lưu nên người dùng bấm được
    /// trong lúc load() còn chạy; load() so số này trước và sau khi tải để không lấy bản đã cũ đè lên thay đổi vừa lưu
    private var edits = 0
    /// Đang tạo nhóm / đang lưu khoản chung: bấm nút lần nữa khi mạng chậm thì bỏ qua, không tạo hai lần
    private var creatingGroup = false, addingSpend = false

    private init() {
        #if DEBUG
        demo = UserDefaults.standard.bool(forKey: "houseDemo")
        #endif
        if !demo { loadCache() }
    }

    // MARK: Bản lưu trên máy (mở màn Nhóm chung là thấy ngay, iCloud tải lại phía sau)

    private static let cacheURL = URL.applicationSupportDirectory.appending(path: "house-cache.bin")

    /// Đọc bản lưu của lần tải trước. Có nhóm thì coi như sẵn sàng; `load()` vẫn tải lại đầy đủ từ iCloud rồi thay vào.
    private func loadCache() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let list = try? NSKeyedUnarchiver.unarchivedObject(
                ofClasses: [NSArray.self, NSDictionary.self, NSString.self, NSNumber.self, CKRecordZone.ID.self, CKRecord.self],
                from: data) as? [[String: Any]] else { return }
        var out: [HouseGroup] = []
        for d in list {
            guard let zone = d["zone"] as? CKRecordZone.ID, let records = d["records"] as? [CKRecord] else { continue }
            let shared = (d["shared"] as? Bool) ?? false
            var g = HouseGroup(zone: zone, scope: shared ? .shared : .private, isOwner: (d["owner"] as? Bool) ?? !shared)
            g.records = Dictionary(records.map { ($0.recordID, $0) }, uniquingKeysWith: { a, _ in a })
            Self.rebuild(&g)
            g.me = UserDefaults.standard.string(forKey: "house.me.\(g.id)").flatMap { id in g.members.contains { $0.id == id } ? id : nil }
            out.append(g)
        }
        guard !out.isEmpty else { return }
        groups = out.sorted { $0.lastActivity > $1.lastActivity }
        phase = .ready
    }

    private var saving: Task<Void, Never>?

    /// Nhóm đổi (tải xong, thêm / sửa / xoá): lưu lại sau một nhịp, gộp các lần đổi liền nhau
    private func scheduleSave() {
        saving?.cancel()
        saving = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            if !Task.isCancelled { self?.saveCache() }
        }
    }

    /// Ghi bản lưu ngay, không chờ nhịp gộp: việc chạy nền (đẩy im lặng, nút trên thông báo) xong là iOS có thể treo app luôn
    private func flushCache() { saving?.cancel(); saveCache() }

    private func saveCache() {
        guard !demo else { return }
        let list: [[String: Any]] = groups.map {
            ["zone": $0.zone, "shared": $0.scope == .shared, "owner": $0.isOwner, "records": Array($0.records.values)]
        }
        let url = Self.cacheURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: list, requiringSecureCoding: true) {
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    /// Không còn đăng nhập iCloud: bỏ bản lưu để không hiện sổ của tài khoản cũ
    private func dropCache() {
        try? FileManager.default.removeItem(at: Self.cacheURL)
        groups = []; currentID = nil
        subscribed = []   // tài khoản đăng nhập sau phải đăng ký nhận đẩy lại
    }

    // MARK: Nhóm đang mở

    private var cur: Int? { currentID.flatMap { id in groups.firstIndex { $0.id == id } } }
    var current: HouseGroup? { cur.map { groups[$0] } }
    var name: String { current?.name ?? "" }
    var members: [HouseMember] { current?.members ?? [] }
    var spends: [HouseSpend] { current?.spends ?? [] }
    var settles: [HouseSettle] { current?.settles ?? [] }
    var isOwner: Bool { current?.isOwner ?? false }
    /// Thành viên là chính mình trong nhóm đang mở (mỗi máy tự chọn, nhớ theo nhóm)
    var me: String? {
        get { current?.me }
        set {
            guard let i = cur else { return }
            edits += 1
            groups[i].me = newValue
            UserDefaults.standard.set(newValue, forKey: "house.me.\(groups[i].id)")
        }
    }
    private var zone: CKRecordZone.ID? { current?.zone }
    private var db: CKDatabase { container.database(with: current?.scope ?? .private) }

    func open(_ id: String?) { currentID = id }

    func setArchived(_ id: String, _ on: Bool) {
        if on { archived.insert(id) } else { archived.remove(id) }
        UserDefaults.standard.set(Array(archived), forKey: "house.archived")
    }

    /// Tổng việc cần xác nhận ở mọi nhóm (số trên nút nhóm ở màn hình chính)
    var pendingTotal: Int { groups.reduce(0) { $0 + $1.pending.count } }

    private func loadDemo() {
        let now = Date()
        func ago(_ d: Double) -> Date { now.addingTimeInterval(-d * 86_400) }
        var home = HouseGroup(zone: CKRecordZone.ID(zoneName: "nha-demo1"), scope: .private, isOwner: true, name: L("Nhà mình"))
        home.members = [HouseMember(id: "a", name: "Thành"), HouseMember(id: "b", name: "Lan", bin: "970416", acct: "123456789"),
                        HouseMember(id: "c", name: "Minh"), HouseMember(id: "d", name: "Hà")]
        home.spends = [
            HouseSpend(id: "e1", amount: 420_000, note: L("Đi chợ cuối tuần"), payer: "a", shares: ["a", "b", "c", "d"], date: ago(0.2), cat: "an"),
            HouseSpend(id: "e2", amount: 860_000, note: L("Tiền điện tháng 9"), payer: "b", shares: ["a", "b", "c", "d"], date: ago(2), cat: "hd"),
            HouseSpend(id: "e3", amount: 300_000, note: L("Lẩu tối thứ 6"), payer: "c", shares: ["a", "c", "d"], date: ago(4), cat: "an"),
            HouseSpend(id: "e4", amount: 250_000, note: "Internet", payer: "a", shares: ["a", "b", "c", "d"], date: ago(8), cat: "hd"),
        ]
        home.settles = [HouseSettle(id: "s1", from: "d", to: "a", amount: 100_000, date: ago(1)),
                        HouseSettle(id: "s2", from: "a", to: "c", amount: 50_000, date: ago(0.1), status: "wait")]
        home.me = "c"
        var trip = HouseGroup(zone: CKRecordZone.ID(zoneName: "nha-demo2"), scope: .shared, isOwner: false, name: L("Đi Đà Lạt"))
        trip.members = [HouseMember(id: "c", name: "Minh"), HouseMember(id: "x", name: "Khoa"), HouseMember(id: "y", name: "Vy")]
        trip.spends = [HouseSpend(id: "t1", amount: 1_800_000, note: L("Homestay 2 đêm"), payer: "c", shares: ["c", "x", "y"], date: ago(12), cat: "di"),
                       HouseSpend(id: "t2", amount: 450_000, note: L("Lẩu gà lá é"), payer: "x", shares: ["c", "x", "y"], date: ago(11), cat: "an")]
        trip.me = "c"
        groups = [home, trip]
        phase = .ready
    }

    /// Màu riêng cho mỗi người (theo mã), dùng cho ảnh đại diện
    func tone(_ id: String) -> Int { Int(Settle.hash(id) % 16) }   // 16 màu nhạt + đậm: thêm bộ màu mới không làm đổi màu ảnh đại diện đã quen

    var memberName: (String) -> String {
        let m = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.name) })
        return { m[$0] ?? L("Người đã xoá") }
    }

    // MARK: Tải

    /// Tải mọi nhóm: vùng mình tạo và vùng người khác chia sẻ cho mình.
    /// prompt = false (tải trước lúc mở app): không hỏi quyền thông báo, việc đó để tới khi người dùng mở màn Nhóm chung
    func load(prompt: Bool = true) async {
        if demo { if groups.isEmpty { loadDemo() }; return }
        if phase != .ready { phase = .loading }
        do {
            switch try await container.accountStatus() {
            case .available: break
            case .noAccount: dropCache(); phase = .noAccount; return
            default:
                // Vẫn đăng nhập nhưng iCloud tạm chưa dùng được (đòi nhập lại mật khẩu, bị giới hạn…): vẫn là tài khoản đó nên
                // giữ bản lưu. Đang có sổ thì xem tiếp, chưa có gì thì báo lỗi kèm nút Thử lại
                if phase != .ready { phase = .failed(L("iCloud tạm thời chưa sẵn sàng. Kiểm tra iCloud trong Cài đặt rồi thử lại.")) }
                return
            }
            // Thay đổi vừa lưu xong trong lúc đang tải (xác nhận, thêm, xoá, tạo, rời nhóm…) có thể chưa nằm trong bản vừa tải,
            // thay vào là mất thay đổi đó trên máy. Thấy `edits` đổi thì bỏ bản này và tải lại, tối đa 3 lượt
            var loaded: [(String, HouseGroup?, Error?)] = []
            var stamp = edits, tries = 0
            repeat {
                stamp = edits; tries += 1
                // Hai cơ sở dữ liệu (của mình, được chia sẻ) hỏi cùng lúc, rồi các nhóm cũng tải cùng lúc thay vì lần lượt
                async let mine = container.privateCloudDatabase.allRecordZones()
                async let theirs = container.sharedCloudDatabase.allRecordZones()
                var found: [(CKRecordZone.ID, CKDatabase.Scope)] = []
                for (zones, scope) in [(try await mine, CKDatabase.Scope.private), (try await theirs, .shared)] {
                    for z in zones where z.zoneID.zoneName.hasPrefix(Self.zonePrefix) { found.append((z.zoneID, scope)) }
                }
                let known = groups
                loaded = await withTaskGroup(of: (String, HouseGroup?, Error?).self) { tasks in
                    for (zid, scope) in found {
                        let g = known.first { $0.id == zid.zoneName } ?? HouseGroup(zone: zid, scope: scope, isOwner: scope == .private)
                        tasks.addTask { @MainActor in
                            do { return (g.id, try await self.fetch(g), nil) } catch { return (g.id, nil, error) }
                        }
                    }
                    var out: [(String, HouseGroup?, Error?)] = []
                    for await one in tasks { out.append(one) }
                    return out
                }
            } while stamp != edits && tries < 3
            // Hết lượt mà vẫn có thay đổi mới: giữ `groups` đang có (nó chứa thay đổi của người dùng), lần tải sau sẽ đồng bộ
            guard stamp == edits else { phase = .ready; return }
            var next: [HouseGroup] = [], failure: Error?, missing = false
            for (id, fresh, why) in loaded {
                if let fresh { next.append(fresh) }
                // Một nhóm đọc lỗi: giữ bản đang có trên máy. Máy chưa có bản nào thì bỏ qua nhóm đó, không đưa nhóm rỗng vào
                // danh sách và bản lưu ("0 người", người dùng thêm lại chính mình thành trùng thành viên)
                else if let old = groups.first(where: { $0.id == id }) { next.append(old) }
                else { missing = true }
                if failure == nil { failure = why }
            }
            if next.isEmpty, let failure {
                // Trên iCloud có nhóm mà không đọc được nhóm nào, máy cũng chưa có sổ: màn báo lỗi có nút Thử lại,
                // không hiện form "Tạo nhóm" như thể chưa có nhóm nào
                phase = groups.isEmpty ? .failed(Self.describe(failure)) : .ready
                return
            }
            groups = next.sorted { $0.lastActivity > $1.lastActivity }
            if let id = currentID, !groups.contains(where: { $0.id == id }) { currentID = nil }
            phase = .ready
            for i in groups.indices { notifyChanges(i) }
            // Nhóm chưa từng tải về máy mà lần này đọc lỗi thì tạm vắng trong danh sách: người dùng đang xem thì báo cho biết
            if missing, prompt, !Task.isCancelled, let failure { Store.shared.showError(Self.describe(failure)) }
            if !groups.isEmpty, prompt { await enableNotifications() }
        } catch let e as CKError where e.code == .notAuthenticated {
            dropCache(); phase = .noAccount
        } catch {
            phase = phase == .ready ? .ready : .failed(Self.describe(error))
        }
    }

    /// Đọc toàn bộ một nhóm và nhận ra "tôi là ai" trong nhóm đó.
    private func fetch(_ group: HouseGroup) async throws -> HouseGroup {
        var g = group
        let db = container.database(with: g.scope)
        var all: [CKRecord.ID: CKRecord] = [:]
        var token: CKServerChangeToken?
        var more = true
        while more {
            let r = try await db.recordZoneChanges(inZoneWith: g.zone, since: token)
            for (id, res) in r.modificationResultsByID { if case .success(let m) = res { all[id] = m.record } }
            token = r.changeToken
            more = r.moreComing
        }
        g.records = all
        Self.rebuild(&g)
        g.me = UserDefaults.standard.string(forKey: "house.me.\(g.id)").flatMap { id in g.members.contains { $0.id == id } ? id : nil }
        // Máy mới / cài lại: nhận ra mình qua Apple ID đã gắn với thành viên
        if g.me == nil, let u = try? await container.userRecordID().recordName {
            g.me = g.members.first { $0.user == u }?.id
        }
        return g
    }

    private static func rebuild(_ g: inout HouseGroup) {
        var ms: [HouseMember] = [], sp: [HouseSpend] = [], st: [HouseSettle] = []
        for r in g.records.values {
            let id = r.recordID.recordName
            switch r.recordType {
            case "Member":
                ms.append(HouseMember(id: id, name: r["name"] as? String ?? "", bin: r["bin"] as? String,
                                      acct: r["acct"] as? String, user: r["user"] as? String,
                                      photo: (r["photo"] as? CKAsset)?.fileURL.flatMap { try? Data(contentsOf: $0) }))
            case "Spend":
                sp.append(HouseSpend(id: id, amount: (r["amount"] as? Int64).map(Int.init) ?? 0, note: r["note"] as? String ?? "",
                                     payer: r["payer"] as? String ?? "", shares: r["shares"] as? [String] ?? [],
                                     date: r["date"] as? Date ?? r.creationDate ?? Date(), cat: r["cat"] as? String ?? "khac"))
            case "Settle":
                st.append(HouseSettle(id: id, from: r["from"] as? String ?? "", to: r["to"] as? String ?? "",
                                      amount: (r["amount"] as? Int64).map(Int.init) ?? 0, date: r["date"] as? Date ?? Date(),
                                      status: r["status"] as? String ?? "ok"))
            case "Info":
                g.name = r["name"] as? String ?? g.name
                g.tone = (r["tone"] as? Int64).map(Int.init)
                g.photo = (r["photo"] as? CKAsset)?.fileURL.flatMap { try? Data(contentsOf: $0) }
            default: break
            }
        }
        g.members = ms.sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
        g.spends = sp.sorted { $0.date > $1.date }
        g.settles = st.sorted { $0.date > $1.date }
    }

    // MARK: Tạo / tham gia / rời nhóm

    /// Tạo nhóm mới với chính mình là thành viên đầu tiên, rồi mở nhóm đó.
    func create(name groupName: String, me myName: String) async {
        if demo {
            var g = HouseGroup(zone: CKRecordZone.ID(zoneName: "nha-" + UUID().uuidString.prefix(6)), scope: .private, isOwner: true, name: groupName)
            g.members = [HouseMember(id: "me", name: myName)]; g.me = "me"
            groups.insert(g, at: 0); currentID = g.id
            return
        }
        guard !creatingGroup else { return }
        creatingGroup = true; defer { creatingGroup = false }
        busy = true; defer { busy = false }
        do {
            let z = CKRecordZone(zoneName: Self.zonePrefix + UUID().uuidString.prefix(8).lowercased())
            _ = try await container.privateCloudDatabase.modifyRecordZones(saving: [z], deleting: [])
            edits += 1
            groups.insert(HouseGroup(zone: z.zoneID, scope: .private, isOwner: true, name: groupName), at: 0)
            currentID = z.zoneID.zoneName
            let info = CKRecord(recordType: "Info", recordID: CKRecord.ID(recordName: "info", zoneID: z.zoneID))
            info["name"] = groupName
            let m = CKRecord(recordType: "Member", recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: z.zoneID))
            m["name"] = myName
            if let u = try? await container.userRecordID().recordName { m["user"] = u }
            // Nhớ "tôi là ai" trước khi lưu: lần tải lại chạy song song cũng nhận ra ngay, khỏi hỏi lại
            UserDefaults.standard.set(m.recordID.recordName, forKey: "house.me.\(z.zoneID.zoneName)")
            try await save([info, m])
            // Gán theo mã nhóm vừa tạo, không theo nhóm đang mở: trong lúc chờ lưu người dùng có thể đã mở nhóm khác
            if let i = groups.firstIndex(where: { $0.id == z.zoneID.zoneName }) { edits += 1; groups[i].me = m.recordID.recordName }
            phase = .ready
            await enableNotifications()
        } catch {
            fail(error)
        }
    }

    /// Người được mời bấm vào link: nhận lời mời rồi mở đúng nhóm đó.
    func accept(_ metadata: CKShare.Metadata) async {
        do {
            _ = try await container.accept(metadata)
            await load()
            currentID = metadata.share.recordID.zoneID.zoneName
            QuickAction.shared.openHouse = true
        } catch {
            // Lời mời được bấm từ ngoài app, màn Nhóm chung thường chưa mở: báo bằng thanh báo trên màn đang hiện.
            // Chỉ đặt phase = .failed thì không ai thấy, lần load() kế tiếp lại xoá mất
            Store.shared.showError(L("Không mở được lời mời") + ". " + Self.describe(error))
        }
    }

    /// Chủ nhóm: xoá cả nhóm. Người được mời: rời nhóm (dữ liệu vẫn còn ở chủ nhóm).
    func leave() async {
        guard let g = current else { return }
        if demo { groups.removeAll { $0.id == g.id }; currentID = nil; return }
        busy = true; defer { busy = false }
        do {
            _ = try await container.database(with: g.scope).modifyRecordZones(saving: [], deleting: [g.zone])
            edits += 1
            UserDefaults.standard.removeObject(forKey: "house.me.\(g.id)")
            groups.removeAll { $0.id == g.id }
            currentID = nil
        } catch {
            fail(error)
        }
    }

    /// Lời mời của nhóm đang mở (tạo nếu chưa có), để mở bảng chia sẻ của iOS.
    func share() async throws -> CKShare {
        guard let zone else { throw CKError(.zoneNotFound) }
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone)
        if let s = try? await db.record(for: shareID) as? CKShare { return s }
        let s = CKShare(recordZoneID: zone)
        s[CKShare.SystemFieldKey.title] = name.isEmpty ? "Nhóm chung" : name
        s.publicPermission = .none
        try await save([s])
        return s
    }

    var cloud: CKContainer { container }

    // MARK: Sửa dữ liệu (nhóm đang mở)

    func addMember(_ n: String) async -> String? {
        if demo, let i = cur { let id = UUID().uuidString; groups[i].members.append(HouseMember(id: id, name: n)); return id }
        guard let zone else { return nil }
        let r = CKRecord(recordType: "Member", recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zone))
        r["name"] = n
        return await run([r]) ? r.recordID.recordName : nil
    }

    /// Sửa tên và tài khoản nhận tiền của một thành viên.
    /// photo: nil = giữ nguyên, Data rỗng = bỏ ảnh
    func updateMember(_ id: String, name n: String, bin: String?, acct: String?, photo: Data? = nil) async {
        if demo, let g = cur {
            if let i = groups[g].members.firstIndex(where: { $0.id == id }) {
                groups[g].members[i].name = n; groups[g].members[i].bin = bin; groups[g].members[i].acct = acct
                if let photo { groups[g].members[i].photo = photo.isEmpty ? nil : photo }
            }
            return
        }
        guard let r = record(id) else { stale(); return }
        r["name"] = n; r["bin"] = bin; r["acct"] = acct
        if let photo {
            if photo.isEmpty { r["photo"] = nil } else {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("avatar-\(id).jpg")
                try? photo.write(to: url)
                r["photo"] = CKAsset(fileURL: url)
            }
        }
        _ = await run([r])
    }

    /// Đổi tên và ảnh đại diện của một nhóm (nhóm bất kỳ, không cần đang mở). Cả nhóm cùng thấy.
    /// tone: nil = màu mặc định theo mã nhóm. photo: nil = giữ nguyên, Data rỗng = bỏ ảnh
    func updateGroup(_ gid: String, name n: String, tone: Int?, photo: Data? = nil) async {
        guard let i = groups.firstIndex(where: { $0.id == gid }) else { return }
        if demo {
            groups[i].name = n; groups[i].tone = tone
            if let photo { groups[i].photo = photo.isEmpty ? nil : photo }
            return
        }
        let g = groups[i]
        let rid = CKRecord.ID(recordName: "info", zoneID: g.zone)
        // Sửa trên bản sao (xem record(_:in:)): lưu hỏng thì bản đang dùng không dính thay đổi chưa lên iCloud
        let r = (g.records[rid]?.copy() as? CKRecord) ?? CKRecord(recordType: "Info", recordID: rid)
        r["name"] = n
        r["tone"] = tone.map { Int64($0) }
        if let photo {
            if photo.isEmpty { r["photo"] = nil } else {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("group-\(gid).jpg")
                try? photo.write(to: url)
                r["photo"] = CKAsset(fileURL: url)
            }
        }
        busy = true; defer { busy = false }
        do {
            let res = try await container.database(with: g.scope).modifyRecords(saving: [r], deleting: [], savePolicy: .changedKeys)
            edits += 1
            guard let j = groups.firstIndex(where: { $0.id == gid }) else { return }
            for (id, one) in res.saveResults { groups[j].records[id] = try one.get() }
            Self.rebuild(&groups[j])
        } catch { fail(error) }
    }

    /// "Tôi là người này": nhớ trên máy và gắn Apple ID vào thành viên, lần sau máy khác tự nhận ra.
    func claim(_ id: String) async {
        // Nhóm đang mở có thể vừa đổi trong lúc chờ (thêm mình xong mới nhận): không lấy mã thành viên của nhóm khác làm "tôi"
        guard members.contains(where: { $0.id == id }) else { return }
        me = id
        if demo { return }
        guard let r = record(id), let u = try? await container.userRecordID().recordName, r["user"] as? String != u else { return }
        r["user"] = u
        _ = await run([r])
    }

    // MARK: Trả ngay qua app ngân hàng

    /// Lần trả đang chờ: đã mở app ngân hàng, quay lại Pay thì hỏi "đã chuyển xong chưa"
    @Published var pendingPay: HouseTransfer?

    /// Mở app ngân hàng đã chọn trong Cài đặt với sẵn người nhận, số tiền, nội dung.
    func payNow(_ t: HouseTransfer, app: BankApp) async {
        guard let to = members.first(where: { $0.id == t.to }), let bin = to.bin, let acct = to.acct else { return }
        let qr = VietQR(raw: "", bin: bin, acct: acct, amount: t.amount, name: strip(to.name).uppercased(),
                        purpose: "Pay " + strip(name.isEmpty ? "Nhom chung" : name))
        // App chỉ mở được (không điền sẵn): chép số tài khoản để dán
        if !app.fill { UIPasteboard.general.string = acct }
        pendingPay = t
        await BankLauncher.open(app, qr: qr, amount: t.amount)
    }

    @discardableResult
    /// Câu nói nhắc tới một nhóm ("300k đi chợ nhà mình", "nhóm Đà Lạt 500k ăn tối", "200k lẩu vào nhà chung"):
    /// nhóm đó và câu đã bỏ phần nhắc nhóm. Chỉ nhóm đã chọn "tôi là ai" (mới biết ai trả). Nói "nhà chung" / "nhóm chung"
    /// mà chỉ có một nhóm thì là nhóm đó.
    func groupMentioned(in text: String) -> (group: HouseGroup, rest: String)? {
        let usable = groups.filter { $0.me != nil && !archived.contains($0.id) && !$0.name.isEmpty }
        guard !usable.isEmpty else { return nil }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        func wholeWord(_ r: Range<String.Index>, in t: String) -> Bool {
            (r.lowerBound == t.startIndex || t[t.index(before: r.lowerBound)].isWhitespace)
                && (r.upperBound == t.endIndex || !t[r.upperBound].isLetter)
        }
        var hit: (HouseGroup, Range<String.Index>)?
        for g in usable.sorted(by: { $0.name.count > $1.name.count }) {
            if let r = text.range(of: g.name, options: opts), wholeWord(r, in: text) { hit = (g, r); break }
        }
        if hit == nil, usable.count == 1 {
            for phrase in ["nhà chung", "nhóm chung", "group"] {
                if let r = text.range(of: phrase, options: opts), wholeWord(r, in: text) { hit = (usable[0], r); break }
            }
        }
        guard let (g, r) = hit else { return nil }
        // Bỏ tên nhóm và các chữ đi kèm ngay trước nó ("vào nhóm", "cho nhà", "nhóm"…)
        var before = text[..<r.lowerBound].split(whereSeparator: \.isWhitespace).map(String.init)
        let fillers: Set<String> = ["vao", "nhom", "cho", "o", "trong", "into", "to", "for", "group"]
        while let w = before.last, fillers.contains(strip(w)) { before.removeLast() }
        let rest = (before + [String(text[r.upperBound...])]).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return (g, rest)
    }

    /// Ghi nhanh một khoản chung vào nhóm `g` (từ giọng nói): mình trả, chia đều cả nhóm. Trả về phần của mình nếu lưu được.
    func quickSpend(in g: HouseGroup, amount: Int, note: String, cat: String) async -> Int? {
        guard let me = g.me else { return nil }
        let shares = g.members.map(\.id)
        let back = currentID
        currentID = g.id
        defer { currentID = back }
        guard await addSpend(amount: amount, note: note, payer: me, shares: shares, cat: cat) else { return nil }
        return Settle.split(amount, shares, seed: "")[me]
    }

    /// Sửa một khoản chung (số tiền, ghi chú, ai trả, chia cho ai, danh mục); giữ nguyên ngày.
    func updateSpend(_ e: HouseSpend) async -> Bool {
        if demo, let i = cur, let j = groups[i].spends.firstIndex(where: { $0.id == e.id }) { groups[i].spends[j] = e; return true }
        guard let r = record(e.id) else { stale(); return false }
        guard knows(e.shares + [e.payer]) else { stale(); return false }
        r["amount"] = Int64(e.amount); r["note"] = e.note; r["payer"] = e.payer; r["shares"] = e.shares; r["cat"] = e.cat
        return await run([r])
    }

    func addSpend(amount: Int, note: String, payer: String, shares: [String], cat: String) async -> Bool {
        if demo, let i = cur {
            groups[i].spends.insert(HouseSpend(id: UUID().uuidString, amount: amount, note: note, payer: payer, shares: shares, date: Date(), cat: cat), at: 0)
            return true
        }
        guard let zone, !addingSpend else { return false }
        guard knows(shares + [payer]) else { stale(); return false }
        addingSpend = true; defer { addingSpend = false }
        let r = CKRecord(recordType: "Spend", recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zone))
        r["amount"] = Int64(amount); r["note"] = note; r["payer"] = payer; r["shares"] = shares; r["date"] = Date(); r["cat"] = cat
        return await run([r])
    }

    /// Các mã này có thuộc nhóm đang mở không (thành viên, kể cả người đã xoá nhưng còn trong sổ). Nhóm đang mở có thể bị đổi
    /// (chạm thông báo của nhóm khác) khi bảng nhập của nhóm cũ còn trên màn hình: không ghi mã của nhóm này vào nhóm kia
    private func knows(_ ids: [String]) -> Bool {
        guard let g = current else { return false }
        var all = Set(g.members.map(\.id))
        for e in g.spends { all.insert(e.payer); all.formUnion(e.shares) }
        for s in g.settles { all.insert(s.from); all.insert(s.to) }
        return ids.allSatisfy { all.contains($0) }
    }

    /// Thao tác bị từ chối vì không còn khớp với nhóm đang mở: báo để người dùng mở lại rồi nhập lại, thay vì bấm Lưu mà không thấy gì
    private func stale() { Store.shared.showError(L("Nhóm đang mở vừa đổi nên chưa lưu được. Mở lại rồi nhập lại.")) }

    /// Ghi một lần trả. Người trả báo thì chờ người nhận xác nhận; người nhận tự bấm "Đã nhận" thì xong luôn.
    func settle(_ t: HouseTransfer) async {
        let status = t.from == me && t.to != me ? "wait" : "ok"
        if demo, let i = cur {
            groups[i].settles.insert(HouseSettle(id: UUID().uuidString, from: t.from, to: t.to, amount: t.amount, date: Date(), status: status), at: 0)
            return
        }
        guard let zone else { return }
        guard knows([t.from, t.to]) else { stale(); return }
        let r = CKRecord(recordType: "Settle", recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zone))
        r["from"] = t.from; r["to"] = t.to; r["amount"] = Int64(t.amount); r["date"] = Date(); r["status"] = status
        guard await run([r]), status == "wait", let i = groups.firstIndex(where: { $0.id == zone.zoneName }) else { return }
        // Ghi nhớ đã thấy lần trả này ở trạng thái "chờ" (iCloud không đẩy về chính máy vừa ghi, nên không có load() nào làm việc đó):
        // thiếu thẻ này thì lúc người nhận xác nhận, notifyChanges không báo "đã nhận" cho người trả
        notifyChanges(i)
    }

    /// Người nhận trả lời: đã nhận (xong) hoặc chưa nhận được (báo lại người trả).
    func respond(_ id: String, received: Bool) async {
        let status = received ? "ok" : "no"
        if demo, let g = cur { if let i = groups[g].settles.firstIndex(where: { $0.id == id }) { groups[g].settles[i].status = status }; return }
        guard let r = record(id) else { return }
        r["status"] = status
        _ = await run([r])
    }

    /// Bấm nút trên thông báo: app có thể vừa được mở lại ở nền với bản lưu cũ hơn thông báo, nên thiếu nhóm hoặc thiếu
    /// lần trả này thì tải lại trước khi trả lời. Ghi thẳng vào nhóm của thông báo, không đổi nhóm đang mở:
    /// bảng nhập của nhóm đang mở có thể còn trên màn hình và sẽ lưu nhầm sang nhóm kia
    func respondFromNotification(_ id: String, group: String, received: Bool) async {
        if record(id, in: group) == nil { await load(prompt: false) }
        if let r = record(id, in: group) {
            r["status"] = received ? "ok" : "no"
            _ = await run([r])
        }
        flushCache()
    }

    // MARK: Thông báo giữa các máy

    /// Cơ sở dữ liệu đã đăng ký nhận đẩy trong lần chạy app này. Chỉ nhớ trong bộ nhớ: đăng ký nằm trên máy chủ theo tài khoản
    /// và môi trường iCloud, cờ lưu trên máy sẽ sai khi đổi Apple ID hoặc cài bản TestFlight đè lên bản chạy từ Xcode
    /// (máy đó không bao giờ nhận đẩy nữa). Lưu lại một đăng ký cùng mã thì không sao
    private var subscribed: Set<String> = []

    /// Nhận thông báo đẩy im lặng mỗi khi dữ liệu nhóm đổi (máy khác ghi), để tải lại và báo cho người liên quan.
    private func subscribe() async {
        for scope in [CKDatabase.Scope.private, .shared] {
            let id = "house-\(scope == .private ? "private" : "shared")"
            guard !subscribed.contains(id) else { continue }
            let sub = CKDatabaseSubscription(subscriptionID: id)
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            sub.notificationInfo = info
            // Lệnh không ném lỗi của riêng từng đăng ký: phải xem kết quả của chính nó mới coi là xong, không thì lần sau thử lại
            if let r = try? await container.database(with: scope).modifySubscriptions(saving: [sub], deleting: []),
               let one = r.saveResults[id], case .success = one {
                subscribed.insert(id)
            }
        }
    }

    /// Máy khác vừa đổi dữ liệu (app đang chạy nền): tải lại rồi báo. Không hỏi quyền hay đăng ký lại ở nền.
    /// Ghi bản lưu luôn: thông báo vừa hiện có nút "Đã nhận", lần mở app sau (để trả lời) phải thấy đúng lần trả đó
    func backgroundRefresh() async { await load(prompt: false); flushCache() }

    /// Báo những lần trả liên quan tới mình mà máy này chưa báo: có người báo đã chuyển cho mình,
    /// người nhận xác nhận hoặc báo chưa nhận được tiền mình chuyển. Lần đầu mở nhóm thì chỉ ghi nhớ, không báo dồn.
    private func notifyChanges(_ gi: Int) {
        let g = groups[gi]
        guard let me = g.me else { return }
        let key = "house.seen.\(g.id)"
        let first = UserDefaults.standard.object(forKey: key) == nil
        var seen = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        let names = Dictionary(uniqueKeysWithValues: g.members.map { ($0.id, $0.name) })
        let name = { (id: String) in names[id] ?? L("Người đã xoá") }
        for s in g.settles where s.to == me || s.from == me {
            let tag = "\(s.id).\(s.status)"
            guard seen.insert(tag).inserted, !first else { continue }
            let c = UNMutableNotificationContent()
            c.sound = .default
            c.subtitle = g.name
            c.userInfo = ["settle": s.id, "group": g.id]
            if s.to == me && s.from != me && s.status == "wait" {
                c.title = L("%@ báo đã chuyển %@đ", name(s.from), fmt(s.amount))
                c.body = L("Kiểm tra tài khoản rồi xác nhận đã nhận.")
                c.categoryIdentifier = "HOUSE_CONFIRM"
            } else if s.from == me && s.to != me && s.status == "no" {
                c.title = L("%@ chưa nhận được %@đ", name(s.to), fmt(s.amount))
                c.body = L("Kiểm tra lại giao dịch trong app ngân hàng hoặc chuyển lại.")
            } else if s.from == me && s.to != me && s.status == "ok" && seen.contains("\(s.id).wait") {
                c.title = L("%@ đã nhận %@đ", name(s.to), fmt(s.amount))
                c.body = L("Khoản trả đã được xác nhận.")
            } else { continue }
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: tag, content: c, trigger: nil))
        }
        UserDefaults.standard.set(Array(seen), forKey: key)
    }

    /// Xin quyền thông báo và đăng ký nhận đẩy (một lần, khi đã ở trong nhóm).
    private func enableNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        UIApplication.shared.registerForRemoteNotifications()
        await subscribe()
    }

    func delete(_ id: String) async {
        if demo, let i = cur { groups[i].spends.removeAll { $0.id == id }; groups[i].settles.removeAll { $0.id == id }; return }
        guard let g = current else { return }
        let gid = g.id, rid = CKRecord.ID(recordName: id, zoneID: g.zone)
        busy = true; defer { busy = false }
        do {
            _ = try await container.database(with: g.scope).modifyRecords(saving: [], deleting: [rid])
            edits += 1
            // Trong lúc chờ, load() có thể đã xếp lại hoặc thay mảng groups, người dùng có thể đã sang nhóm khác:
            // tìm lại nhóm theo mã, không dùng chỉ số lấy từ trước
            guard let i = groups.firstIndex(where: { $0.id == gid }) else { return }
            groups[i].records[rid] = nil
            Self.rebuild(&groups[i])
        } catch { fail(error) }
    }

    /// Bản ghi của một thành viên / lần trả để sửa rồi lưu (gid = nil: trong nhóm đang mở). Trả về bản sao: lưu hỏng thì bỏ bản sao,
    /// bản đang dùng trong `groups` (và bản lưu trên máy) không dính thay đổi chưa lên iCloud
    private func record(_ id: String, in gid: String? = nil) -> CKRecord? {
        guard let g = gid == nil ? current : groups.first(where: { $0.id == gid }) else { return nil }
        return g.records[CKRecord.ID(recordName: id, zoneID: g.zone)]?.copy() as? CKRecord
    }

    private func run(_ rs: [CKRecord]) async -> Bool {
        busy = true; defer { busy = false }
        do { try await save(rs); return true } catch { fail(error); return false }
    }

    private func save(_ rs: [CKRecord]) async throws {
        // Nhóm đích lấy từ chính bản ghi, không theo nhóm đang mở: trong lúc chờ iCloud người dùng có thể đã lùi ra danh sách
        // hoặc sang nhóm khác, khi đó bản ghi vừa lưu bị bỏ khỏi máy hoặc gắn nhầm nhóm
        guard let gid = rs.first?.recordID.zoneID.zoneName, let g = groups.first(where: { $0.id == gid }) else { throw CKError(.zoneNotFound) }
        let r = try await container.database(with: g.scope).modifyRecords(saving: rs, deleting: [], savePolicy: .changedKeys)
        edits += 1
        guard let i = groups.firstIndex(where: { $0.id == gid }) else { return }
        for (id, res) in r.saveResults {
            let saved = try res.get()
            if !(saved is CKShare) { groups[i].records[id] = saved }
        }
        Self.rebuild(&groups[i])
    }

    /// Một thao tác (lưu, xoá, rời nhóm…) không thành: đang có sổ thì giữ nguyên màn hình, chỉ báo lỗi bằng thanh báo;
    /// chưa có gì để hiện thì mới chuyển sang màn báo lỗi có nút Thử lại
    private func fail(_ error: Error) {
        if groups.isEmpty { phase = .failed(Self.describe(error)); return }
        phase = .ready
        Store.shared.showError(Self.describe(error))
    }

    static func describe(_ e: Error) -> String {
        guard let ck = e as? CKError else { return e.localizedDescription }
        switch ck.code {
        case .networkUnavailable, .networkFailure: return L("Không có mạng. Thử lại khi có mạng.")
        case .notAuthenticated: return L("Máy chưa đăng nhập iCloud.")
        case .quotaExceeded: return L("iCloud đã đầy dung lượng.")
        case .permissionFailure: return L("Bạn không có quyền sửa nhóm này.")
        default: return ck.localizedDescription
        }
    }
}

// MARK: Bảng mời thành viên của iOS

/// Mở bảng chia sẻ iCloud (gửi lời mời qua Tin nhắn, Zalo…, xem / xoá người tham gia).
enum HouseInvite {
    @MainActor static func present(share: CKShare, container: CKContainer) {
        let c = UICloudSharingController(share: share, container: container)
        c.availablePermissions = [.allowReadWrite, .allowPrivate]
        guard let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController else { return }
        var top = root
        while let p = top.presentedViewController { top = p }
        top.present(c, animated: true)
    }
}

// MARK: Nhận lời mời

/// iOS gọi khi người được mời bấm vào link nhóm: chuyển cho House nhận lời mời.
final class HouseSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in await House.shared.accept(metadata) }
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        if let m = options.cloudKitShareMetadata { Task { @MainActor in await House.shared.accept(m) } }
    }
}

final class PayAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // Nút ngay trên thông báo: xác nhận mà không cần mở app
        center.setNotificationCategories([UNNotificationCategory(identifier: "HOUSE_CONFIRM", actions: [
            UNNotificationAction(identifier: "yes", title: L("Đã nhận"), options: []),
            UNNotificationAction(identifier: "no", title: L("Chưa nhận được"), options: [.destructive]),
        ], intentIdentifiers: [])])
        application.registerForRemoteNotifications()
        return true
    }

    /// Đẩy im lặng từ iCloud: nhóm vừa đổi trên máy khác
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await House.shared.backgroundRefresh()
        return .newData
    }

    /// Đang mở app vẫn hiện thông báo
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let id = info["settle"] as? String, let group = info["group"] as? String else { return }
        switch response.actionIdentifier {
        case "yes": await House.shared.respondFromNotification(id, group: group, received: true)
        case "no": await House.shared.respondFromNotification(id, group: group, received: false)
        default: await MainActor.run { House.shared.open(group); QuickAction.shared.openHouse = true }
        }
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: nil, sessionRole: session.role)
        c.delegateClass = HouseSceneDelegate.self
        return c
    }
}
