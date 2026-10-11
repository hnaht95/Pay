import UIKit

/// Ảnh hoá đơn lưu kèm khoản chi, đặt tên theo mã khoản: <mã>.jpg.
///
/// Lưu trong thư mục riêng của Pay (không vào app Ảnh, không cần xin quyền), nén còn chừng 200–300 KB.
/// Bật Đồng bộ iCloud thì chép thêm một bản lên iCloud của Pay (cùng chỗ với pay.json, thư mục Receipts):
/// máy khác cùng Apple ID mở khoản đó là tải ảnh về. Ảnh trong máy cũng nằm trong bản sao lưu iCloud của iPhone.
enum ReceiptPhotos {
    private static let fm = FileManager.default

    private static var localDir: URL {
        let d = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Receipts", isDirectory: true)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Thư mục ảnh trên iCloud của Pay, nil khi chưa bật đồng bộ / chưa đăng nhập iCloud (gọi ngoài luồng chính: lần đầu có thể chậm)
    private static func cloudDir() -> URL? {
        guard UserDefaults.standard.object(forKey: "cloudSync") as? Bool ?? true, UserDefaults.standard.bool(forKey: "proActive"),
              let base = fm.url(forUbiquityContainerIdentifier: nil) else { return nil }
        let d = base.appendingPathComponent("Documents/Receipts", isDirectory: true)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static func name(_ id: String) -> String { id + ".jpg" }

    /// Thu nhỏ cạnh dài còn 1600 px, nén JPEG chất lượng 0,6
    static func save(_ image: UIImage, id: String) {
        let maxSide: CGFloat = 1600
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let small = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
            .image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = small.jpegData(compressionQuality: 0.6) else { return }
        try? data.write(to: localDir.appendingPathComponent(name(id)), options: .atomic)
        DispatchQueue.global(qos: .utility).async {
            guard let dir = cloudDir() else { return }
            NSFileCoordinator().coordinate(writingItemAt: dir.appendingPathComponent(name(id)), options: .forReplacing, error: nil) { u in
                try? data.write(to: u, options: .atomic)
            }
        }
    }

    /// Ảnh của khoản: trong máy trước; chưa có thì lấy bản trên iCloud (chưa tải về thì bảo iCloud tải, lần mở sau sẽ có)
    static func load(_ id: String) async -> UIImage? {
        let local = localDir.appendingPathComponent(name(id))
        if let img = UIImage(contentsOfFile: local.path) { return img }
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let dir = cloudDir() else { return nil }
            let url = dir.appendingPathComponent(name(id))
            try? fm.startDownloadingUbiquitousItem(at: url)
            var data: Data?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: nil) { u in data = try? Data(contentsOf: u) }
            guard let data, let img = UIImage(data: data) else { return nil }
            try? data.write(to: local, options: .atomic)   // giữ một bản trong máy cho lần sau
            return img
        }.value
    }

    /// Khoản này có ảnh không (trong máy, hoặc bản trên iCloud kể cả khi chưa tải về)
    static func has(_ id: String) -> Bool {
        if fm.fileExists(atPath: localDir.appendingPathComponent(name(id)).path) { return true }
        return cloudIndex.contains(id)
    }

    static func remove(_ id: String) {
        try? fm.removeItem(at: localDir.appendingPathComponent(name(id)))
        cloudIndex.remove(id)
        DispatchQueue.global(qos: .utility).async {
            guard let dir = cloudDir() else { return }
            let url = dir.appendingPathComponent(name(id))
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: nil) { u in try? fm.removeItem(at: u) }
        }
    }

    /// Mã các khoản có ảnh trên iCloud (đọc tên tệp, kể cả tệp chưa tải về dạng ".<tên>.icloud"); làm mới khi mở app
    nonisolated(unsafe) private static var cloudIndex = Set<String>()

    static func refreshCloudIndex() {
        DispatchQueue.global(qos: .utility).async {
            guard let dir = cloudDir(), let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
            let ids = Set(names.compactMap { n -> String? in
                var s = n
                if s.hasPrefix("."), s.hasSuffix(".icloud") { s = String(s.dropFirst().dropLast(7)) }
                return s.hasSuffix(".jpg") ? String(s.dropLast(4)) : nil
            })
            DispatchQueue.main.async { cloudIndex = ids }
        }
    }
}
