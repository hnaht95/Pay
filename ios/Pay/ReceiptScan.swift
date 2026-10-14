import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Photos
import PhotosUI
import SwiftUI

/// Màn chụp hoá đơn / ảnh đính kèm, tối giản: khung xem bo góc (3:4), thu phóng ngay trên khung, nút chụp to ở giữa,
/// chọn ảnh có sẵn bên trái. Không có bộ lọc, lưới, tỉ lệ, hẹn giờ, đèn, đổi camera, nhiệt độ màu / độ sáng.
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
    @State private var dialShown = false
    @State private var dragStartZoom: CGFloat?
    @State private var dialHide: DispatchWorkItem?

    /// Khung cố định 3:4 (ảnh dọc), như ảnh của camera
    private let aspect = CamRatio.r34

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 8)
                viewfinder
                Spacer(minLength: 8)
                // Nút chụp và ô ảnh nâng cao hơn vạch Home một chút (trước sát quá, 8)
                bottomRow.padding(.top, 22).padding(.bottom, 28)
            }
            .padding(.horizontal, 16)
        }
        .overlay { Color.white.opacity(flash ? 0.7 : 0).ignoresSafeArea().allowsHitTesting(false) }
        .preferredColorScheme(.dark)
        // Chọn ảnh có sẵn (ảnh Pay đã chụp hoặc thư viện máy) cũng qua bước căn lại; chờ bảng chọn đóng hẳn rồi mới mở
        .onAppear { cam.filter = .none; cam.start() }
        .onDisappear { cam.stop() }
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
            // Lưới chia ba (như lưới của Camera iOS): giúp đặt hoá đơn thẳng và giữa khung. Không có trong ảnh chụp
            ThirdsGrid().allowsHitTesting(false)
            // Bộ lọc khác "Gốc": khung xem vẽ lại từng hình đã qua bộ lọc (giống ảnh sẽ chụp)
            if let e = cam.error {
                Text(e).font(.system(size: 16, weight: .medium)).foregroundStyle(.white).multilineTextAlignment(.center).padding(28)
            }
            // Vòng tiêu cự (đang vuốt trái / phải ở chỗ số tiêu cự): nửa vòng tròn chia vạch như Camera của iOS
            if dialShown {
                ZoomDial(zoom: cam.zoom, min: cam.minZoom, max: cam.maxZoom)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            VStack(spacing: 10) {
                Spacer()
                zoomControl.padding(.bottom, 10)
            }
        }
        .aspectRatio(aspect.value, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(shape)
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
                    // Kéo sang phải: vạch chạy sang phải, nấc nhỏ hơn về giữa (như Camera của iOS); ~110 pt mỗi lần gấp đôi
                    let z = (dragStartZoom ?? 1) * pow(2, -v.translation.width / 110)
                    let old = cam.zoom
                    cam.setZoom(z)
                    if ZoomDial.majors.contains(where: { (old - $0) * (cam.zoom - $0) < 0 }) { Haptic.select() }
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

    // MARK: Hàng dưới: chọn ảnh, chụp, bộ lọc

    private var bottomRow: some View {
        HStack {
            // Ảnh mới nhất trong app Ảnh (khung dọc bo góc); chạm: chọn ảnh từ thư viện máy, xong qua bước căn lại như ảnh chụp
            PhotosPicker(selection: $photo, matching: .images) { LatestPhotoTile() }
                .buttonStyle(Pressable())
                .frame(width: 58, height: 58)
                .accessibilityLabel(L("Chọn ảnh"))
            Spacer()
            Button(action: shoot) {
                Capsule().fill(Color(hex: 0xE8EBDD))
                    // Chấm trang trí: 2 hàng × 3 chấm, cách đều, căn giữa nút
                    .overlay {
                        Grid(horizontalSpacing: 9, verticalSpacing: 9) {
                            ForEach(0..<2, id: \.self) { _ in
                                GridRow { ForEach(0..<3, id: \.self) { _ in Circle().frame(width: 7, height: 7) } }
                            }
                        }
                        .foregroundStyle(.black.opacity(0.25))
                    }
                    .frame(width: 170, height: 76)
                    .padding(6)
                    .background(Capsule().fill(.white.opacity(0.08)))
            }
            .buttonStyle(Pressable())
            .accessibilityLabel(L("Chụp"))
            Spacer()
            // Chỗ trống cùng cỡ ô ảnh bên trái, để nút chụp nằm giữa
            Color.clear.frame(width: 58, height: 58)
        }
    }

    // MARK: Chụp

    private func shoot() { snap() }

    private func snap() {
        // Rung một nhịp như nút chụp của Camera, màn loé trắng thoáng qua
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        flash = true
        withAnimation(.easeOut(duration: 0.35)) { flash = false }
        let r = aspect.value, f = CamFilter.none
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
        zoomSteps = d.position == .front ? [1] : wide ? [1, 0.5, 2] : [1, 2]
        minZoom = d.minAvailableVideoZoomFactor / zoomBase
        maxZoom = max(minZoom, min(d.maxAvailableVideoZoomFactor / zoomBase, 15))
        zoomIndex = 0
        setZoom(1)
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

/// Hai vạch dọc, hai vạch ngang chia khung làm ba, nét mảnh trắng mờ có bóng nhẹ để thấy được trên cả nền sáng
private struct ThirdsGrid: View {
    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            for i in 1...2 {
                let x = (size.width * CGFloat(i) / 3).rounded(), y = (size.height * CGFloat(i) / 3).rounded()
                p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
            }
            ctx.stroke(p, with: .color(.black.opacity(0.15)), lineWidth: 1.5)
            ctx.stroke(p, with: .color(.white.opacity(0.45)), lineWidth: 0.75)
        }
        .accessibilityHidden(true)
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

/// Vòng tiêu cự: nửa vòng tròn tối ở đáy khung, vạch chia theo thang log (mỗi lần gấp đôi một khoảng bằng nhau), số ở các nấc
/// chính, nấc đang chọn ở đỉnh vòng màu vàng kèm tiêu cự tương đương (mm)
struct ZoomDial: View {
    let zoom: CGFloat, min: CGFloat, max: CGFloat
    static let majors: [CGFloat] = [0.5, 1, 2, 3, 5, 10, 15]
    /// Góc cho mỗi lần gấp đôi tiêu cự
    private static let perDouble = 34.0

    var body: some View {
        Canvas { ctx, size in
            let r = size.width * 0.78
            let c = CGPoint(x: size.width / 2, y: size.height + r - 150)
            // Nền nửa vòng
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r - 30, y: c.y - r - 30, width: (r + 30) * 2, height: (r + 30) * 2)),
                     with: .color(.black.opacity(0.45)))
            func angle(_ v: CGFloat) -> Double { (log2(Double(v)) - log2(Double(zoom))) * Self.perDouble }
            func point(_ deg: Double, _ rad: CGFloat) -> CGPoint {
                let a = (deg - 90) * .pi / 180
                return CGPoint(x: c.x + rad * CGFloat(cos(a)), y: c.y + rad * CGFloat(sin(a)))
            }
            // Vạch nhỏ cách đều nhau theo góc (thang log: mỗi lần gấp đôi tiêu cự là 12 vạch), mốc ở 1x nên vạch đứng yên trên vòng
            // khi xoay; chỉ vẽ trong khoảng máy làm được. Vạch quá gần một nấc chính thì bỏ, nấc chính vẽ riêng đúng vị trí của nó.
            // Hai mép mờ dần
            let step = Self.perDouble / 12
            let lo = log2(Double(min)) * Self.perDouble, hi = log2(Double(max)) * Self.perDouble
            let majorAngles = Self.majors.filter { $0 >= min - 0.01 && $0 <= max + 0.01 }.map { log2(Double($0)) * Self.perDouble }
            let cur = log2(Double(zoom)) * Self.perDouble
            // Góc của mép khung (vòng rộng hơn khung): vạch, số chỉ vẽ trong phần nhìn thấy, mờ dần tới mép
            let edge = asin(Double(Swift.min(1, size.width / 2 / r))) * 180 / .pi
            func fade(_ deg: Double) -> Double { Swift.max(0, Swift.min(1, (edge - abs(deg)) / 12)) }
            var k = (lo / step).rounded(.up)
            while k * step <= hi + 0.001 {
                let at = k * step, deg = at - cur
                k += 1
                guard abs(deg) < edge, !majorAngles.contains(where: { abs($0 - at) < step * 0.5 }) else { continue }
                var p = Path(); p.move(to: point(deg, r)); p.addLine(to: point(deg, r - 11))
                ctx.stroke(p, with: .color(.white.opacity(0.5 * fade(deg))), lineWidth: 1)
            }
            for at in majorAngles {
                let deg = at - cur
                guard abs(deg) < edge else { continue }
                var p = Path(); p.move(to: point(deg, r)); p.addLine(to: point(deg, r - 20))
                ctx.stroke(p, with: .color(.white.opacity(0.95 * fade(deg))), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            // Số ở nấc chính (trừ chỗ đang chọn, chỗ đó vẽ số vàng)
            for m in Self.majors where m >= min - 0.01 && m <= max + 0.01 {
                let deg = angle(m)
                guard abs(deg) < edge - 6, abs(deg) > 9 else { continue }
                let s = m < 1 ? "0,5" : "\(Int(m))"
                ctx.draw(Text(s).font(.system(size: 15, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(fade(deg))),
                         at: point(deg, r - 38))
            }
            // Nấc đang chọn: tam giác vàng ở đỉnh, số và mm
            var tri = Path()
            tri.move(to: CGPoint(x: c.x - 5, y: c.y - r - 4)); tri.addLine(to: CGPoint(x: c.x + 5, y: c.y - r - 4))
            tri.addLine(to: CGPoint(x: c.x, y: c.y - r + 6)); tri.closeSubpath()
            ctx.fill(tri, with: .color(Color(hex: 0xFFD43B)))
            let z = (zoom * 10).rounded() / 10
            let label = (z == z.rounded() ? "\(Int(z))" : String(format: "%.1f", z)).replacingOccurrences(of: ".", with: ",") + "×"
            ctx.draw(Text(label).font(.system(size: 20, weight: .semibold, design: .monospaced)).foregroundStyle(Color(hex: 0xFFD43B)),
                     at: CGPoint(x: c.x, y: c.y - r + 40))
            ctx.draw(Text("\(Int((24 * zoom).rounded())) MM").font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(hex: 0xFFD43B)),
                     at: CGPoint(x: c.x, y: c.y - r + 64))
        }
    }
}
