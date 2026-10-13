import SwiftUI

/// Ảnh đang chờ căn khung (bọc lại để dùng với fullScreenCover(item:))
struct CropItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Căn khung ảnh sau khi chọn: kéo để dời, chụm hai ngón để phóng to, ảnh luôn phủ kín khung. Xong: trả ảnh vuông đã cắt.
/// circle: khung tròn (ảnh đại diện); không thì vuông bo góc (ảnh danh mục, ảnh nhóm)
struct ImageCropper: View {
    let image: UIImage
    var circle = false
    var done: (UIImage?) -> Void

    @State private var zoom: CGFloat = 1
    @State private var zoomStart: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var offsetStart: CGSize = .zero
    @State private var side: CGFloat = 300

    /// Ảnh đã xoay đúng chiều (ảnh chụp có thể mang cờ xoay)
    private var upright: UIImage {
        guard image.imageOrientation != .up else { return image }
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: f).image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
    }

    /// Tỉ lệ để ảnh vừa phủ kín khung khi zoom = 1
    private var base: CGFloat { side / max(1, min(image.size.width, image.size.height)) }
    private var shown: CGSize { CGSize(width: image.size.width * base * zoom, height: image.size.height * base * zoom) }

    var body: some View {
        ZStack {
            // Ảnh, lớp tối ngoài khung và viền khung cùng một khung toàn màn, cùng tâm (ảnh to hơn màn cũng không đẩy bố cục)
            Color.black
                .overlay {
                    Image(uiImage: image).resizable()
                        .frame(width: shown.width, height: shown.height)
                        .offset(offset)
                }
                .overlay {
                    let shape = circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: side * 0.22, style: .continuous))
                    GeometryReader { g in
                        let hole = CGRect(x: (g.size.width - side) / 2, y: (g.size.height - side) / 2, width: side, height: side)
                        Rectangle().fill(Color.black.opacity(0.62))
                            .mask {
                                ZStack {
                                    Rectangle()
                                    shape.path(in: hole).fill(Color.black).blendMode(.destinationOut)
                                }
                                .compositingGroup()
                            }
                        shape.path(in: hole).stroke(.white.opacity(0.9), lineWidth: 2)
                    }
                    .allowsHitTesting(false)
                }
                .clipped()
                .ignoresSafeArea()

            VStack {
                Text(L("Kéo, chụm để căn ảnh")).font(.system(size: 16, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 24)
                Spacer()
                HStack(spacing: 12) {
                    BigButton(title: L("Huỷ"), icon: "", primary: false, tint: BigButton.cancelTint) { done(nil) }
                    BigButton(title: L("Xong"), icon: "", primary: true) { done(crop()) }
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            SimultaneousGesture(
                DragGesture()
                    .onChanged { v in offset = clamp(CGSize(width: offsetStart.width + v.translation.width, height: offsetStart.height + v.translation.height)) }
                    .onEnded { _ in offsetStart = offset },
                MagnifyGesture()
                    .onChanged { v in zoom = min(6, max(1, zoomStart * v.magnification)); offset = clamp(offset) }
                    .onEnded { _ in zoomStart = zoom; offsetStart = offset }
            )
        )
        .onGeometryChange(for: CGFloat.self) { min($0.size.width - 48, 360) } action: { side = $0; offset = clamp(offset) }
        .preferredColorScheme(.dark)
    }

    /// Ảnh luôn phủ kín khung: không dời quá mép
    private func clamp(_ o: CGSize) -> CGSize {
        let mx = max(0, (shown.width - side) / 2), my = max(0, (shown.height - side) / 2)
        return CGSize(width: min(mx, max(-mx, o.width)), height: min(my, max(-my, o.height)))
    }

    private func crop() -> UIImage {
        let img = upright
        let k = base * zoom   // điểm màn hình trên mỗi điểm ảnh
        let s = side / k
        let cx = img.size.width / 2 - offset.width / k, cy = img.size.height / 2 - offset.height / k
        let rect = CGRect(x: cx - s / 2, y: cy - s / 2, width: s, height: s)
        let out = min(1024, s * img.scale)
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: f).image { _ in
            let r = out / s
            img.draw(in: CGRect(x: -rect.minX * r, y: -rect.minY * r, width: img.size.width * r, height: img.size.height * r))
        }
    }
}
