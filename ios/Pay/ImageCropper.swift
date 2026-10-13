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
    /// Tỉ lệ khung (rộng / cao). 1 = vuông (ảnh đại diện, ảnh danh mục); khác 1 = khung chữ nhật góc bo nhẹ (ảnh vừa chụp)
    var aspect: CGFloat = 1
    /// Cạnh dài nhất của ảnh trả về (điểm ảnh): ảnh đại diện 1024 là đủ, ảnh hoá đơn cần nét hơn để còn đọc chữ
    var maxPixel: CGFloat = 1024
    /// Tên nút bên trái (mặc định Huỷ; sau khi chụp là Chụp lại)
    var cancelTitle: String? = nil
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

    /// Khung căn: rộng `side`, cao theo tỉ lệ
    private var frame: CGSize { CGSize(width: side, height: side / max(0.1, aspect)) }
    /// Tỉ lệ để ảnh vừa phủ kín khung khi zoom = 1
    private var base: CGFloat { max(frame.width / max(1, image.size.width), frame.height / max(1, image.size.height)) }
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
                    let shape = circle ? AnyShape(Circle())
                        : AnyShape(RoundedRectangle(cornerRadius: aspect == 1 ? side * 0.22 : 14, style: .continuous))
                    GeometryReader { g in
                        let hole = CGRect(x: (g.size.width - frame.width) / 2, y: (g.size.height - frame.height) / 2, width: frame.width, height: frame.height)
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
                    BigButton(title: cancelTitle ?? L("Huỷ"), icon: "", primary: false, tint: BigButton.cancelTint) { done(nil) }
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
        // Khung vuông: tối đa 360. Khung chữ nhật (ảnh vừa chụp): rộng gần hết màn, nhưng cao không lấn dòng chữ trên và hàng nút dưới
        .onGeometryChange(for: CGFloat.self) { g in
            aspect == 1 ? min(g.size.width - 48, 360) : max(120, min(g.size.width - 32, (g.size.height - 230) * aspect))
        } action: { side = $0; offset = clamp(offset) }
        .preferredColorScheme(.dark)
    }

    /// Ảnh luôn phủ kín khung: không dời quá mép
    private func clamp(_ o: CGSize) -> CGSize {
        let mx = max(0, (shown.width - frame.width) / 2), my = max(0, (shown.height - frame.height) / 2)
        return CGSize(width: min(mx, max(-mx, o.width)), height: min(my, max(-my, o.height)))
    }

    private func crop() -> UIImage {
        let img = upright
        let k = base * zoom   // điểm màn hình trên mỗi điểm ảnh
        let w = frame.width / k, h = frame.height / k
        let cx = img.size.width / 2 - offset.width / k, cy = img.size.height / 2 - offset.height / k
        let rect = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
        let r = min(1, maxPixel / max(1, max(w, h) * img.scale)) * img.scale   // điểm ảnh ra trên mỗi điểm ảnh gốc
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: (w * r).rounded(), height: (h * r).rounded()), format: f).image { _ in
            img.draw(in: CGRect(x: -rect.minX * r, y: -rect.minY * r, width: img.size.width * r, height: img.size.height * r))
        }
    }
}
