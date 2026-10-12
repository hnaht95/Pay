import SwiftUI
import UIKit

/// Ảnh riêng của danh mục (thay cho biểu tượng), đặt tên theo mã danh mục: <mã>.jpg.
///
/// Cắt vuông giữa ảnh, thu còn 512 px. Lưu trong thư mục riêng của Pay; bật Đồng bộ iCloud thì chép thêm lên iCloud
/// của Pay (thư mục CategoryPhotos) để máy khác cùng Apple ID cũng thấy. Đổi / xoá ảnh là báo `changed` cho các ô vẽ lại.
enum CategoryPhotos {
    static let changed = Notification.Name("CategoryPhotos.changed")
    private static let fm = FileManager.default

    private static var localDir: URL {
        let d = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CategoryPhotos", isDirectory: true)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static func cloudDir() -> URL? {
        guard UserDefaults.standard.object(forKey: "cloudSync") as? Bool ?? true, UserDefaults.standard.bool(forKey: "proActive"),
              let base = fm.url(forUbiquityContainerIdentifier: nil) else { return nil }
        let d = base.appendingPathComponent("Documents/CategoryPhotos", isDirectory: true)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static func name(_ k: String) -> String { k + ".jpg" }

    /// Ảnh đã đọc (kể cả "không có ảnh"), để mỗi lần vẽ ô không phải đọc đĩa
    nonisolated(unsafe) private static var cache: [String: UIImage?] = [:]

    /// Ảnh của danh mục; chưa có trong máy thì thử lấy bản trên iCloud ở nền (lấy được thì báo `changed`)
    static func image(_ k: String) -> UIImage? {
        if let c = cache[k] { return c }
        let img = UIImage(contentsOfFile: localDir.appendingPathComponent(name(k)).path)
        cache[k] = .some(img)
        if img == nil { fetchCloud(k) }
        return img
    }

    static func save(_ image: UIImage, k: String) {
        let side: CGFloat = 512
        let s = min(image.size.width, image.size.height)
        let scale = side / s
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let square = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
            .image { _ in image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height)) }
        guard let data = square.jpegData(compressionQuality: 0.8) else { return }
        try? data.write(to: localDir.appendingPathComponent(name(k)), options: .atomic)
        cache[k] = .some(square)
        NotificationCenter.default.post(name: changed, object: nil)
        DispatchQueue.global(qos: .utility).async {
            guard let dir = cloudDir() else { return }
            NSFileCoordinator().coordinate(writingItemAt: dir.appendingPathComponent(name(k)), options: .forReplacing, error: nil) { u in
                try? data.write(to: u, options: .atomic)
            }
        }
    }

    static func remove(_ k: String) {
        try? fm.removeItem(at: localDir.appendingPathComponent(name(k)))
        cache[k] = .some(nil)
        NotificationCenter.default.post(name: changed, object: nil)
        DispatchQueue.global(qos: .utility).async {
            guard let dir = cloudDir() else { return }
            NSFileCoordinator().coordinate(writingItemAt: dir.appendingPathComponent(name(k)), options: .forDeleting, error: nil) { u in
                try? fm.removeItem(at: u)
            }
        }
    }

    private static func fetchCloud(_ k: String) {
        let local = localDir.appendingPathComponent(name(k))
        DispatchQueue.global(qos: .utility).async {
            guard let dir = cloudDir() else { return }
            let url = dir.appendingPathComponent(name(k))
            let stub = dir.appendingPathComponent("." + name(k) + ".icloud")
            guard fm.fileExists(atPath: url.path) || fm.fileExists(atPath: stub.path) else { return }
            try? fm.startDownloadingUbiquitousItem(at: url)
            var data: Data?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: nil) { u in data = try? Data(contentsOf: u) }
            guard let data, let img = UIImage(data: data) else { return }
            try? data.write(to: local, options: .atomic)
            DispatchQueue.main.async {
                cache[k] = .some(img)
                NotificationCenter.default.post(name: changed, object: nil)
            }
        }
    }
}

/// Ô vuông bo góc nền trắng của danh mục: ảnh riêng (phủ kín ô) nếu có, không thì biểu tượng ở giữa
struct CategoryBadge: View {
    let c: Category
    var side: CGFloat = 52
    var radius: CGFloat = 14
    var iconSize: CGFloat = 30
    /// Viền mảnh màu danh mục quanh ô (ở danh sách, nơi ô không nằm trên nền màu danh mục)
    var ring = false
    /// Viền xám rất mảnh, để ô trắng không chìm khi nằm trên thẻ trắng
    var edge = false
    @State private var tick = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if let img = CategoryPhotos.image(c.k) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                CategoryIcon(c: c, size: iconSize)
            }
        }
        .frame(width: side, height: side)
        // Tối giản: không nền trắng, biểu tượng nằm thẳng trên ô / thẻ (ảnh riêng của danh mục vẫn cắt theo khung)
        .background(Appearance.minimalOn ? Color.clear : .white)
        .clipShape(shape)
        .overlay { if ring { shape.strokeBorder(c.color, lineWidth: 2.5) } }
        .overlay { if edge { shape.strokeBorder(Color.black.opacity(0.08), lineWidth: 1) } }
        .id(tick)
        .onReceive(NotificationCenter.default.publisher(for: CategoryPhotos.changed)) { _ in tick += 1 }
    }
}
