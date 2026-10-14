import Photos
import SwiftUI

/// Ảnh mới nhất trong app Ảnh của máy, cho ô ảnh ở màn chụp (như ô ảnh của app Camera). Cập nhật khi thư viện đổi
/// (vd vừa chụp xong, ảnh được lưu vào app Ảnh). Chưa cho phép đọc thư viện thì không có ảnh
@MainActor
final class LatestPhoto: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    /// Hai ảnh mới nhất (mới nhất trước)
    @Published private(set) var images: [UIImage?] = []

    func start() {
        #if DEBUG
        // Ảnh so sánh (máy ảo không cấp được quyền đọc thư viện): -shotPhotos YES dùng hai ảnh mẫu
        if UserDefaults.standard.bool(forKey: "shotPhotos") {
            images = [UIColor(red: 0.95, green: 0.6, blue: 0.2, alpha: 1), UIColor(red: 0.3, green: 0.6, blue: 0.95, alpha: 1)].map { c in
                UIGraphicsImageRenderer(size: CGSize(width: 90, height: 120)).image { ctx in c.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 90, height: 120)) }
            }
            return
        }
        #endif
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited: begin()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { s in
                Task { @MainActor in if s == .authorized || s == .limited { self.begin() } }
            }
        default: break
        }
    }

    func stop() { PHPhotoLibrary.shared().unregisterChangeObserver(self) }

    private func begin() {
        PHPhotoLibrary.shared().register(self)
        load()
    }

    nonisolated func photoLibraryDidChange(_ change: PHChange) {
        Task { @MainActor in self.load() }
    }

    private func load() {
        let o = PHFetchOptions()
        o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        o.fetchLimit = 2
        let found = PHAsset.fetchAssets(with: .image, options: o)
        guard found.count > 0 else { images = []; return }
        if images.count != found.count { images = Array(repeating: nil, count: found.count) }
        let r = PHImageRequestOptions()
        r.deliveryMode = .opportunistic
        r.isNetworkAccessAllowed = true
        for i in 0..<found.count {
            PHImageManager.default().requestImage(for: found[i], targetSize: CGSize(width: 180, height: 240), contentMode: .aspectFill, options: r) { img, _ in
                Task { @MainActor in if let img, i < self.images.count { self.images[i] = img } }
            }
        }
    }
}

/// Ô ảnh ở màn chụp: hai ảnh mới nhất trong app Ảnh, khung 3:4 bo góc nhẹ, xếp chồng lệch nhau (ảnh mới nhất nằm trên, ảnh
/// trước đó nghiêng ló ra phía sau). Chưa có quyền / chưa có ảnh thì khung trống có biểu tượng ảnh
struct LatestPhotoTile: View {
    @StateObject private var latest = LatestPhoto()
    static let size = CGSize(width: 39, height: 52)

    var body: some View {
        ZStack {
            if latest.images.count > 1 {
                card(latest.images[1]).rotationEffect(.degrees(-10)).offset(x: -4, y: -1).opacity(0.85)
            }
            card(latest.images.first ?? nil).rotationEffect(.degrees(4))
        }
        .onAppear { latest.start() }
        .onDisappear { latest.stop() }
    }

    /// Một ảnh: khung 3:4 bo góc nhẹ, viền trắng mảnh để hai ảnh chồng nhau vẫn tách bạch
    private func card(_ img: UIImage?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return ZStack {
            Color(hex: 0x2C2C2E)
            if let img { Image(uiImage: img).resizable().scaledToFill() }
            else { Image(systemName: "photo").font(.system(size: 15)).foregroundStyle(.white.opacity(0.85)) }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
    }
}
