import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Photos
import PhotosUI
import SwiftUI

/// Màn chụp hoá đơn / ảnh đính kèm, kiểu app máy ảnh: khung xem bo góc có lưới, nhiệt độ màu · thu phóng · độ sáng ngay trên
/// khung, hàng tỉ lệ / hẹn giờ / đèn / đổi camera, nút chụp to ở giữa, chọn ảnh có sẵn bên trái, bộ lọc bên phải.
/// Không dùng máy quét tài liệu của iOS: nó có sẵn bộ lọc / chế độ chụp không ẩn được
struct ReceiptCamera: View {
    var done: (UIImage?) -> Void
    @StateObject private var cam = ReceiptCam()
    @State private var photo: PhotosPickerItem?
    @State private var finished = false
    @State private var flash = false
    /// Ảnh vừa chụp / vừa chọn từ thư viện, đang chờ căn lại (dời, phóng to) trước khi dùng
    @State private var review: CropItem?
    /// Ảnh đang căn là ảnh vừa chụp (căn xong mới lưu vào ảnh Pay đã chụp / Ảnh của máy); ảnh chọn từ thư viện thì không lưu lại
    @State private var reviewIsShot = false
    @AppStorage("cam.grid") private var grid = true
    @AppStorage("cam.ratio") private var ratio = CamRatio.r34.rawValue
    @AppStorage("cam.timer") private var timer = 0
    @AppStorage("cam.filter") private var filterRaw = CamFilter.none.rawValue
    /// Đang chỉnh nhiệt độ màu hay độ sáng (thanh trượt hiện trên khung)
    @State private var adjusting: CamAdjust?
    @State private var showFilters = false
    @State private var countdown = 0
    @State private var showShots = false
    @State private var dialShown = false
    @State private var dragStartZoom: CGFloat?
    @State private var dialHide: DispatchWorkItem?

    private var filter: CamFilter { CamFilter(rawValue: filterRaw) ?? .none }
    private var aspect: CamRatio { CamRatio(rawValue: ratio) ?? .r34 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 8)
                viewfinder
                Spacer(minLength: 8)
                if showFilters { filterRow.transition(.move(edge: .bottom).combined(with: .opacity)) }
                toolRow.padding(.top, 14)
                bottomRow.padding(.top, 22).padding(.bottom, 8)
            }
            .padding(.horizontal, 16)
        }
        .overlay { Color.white.opacity(flash ? 0.7 : 0).ignoresSafeArea().allowsHitTesting(false) }
        .preferredColorScheme(.dark)
        // Chọn ảnh có sẵn (ảnh Pay đã chụp hoặc thư viện máy) cũng qua bước căn lại; chờ bảng chọn đóng hẳn rồi mới mở
        .sheet(isPresented: $showShots) {
            PayShotsSheet { img in
                reviewIsShot = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { review = CropItem(image: img) }
            }
        }
        .onAppear { cam.filter = filter; cam.start() }
        .onDisappear { cam.stop() }
        .onChange(of: filterRaw) { _, _ in cam.filter = filter }
        .task(id: photo) {
            guard let item = photo, let data = try? await item.loadTransferable(type: Data.self), !Task.isCancelled,
                  let img = UIImage(data: data) else { return }
            reviewIsShot = false
            review = CropItem(image: img)
        }
        // Chụp xong (hoặc chọn ảnh xong): căn lại trước khi dùng. Khung giữ đúng tỉ lệ của ảnh, kéo để dời, chụm để phóng to
        // vào phần cần lấy. Chụp lại / Huỷ: quay về màn chụp
        .fullScreenCover(item: $review) { c in
            ImageCropper(image: c.image, aspect: c.image.size.width / max(1, c.image.size.height), maxPixel: 2400,
                         cancelTitle: reviewIsShot ? L("Chụp lại") : nil) { img in
                review = nil
                photo = nil
                guard let img else { return }
                if reviewIsShot {
                    PayShots.save(img)
                    if UserDefaults.standard.object(forKey: CamFilter.saveKey) as? Bool ?? true { CamFilter.saveToPhotos(img) }
                }
                finish(img)
            }
        }
    }

    // MARK: Phần trên

    private var topBar: some View {
        HStack {
            Button { finish(nil) } label: {
                Image(systemName: "arrow.left").font(.system(size: 22, weight: .medium)).frame(width: 44, height: 44)
            }
            .accessibilityLabel(L("Đóng"))
            Spacer()
            Button { toggle(.warmth) } label: {
                Image(systemName: "thermometer.medium").font(.system(size: 20, weight: .medium))
                    .foregroundStyle(adjusting == .warmth || cam.warmth != 0 ? Color(hex: 0x61BE6E) : .white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(L("Nhiệt độ màu"))
            Button { toggle(.exposure) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sun.max").font(.system(size: 19, weight: .medium))
                    if cam.exposure != 0 {
                        Text(String(format: "%+.1f", cam.exposure)).font(.system(size: 13, weight: .semibold, design: .monospaced))
                    }
                }
                .foregroundStyle(adjusting == .exposure || cam.exposure != 0 ? Color(hex: 0x61BE6E) : .white)
                .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(L("Độ sáng"))
            Button { grid.toggle(); Haptic.select() } label: {
                Image(systemName: grid ? "squareshape.split.3x3" : "square").font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44)
            }
            .accessibilityLabel(L("Lưới"))
        }
        .foregroundStyle(.white)
        .buttonStyle(Pressable())
    }

    // MARK: Khung xem

    private var viewfinder: some View {
        let shape = RoundedRectangle(cornerRadius: 32, style: .continuous)
        return ZStack {
            Color(hex: 0x1C1C1E)
            CameraPreview(session: cam.session)
            // Bộ lọc khác "Gốc": khung xem vẽ lại từng hình đã qua bộ lọc (giống ảnh sẽ chụp)
            if filter != .none, let f = cam.frame {
                Image(decorative: f, scale: 1).resizable().scaledToFill()
            }
            if grid { GridLines().stroke(.white.opacity(0.45), lineWidth: 1).allowsHitTesting(false) }
            if let e = cam.error {
                Text(e).font(.system(size: 16, weight: .medium)).foregroundStyle(.white).multilineTextAlignment(.center).padding(28)
            }
            if countdown > 0 {
                Text("\(countdown)").font(.system(size: 96, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .contentTransition(.numericText()).shadow(radius: 8)
            }
            // Thước tiêu cự (đang vuốt trái / phải ở chỗ số tiêu cự), cùng kiểu thước hẹn giờ của Peek
            if dialShown {
                VStack(spacing: 6) {
                    Text(zoomText(cam.zoom)).font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ZoomRuler.amber)
                    ZoomRuler(zoom: cam.zoom, min: cam.minZoom, max: cam.maxZoom)
                }
                .padding(.top, 14).padding(.bottom, 62)
                .background(LinearGradient(colors: [.black.opacity(0), .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
            VStack(spacing: 10) {
                Spacer()
                if let a = adjusting, !dialShown { slider(a).transition(.opacity) }
                zoomControl.padding(.bottom, 10)
            }
        }
        .aspectRatio(aspect.value, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(shape)
        .animation(.snappy(duration: 0.25), value: ratio)
        .animation(.snappy(duration: 0.2), value: adjusting)
        .animation(.easeOut(duration: 0.2), value: dialShown)
    }

    /// Chỉ số tiêu cự, chữ đơn cách, không nền. Chạm: đổi nấc (1x · 0.5x · 2x); vuốt trái / phải: thu phóng liền, hiện vòng tiêu cự
    private var zoomControl: some View {
        Text(zoomText(cam.zoom))
            .font(.system(size: dialShown ? 17 : 15, weight: .semibold, design: .monospaced))
            .foregroundStyle(dialShown ? Color(hex: 0xFFD43B) : .white)
            .shadow(color: .black.opacity(0.5), radius: 3)
            .opacity(dialShown ? 0 : 1)   // đang hiện vòng tiêu cự: số đã nằm trên vòng
            .frame(width: 140, height: 52)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if dragStartZoom == nil { dragStartZoom = cam.zoom }
                    guard abs(v.translation.width) > 6 || dialShown else { return }
                    if !dialShown { dialShown = true; Haptic.select() }
                    dialHide?.cancel()
                    // Kéo sang phải: vạch chạy sang phải, nấc nhỏ hơn về giữa; thước đi đúng theo tay (ZoomRuler.perDouble pt mỗi lần gấp đôi)
                    let z = (dragStartZoom ?? 1) * pow(2, -v.translation.width / ZoomRuler.perDouble)
                    let old = cam.zoom
                    cam.setZoom(z)
                    if ZoomRuler.labels.contains(where: { (old - $0) * (cam.zoom - $0) < 0 }) { Haptic.select() }
                }
                .onEnded { v in
                    if !dialShown { cam.nextZoom(); Haptic.select() }
                    dragStartZoom = nil
                    let job = DispatchWorkItem { dialShown = false }
                    dialHide = job
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: job)
                })
            .accessibilityLabel(L("Thu phóng"))
            .accessibilityAddTraits(.isButton)
    }

    private func zoomText(_ z: CGFloat) -> String {
        let r = (z * 10).rounded() / 10
        let s = r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
        return (s.hasPrefix("0.") ? String(s.dropFirst()) : s) + "x"
    }

    private func pillBg(_ on: Bool) -> Color { on ? Color(hex: 0x61BE6E).opacity(0.9) : Color(hex: 0x2C2C2E).opacity(0.8) }

    private func toggle(_ a: CamAdjust) {
        Haptic.select()
        adjusting = adjusting == a ? nil : a
    }

    private func slider(_ a: CamAdjust) -> some View {
        HStack(spacing: 12) {
            Image(systemName: a == .warmth ? "snowflake" : "sun.min").font(.system(size: 14))
            Slider(value: a == .warmth ? Binding(get: { Double(cam.warmth) }, set: { cam.setWarmth(Float($0)) })
                                       : Binding(get: { Double(cam.exposure) }, set: { cam.setExposure(Float($0)) }),
                   in: a == .warmth ? -1...1 : -2...2)
                .tint(Color(hex: 0x61BE6E))
            Image(systemName: a == .warmth ? "flame" : "sun.max.fill").font(.system(size: 14))
            Button { a == .warmth ? cam.setWarmth(0) : cam.setExposure(0); Haptic.select() } label: {
                Text(L("Đặt lại")).font(.system(size: 13, weight: .semibold))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(hex: 0x2C2C2E).opacity(0.85), in: Capsule())
        .padding(.horizontal, 14)
    }

    // MARK: Hàng công cụ: tỉ lệ, hẹn giờ, đèn, đổi camera

    private var toolRow: some View {
        HStack {
            Button { ratio = aspect.next.rawValue; Haptic.select() } label: {
                Text(aspect.label).font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .frame(width: 52, height: 40)
                    .overlay(CornerMarks().stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)))
            }
            .accessibilityLabel(L("Tỉ lệ ảnh"))
            Spacer()
            Button { timer = timer == 0 ? 3 : timer == 3 ? 10 : 0; Haptic.select() } label: {
                ZStack {
                    Image(systemName: "timer").font(.system(size: 24))
                    if timer > 0 {
                        Text("\(timer)").font(.system(size: 11, weight: .bold)).foregroundStyle(.black)
                            .padding(.horizontal, 4).background(Color(hex: 0x61BE6E), in: Capsule()).offset(x: 14, y: -12)
                    }
                }
                .frame(width: 52, height: 44)
            }
            .accessibilityLabel(L("Hẹn giờ"))
            Spacer()
            Button { cam.nextFlash(); Haptic.select() } label: {
                Image(systemName: cam.flashMode == .on ? "bolt.fill" : cam.flashMode == .auto ? "bolt.badge.automatic" : "bolt.slash")
                    .font(.system(size: 24)).foregroundStyle(cam.flashMode == .on ? Color(hex: 0xFFD43B) : .white)
                    .frame(width: 52, height: 44)
            }
            .accessibilityLabel(L("Đèn flash"))
            Spacer()
            Button { cam.flip(); Haptic.select() } label: {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 24)).frame(width: 52, height: 44)
            }
            .accessibilityLabel(L("Đổi camera"))
        }
        .foregroundStyle(.white)
        .buttonStyle(Pressable())
        .padding(.horizontal, 24)
    }

    // MARK: Hàng dưới: chọn ảnh, chụp, bộ lọc

    private var bottomRow: some View {
        HStack {
            // Ảnh mới nhất Pay đã chụp; chạm: danh sách ảnh Pay đã chụp (trong đó vẫn chọn được từ thư viện máy)
            Button { showShots = true } label: { LatestShotTile() }
                .buttonStyle(Pressable())
                .accessibilityLabel(L("Ảnh đã chụp"))
            Spacer()
            Button(action: shoot) {
                Capsule().fill(Color(hex: 0xE8EBDD))
                    .overlay(Image(systemName: "circle.grid.3x3.fill").font(.system(size: 22)).foregroundStyle(.black.opacity(0.25)))
                    .frame(width: 170, height: 76)
                    .padding(6)
                    .background(Capsule().fill(.white.opacity(0.08)))
            }
            .buttonStyle(Pressable())
            .accessibilityLabel(L("Chụp"))
            .disabled(countdown > 0)
            Spacer()
            Button { withAnimation(.snappy) { showFilters.toggle() }; Haptic.select() } label: {
                VStack(spacing: 4) {
                    Image(systemName: "camera.filters").font(.system(size: 24))
                        .foregroundStyle(filter == .none ? .white : Color(hex: 0x61BE6E))
                    Text(filter.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                }
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
            }
            .buttonStyle(Pressable())
            .accessibilityLabel(L("Bộ lọc"))
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CamFilter.allCases, id: \.self) { f in
                    Button { filterRaw = f.rawValue; Haptic.select() } label: {
                        Text(f.title).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(f == filter ? .black : .white)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(f == filter ? Color(hex: 0x61BE6E) : .white.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(Pressable())
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(.top, 6)
    }

    // MARK: Chụp

    private func shoot() {
        guard countdown == 0 else { return }
        if timer > 0 {
            countdown = timer
            Task {
                while countdown > 0 {
                    Haptic.select()
                    try? await Task.sleep(for: .seconds(1))
                    withAnimation { countdown -= 1 }
                }
                snap()
            }
        } else { snap() }
    }

    private func snap() {
        // Rung một nhịp như nút chụp của Camera, màn loé trắng thoáng qua
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        flash = true
        withAnimation(.easeOut(duration: 0.35)) { flash = false }
        let r = aspect.value, f = filter
        cam.capture { img in
            guard let img else { finish(nil); return }
            let out = CamFilter.develop(img, ratio: r, filter: f)
            // Chưa dùng ngay: mở bước căn lại, căn xong mới lưu và trả ảnh (xem fullScreenCover ở trên)
            reviewIsShot = true
            review = CropItem(image: out)
        }
    }

    private func finish(_ img: UIImage?) {
        guard !finished else { return }
        finished = true
        if img != nil { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        done(img)
    }
}

enum CamAdjust { case warmth, exposure }

/// Tỉ lệ khung (rộng / cao, ảnh dọc)
enum CamRatio: String, CaseIterable {
    case r34, r11, r916
    var value: CGFloat { switch self { case .r34: 3.0 / 4; case .r11: 1; case .r916: 9.0 / 16 } }
    var label: String { switch self { case .r34: "4:3"; case .r11: "1:1"; case .r916: "16:9" } }
    var next: CamRatio { switch self { case .r34: .r11; case .r11: .r916; case .r916: .r34 } }
}

/// Bộ lọc áp lên khung xem và ảnh chụp
enum CamFilter: String, CaseIterable {
    case none, document, mono, vivid, classic, warm

    var title: String {
        switch self {
        case .none: L("Gốc")
        case .document: L("Tài liệu")
        case .mono: L("Trắng đen")
        case .vivid: L("Tươi")
        case .classic: L("Cổ điển")
        case .warm: L("Ấm")
        }
    }

    func apply(_ img: CIImage) -> CIImage {
        switch self {
        case .none: return img
        case .document:
            // Hoá đơn: bỏ màu, tăng tương phản và sáng cho chữ rõ trên nền giấy
            let f = CIFilter.colorControls(); f.inputImage = img; f.saturation = 0; f.contrast = 1.55; f.brightness = 0.06
            return f.outputImage ?? img
        case .mono:
            let f = CIFilter.photoEffectNoir(); f.inputImage = img; return f.outputImage ?? img
        case .vivid:
            let f = CIFilter.colorControls(); f.inputImage = img; f.saturation = 1.35; f.contrast = 1.08
            return f.outputImage ?? img
        case .classic:
            let f = CIFilter.photoEffectTransfer(); f.inputImage = img; return f.outputImage ?? img
        case .warm:
            let f = CIFilter.temperatureAndTint(); f.inputImage = img
            f.neutral = CIVector(x: 6500, y: 0); f.targetNeutral = CIVector(x: 5200, y: 0)
            return f.outputImage ?? img
        }
    }

    nonisolated(unsafe) static let context = CIContext()

    /// Cài đặt: lưu ảnh chụp trong Pay vào app Ảnh (mặc định bật, như app máy ảnh)
    static let saveKey = "cam.saveToPhotos"

    /// Chỉ xin quyền thêm ảnh (không đọc thư viện); bị từ chối thì thôi, ảnh vẫn đính kèm khoản chi
    static func saveToPhotos(_ img: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { s in
            guard s == .authorized || s == .limited else { return }
            PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: img) }
        }
    }

    /// Ảnh chụp: xoay đúng chiều, cắt giữa theo tỉ lệ khung (khung xem là phần giữa của cảm biến), rồi qua bộ lọc
    static func develop(_ src: UIImage, ratio: CGFloat, filter: CamFilter) -> UIImage {
        let up = UIGraphicsImageRenderer(size: src.size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
            .image { _ in src.draw(in: CGRect(origin: .zero, size: src.size)) }
        guard var ci = CIImage(image: up) else { return up }
        let e = ci.extent
        var crop = e
        if e.width / e.height > ratio { crop.size.width = e.height * ratio; crop.origin.x = e.midX - crop.width / 2 }
        else { crop.size.height = e.width / ratio; crop.origin.y = e.midY - crop.height / 2 }
        ci = filter.apply(ci.cropped(to: crop))
        guard let cg = context.createCGImage(ci, from: ci.extent) else { return up }
        return UIImage(cgImage: cg)
    }
}

/// Lưới 3 × 3
private struct GridLines: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in 1...2 {
            let x = r.minX + r.width * CGFloat(i) / 3, y = r.minY + r.height * CGFloat(i) / 3
            p.move(to: CGPoint(x: x, y: r.minY)); p.addLine(to: CGPoint(x: x, y: r.maxY))
            p.move(to: CGPoint(x: r.minX, y: y)); p.addLine(to: CGPoint(x: r.maxX, y: y))
        }
        return p
    }
}

/// Bốn góc ngoặc quanh chữ tỉ lệ
private struct CornerMarks: Shape {
    func path(in r: CGRect) -> Path {
        let l: CGFloat = 8
        var p = Path()
        for (cx, cy, dx, dy) in [(r.minX, r.minY, 1.0, 1.0), (r.maxX, r.minY, -1.0, 1.0), (r.minX, r.maxY, 1.0, -1.0), (r.maxX, r.maxY, -1.0, -1.0)] {
            p.move(to: CGPoint(x: cx + l * dx, y: cy)); p.addLine(to: CGPoint(x: cx, y: cy)); p.addLine(to: CGPoint(x: cx, y: cy + l * dy))
        }
        return p
    }
}

/// Camera của màn chụp: ảnh tĩnh, khung hình xem trước qua bộ lọc, nhiệt độ màu / độ sáng / thu phóng của máy, đèn, đổi camera
@MainActor
final class ReceiptCam: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let videoOut = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "pay.cam.video")
    private var input: AVCaptureDeviceInput?
    private var device: AVCaptureDevice? { input?.device }
    private var configured = false
    private var onPhoto: ((UIImage?) -> Void)?
    @Published var error: String?
    @Published var frame: CGImage?
    @Published var warmth: Float = 0
    @Published var exposure: Float = 0
    @Published var flashMode: AVCaptureDevice.FlashMode = .off
    /// Tiêu cự đang dùng, tính theo camera chính = 1x
    @Published private(set) var zoom: CGFloat = 1
    @Published private(set) var minZoom: CGFloat = 1
    @Published private(set) var maxZoom: CGFloat = 10
    private var zoomSteps: [CGFloat] = [1, 2]
    private var zoomIndex = 0
    /// Hệ số thu phóng của máy ứng với "1x" (camera ảo có góc siêu rộng: 1x là camera chính, nằm ở mốc chuyển thứ nhất)
    private var zoomBase: CGFloat = 1
    var filter: CamFilter = .none { didSet { liveFilter = filter; if filter == .none { frame = nil } } }
    nonisolated(unsafe) private var liveFilter: CamFilter = .none
    nonisolated(unsafe) private var lastFrame = Date.distantPast

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            Task { @MainActor in
                guard ok else { self.error = L("Hãy cho phép Pay dùng camera trong Cài đặt của iPhone, hoặc bấm \"Chọn ảnh\"."); return }
                self.configure()
            }
        }
    }

    private static func camera(_ pos: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if pos == .front { return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) }
        return AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    private func configure() {
        if !configured {
            guard let d = Self.camera(.back), let inp = try? AVCaptureDeviceInput(device: d),
                  session.canAddInput(inp), session.canAddOutput(output) else {
                error = L("Không mở được camera. Bấm \"Chọn ảnh\" để dùng ảnh có sẵn."); return
            }
            session.beginConfiguration()
            session.sessionPreset = .photo
            session.addInput(inp)
            session.addOutput(output)
            videoOut.alwaysDiscardsLateVideoFrames = true
            videoOut.setSampleBufferDelegate(self, queue: videoQueue)
            if session.canAddOutput(videoOut) { session.addOutput(videoOut) }
            session.commitConfiguration()
            input = inp
            orientVideo()
            setupZoom()
            configured = true
        }
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { if !s.isRunning { s.startRunning() } }
    }

    private func orientVideo() {
        guard let c = videoOut.connection(with: .video) else { return }
        if c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
        if c.isVideoMirroringSupported { c.isVideoMirrored = device?.position == .front }
    }

    private func setupZoom() {
        guard let d = device else { return }
        let wide = d.deviceType == .builtInTripleCamera || d.deviceType == .builtInDualWideCamera
        zoomBase = wide ? CGFloat(d.virtualDeviceSwitchOverVideoZoomFactors.first?.doubleValue ?? 2) : 1
        // Camera sau mở ở 1.2x (gần hoá đơn hơn, ít méo hơn 1x); bấm nhãn tiêu cự xoay vòng các mốc, mốc đầu là mặc định
        zoomSteps = d.position == .front ? [1] : wide ? [1.2, 0.5, 2] : [1.2, 2]
        minZoom = d.minAvailableVideoZoomFactor / zoomBase
        maxZoom = max(minZoom, min(d.maxAvailableVideoZoomFactor / zoomBase, 15))
        zoomIndex = 0
        setZoom(zoomSteps[0])
    }

    func nextZoom() {
        guard zoomSteps.count > 1 else { return }
        zoomIndex = (zoomIndex + 1) % zoomSteps.count
        setZoom(zoomSteps[zoomIndex])
    }

    /// Tiêu cự liền (vuốt vòng tiêu cự), kẹp trong khoảng máy làm được
    func setZoom(_ z: CGFloat) {
        zoom = min(max(z, minZoom), maxZoom)
        guard let d = device, (try? d.lockForConfiguration()) != nil else { return }
        d.videoZoomFactor = min(max(zoom * zoomBase, d.minAvailableVideoZoomFactor), d.maxAvailableVideoZoomFactor)
        d.unlockForConfiguration()
    }

    /// -1 lạnh … 1 ấm; 0 là cân bằng trắng tự động
    func setWarmth(_ w: Float) {
        warmth = w
        guard let d = device, (try? d.lockForConfiguration()) != nil else { return }
        defer { d.unlockForConfiguration() }
        if abs(w) < 0.03 {
            if d.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { d.whiteBalanceMode = .continuousAutoWhiteBalance }
            return
        }
        guard d.isLockingWhiteBalanceWithCustomDeviceGainsSupported else { return }
        // Báo cho máy là ánh sáng có nhiệt độ cao hơn → ảnh ngả ấm, thấp hơn → ngả lạnh
        var g = d.deviceWhiteBalanceGains(for: .init(temperature: 5500 + w * 3000, tint: 0))
        let m = d.maxWhiteBalanceGain
        g.redGain = min(max(g.redGain, 1), m); g.greenGain = min(max(g.greenGain, 1), m); g.blueGain = min(max(g.blueGain, 1), m)
        d.setWhiteBalanceModeLocked(with: g)
    }

    /// Bù sáng, -2 … 2 EV
    func setExposure(_ v: Float) {
        exposure = (v * 10).rounded() / 10
        guard let d = device, (try? d.lockForConfiguration()) != nil else { return }
        d.setExposureTargetBias(min(max(exposure, d.minExposureTargetBias), d.maxExposureTargetBias))
        d.unlockForConfiguration()
    }

    func nextFlash() {
        flashMode = flashMode == .off ? .auto : flashMode == .auto ? .on : .off
    }

    func flip() {
        guard configured, let cur = input, let d = Self.camera(cur.device.position == .back ? .front : .back),
              let inp = try? AVCaptureDeviceInput(device: d) else { return }
        session.beginConfiguration()
        session.removeInput(cur)
        if session.canAddInput(inp) { session.addInput(inp); input = inp } else { session.addInput(cur) }
        session.commitConfiguration()
        orientVideo()
        setupZoom()
        let w = warmth, e = exposure
        setWarmth(w); setExposure(e)
    }

    func stop() {
        let s = session
        DispatchQueue.global().async { if s.isRunning { s.stopRunning() } }
    }

    func capture(_ done: @escaping (UIImage?) -> Void) {
        #if targetEnvironment(simulator)
        if !configured { done(nil); return }
        #endif
        guard configured else { return }
        onPhoto = done
        let s = AVCapturePhotoSettings()
        if output.supportedFlashModes.contains(flashMode) { s.flashMode = flashMode }
        output.capturePhoto(with: s, delegate: self)
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let img = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        Task { @MainActor in self.onPhoto?(img); self.onPhoto = nil }
    }

    /// Khung xem qua bộ lọc: chỉ khi đang chọn bộ lọc, thu nhỏ còn ~900 px, tối đa ~24 hình / giây
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let f = liveFilter
        guard f != .none, Date().timeIntervalSince(lastFrame) > 0.04, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = Date()
        var ci = CIImage(cvPixelBuffer: pb)
        let s = min(1, 900 / max(ci.extent.width, ci.extent.height))
        ci = f.apply(ci.transformed(by: CGAffineTransform(scaleX: s, y: s)))
        guard let cg = CamFilter.context.createCGImage(ci, from: ci.extent) else { return }
        Task { @MainActor in if self.liveFilter != .none { self.frame = cg } }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.layer.session = session
        v.layer.videoGravity = .resizeAspectFill
        v.backgroundColor = .black
        return v
    }

    func updateUIView(_ v: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        override var layer: AVCaptureVideoPreviewLayer { super.layer as! AVCaptureVideoPreviewLayer }
    }
}

/// Thước tiêu cự, cùng kiểu thước hẹn giờ của Peek (TimerRuler): hàng nhãn, dải vạch, kim tam giác đứng yên ở giữa, thước
/// trôi dưới kim. Vạch sáng tới mốc đang chọn, tối phía sau; hai mép nhoè và mờ dần (smoothstep, nhoè từng vạch một).
/// Thang log: mỗi lần gấp đôi tiêu cự là một khoảng bằng nhau (0,5 → 1 → 2 cách đều)
struct ZoomRuler: View {
    let zoom: CGFloat, min: CGFloat, max: CGFloat
    /// Màu hổ phách như thước hẹn giờ của Peek
    static let amber = Color(red: 0xF0 / 255, green: 0x97 / 255, blue: 0x48 / 255)
    static let labels: [CGFloat] = [0.5, 1, 2, 3, 5, 10, 15]
    /// Điểm cho mỗi lần gấp đôi; kéo cũng theo tỉ lệ này nên vạch đi đúng theo tay
    static let perDouble: CGFloat = 120
    /// Số vạch mỗi lần gấp đôi: ~6,7 pt một vạch, như mật độ thước Peek
    private let ticksPerDouble = 18
    private let softenFrom = 0.40, fadeFrom = 0.72
    private let softenRadius: CGFloat = 4
    private let tickHeight: CGFloat = 24, labelHeight: CGFloat = 12, pointerHeight: CGFloat = 5
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            VStack(spacing: 3) {
                labelsRow(w)
                ticksRow(w)
                Triangle().fill(Self.amber).frame(width: 9, height: pointerHeight)
            }
            .frame(width: w)
        }
        .frame(height: labelHeight + tickHeight + pointerHeight + 6)
        .padding(.horizontal, 8)
    }

    private var cur: Double { log2(Double(zoom)) }
    private func x(_ v: Double, _ w: CGFloat) -> CGFloat { w / 2 + CGFloat(v - cur) * Self.perDouble }
    private func shade(_ v: Double) -> Color { v <= cur + 0.001 ? Self.amber : Self.amber.opacity(0.24) }

    private static func smooth(_ from: Double, _ d: Double) -> Double {
        let t = Swift.min(1, Swift.max(0, (d - from) / (1 - from))); return t * t * (3 - 2 * t)
    }
    @ViewBuilder private func soften<C: View>(_ c: C, at px: CGFloat, _ w: CGFloat) -> some View {
        let d = Swift.min(1, abs(Double(px - w / 2)) / Double(w / 2))
        let b = softenRadius * CGFloat(Self.smooth(softenFrom, d))
        let f = 1 - Self.smooth(fadeFrom, d)
        if b > 0.03 { c.blur(radius: b).opacity(f) } else { c.opacity(f) }
    }

    private func labelsRow(_ w: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Self.labels.filter { $0 >= min - 0.01 && $0 <= max + 0.01 }, id: \.self) { z in
                let v = log2(Double(z)), px = x(v, w)
                if px > -20 && px < w + 20 {
                    soften(Text(z < 1 ? ".5" : "\(Int(z))").font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(shade(v)), at: px, w)
                        .position(x: px, y: labelHeight / 2)
                }
            }
        }
        .frame(height: labelHeight)
    }

    private func ticksRow(_ w: CGFloat) -> some View {
        let lo = log2(Double(min)), hi = log2(Double(max))
        let half = Double(w / Self.perDouble) / 2 + 0.2
        let a = Int(((cur - half) * Double(ticksPerDouble)).rounded(.down))
        let b = Int(((cur + half) * Double(ticksPerDouble)).rounded(.up))
        let bar = Swift.max(1, (2.5 * displayScale).rounded()) / displayScale
        return ZStack(alignment: .topLeading) {
            ForEach(a...Swift.max(a, b), id: \.self) { i in
                let v = Double(i) / Double(ticksPerDouble), px = x(v, w)
                let outside = v < lo - 0.001 || v > hi + 0.001
                soften(Capsule().fill(outside ? Self.amber.opacity(0.1) : shade(v)).frame(width: bar, height: tickHeight), at: px, w)
                    .position(x: px, y: tickHeight / 2)
            }
        }
        .frame(height: tickHeight)
    }
}

/// Tam giác nhọn hướng lên, kim của thước
private struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath(); return p
    }
}
