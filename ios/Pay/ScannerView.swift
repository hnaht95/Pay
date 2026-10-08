import AVFoundation
import PhotosUI
import SwiftUI

/// Camera quét mã QR toàn màn hình, kèm nút chọn ảnh QR từ thư viện.
struct ScannerView: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var error: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraView(onCode: found, onError: { error = $0 }).ignoresSafeArea()

            // Khung ngắm
            GeometryReader { g in
                let side = min(g.size.width, g.size.height) * 0.68
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .strokeBorder(.white.opacity(0.9), lineWidth: 3)
                    .frame(width: side, height: side)
                    .position(x: g.size.width / 2, y: g.size.height * 0.45)
            }
            .allowsHitTesting(false)

            VStack {
                Text("Đưa mã QR của quán vào khung")
                    .font(.system(size: 18, weight: .medium)).foregroundStyle(.white)
                    .padding(.top, 20)
                if let error {
                    Spacer()
                    Text(error).font(.system(size: 17)).foregroundStyle(.white).multilineTextAlignment(.center).padding(24)
                }
                Spacer()
                HStack(spacing: 12) {
                    PhotosPicker(selection: $photo, matching: .images) { pill("Chọn ảnh QR") }
                    Button { dismiss() } label: { pill("Đóng") }
                }
                .padding(.horizontal, 16).padding(.bottom, 12)
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let code = decodeQR(data) else {
                    error = "Không đọc được mã QR trong ảnh"; return
                }
                found(code)
            }
        }
    }

    private func pill(_ s: String) -> some View {
        Text(s).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(.white.opacity(0.18), in: Capsule())
    }

    private func found(_ code: String) {
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
    let onCode: (String) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> CameraController {
        let c = CameraController()
        c.onCode = onCode
        c.onError = onError
        return c
    }

    func updateUIViewController(_ vc: CameraController, context: Context) {}
}

final class CameraController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onError: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var done = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        AVCaptureDevice.requestAccess(for: .video) { ok in
            DispatchQueue.main.async { ok ? self.configure() : self.onError?("Hãy cho phép Pay dùng camera trong Cài đặt của iPhone, hoặc bấm \"Chọn ảnh QR\".") }
        }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            onError?("Không mở được camera. Bấm \"Chọn ảnh QR\" để dùng ảnh chụp màn hình.")
            return
        }
        session.addInput(input)
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
        if session.isRunning { DispatchQueue.global().async { self.session.stopRunning() } }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !done, let s = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        done = true
        onCode?(s)
    }
}
