import AVFoundation
import Speech
import SwiftUI

/// Nghe giọng nói tiếng Việt, ngừng nói ~1,4 giây thì tự kết thúc và trả về câu đã nghe.
@MainActor
final class VoiceListener: ObservableObject {
    enum Phase: Equatable { case idle, listening, denied, failed(String) }

    @Published var text = ""
    @Published var phase: Phase = .idle
    var onFinish: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silence: Task<Void, Never>?

    func start() async {
        text = ""
        let speechOK = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard speechOK, micOK else { phase = .denied; return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "vi-VN")), recognizer.isAvailable else {
            phase = .failed("iPhone chưa nhận được giọng tiếng Việt lúc này. Thử lại sau, hoặc nhập tay.")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            // Báo trước những từ hay nói để nhận dạng số tiền chuẩn hơn
            req.contextualStrings = ["nghìn", "ngàn", "triệu", "trăm", "mươi", "rưỡi", "nửa triệu", "đồng", "củ",
                                     "cà phê", "cafe", "trà sữa", "ăn sáng", "ăn trưa", "phở", "cơm", "grab", "xăng", "gửi xe", "shopee"]
            req.taskHint = .dictation
            if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }   // không gửi giọng lên mạng nếu máy tự làm được
            request = req

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            // Không có micro dùng được (vd máy ảo, micro đang bị app khác chiếm): báo lỗi thay vì để app văng
            guard format.sampleRate > 0, format.channelCount > 0 else {
                stop()
                phase = .failed("Không dùng được micro lúc này. Thử lại, hoặc nhập tay.")
                return
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in req.append(buffer) }
            engine.prepare()
            try engine.start()
            phase = .listening

            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.phase == .listening else { return }
                    if let result {
                        self.text = result.bestTranscription.formattedString
                        if result.isFinal { self.finish() } else { self.waitForSilence() }
                    } else if error != nil {
                        self.finish()
                    }
                }
            }
            waitForSilence()
        } catch {
            stop()
            phase = .failed("Không bật được micro.")
        }
    }

    /// Chưa nói gì thì chờ tối đa 6 giây; đã nói thì ngừng 1,4 giây là xong.
    private func waitForSilence() {
        silence?.cancel()
        let wait: Duration = text.isEmpty ? .seconds(6) : .milliseconds(1400)
        silence = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    func finish() {
        guard phase == .listening else { return }
        stop()
        phase = .idle
        onFinish?(text)
    }

    func stop() {
        silence?.cancel()
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Bảng "đang nghe": mở từ nút Tác vụ / Trung tâm điều khiển, nói "35k cafe" là ghi.
struct VoiceEntryView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @StateObject private var mic = VoiceListener()
    @State private var saved: Expense?
    @State private var notUnderstood = false
    @State private var autoClose: Task<Void, Never>?
    /// Bấm "Nhập tay": đóng bảng này và mở màn hình nhập.
    var onTypeInstead: () -> Void
    /// Bấm "Sửa" sau khi ghi: đóng bảng này và mở khoản vừa ghi để sửa.
    var onEdit: (Expense) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Spacer()
                Button("Huỷ") { mic.stop(); dismiss() }.font(.system(size: 17))
            }
            Spacer(minLength: 0)
            icon
            Text(title).font(.system(size: 20, weight: .semibold)).multilineTextAlignment(.center)
            Text(detail).font(.system(size: 17)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .lineLimit(3).frame(minHeight: 48)
            Spacer(minLength: 0)
            buttons
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .task {
            mic.onFinish = { said in handle(said) }
            await mic.start()
        }
        .onDisappear { mic.stop() }
    }

    private func handle(_ said: String) {
        guard !said.isEmpty, let e = store.quickAdd(said, spoken: true) else { notUnderstood = true; return }
        saved = e
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // Để 3 giây cho kịp nhìn số tiền; bấm Sửa / Hoàn tác thì không tự đóng
        autoClose = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    private func retry() {
        notUnderstood = false
        Task { await mic.start() }
    }

    @ViewBuilder private var icon: some View {
        let listening = mic.phase == .listening
        Image(systemName: saved != nil ? "checkmark" : (notUnderstood ? "questionmark" : "mic.fill"))
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(saved != nil ? .white : Palette.ctaInk)
            .frame(width: 88, height: 88)
            .background(saved != nil ? Color.green : Palette.cta, in: Circle())
            .overlay(Circle().stroke(Palette.cta.opacity(0.25), lineWidth: 10).scaleEffect(listening ? 1.25 : 1).opacity(listening ? 1 : 0))
            .animation(listening ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default, value: listening)
    }

    private var title: String {
        if let e = saved { return "Đã ghi \(fmt(e.a))đ · \(Category.get(e.c).name)" }
        if notUnderstood { return "Chưa nghe rõ số tiền" }
        switch mic.phase {
        case .listening: return mic.text.isEmpty ? "Đang nghe…" : understood(mic.text)
        case .denied: return "Cần quyền micro và nhận giọng nói"
        case .failed(let why): return why
        case .idle: return "Đang bật micro…"
        }
    }

    private var detail: String {
        if let e = saved { return e.n ?? "" }   // chỉ hiện ghi chú (vd "tiền nhà"), không hiện chữ thô của Siri
        if notUnderstood { return mic.text.isEmpty ? "Không nghe thấy gì." : "Đã nghe: \"\(mic.text)\"" }
        switch mic.phase {
        case .listening: return mic.text.isEmpty ? "Nói ví dụ: \"35k cafe\", \"1tr2 tiền nhà\"" : "Ngừng nói là tự ghi"
        case .denied: return "Vào Cài đặt › Pay để bật Micro và Nhận dạng giọng nói."
        default: return ""
        }
    }

    /// Hiện điều app hiểu được thay cho chữ thô của Siri ("1.000.005" -> "1.500.000đ"); chưa ra số thì hiện nguyên câu.
    private func understood(_ said: String) -> String {
        guard let q = QuickParse.spoken(said) else { return said }
        return "\(fmt(q.amount))đ" + (q.note.isEmpty ? "" : " · \(q.note)")
    }

    @ViewBuilder private var buttons: some View {
        if let e = saved {
            HStack(spacing: 12) {
                pill("Hoàn tác", primary: false) {
                    autoClose?.cancel()
                    store.remove(id: e.id, toast: false)
                    saved = nil
                    retry()
                }
                pill("Sửa", primary: true) {
                    autoClose?.cancel()
                    dismiss()
                    onEdit(e)
                }
            }
        } else if mic.phase != .listening {
            HStack(spacing: 12) {
                if mic.phase == .denied {
                    pill("Mở Cài đặt", primary: true) {
                        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                    }
                } else if notUnderstood || mic.phase != .idle {
                    pill("Nói lại", primary: true) { retry() }
                }
                pill("Nhập tay", primary: false) { mic.stop(); dismiss(); onTypeInstead() }
            }
        }
    }

    private func pill(_ title: String, primary: Bool, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title).font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(primary ? Palette.ctaInk : .primary)
                .background(primary ? Palette.cta : Palette.pill, in: Capsule())
        }
        .buttonStyle(Pressable())
    }
}
