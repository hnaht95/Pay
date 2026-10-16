import AVFoundation
import PhotosUI
import SwiftUI

/// Camera quét mã QR toàn màn hình, kèm nút chọn ảnh QR từ thư viện.
struct ScannerView: View {
    /// Dòng nhắc trên cùng (quét mã nhóm chung thì khác quét mã của quán)
    var hint = L("Đưa mã QR của quán vào khung")
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var error: String?
    /// Lần mở này đã xong (đã có mã, hoặc đã bấm Đóng): camera và ảnh cùng đổ về `found`, mã tới sau đó bị bỏ qua
    @State private var done = false
    /// Đèn pin: camera đang dùng có đèn thì mới hiện nút
    @State private var hasTorch = false
    @State private var torch = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraView(torch: torch, onCode: found, onError: { error = $0 }, onTorch: { hasTorch = $0 }).ignoresSafeArea()

            // Khung ngắm: chỉ trong khung thấy camera sáng, bên ngoài phủ tối để chữ và hai nút dễ đọc
            GeometryReader { g in
                let side = min(g.size.width, g.size.height) * 0.68
                let hole = RoundedRectangle(cornerRadius: 36, style: .continuous)
                ZStack {
                    Color.black.opacity(0.72)
                    hole.frame(width: side, height: side)
                        .position(x: g.size.width / 2, y: g.size.height * 0.45)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                hole.strokeBorder(.white.opacity(0.9), lineWidth: 3)
                    .frame(width: side, height: side)
                    .position(x: g.size.width / 2, y: g.size.height * 0.45)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack {
                Text(hint)
                    .font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
                    .padding(.top, 20)
                if let error {
                    Spacer()
                    Text(error).font(.system(size: 17)).foregroundStyle(.white).multilineTextAlignment(.center).padding(24)
                }
                Spacer()
                // Nút đèn pin: tròn kính mờ, giữa màn, ngay trên hai nút dưới (không đè khung ngắm)
                if hasTorch { torchButton.padding(.bottom, 20) }
                HStack(spacing: 12) {
                    PhotosPicker(selection: $photo, matching: .images) { pill(L("Chọn ảnh QR")) }
                    Button { done = true; dismiss() } label: { pill(L("Đóng")) }.buttonStyle(Pressable())
                }
                .padding(.horizontal, 16).padding(.bottom, 12)
            }
        }
        // Việc đọc ảnh gắn với màn quét: màn hình đóng (hoặc chọn ảnh khác) thì bị huỷ. Để Task rời thì ảnh tải chậm
        // (còn trên iCloud) vẫn bắn onCode sau khi màn quét đã đóng, và mã đó nằm lại ở màn hình chính tới lần quét sau
        .task(id: photo) {
            guard let item = photo else { return }
            let data = try? await item.loadTransferable(type: Data.self)
            // loadTransferable không chắc dừng ngay khi bị huỷ
            guard !Task.isCancelled else { return }
            guard let data, let code = decodeQR(data) else {
                error = L("Không đọc được mã QR trong ảnh"); return
            }
            found(code)
        }
    }

    private var torchButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            torch.toggle()
        } label: {
            Image(systemName: torch ? "flashlight.on.fill" : "flashlight.off.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(torch ? .yellow : .white)
                .frame(width: 56, height: 56)
                .background(.ultraThinMaterial, in: Circle())
                .environment(\.colorScheme, .dark)
                .contentShape(Circle())
        }
        .buttonStyle(Pressable())
        .accessibilityLabel(torch ? L("Tắt đèn pin") : L("Bật đèn pin"))
    }

    private func pill(_ s: String) -> some View {
        Text(s).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(.white.opacity(0.18), in: Capsule())
    }

    private func found(_ code: String) {
        // Mỗi lần mở chỉ đưa ra một mã: camera bắt được mã trong lúc ảnh đang đọc (hoặc ngược lại) thì mã tới sau
        // không được ghi đè mã màn hình chính đang xử lý
        guard !done else { return }
        done = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onCode(code)
    }

    private func decodeQR(_ data: Data) -> String? {
        guard let img = CIImage(data: data),
              let det = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else { return nil }
        return det.features(in: img).compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
    }
}

private struct CameraView: UIViewControllerRepresentable {
    let torch: Bool
    let onCode: (String) -> Void
    let onError: (String) -> Void
    let onTorch: (Bool) -> Void

    func makeUIViewController(context: Context) -> CameraController {
        let c = CameraController()
        c.onCode = onCode
        c.onError = onError
        c.onTorch = onTorch
        return c
    }

    func updateUIViewController(_ vc: CameraController, context: Context) { vc.setTorch(torch) }
}

final class CameraController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onError: ((String) -> Void)?
    /// Báo camera có đèn pin hay không (sau khi mở camera)
    var onTorch: ((Bool) -> Void)?
    private var device: AVCaptureDevice?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var done = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        AVCaptureDevice.requestAccess(for: .video) { ok in
            DispatchQueue.main.async { ok ? self.configure() : self.onError?(L("Hãy cho phép Payso dùng camera trong Cài đặt của iPhone, hoặc bấm \"Chọn ảnh QR\".")) }
        }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            onError?(L("Không mở được camera. Bấm \"Chọn ảnh QR\" để dùng ảnh chụp màn hình."))
            return
        }
        session.addInput(input)
        self.device = device
        onTorch?(device.hasTorch)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setTorch(false)
        if session.isRunning { DispatchQueue.global().async { self.session.stopRunning() } }
    }

    /// Bật / tắt đèn pin của camera đang quét. Phiên chụp phải đang chạy thì đèn mới sáng; bật lúc chưa chạy thì iOS tự bật khi chạy
    func setTorch(_ on: Bool) {
        guard let d = device, d.hasTorch, d.isTorchAvailable || !on else { return }
        let mode: AVCaptureDevice.TorchMode = on ? .on : .off
        guard d.torchMode != mode, (try? d.lockForConfiguration()) != nil else { return }
        if d.isTorchModeSupported(mode) { d.torchMode = mode }
        d.unlockForConfiguration()
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !done, let s = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        done = true
        onCode?(s)
    }
}
