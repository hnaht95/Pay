import Foundation

/// Lưu pay.json vào iCloud Drive (thư mục ẩn của app) để các máy cùng Apple ID dùng chung dữ liệu.
/// Không có iCloud (chưa đăng nhập, hoặc bản build không có quyền iCloud) thì app vẫn chạy với file trên máy.
@MainActor
final class Cloud {
    private(set) var url: URL?
    private let query = NSMetadataQuery()
    private var observers: [NSObjectProtocol] = []
    private var onChange: (@MainActor (Backup?) -> Void)?
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
        if let b = await Cloud.read(url) { onChange?(b); onSynced?() }
        else if query.resultCount == 0 { onChange?(nil) }   // chưa có file: đẩy dữ liệu máy này lên
    }

    /// Ghi lên iCloud: đọc bản đang có, gộp với bản máy này rồi mới ghi, để không đè mất dữ liệu máy khác.
    func push(_ mine: Backup) {
        guard let url else { return }
        Cloud.io.async {
            var ok = false
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: nil) { u in
                let data = try? Data(contentsOf: u)
                if data == nil && FileManager.default.fileExists(atPath: u.path) { return }   // có file mà chưa tải về được: đợi lần sau
                let existing = data.flatMap { try? JSONDecoder().decode(Backup.self, from: $0) }
                let merged = existing.map { Backup.merge(mine, $0) } ?? mine
                if let existing, merged.same(as: existing) { ok = true; return }
                if let out = try? JSONEncoder().encode(merged) { ok = (try? out.write(to: u, options: .atomic)) != nil }
            }
            if ok { Task { @MainActor [weak self] in self?.onSynced?() } }
        }
    }

    nonisolated private static func read(_ url: URL) async -> Backup? {
        await withCheckedContinuation { cont in
            io.async {
                var result: Backup?
                NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: nil) { u in
                    result = (try? Data(contentsOf: u)).flatMap { try? JSONDecoder().decode(Backup.self, from: $0) }
                }
                cont.resume(returning: result)
            }
        }
    }
}
