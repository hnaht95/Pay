import CloudKit
import SwiftUI
import UIKit

// MARK: Dữ liệu nhóm "Nhà chung"

/// Thành viên trong nhóm. Ai cũng thêm được, kể cả người chưa cài Pay (như sổ Tab).
struct HouseMember: Identifiable, Hashable {
    let id: String
    var name: String
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
        for s in settles {
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

/// Một nhóm = một vùng dữ liệu (zone) trong iCloud của người tạo, chia sẻ bằng CKShare cho cả vùng.
/// Người được mời thấy vùng đó trong cơ sở dữ liệu "được chia sẻ" của họ; ai cũng thêm / sửa / xoá được.
@MainActor
final class House: ObservableObject {
    static let shared = House()

    enum Phase: Equatable { case loading, none, ready, noAccount, failed(String) }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var name = ""
    @Published private(set) var members: [HouseMember] = []
    @Published private(set) var spends: [HouseSpend] = []
    @Published private(set) var settles: [HouseSettle] = []
    @Published private(set) var isOwner = false
    @Published private(set) var busy = false
    /// Thành viên là chính mình (mỗi máy tự chọn, nhớ theo nhóm)
    @Published var me: String? {
        didSet { if let zone { UserDefaults.standard.set(me, forKey: "house.me.\(zone.zoneName)") } }
    }

    private let container = CKContainer(identifier: "iCloud.com.hnaht95.sochipay")
    private var zone: CKRecordZone.ID?
    private var scope: CKDatabase.Scope = .private
    private var db: CKDatabase { container.database(with: scope) }
    private var records: [CKRecord.ID: CKRecord] = [:]
    private static let zonePrefix = "nha-"

    /// Bản Debug chạy với "-houseDemo YES": dữ liệu mẫu, không cần iCloud, sửa gì cũng chỉ trên máy (để xem giao diện trên máy ảo)
    private var demo = false

    private init() {
        #if DEBUG
        demo = UserDefaults.standard.bool(forKey: "houseDemo")
        #endif
    }

    private func loadDemo() {
        let now = Date()
        func ago(_ d: Double) -> Date { now.addingTimeInterval(-d * 86_400) }
        name = "Nhà mình"; isOwner = true
        members = [HouseMember(id: "a", name: "Thành"), HouseMember(id: "b", name: "Lan"),
                   HouseMember(id: "c", name: "Minh"), HouseMember(id: "d", name: "Hà")]
        spends = [
            HouseSpend(id: "e1", amount: 420_000, note: "Đi chợ cuối tuần", payer: "a", shares: ["a", "b", "c", "d"], date: ago(0.2), cat: "an"),
            HouseSpend(id: "e2", amount: 860_000, note: "Tiền điện tháng 9", payer: "b", shares: ["a", "b", "c", "d"], date: ago(2), cat: "hd"),
            HouseSpend(id: "e3", amount: 300_000, note: "Lẩu tối thứ 6", payer: "c", shares: ["a", "c", "d"], date: ago(4), cat: "an"),
            HouseSpend(id: "e4", amount: 250_000, note: "Internet", payer: "a", shares: ["a", "b", "c", "d"], date: ago(8), cat: "hd"),
        ]
        settles = [HouseSettle(id: "s1", from: "d", to: "a", amount: 100_000, date: ago(1))]
        if me == nil { me = "a" }
        phase = .ready
    }

    /// Màu riêng cho mỗi người (theo mã), dùng cho ảnh đại diện
    func tone(_ id: String) -> Int { Int(Settle.hash(id) % UInt32(CategoryTone.all.count)) }

    var memberName: (String) -> String {
        let m = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.name) })
        return { m[$0] ?? "Người đã xoá" }
    }

    // MARK: Tải

    /// Tìm nhóm: trước trong vùng mình tạo, không có thì trong các vùng người khác chia sẻ cho mình.
    func load() async {
        if demo { if phase != .ready { loadDemo() }; return }
        if phase != .ready { phase = .loading }
        do {
            guard try await container.accountStatus() == .available else { phase = .noAccount; return }
            if zone == nil {
                if let z = try await container.privateCloudDatabase.allRecordZones().first(where: { $0.zoneID.zoneName.hasPrefix(Self.zonePrefix) }) {
                    zone = z.zoneID; scope = .private; isOwner = true
                } else if let z = try await container.sharedCloudDatabase.allRecordZones().first(where: { $0.zoneID.zoneName.hasPrefix(Self.zonePrefix) }) {
                    zone = z.zoneID; scope = .shared; isOwner = false
                }
            }
            guard zone != nil else { phase = .none; return }
            try await fetchAll()
            phase = .ready
        } catch let e as CKError where e.code == .zoneNotFound || e.code == .userDeletedZone || e.code == .notAuthenticated {
            reset()
            phase = e.code == .notAuthenticated ? .noAccount : .none
        } catch {
            phase = phase == .ready ? .ready : .failed(Self.describe(error))
        }
    }

    private func fetchAll() async throws {
        guard let zone else { return }
        var all: [CKRecord.ID: CKRecord] = [:]
        var token: CKServerChangeToken?
        var more = true
        while more {
            let r = try await db.recordZoneChanges(inZoneWith: zone, since: token)
            for (id, res) in r.modificationResultsByID { if case .success(let m) = res { all[id] = m.record } }
            token = r.changeToken
            more = r.moreComing
        }
        records = all
        rebuild()
        me = UserDefaults.standard.string(forKey: "house.me.\(zone.zoneName)").flatMap { id in members.contains { $0.id == id } ? id : nil }
    }

    private func rebuild() {
        var ms: [HouseMember] = [], sp: [HouseSpend] = [], st: [HouseSettle] = []
        for r in records.values {
            let id = r.recordID.recordName
            switch r.recordType {
            case "Member": ms.append(HouseMember(id: id, name: r["name"] as? String ?? ""))
            case "Spend":
                sp.append(HouseSpend(id: id, amount: (r["amount"] as? Int64).map(Int.init) ?? 0, note: r["note"] as? String ?? "",
                                     payer: r["payer"] as? String ?? "", shares: r["shares"] as? [String] ?? [],
                                     date: r["date"] as? Date ?? r.creationDate ?? Date(), cat: r["cat"] as? String ?? "khac"))
            case "Settle":
                st.append(HouseSettle(id: id, from: r["from"] as? String ?? "", to: r["to"] as? String ?? "",
                                      amount: (r["amount"] as? Int64).map(Int.init) ?? 0, date: r["date"] as? Date ?? Date()))
            case "Info": name = r["name"] as? String ?? name
            default: break
            }
        }
        members = ms.sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
        spends = sp.sorted { $0.date > $1.date }
        settles = st.sorted { $0.date > $1.date }
    }

    private func reset() {
        zone = nil; records = [:]; members = []; spends = []; settles = []; name = ""; me = nil; isOwner = false
    }

    // MARK: Tạo / tham gia / rời nhóm

    /// Tạo nhóm mới với chính mình là thành viên đầu tiên.
    func create(name groupName: String, me myName: String) async {
        if demo { loadDemo(); name = groupName; members[0].name = myName; return }
        busy = true; defer { busy = false }
        do {
            let z = CKRecordZone(zoneName: Self.zonePrefix + UUID().uuidString.prefix(8).lowercased())
            _ = try await container.privateCloudDatabase.modifyRecordZones(saving: [z], deleting: [])
            zone = z.zoneID; scope = .private; isOwner = true
            let info = CKRecord(recordType: "Info", recordID: CKRecord.ID(recordName: "info", zoneID: z.zoneID))
            info["name"] = groupName
            let m = CKRecord(recordType: "Member", recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: z.zoneID))
            m["name"] = myName
            try await save([info, m])
            name = groupName
            me = m.recordID.recordName
            phase = .ready
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    /// Người được mời bấm vào link: nhận lời mời rồi mở nhóm.
    func accept(_ metadata: CKShare.Metadata) async {
        phase = .loading
        do {
            _ = try await container.accept(metadata)
            reset()
            zone = metadata.share.recordID.zoneID; scope = .shared; isOwner = false
            try await fetchAll()
            phase = .ready
            QuickAction.shared.openHouse = true
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    /// Chủ nhóm: xoá cả nhóm. Người được mời: rời nhóm (dữ liệu vẫn còn ở chủ nhóm).
    func leave() async {
        if demo { members = []; spends = []; settles = []; me = nil; phase = .none; return }
        guard let zone else { return }
        busy = true; defer { busy = false }
        do {
            if isOwner { _ = try await container.privateCloudDatabase.modifyRecordZones(saving: [], deleting: [zone]) }
            else { _ = try await container.sharedCloudDatabase.modifyRecordZones(saving: [], deleting: [zone]) }
            UserDefaults.standard.removeObject(forKey: "house.me.\(zone.zoneName)")
            reset()
            phase = .none
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    /// Lời mời của cả nhóm (tạo nếu chưa có), để mở bảng chia sẻ của iOS.
    func share() async throws -> CKShare {
        guard let zone else { throw CKError(.zoneNotFound) }
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone)
        if let s = try? await db.record(for: shareID) as? CKShare { return s }
        let s = CKShare(recordZoneID: zone)
        s[CKShare.SystemFieldKey.title] = name.isEmpty ? "Nhà chung" : name
        s.publicPermission = .none
        try await save([s])
        return s
    }

    var cloud: CKContainer { container }

    // MARK: Sửa dữ liệu

    func addMember(_ n: String) async -> String? {
        if demo { let id = UUID().uuidString; members.append(HouseMember(id: id, name: n)); return id }
        guard let zone else { return nil }
        let r = CKRecord(recordType: "Member", recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zone))
        r["name"] = n
        return await run([r]) ? r.recordID.recordName : nil
    }

    func renameMember(_ id: String, _ n: String) async {
        guard let r = record(id) else { return }
        r["name"] = n
        _ = await run([r])
    }

    @discardableResult
    func addSpend(amount: Int, note: String, payer: String, shares: [String], cat: String) async -> Bool {
        if demo {
            spends.insert(HouseSpend(id: UUID().uuidString, amount: amount, note: note, payer: payer, shares: shares, date: Date(), cat: cat), at: 0)
            return true
        }
        guard let zone else { return false }
        let r = CKRecord(recordType: "Spend", recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zone))
        r["amount"] = Int64(amount); r["note"] = note; r["payer"] = payer; r["shares"] = shares; r["date"] = Date(); r["cat"] = cat
        return await run([r])
    }

    func settle(_ t: HouseTransfer) async {
        if demo { settles.insert(HouseSettle(id: UUID().uuidString, from: t.from, to: t.to, amount: t.amount, date: Date()), at: 0); return }
        guard let zone else { return }
        let r = CKRecord(recordType: "Settle", recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zone))
        r["from"] = t.from; r["to"] = t.to; r["amount"] = Int64(t.amount); r["date"] = Date()
        _ = await run([r])
    }

    func delete(_ id: String) async {
        if demo { spends.removeAll { $0.id == id }; settles.removeAll { $0.id == id }; return }
        guard let zone else { return }
        let rid = CKRecord.ID(recordName: id, zoneID: zone)
        busy = true; defer { busy = false }
        do {
            _ = try await db.modifyRecords(saving: [], deleting: [rid])
            records[rid] = nil
            rebuild()
        } catch { phase = .failed(Self.describe(error)) }
    }

    private func record(_ id: String) -> CKRecord? {
        guard let zone else { return nil }
        return records[CKRecord.ID(recordName: id, zoneID: zone)]
    }

    private func run(_ rs: [CKRecord]) async -> Bool {
        busy = true; defer { busy = false }
        do { try await save(rs); return true } catch { phase = .failed(Self.describe(error)); return false }
    }

    private func save(_ rs: [CKRecord]) async throws {
        let r = try await db.modifyRecords(saving: rs, deleting: [], savePolicy: .changedKeys)
        for (id, res) in r.saveResults {
            let saved = try res.get()
            if !(saved is CKShare) { records[id] = saved }
        }
        rebuild()
    }

    static func describe(_ e: Error) -> String {
        guard let ck = e as? CKError else { return e.localizedDescription }
        switch ck.code {
        case .networkUnavailable, .networkFailure: return "Không có mạng. Thử lại khi có mạng."
        case .notAuthenticated: return "Máy chưa đăng nhập iCloud."
        case .quotaExceeded: return "iCloud đã đầy dung lượng."
        case .permissionFailure: return "Bạn không có quyền sửa nhóm này."
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

final class PayAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: nil, sessionRole: session.role)
        c.delegateClass = HouseSceneDelegate.self
        return c
    }
}
