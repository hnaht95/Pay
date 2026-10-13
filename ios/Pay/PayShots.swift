import Photos
import SwiftUI

/// Ảnh mới nhất trong app Ảnh của máy, cho ô ảnh ở màn chụp (như ô ảnh của app Camera). Cập nhật khi thư viện đổi
/// (vd vừa chụp xong, ảnh được lưu vào app Ảnh). Chưa cho phép đọc thư viện thì không có ảnh
@MainActor
final class LatestPhoto: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published private(set) var image: UIImage?

    func start() {
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
        o.fetchLimit = 1
        guard let a = PHAsset.fetchAssets(with: .image, options: o).firstObject else { image = nil; return }
        let r = PHImageRequestOptions()
        r.deliveryMode = .opportunistic
        r.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(for: a, targetSize: CGSize(width: 160, height: 220), contentMode: .aspectFill, options: r) { img, _ in
            Task { @MainActor in if let img { self.image = img } }
        }
    }
}

/// Ô ảnh ở màn chụp: ảnh mới nhất trong app Ảnh, khung dọc bo góc (chưa có quyền / chưa có ảnh thì biểu tượng ảnh)
struct LatestPhotoTile: View {
    @StateObject private var latest = LatestPhoto()
    static let size = CGSize(width: 46, height: 62)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        ZStack {
            if let img = latest.image { Image(uiImage: img).resizable().scaledToFill() }
            else { Image(systemName: "photo").font(.system(size: 20)).foregroundStyle(.white) }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(.white.opacity(0.14))
        .clipShape(shape)
        .onAppear { latest.start() }
        .onDisappear { latest.stop() }
    }
}
