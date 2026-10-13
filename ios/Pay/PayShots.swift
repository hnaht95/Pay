import SwiftUI
import PhotosUI

/// Ảnh chụp bằng Pay, lưu riêng trong thư mục của app (ngoài bản lưu vào app Ảnh): ô ảnh ở màn chụp hiện ảnh mới nhất,
/// chạm vào là danh sách ảnh Pay đã chụp (không phải cả thư viện ảnh của máy)
enum PayShots {
    private static let fm = FileManager.default
    static let changed = Notification.Name("payShotsChanged")

    private static var dir: URL {
        let d = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Shots", isDirectory: true)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func save(_ img: UIImage) {
        guard let data = img.jpegData(compressionQuality: 0.8) else { return }
        let name = "\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    /// Mới nhất trước
    static func all() -> [URL] {
        ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "jpg" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func remove(_ u: URL) {
        try? fm.removeItem(at: u)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    static func thumb(_ u: URL, side: CGFloat = 200) -> UIImage? {
        guard let img = UIImage(contentsOfFile: u.path) else { return nil }
        let s = max(side / img.size.width, side / img.size.height)
        let size = CGSize(width: img.size.width * s, height: img.size.height * s)
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: f).image { _ in
            img.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
        }
    }
}

/// Danh sách ảnh Pay đã chụp: chạm một ảnh để dùng; nhấn giữ để xoá. Dưới cùng vẫn có lối chọn từ thư viện ảnh của máy
struct PayShotsSheet: View {
    var pick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var shots: [URL] = []
    @State private var library: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                if shots.isEmpty {
                    Text(L("Chưa có ảnh nào chụp bằng Pay.")).font(.system(size: 16)).foregroundStyle(.secondary).padding(.top, 60)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                    ForEach(shots, id: \.self) { u in
                        ShotCell(url: u)
                            .onTapGesture {
                                if let img = UIImage(contentsOfFile: u.path) { Haptic.tap(); dismiss(); pick(img) }
                            }
                            .contextMenu {
                                Button(role: .destructive) { PayShots.remove(u); shots = PayShots.all() } label: { Label(L("Xoá"), systemImage: "trash") }
                            }
                    }
                }
                .padding(.bottom, 100)
            }
            .background(Palette.bg.ignoresSafeArea())
            .screenTitle(L("Ảnh đã chụp"))
            .navigationBarTitleDisplayMode(.inline)
            .bottomBar {
                PhotosPicker(selection: $library, matching: .images) {
                    Text(L("Chọn từ thư viện ảnh")).font(.system(size: 17, weight: .semibold)).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(Palette.card, in: Capsule())
                }
                .tint(.primary)
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
        .onAppear { shots = PayShots.all() }
        .task(id: library) {
            guard let item = library, let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) else { return }
            dismiss(); pick(img)
        }
        .sheetGrabber()
    }
}

private struct ShotCell: View {
    let url: URL
    @State private var img: UIImage?
    var body: some View {
        Color.gray.opacity(0.15)
            .aspectRatio(1, contentMode: .fit)
            .overlay { if let img { Image(uiImage: img).resizable().scaledToFill() } }
            .clipped()
            .task { img = await Task.detached { PayShots.thumb(url, side: 300) }.value }
    }
}

/// Ô ảnh ở màn chụp: ảnh mới nhất Pay đã chụp (chưa có thì biểu tượng ảnh)
struct LatestShotTile: View {
    @State private var img: UIImage?
    var body: some View {
        ZStack {
            if let img { Image(uiImage: img).resizable().scaledToFill() }
            else { Image(systemName: "photo.on.rectangle").font(.system(size: 22)).foregroundStyle(.white) }
        }
        .frame(width: 58, height: 58)
        .background(.white.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 1))
        .task { load() }
        .onReceive(NotificationCenter.default.publisher(for: PayShots.changed)) { _ in load() }
    }
    private func load() { img = PayShots.all().first.flatMap { PayShots.thumb($0, side: 174) } }
}
