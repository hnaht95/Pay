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
    /// Đổi số này để màn chụp nhận chụp tiếp sau khi đã chụp xong một ảnh (quay lại từ màn nhập), giữ nguyên camera đang chạy
    var resume = 0
    /// Nút về trang chủ bên phải nút chụp (chụp hoá đơn mở từ trang chủ). Không có thì chỗ đó để trống
    var home: (() -> Void)? = nil
    var done: (UIImage?) -> Void
    @StateObject private var cam = ReceiptCam()
    @State private var photo: PhotosPickerItem?
    @State private var finished = false
    @State private var flash = false
    /// Số lần đổi camera trước / sau (để xoay biểu tượng)
    @State private var flips = 0
    /// Lật khung xem lúc đổi camera (như app Camera): góc quay quanh trục dọc, và lớp mờ phủ hình trong lúc lật
    @State private var flipAngle: Double = 0
    @State private var flipVeil = false
    @State private var flipping = false
    private let flipHaptic = UIImpactFeedbackGenerator(style: .medium)
    /// Ảnh vừa chụp / vừa chọn từ thư viện, đang chờ căn lại (dời, phóng to) trước khi dùng
    @State private var review: CropItem?
    /// Ảnh đang căn là ảnh vừa chụp (căn xong mới lưu vào ảnh Pay đã chụp / Ảnh của máy); ảnh chọn từ thư viện thì không lưu lại
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
        .preferredColorScheme(.dark)
        // Ảnh chọn từ thư viện máy qua bước căn vào khung 3:4; chờ bảng chọn đóng hẳn rồi mới mở
        .onAppear { cam.filter = .none; cam.start(); flipHaptic.prepare() }
        .onChange(of: resume) { finished = false }
        .onDisappear { cam.stop() }
        .task(id: photo) {
            guard let item = photo, let data = try? await item.loadTransferable(type: Data.self), !Task.isCancelled,
                  let img = UIImage(data: data) else { return }
            review = CropItem(image: img)
        }
        // Ảnh chọn từ thư viện: căn vào khung 3:4 như ảnh chụp (kéo để dời, chụm để phóng to vào phần cần lấy). Ảnh chụp thì
        // dùng luôn, không qua bước này (xem snap)
        .fullScreenCover(item: $review) { c in
            ImageCropper(image: c.image, aspect: aspect.value, maxPixel: 2400, cancelTitle: nil) { img in
                review = nil
                photo = nil
                guard let img else { return }
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
            // Đèn flash: chạm đổi lần lượt tắt → tự động → bật. Camera không có đèn (thường là camera trước) thì ẩn
            if cam.hasFlash { flashButton }
        }
        .foregroundStyle(.white)
        .buttonStyle(Pressable())
    }

    private var flashButton: some View {
        let m = cam.flashMode
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            cam.nextFlash()
        } label: {
            Image(systemName: m == .on ? "bolt.fill" : m == .auto ? "bolt.badge.automatic" : "bolt.slash")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(m == .on ? .yellow : .white)
                .frame(width: 44, height: 44)
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel(m == .on ? L("Đèn flash: bật") : m == .auto ? L("Đèn flash: tự động") : L("Đèn flash: tắt"))
    }

    // MARK: Khung xem

    private var viewfinder: some View {
        let shape = RoundedRectangle(cornerRadius: 32, style: .continuous)
        return ZStack {
            Color(hex: 0x1C1C1E)
            CameraPreview(session: cam.session)
                // Lớp kính mờ che hình trong lúc lật: nửa đầu hình cũ mờ đi, nửa sau hình camera mới hiện dần ra
                .overlay { Rectangle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark).opacity(flipVeil ? 1 : 0) }
                .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            // Chụp: khung xem tối sầm thoáng qua (như màn trập của Camera), chỉ trong khung, phần còn lại của màn để nguyên
            Color.black.opacity(flash ? 0.85 : 0).allowsHitTesting(false)
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
                // Số tiêu cự ở giữa; nút đổi camera ngang hàng bên phải, cùng cỡ và kiểu với số (trắng, có bóng mờ)
                zoomControl
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .trailing) { flipButton.opacity(dialShown ? 0 : 1) }
                    .padding(.bottom, 10)
            }
        }
        .aspectRatio(aspect.value, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(shape)
        .animation(.easeOut(duration: 0.2), value: dialShown)
    }

    /// Đổi camera như app Camera: rung ngay khi chạm, khung xem lật nửa vòng quanh trục dọc và mờ đi. Đổi camera bắt đầu ngay lúc
    /// chạm, chạy song song với nửa đầu hiệu ứng (trước đây đợi lật xong nửa đầu mới đổi, cộng dồn hai khoảng thời gian); xong thì
    /// lật nốt về và hiện hình camera mới
    private func flipCamera() {
        guard !flipping else { return }
        flipping = true
        flipHaptic.impactOccurred()
        withAnimation(.snappy(duration: 0.35)) { flips += 1 }
        withAnimation(.easeIn(duration: 0.16)) { flipAngle = 90; flipVeil = true }
        Task {
            let started = Date()
            await cam.flip()
            // Nửa đầu chưa lật xong thì đợi cho xong, khỏi giật
            let left = 0.16 - Date().timeIntervalSince(started)
            if left > 0 { try? await Task.sleep(for: .milliseconds(Int(left * 1000))) }
            flipAngle = -90
            withAnimation(.easeOut(duration: 0.22)) { flipAngle = 0 }
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.easeOut(duration: 0.2)) { flipVeil = false }
            flipping = false
        }
    }

    /// Đổi camera trước / sau; biểu tượng xoay nửa vòng mỗi lần chạm
    private var flipButton: some View {
        Button { flipCamera() } label: {
            Group {
                if #available(iOS 18.0, *) { Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90") }
                else { Image(systemName: "arrow.triangle.2.circlepath") }   // biểu tượng trên chưa có ở iOS 17
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .rotationEffect(.degrees(Double(flips) * 180))
            // Nền tròn kính mờ (nhoè hình camera phía sau), để biểu tượng rõ trên mọi cảnh
            .frame(width: 40, height: 40)
            .background(.ultraThinMaterial, in: Circle())
            .environment(\.colorScheme, .dark)
            .frame(width: 52, height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(Pressable())
        .padding(.trailing, 6)
        .accessibilityLabel(L("Đổi camera"))
    }

    /// Mức thu phóng như app Camera (1× · 2× · 0,5×), chữ đơn cách, không nền. Chạm: đổi nấc; vuốt trái / phải: thu phóng liền,
    /// hiện vòng tiêu cự (có thêm số mm)
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

    private func zoomText(_ z: CGFloat) -> String { ReceiptCam.times(z) }

    // MARK: Hàng dưới: chọn ảnh, chụp, bộ lọc

    /// Ô ảnh và nút về trang chủ đứng giữa khoảng trống hai bên nút chụp (giữa mép màn và mép nút chụp)
    private var bottomRow: some View {
        HStack(spacing: 0) {
            // Hai ảnh mới nhất trong app Ảnh; chạm: chọn ảnh từ thư viện máy, xong căn vào khung 3:4 như ảnh chụp
            PhotosPicker(selection: $photo, matching: .images) {
                LatestPhotoTile().frame(width: 60, height: 68).contentShape(Rectangle())
            }
            .buttonStyle(Pressable())
            .accessibilityLabel(L("Chọn ảnh"))
            .frame(maxWidth: .infinity)
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
            Group {
                if let home {
                    Button(action: home) {
                        // Biểu tượng nhà của SF Symbols, nét dày vừa, không khung nền
                        Image(systemName: "house").font(.system(size: 25, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                            .frame(width: 60, height: 68)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(Pressable())
                    .accessibilityLabel(L("Về trang chủ"))
                } else {
                    Color.clear.frame(width: 60, height: 68)
                }
            }
            .frame(maxWidth: .infinity)
        }
        // Tràn ra hai mép màn (bỏ lề 16 của màn chụp) để "giữa khoảng trống" tính từ mép màn
        .padding(.horizontal, -16)
    }

    // MARK: Chụp

    private func shoot() { snap() }

    private func snap() {
        // Rung một nhịp như nút chụp của Camera, khung xem tối sầm thoáng qua
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        flash = true
        withAnimation(.easeOut(duration: 0.35)) { flash = false }
        let r = aspect.value, f = CamFilter.none
        cam.capture { img in
            guard let img else { finish(nil); return }
            // Cắt đúng khung 3:4 đang xem rồi dùng luôn, không mở bước căn lại
            let out = CamFilter.develop(img, ratio: r, filter: f)
            if UserDefaults.standard.object(forKey: CamFilter.saveKey) as? Bool ?? true { CamFilter.saveToPhotos(out) }
            finish(out)
        }
    }

    private func finish(_ img: UIImage?) {
        guard !finished else { return }
        finished = true
        // Camera vẫn chạy dưới màn nhập (xem ReceiptFlow): Huỷ ở màn nhập thì quay lại chụp tiếp ngay, không phải bật lại camera
        // (bật lại thì khung xem đen một nhịp). Màn chụp đóng hẳn mới tắt (onDisappear)
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
    /// Chế độ đèn flash, app nhớ cho lần sau
    @Published var flashMode: AVCaptureDevice.FlashMode = AVCaptureDevice.FlashMode(rawValue: UserDefaults.standard.integer(forKey: ReceiptCam.flashKey)) ?? .off {
        didSet { UserDefaults.standard.set(flashMode.rawValue, forKey: Self.flashKey) }
    }
    nonisolated static let flashKey = "receiptFlash"
    /// Camera đang dùng có đèn flash (camera trước thường không có): không có thì ẩn nút
    @Published private(set) var hasFlash = false
    /// Tiêu cự đang dùng, tính theo camera chính = 1x
    @Published private(set) var zoom: CGFloat = 1
    @Published private(set) var minZoom: CGFloat = 1
    @Published private(set) var maxZoom: CGFloat = 10
    private var zoomSteps: [CGFloat] = [1, 2]
    /// Như app Camera: mở ở 1× (camera chính, 24 mm)
    static let startZoom: CGFloat = 1
    /// Tiêu cự quy đổi ra phim 35 mm ứng với mức thu phóng (camera chính iPhone đời mới: 24 mm)
    nonisolated static func mm(_ zoom: CGFloat) -> Int { Int((24 * zoom).rounded()) }
    /// Mức thu phóng dạng app Camera: "1×", "2×", "0,5×", "1,3×" (dấu phẩy thập phân kiểu Việt)
    nonisolated static func times(_ zoom: CGFloat) -> String {
        let z = (zoom * 10).rounded() / 10
        let s = z == z.rounded() ? "\(Int(z))" : String(format: "%.1f", z).replacingOccurrences(of: ".", with: ",")
        return s + "×"
    }
    private var zoomIndex = 0
    var filter: CamFilter = .none { didSet { liveFilter = filter; if filter == .none { frame = nil } } }
    nonisolated(unsafe) private var liveFilter: CamFilter = .none
    nonisolated(unsafe) private var lastFrame = Date.distantPast

    /// Khởi động trước phần nặng của camera lúc app vừa mở (đã có quyền camera): tìm các ống kính, tạo đầu vào, dựng thử một phiên
    /// chụp rồi bỏ. Lần đầu mở camera sau khi mở app, iOS phải làm mấy việc này (kết nối dịch vụ camera, nạp thông tin ống kính)
    /// nên chậm hẳn; làm sẵn trong nền thì lần vuốt đầu cũng mở nhanh như các lần sau. Không bật camera (không có chấm xanh)
    static func prewarm() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        LatestPhoto.prewarm()
        let devices = [wide, ultra, front].compactMap { $0 }
        sessionQueue.async {
            let s = AVCaptureSession()
            s.beginConfiguration()
            s.sessionPreset = .photo
            if let d = devices.first, let inp = try? AVCaptureDeviceInput(device: d), s.canAddInput(inp) { s.addInput(inp) }
            let out = AVCapturePhotoOutput()
            if s.canAddOutput(out) { s.addOutput(out) }
            s.commitConfiguration()
            for d in devices.dropFirst() { _ = try? AVCaptureDeviceInput(device: d) }
        }
    }

    /// Phiên chụp bật sớm (lệnh Chụp hoá đơn): camera chạy sẵn trong lúc app còn đang mở màn chụp. Màn chụp bật phiên của nó
    /// thì tắt phiên này; camera đã nóng nên phiên của màn chụp lên gần như ngay. Không ai dùng tới thì tự tắt sau 5 giây
    nonisolated(unsafe) private static var warm: AVCaptureSession?
    /// Màn chụp đang mở (camera thật đang chạy): không dựng phiên khởi động trước nữa, hai phiên cùng một camera thì phiên đang
    /// xem bị ngắt
    nonisolated(unsafe) private static var live = false

    static func warmStart() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized, let d = back(for: startZoom) else { return }
        sessionQueue.async {
            guard warm == nil, !live else { return }
            let s = AVCaptureSession()
            s.beginConfiguration()
            s.sessionPreset = .photo
            if let inp = try? AVCaptureDeviceInput(device: d), s.canAddInput(inp) { s.addInput(inp) }
            let out = AVCapturePhotoOutput()
            if s.canAddOutput(out) { s.addOutput(out) }
            s.commitConfiguration()
            s.startRunning()
            warm = s
            sessionQueue.asyncAfter(deadline: .now() + 5) { if warm === s { s.stopRunning(); warm = nil } }
        }
    }

    func start() {
        Self.sessionQueue.async { Self.live = true }
        AVCaptureDevice.requestAccess(for: .video) { ok in
            Task { @MainActor in
                guard ok else { self.error = L("Hãy cho phép Payso dùng camera trong Cài đặt của iPhone, hoặc bấm \"Chọn ảnh\"."); return }
                self.configure()
            }
        }
    }

    /// Mọi việc nặng với phiên chụp (bật, đổi camera) chạy lần lượt trên một hàng đợi riêng, như Apple hướng dẫn: không chiếm
    /// luồng chính, và không chạy chồng lên nhau (bật camera chưa xong đã đổi camera thì chậm, có khi lỗi)
    nonisolated static let sessionQueue = DispatchQueue(label: "pay.cam.session", qos: .userInitiated)

    /// Camera trước và hai ống camera sau, mỗi cái là một camera vật lý riêng (một ống kính). Không dùng camera "ghép" của iOS
    /// (ghép hai / ba ống, tự chuyển ống khi phóng): mỗi lần gắn vào phiên chụp nó phải khởi động mọi ống bên trong, nên đổi từ
    /// camera trước về camera sau chậm hẳn so với chiều ngược lại. Các app chụp ảnh khác cũng dùng camera vật lý và tự đổi ống:
    /// camera trước ↔ camera sau giờ cùng là một ống, nhanh như nhau
    private static let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
    private static let wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    private static let ultra = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)

    /// Camera sau cho mức thu phóng `z`: dưới 1× là ống góc siêu rộng (nếu máy có), còn lại ống chính
    private static func back(for z: CGFloat) -> AVCaptureDevice? { z < 1 ? (ultra ?? wide) : wide }

    /// Ống góc siêu rộng ứng với 0,5×: hệ số phóng của nó = mức thu phóng / 0,5
    nonisolated private static func lensZoom(_ d: AVCaptureDevice) -> CGFloat { d.deviceType == .builtInUltraWideCamera ? 0.5 : 1 }

    private func configure() {
        if !configured {
            guard let d = Self.back(for: Self.startZoom), let inp = try? AVCaptureDeviceInput(device: d),
                  session.canAddInput(inp), session.canAddOutput(output) else {
                error = L("Không mở được camera. Bấm \"Chọn ảnh\" để dùng ảnh có sẵn."); return
            }
            prepareZoom(d, to: Self.startZoom)
            session.beginConfiguration()
            session.sessionPreset = .photo
            session.addInput(inp)
            session.addOutput(output)
            // Không gắn đầu ra khung hình (videoOut): chỉ dùng cho bộ lọc xem trước, mà màn chụp đã bỏ bộ lọc. Gắn thêm nó thì mỗi lần
            // đổi camera phiên chụp phải dựng thêm một luồng khung hình, đổi camera chậm hẳn
            session.commitConfiguration()
            input = inp
            hasFlash = d.hasFlash
            // Đặt lại tiêu cự sau khi cấu hình xong: đổi sessionPreset / gắn camera làm camera về định dạng mới, tiêu cự đặt trước
            // đó bị trả về mặc định trong khi số vẫn hiện mức cũ. Phiên chưa chạy nên khung đầu tiên đã đúng tiêu cự
            Self.apply(zoom, to: d)
            configured = true
        }
        let s = session
        Self.sessionQueue.async {
            // Phiên bật sớm (nếu có) nhường camera cho phiên của màn chụp
            if let w = Self.warm { w.stopRunning(); Self.warm = nil }
            if !s.isRunning { s.startRunning() }
        }
    }


    /// Tiêu cự camera sau lúc chuyển sang camera trước: quay lại camera sau thì về đúng tiêu cự này (như app Camera), không
    /// đặt lại 1×
    private var backZoom: CGFloat = ReceiptCam.startZoom

    /// Đặt các nấc thu phóng cho phía camera của `d` và đặt sẵn tiêu cự `target` lên `d`. Gọi trước khi gắn camera vào phiên chụp:
    /// gắn xong mới đặt thì vài khung hình đầu ra ở tiêu cự mặc định rồi mới nhảy về tiêu cự đúng
    private func prepareZoom(_ d: AVCaptureDevice, to target: CGFloat) {
        let isBack = d.position == .back
        // Như app Camera: camera sau mở ở 1×, chạm lần lượt 2× · 0,5× rồi về 1× (máy không có góc siêu rộng: 1× · 2×)
        zoomSteps = !isBack ? [1] : Self.ultra != nil ? [1, 2, 0.5] : [1, 2]
        minZoom = isBack && Self.ultra != nil ? 0.5 : 1
        maxZoom = max(minZoom, min((isBack ? Self.wide ?? d : d).maxAvailableVideoZoomFactor, 15))
        zoom = min(max(target, minZoom), maxZoom)
        // Nấc gần nhất với tiêu cự đặt lại, để chạm tiếp đi sang nấc kế tiếp như thường
        zoomIndex = zoomSteps.indices.min { abs(zoomSteps[$0] - zoom) < abs(zoomSteps[$1] - zoom) } ?? 0
        Self.apply(zoom, to: d)
    }

    /// Đặt hệ số phóng lên camera vật lý `d` cho mức thu phóng `z` (tính theo ống chính = 1×)
    nonisolated private static func apply(_ z: CGFloat, to d: AVCaptureDevice) {
        guard (try? d.lockForConfiguration()) != nil else { return }
        d.videoZoomFactor = min(max(z / lensZoom(d), d.minAvailableVideoZoomFactor), d.maxAvailableVideoZoomFactor)
        d.unlockForConfiguration()
    }

    /// Gắn camera `d` thay camera đang dùng (đổi trước / sau, hoặc đổi ống khi phóng qua mốc 1×), đặt tiêu cự `z`. Chạy trên hàng
    /// đợi của phiên chụp, không chiếm luồng chính
    private func attach(_ d: AVCaptureDevice, zoom z: CGFloat) async -> Bool {
        guard let cur = input else { return false }
        let s = session
        let inp: AVCaptureDeviceInput? = await withCheckedContinuation { done in
            Self.sessionQueue.async {
                guard let inp = try? AVCaptureDeviceInput(device: d) else { done.resume(returning: nil); return }
                Self.apply(z, to: d)
                s.beginConfiguration()
                s.removeInput(cur)
                let ok = s.canAddInput(inp)
                if ok { s.addInput(inp) } else { s.addInput(cur) }
                s.commitConfiguration()
                if ok { Self.apply(z, to: d) }   // gắn xong tiêu cự có thể bị trả về mặc định: đặt lại
                done.resume(returning: ok ? inp : nil)
            }
        }
        guard let inp else { return false }
        input = inp
        hasFlash = d.hasFlash
        let w = warmth, e = exposure
        setWarmth(w); setExposure(e)
        return true
    }

    /// Đang đổi ống (phóng qua mốc 1×): mức thu phóng mới nhất trong lúc chờ, áp lên khi đổi xong
    private var lensSwapping = false
    private var pendingZoom: CGFloat?

    func nextZoom() {
        guard zoomSteps.count > 1 else { return }
        zoomIndex = (zoomIndex + 1) % zoomSteps.count
        setZoom(zoomSteps[zoomIndex])
    }

    /// Tiêu cự liền (vuốt vòng tiêu cự), kẹp trong khoảng máy làm được
    func setZoom(_ z: CGFloat) {
        zoom = min(max(z, minZoom), maxZoom)
        guard let d = device else { return }
        // Camera sau: phóng qua mốc 1× thì đổi ống (góc siêu rộng ↔ ống chính)
        if d.position == .back, let want = Self.back(for: zoom), want != d {
            pendingZoom = zoom
            guard !lensSwapping else { return }
            lensSwapping = true
            Task {
                while let z = pendingZoom {
                    pendingZoom = nil
                    if let want = Self.back(for: z), want != device { _ = await attach(want, zoom: z) }
                    else if let d = device { Self.apply(z, to: d) }
                }
                lensSwapping = false
            }
            return
        }
        Self.apply(zoom, to: d)
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

    /// Đổi camera trước / sau như app Camera: camera trước luôn 1×; quay lại camera sau thì giữ tiêu cự đang dùng trước khi đổi
    func flip() async {
        guard configured, let cur = input else { return }
        let toBack = cur.device.position == .front
        if !toBack { backZoom = zoom }
        let target: CGFloat = toBack ? backZoom : 1
        guard let d = toBack ? Self.back(for: target) : Self.front else { return }
        prepareZoom(d, to: target)
        _ = await attach(d, zoom: zoom)
    }

    func stop() {
        let s = session
        Self.sessionQueue.async { if s.isRunning { s.stopRunning() }; Self.live = false }
    }

    func capture(_ done: @escaping (UIImage?) -> Void) {
        #if targetEnvironment(simulator)
        if !configured { done(nil); return }
        #endif
        guard configured else { return }
        onPhoto = done
        // Camera trước: khung xem hiện như soi gương, nên ảnh chụp cũng lật gương cho giống hệt cái đã thấy (mặc định iOS trả ảnh
        // không lật, chụp xong thấy ảnh bị đảo ngược so với lúc ngắm)
        if let c = output.connection(with: .video), c.isVideoMirroringSupported {
            c.automaticallyAdjustsVideoMirroring = false
            c.isVideoMirrored = device?.position == .front
        }
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
            ctx.draw(Text(ReceiptCam.times(zoom)).font(.system(size: 20, weight: .semibold, design: .monospaced)).foregroundStyle(Color(hex: 0xFFD43B)),
                     at: CGPoint(x: c.x, y: c.y - r + 40))
            ctx.draw(Text("\(ReceiptCam.mm(zoom)) MM").font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(hex: 0xFFD43B)),
                     at: CGPoint(x: c.x, y: c.y - r + 64))
        }
    }
}
