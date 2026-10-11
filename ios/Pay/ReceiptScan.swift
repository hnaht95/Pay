import AVFoundation
import PhotosUI
import SwiftUI
import Vision

/// Màn chụp hoá đơn của Pay, cùng kiểu màn quét QR: camera toàn màn hình, khung dọc gợi ý chỗ đặt hoá đơn (ngoài khung tối),
/// một nút chụp tròn, "Đóng" và "Chọn ảnh". Không dùng máy quét tài liệu của iOS: nó có sẵn bộ lọc / chế độ chụp không ẩn được
struct ReceiptCamera: View {
    var done: (UIImage?) -> Void
    @StateObject private var cam = ReceiptCam()
    @State private var photo: PhotosPickerItem?
    @State private var finished = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: cam.session).ignoresSafeArea()
            // Khung dọc tỉ lệ tờ hoá đơn: trong khung sáng, ngoài phủ tối
            GeometryReader { g in
                let w = g.size.width * 0.78, h = min(g.size.height * 0.62, w * 1.45)
                let hole = RoundedRectangle(cornerRadius: 28, style: .continuous)
                ZStack {
                    Color.black.opacity(0.62)
                    hole.frame(width: w, height: h).position(x: g.size.width / 2, y: g.size.height * 0.44).blendMode(.destinationOut)
                }
                .compositingGroup()
                hole.strokeBorder(.white.opacity(0.9), lineWidth: 3)
                    .frame(width: w, height: h).position(x: g.size.width / 2, y: g.size.height * 0.44)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack {
                Text(cam.error ?? L("Đặt hoá đơn vào khung rồi bấm chụp"))
                    .font(.system(size: 18, weight: .medium)).foregroundStyle(.white)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
                    .padding(.top, 20)
                Spacer()
                // Ba nút to: cột trái Đóng / Chọn ảnh, cột phải nút chụp cao bằng cả hai
                HStack(spacing: 12) {
                    VStack(spacing: 12) {
                        Button { finish(nil) } label: { pill(L("Đóng")) }.buttonStyle(Pressable())
                        PhotosPicker(selection: $photo, matching: .images) { pill(L("Chọn ảnh")) }
                    }
                    Button { cam.capture { finish($0) } } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "camera.aperture").font(.system(size: 30, weight: .medium))
                            Text(L("Chụp")).font(.system(size: 18, weight: .semibold))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.white, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                    }
                    .buttonStyle(Pressable())
                    .disabled(cam.error != nil)
                    .opacity(cam.error != nil ? 0.4 : 1)
                }
                .frame(height: 64 * 2 + 12)
                .padding(.horizontal, 16).padding(.bottom, 12)
            }
        }
        .onAppear { cam.start() }
        .onDisappear { cam.stop() }
        .task(id: photo) {
            guard let item = photo, let data = try? await item.loadTransferable(type: Data.self), !Task.isCancelled,
                  let img = UIImage(data: data) else { return }
            finish(img)
        }
    }

    private func pill(_ s: String) -> some View {
        Text(s).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(.white.opacity(0.18), in: Capsule())
    }

    private func finish(_ img: UIImage?) {
        guard !finished else { return }
        finished = true
        if img != nil { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        done(img)
    }
}

/// Camera chụp ảnh tĩnh cho màn chụp hoá đơn
@MainActor
final class ReceiptCam: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var configured = false
    private var onPhoto: ((UIImage?) -> Void)?
    @Published var error: String?

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            Task { @MainActor in
                guard ok else { self.error = L("Hãy cho phép Pay dùng camera trong Cài đặt của iPhone, hoặc bấm \"Chọn ảnh\"."); return }
                self.configure()
            }
        }
    }

    private func configure() {
        if !configured {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input), session.canAddOutput(output) else {
                error = L("Không mở được camera. Bấm \"Chọn ảnh\" để dùng ảnh có sẵn."); return
            }
            session.sessionPreset = .photo
            session.addInput(input)
            session.addOutput(output)
            configured = true
        }
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { if !s.isRunning { s.startRunning() } }
    }

    func stop() {
        let s = session
        DispatchQueue.global().async { if s.isRunning { s.stopRunning() } }
    }

    func capture(_ done: @escaping (UIImage?) -> Void) {
        guard configured else { return }
        onPhoto = done
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let img = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        Task { @MainActor in self.onPhoto?(img); self.onPhoto = nil }
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

/// Đọc chữ trên hoá đơn ngay trên máy (Vision, không gửi ảnh đi đâu) rồi lấy ra tổng tiền và tên quán
enum ReceiptReader {
    struct Result { var amount: Int?; var merchant: String? }

    static func read(_ image: UIImage) async -> Result {
        guard let cg = image.cgImage else { return Result() }
        let rows: [String] = await withCheckedContinuation { c in
            let req = VNRecognizeTextRequest { r, _ in
                let obs = (r.results as? [VNRecognizedTextObservation]) ?? []
                c.resume(returning: Self.rows(obs))
            }
            req.recognitionLevel = .accurate
            req.recognitionLanguages = ["vi-VN", "en-US"]
            req.usesLanguageCorrection = true
            do { try VNImageRequestHandler(cgImage: cg).perform([req]) } catch { c.resume(returning: []) }
        }
        return parse(rows)
    }

    /// Ghép các mẩu chữ cùng một hàng (hoá đơn hay để chữ "Tổng cộng" và số tiền ở hai cột) thành từng dòng, trên xuống dưới
    private static func rows(_ obs: [VNRecognizedTextObservation]) -> [String] {
        let items = obs.compactMap { o in o.topCandidates(1).first.map { (box: o.boundingBox, text: $0.string) } }
            .sorted { $0.box.midY > $1.box.midY }
        var out: [[(box: CGRect, text: String)]] = []
        for it in items {
            if let last = out.last?.first, abs(last.box.midY - it.box.midY) < max(last.box.height, it.box.height) * 0.6 {
                out[out.count - 1].append(it)
            } else { out.append([it]) }
        }
        return out.map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
    }

    /// Tổng tiền: số trên dòng có chữ "tổng / thanh toán / total" (ưu tiên dòng dưới cùng), không có thì số lớn nhất hợp lý.
    /// Tên quán: dòng chữ đầu tiên đủ dài, không phải tiêu đề kiểu "Hoá đơn".
    static func parse(_ rows: [String]) -> Result {
        let keys = ["tong thanh toan", "thanh toan", "tong cong", "tong tien", "can thanh toan", "total", "tong"]
        let skip = ["tien thua", "tien khach", "khach dua", "change", "cash", "giam gia", "discount", "vat", "thue"]
        var best: Int?
        for (i, r) in rows.enumerated().reversed() {
            let k = Store.noteKey(r)
            guard keys.contains(where: { k.contains($0) }), !skip.contains(where: { k.contains($0) }) else { continue }
            if let a = amounts(r).last ?? (i + 1 < rows.count ? amounts(rows[i + 1]).first : nil) { best = a; break }
        }
        if best == nil {
            // Bỏ dòng ngày giờ ("11/10/2026 18:30") để năm không bị lấy làm số tiền
            best = rows.filter { r in !skip.contains(where: { Store.noteKey(r).contains($0) }) && !r.contains("/") && !r.contains(":") }
                .flatMap(amounts).filter { $0 < 50_000_000 }.max()
        }
        let titles = ["hoa don", "phieu", "receipt", "invoice", "bill", "ban le", "thanh toan"]
        let merchant = rows.first { r in
            let k = Store.noteKey(r)
            return r.filter(\.isLetter).count >= 3 && !titles.contains(where: { k.contains($0) }) && amounts(r).isEmpty
        }
        return Result(amount: best, merchant: merchant?.trimmingCharacters(in: .whitespaces).capitalized)
    }

    /// Các số tiền trong một dòng: "125.000", "1,250,000", "125000đ", "125.000 VND". Bỏ số quá ngắn (< 1.000) và số dài như số điện thoại
    static func amounts(_ s: String) -> [Int] {
        // Chặn hai đầu: một dãy số dài hơn (số điện thoại, mã hoá đơn) không bị cắt ra thành một "số tiền"
        let re = try! NSRegularExpression(pattern: #"(?<![\d.,])(?:\d{1,3}(?:[.,]\d{3})+|\d{4,9})(?![\d])"#)
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { m in
            guard let r = Range(m.range, in: s) else { return nil }
            let n = Int(s[r].filter(\.isNumber)) ?? 0
            return n >= 1000 && n < 1_000_000_000 ? n : nil
        }
    }
}
