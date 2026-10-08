import Foundation

/// Lưu pay.json vào iCloud Drive (thư mục ẩn của app) để các máy cùng Apple ID dùng chung dữ liệu.
/// Không có iCloud (chưa đăng nhập, hoặc bản build không có quyền iCloud) thì app vẫn chạy với file trên máy.
@MainActor
final class Cloud {
    private(set) var url: URL?
    private let query = NSMetadataQuery()
    nonisolated private static let io = DispatchQueue(label: "pay.cloud")

    /// Tìm thư mục iCloud rồi theo dõi file; mỗi lần máy khác sửa sẽ gọi onChange (nil = trên iCloud chưa có file).
    func start(onChange: @escaping @MainActor (Backup?) -> Void) async {
        let dir = await Task.detached {
            FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents", isDirectory: true)
        }.value
        guard let dir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("pay.json")
        self.url = url

        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, "pay.json")
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if let b = await Cloud.read(url) { onChange(b) }
                    else if self.query.resultCount == 0 { onChange(nil) }   // chưa có file: đẩy dữ liệu máy này lên
                }
            }
        }
        query.start()
    }

    /// Ghi lên iCloud: đọc bản đang có, gộp với bản máy này rồi mới ghi, để không đè mất dữ liệu máy khác.
    func push(_ mine: Backup) {
        guard let url else { return }
        Cloud.io.async {
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: nil) { u in
                let data = try? Data(contentsOf: u)
                if data == nil && FileManager.default.fileExists(atPath: u.path) { return }   // có file mà chưa tải về được: đợi lần sau
                let existing = data.flatMap { try? JSONDecoder().decode(Backup.self, from: $0) }
                let merged = existing.map { Backup.merge(mine, $0) } ?? mine
                if let existing, merged.same(as: existing) { return }
                if let out = try? JSONEncoder().encode(merged) { try? out.write(to: u, options: .atomic) }
            }
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
