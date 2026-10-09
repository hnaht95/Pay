import Foundation

/// Lưu pay.json vào iCloud Drive (thư mục ẩn của app) để các máy cùng Apple ID dùng chung dữ liệu.
/// Không có iCloud (chưa đăng nhập, hoặc bản build không có quyền iCloud) thì app vẫn chạy với file trên máy.
///
/// Không để mất dữ liệu khi hai máy cùng ghi: mọi lần đọc / ghi đều gộp cả bản hiện tại, các bản xung đột
/// iOS giữ lại (NSFileVersion) và các bản trùng tên iCloud tạo ra ("pay 2.json"), rồi mới dọn chúng đi.
@MainActor
final class Cloud {
    private(set) var url: URL?
    private let query = NSMetadataQuery()
    private var observers: [NSObjectProtocol] = []
    private var onChange: (@MainActor (Backup?) -> Void)?
    private var waitingFirstPush = false
    /// Gọi mỗi lần đọc / ghi iCloud xong, để hiện "Đã đồng bộ lúc ..."
    var onSynced: (@MainActor () -> Void)?
    nonisolated private static let io = DispatchQueue(label: "pay.cloud")

    var active: Bool { url != nil }

    /// Tìm thư mục iCloud rồi theo dõi file; mỗi lần máy khác sửa sẽ gọi onChange (nil = trên iCloud chưa có file).
    /// Trả về false nếu máy này không dùng được iCloud.
    func start(onChange: @escaping @MainActor (Backup?) -> Void) async -> Bool {
        if active { return true }
        let dir = await Task.detached {
            FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents", isDirectory: true)
        }.value
        guard let dir else { return false }
        if active { return true }   // lần gọi khác đã bật xong trong lúc chờ: không đăng ký theo dõi lần hai
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("pay.json")
        self.onChange = onChange

        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, "pay.json")
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.pull() }
            })
        }
        query.start()
        return true
    }

    /// Tắt đồng bộ: thôi theo dõi iCloud, dữ liệu trên máy giữ nguyên.
    func stop() {
        query.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        url = nil
        onChange = nil
    }

    /// Đọc bản trên iCloud và gộp vào máy.
    func pull() async {
        guard let url else { return }
        if let b = await Cloud.read(url) { onChange?(b); onSynced?(); return }

        // Chưa thấy file trên iCloud. Máy mới / vừa cài lại thường chưa tải xong danh sách file,
        // nên đợi rồi kiểm tra lại; tạo file mới ngay có thể che mất bản đang có của máy khác
        guard query.resultCount == 0, !waitingFirstPush else { return }
        waitingFirstPush = true
        try? await Task.sleep(for: .seconds(10))
        waitingFirstPush = false
        guard self.url == url, query.resultCount == 0, !FileManager.default.fileExists(atPath: url.path) else { return }
        onChange?(nil)   // vẫn chưa có: đẩy dữ liệu máy này lên
    }

    /// Ghi lên iCloud: đọc bản đang có (kèm bản xung đột, bản trùng tên), gộp với bản máy này rồi mới ghi,
    /// để không đè mất dữ liệu máy khác; ghi xong thì dọn bản xung đột và bản trùng tên.
    func push(_ mine: Backup) {
        guard let url else { return }
        Cloud.io.async {
            var ok = false
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: nil) { u in
                let data = try? Data(contentsOf: u)
                if data == nil && FileManager.default.fileExists(atPath: u.path) { return }   // có file mà chưa tải về được: đợi lần sau
                let existing = data.flatMap(Cloud.decode)
                let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: u) ?? []
                let extras = Cloud.siblings(of: u)

                var merged = existing.map { Backup.merge(mine, $0) } ?? mine
                for b in conflicts.compactMap({ (try? Data(contentsOf: $0.url)).flatMap(Cloud.decode) }) { merged = Backup.merge(merged, b) }
                for x in extras { if let b = Cloud.readFile(x) { merged = Backup.merge(merged, b) } }

                if let existing, conflicts.isEmpty, extras.isEmpty, merged.same(as: existing) { ok = true; return }
                guard let out = try? JSONEncoder().encode(merged), (try? out.write(to: u, options: .atomic)) != nil else { return }
                ok = true
                // Dữ liệu của các bản này đã nằm trong file vừa ghi: dọn đi
                for v in conflicts { v.isResolved = true }
                if !conflicts.isEmpty { try? NSFileVersion.removeOtherVersionsOfItem(at: u) }
                for x in extras { Cloud.remove(x) }
            }
            if ok { Task { @MainActor [weak self] in self?.onSynced?() } }
        }
    }

    // MARK: Đọc / ghi file (chạy trên hàng đợi riêng)

    nonisolated private static func read(_ url: URL) async -> Backup? {
        await withCheckedContinuation { cont in
            io.async {
                var result: Backup?
                NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: nil) { u in
                    result = (try? Data(contentsOf: u)).flatMap(decode)
                    for v in NSFileVersion.unresolvedConflictVersionsOfItem(at: u) ?? [] {
                        if let b = (try? Data(contentsOf: v.url)).flatMap(decode) { result = result.map { Backup.merge($0, b) } ?? b }
                    }
                }
                for x in siblings(of: url) {
                    if let b = readFile(x) { result = result.map { Backup.merge($0, b) } ?? b }
                }
                cont.resume(returning: result)
            }
        }
    }

    nonisolated private static func decode(_ data: Data) -> Backup? { try? JSONDecoder().decode(Backup.self, from: data) }

    /// Đọc một file trong iCloud (tự tải về nếu mới chỉ có tên).
    nonisolated private static func readFile(_ url: URL) -> Backup? {
        var result: Backup?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: nil) { u in
            result = (try? Data(contentsOf: u)).flatMap(decode)
        }
        return result
    }

    nonisolated private static func remove(_ url: URL) {
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: nil) { u in
            try? FileManager.default.removeItem(at: u)
        }
    }

    /// Các bản trùng tên iCloud tạo khi hai máy cùng tạo pay.json ("pay 2.json"). Bản chưa tải về có tên ".pay 2.json.icloud".
    nonisolated private static func siblings(of url: URL) -> [URL] {
        let dir = url.deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.compactMap { n -> URL? in
            var name = n
            if name.hasPrefix("."), name.hasSuffix(".icloud") { name = String(name.dropFirst().dropLast(".icloud".count)) }
            guard name != url.lastPathComponent, name.hasPrefix("pay "), name.hasSuffix(".json") else { return nil }
            return dir.appendingPathComponent(name)
        }
    }
}
