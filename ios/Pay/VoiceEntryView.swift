import AVFoundation
import Speech
import SwiftUI

/// Độ to micro (0…1), tách riêng khỏi VoiceListener: cập nhật theo nhịp âm thanh (~43 lần/giây)
/// nên chỉ sóng âm theo dõi, cả thẻ không phải vẽ lại.
@MainActor
final class MicLevel: ObservableObject {
    @Published var value: CGFloat = 0
}

/// Nghe giọng nói tiếng Việt, ngừng nói ~1,4 giây thì tự kết thúc và trả về câu đã nghe.
@MainActor
final class VoiceListener: ObservableObject {
    enum Phase: Equatable { case idle, listening, denied, failed(String) }

    @Published var text = ""
    @Published var phase: Phase = .idle
    let meter = MicLevel()
    var onFinish: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silence: Task<Void, Never>?
    private var starting = false

    func start() async {
        // Bấm "Nói lại" liên tiếp: không bật micro hai lần (installTap lần hai làm app văng)
        guard !starting, phase != .listening else { return }
        starting = true
        defer { starting = false }
        text = ""
        #if DEBUG
        // Chỉ bản Debug: chạy với "-voiceDemo <câu>" để xem giao diện đang nghe trên máy ảo (không có micro)
        if let demo = UserDefaults.standard.string(forKey: "voiceDemo") {
            phase = .listening; text = demo; meter.value = 0.7
            // Thêm "-voiceDemoPlay YES": hiện từng chữ như đang nói rồi tự ghi (để quay phim giới thiệu)
            if UserDefaults.standard.bool(forKey: "voiceDemoPlay") {
                text = ""
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(900))
                    for w in demo.split(separator: " ") {
                        text += (text.isEmpty ? "" : " ") + w
                        meter.value = .random(in: 0.45...0.95)
                        try? await Task.sleep(for: .milliseconds(380))
                    }
                    meter.value = 0.1
                    try? await Task.sleep(for: .milliseconds(1100))
                    guard phase == .listening else { return }
                    meter.value = 0; phase = .idle
                    onFinish?(text)
                }
            }
            return
        }
        #endif
        let speechOK = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard speechOK, micOK else { phase = .denied; return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "vi-VN")), recognizer.isAvailable else {
            phase = .failed("iPhone chưa nhận được giọng tiếng Việt lúc này. Thử lại sau, hoặc quét QR.")
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
                phase = .failed("Không dùng được micro lúc này. Thử lại, hoặc quét QR.")
                return
            }
            input.removeTap(onBus: 0)   // phòng còn tap cũ
            let meter = meter
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                req.append(buffer)
                // Độ to (RMS) đổi sang thang 0…1 cho sóng âm. Micro ở chế độ đo (không tự khuếch đại) nên giọng thường
                // chỉ khoảng -40…-25 dB: lấy dải -55…-25 dB và nâng phần giữa (mũ 0,7) để nói nhỏ vẫn thấy rõ
                guard let ch = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
                let n = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<n { sum += ch[i] * ch[i] }
                let db = 20 * log10(max(sqrt(sum / Float(n)), 1e-6))
                let v = CGFloat(pow(min(max((db + 55) / 30, 0), 1), 0.7))
                Task { @MainActor in meter.value = v }
            }
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
        meter.value = 0
        stop()
        phase = .idle
        onFinish?(text)
    }

    func stop() {
        silence?.cancel()
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)   // gỡ cả khi engine chưa chạy được (vd micro đang bận)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Thẻ "đang nghe" nổi ở đáy màn hình: nói "35k cafe" là ghi.
/// Mở bằng fullScreenCover nền trong suốt; nền tối phía sau chạm vào là huỷ.
struct VoiceEntryView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @StateObject private var mic = VoiceListener()
    @State private var saved: Expense?
    @State private var notUnderstood = false
    /// Vừa bấm Hoàn tác: khoản vừa ghi đã xoá
    @State private var undone = false
    @State private var autoClose: Task<Void, Never>?
    @State private var shown = false
    /// Bấm "Quét QR": đóng thẻ này và mở camera quét mã.
    var onScan: () -> Void
    /// Bấm "Sửa" sau khi ghi: đóng thẻ này và mở khoản vừa ghi để sửa.
    var onEdit: (Expense) -> Void = { _ in }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(shown ? 0.35 : 0).ignoresSafeArea()
                .onTapGesture { close() }
            if shown {
                // Nâng lên khỏi đáy để thẻ không dính vào góc bo màn hình và các ô phía sau
                card
                    .padding(.horizontal, 12).padding(.bottom, 34)
                    // Chỉ trượt, không mờ dần: thẻ mờ nửa chừng đè lên các ô phía sau trông như bóng ma
                    .transition(.move(edge: .bottom))
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: shown)
        .presentationBackground(.clear)
        .task {
            shown = true
            mic.onFinish = { said in handle(said) }
            await mic.start()
        }
        .onDisappear { mic.stop() }
    }

    // MARK: Thẻ

    private var card: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            amountBlock
            if mic.phase == .listening { Waveform(meter: mic.meter).frame(height: 56) }
            buttons
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 42, style: .continuous))
        // Viền mảnh cho thẻ tách khỏi nền phía sau (chế độ tối thẻ và nền gần cùng màu)
        .overlay(RoundedRectangle(cornerRadius: 42, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if saved != nil {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Đã ghi").foregroundStyle(.secondary)
            } else if mic.phase == .listening {
                PulseDot()
                Text("Đang nghe").foregroundStyle(.secondary)
            } else if undone {
                Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(.secondary)
                Text("Đã hoàn tác, chưa ghi gì").foregroundStyle(.secondary)
            } else if notUnderstood {
                Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
                Text("Chưa nghe rõ số tiền").foregroundStyle(.secondary)
            } else {
                Image(systemName: "mic.fill").foregroundStyle(.secondary)
                Text(statusText).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button { close() } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30).background(Palette.pill, in: Circle())
            }
            .foregroundStyle(.primary)
            .accessibilityLabel("Đóng")
        }
        .font(.system(size: 15, weight: .medium))
    }

    /// Số tiền to + danh mục đoán được + ghi chú, cập nhật ngay trong lúc nói.
    @ViewBuilder private var amountBlock: some View {
        // Vừa hoàn tác: không hiện lại số đã nghe, kẻo tưởng vẫn còn ghi
        let live = saved.map { (amount: $0.a, note: $0.n ?? "", cat: $0.c) }
            ?? (undone ? nil : QuickParse.spoken(mic.text)).map { (amount: $0.amount, note: $0.note, cat: store.guessCategory($0.note)) }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(live.map { fmt($0.amount) } ?? "0")
                    .font(.system(size: 46, weight: .bold)).kerning(-1.5)
                    .foregroundStyle(live == nil ? Color.secondary.opacity(0.5) : .primary)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.5).lineLimit(1)
                Text("đ").font(.system(size: 24, weight: .semibold)).foregroundStyle(.secondary)
            }
            .animation(.snappy, value: live?.amount)
            if let l = live {
                let c = Category.get(l.cat)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            CategoryIcon(c: c, size: 18)
                            Text(c.name).font(.system(size: 14, weight: .semibold))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(c.color, in: Capsule())
                        .foregroundStyle(.black)
                        if !l.note.isEmpty {
                            Text(l.note).font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    // Câu nhắc tới nhiều danh mục ("mua cát cho mèo"): hiện các danh mục còn lại, chạm là đổi
                    let others = Category.matches(l.note).filter { $0 != l.cat }.prefix(3)
                    if !others.isEmpty {
                        HStack(spacing: 6) {
                            Text("Hay là").font(.system(size: 14)).foregroundStyle(.secondary)
                            ForEach(Array(others), id: \.self) { k in
                                let o = Category.get(k)
                                Button { switchCategory(to: k) } label: {
                                    HStack(spacing: 5) {
                                        CategoryIcon(c: o, size: 16)
                                        Text(o.name).font(.system(size: 14, weight: .medium))
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Palette.pill, in: Capsule())
                                    .foregroundStyle(.primary)
                                }
                                .buttonStyle(Pressable())
                            }
                        }
                    }
                }
            } else {
                Text(hint).font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    private var hint: String {
        if undone { return "Bấm Nói lại để nói khoản khác." }
        if notUnderstood { return mic.text.isEmpty ? "Không nghe thấy gì." : "Đã nghe: \"\(mic.text)\"" }
        if mic.phase == .listening { return mic.text.isEmpty ? "Nói ví dụ: \"ba lăm nghìn cà phê\"" : mic.text }
        if mic.phase == .denied { return "Vào Cài đặt › Pay để bật Micro và Nhận dạng giọng nói." }
        return ""
    }

    private var statusText: String {
        switch mic.phase {
        case .denied: return "Cần quyền micro"
        case .failed(let why): return why
        default: return "Đang bật micro…"
        }
    }

    // MARK: Nút

    @ViewBuilder private var buttons: some View {
        HStack(spacing: 10) {
            if let e = saved {
                // Hoàn tác nằm ngay trong thẻ (không hiện thanh "Đã lưu" bên ngoài nữa)
                pill("Hoàn tác", primary: false) { undo(e) }
                pill("Sửa", primary: false) { autoClose?.cancel(); leave(); onEdit(e) }
                pill("Xong", primary: true) { autoClose?.cancel(); leave() }
            } else if mic.phase == .listening {
                pill("Quét QR", primary: false) { mic.stop(); leave(); onScan() }
                pill("Xong", primary: true) { mic.finish() }          // ngừng nghe ngay, không chờ im lặng
                    .disabled(mic.text.isEmpty).opacity(mic.text.isEmpty ? 0.4 : 1)
            } else if mic.phase == .denied {
                pill("Quét QR", primary: false) { leave(); onScan() }
                pill("Mở Cài đặt", primary: true) {
                    if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                }
            } else if notUnderstood || undone || mic.phase != .idle {
                pill("Quét QR", primary: false) { mic.stop(); leave(); onScan() }
                pill("Nói lại", primary: true) { retry() }
            }
        }
    }

    private func pill(_ title: String, primary: Bool, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title).font(.system(size: 18, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 64)   // cao cho dễ nhấn
                .foregroundStyle(primary ? Palette.ctaInk : .primary)
                .background(primary ? Palette.cta : Palette.pill, in: Capsule())
        }
        .buttonStyle(Pressable())
    }

    // MARK: Xử lý

    private func handle(_ said: String) {
        guard !said.isEmpty, let e = store.quickAdd(said, spoken: true, toast: false) else {
            notUnderstood = true
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        saved = e
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // Để 5 giây cho kịp nhìn số tiền và bấm Hoàn tác rồi tự đóng; bấm Sửa / Xong thì đóng ngay
        autoClose = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            leave()
        }
    }

    /// Xoá khoản vừa ghi, thẻ vẫn mở để nói lại hoặc quét QR
    private func undo(_ e: Expense) {
        autoClose?.cancel()
        store.remove(id: e.id, toast: false)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.snappy) { saved = nil; undone = true }
    }

    /// Chọn danh mục khác trong số được nhắc tới: đổi luôn khoản vừa ghi (hoặc khoản đang nghe) và nhớ cho lần sau.
    private func switchCategory(to k: String) {
        UISelectionFeedbackGenerator().selectionChanged()
        if var e = saved {
            autoClose?.cancel()
            e.c = k
            store.update(e)
            store.learnCategory(e.n ?? "", k)
            withAnimation(.snappy) { saved = e }
        } else if let q = QuickParse.spoken(mic.text) {
            store.learnCategory(q.note, k)
        }
    }

    private func retry() {
        notUnderstood = false
        undone = false
        Task { await mic.start() }
    }

    private func close() {
        autoClose?.cancel()
        mic.stop()
        leave()
    }

    /// Đóng thẻ: tự trượt thẻ xuống và mờ nền trước, xong mới gỡ màn hình (không hiệu ứng).
    /// Để hệ thống tự kéo cả màn hình xuống thì nền tối tắt phụt và bóng đổ của thẻ bị vệt.
    private func leave() {
        guard shown else { return }
        withAnimation(.easeIn(duration: 0.25)) { shown = false }
        Task {
            try? await Task.sleep(for: .milliseconds(270))
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { dismiss() }
        }
    }
}

/// Sóng âm: độ cao chung theo độ to thật của giọng; hình dáng (giữa cao, rung nhẹ) là trang trí.
private struct Waveform: View {
    @ObservedObject var meter: MicLevel

    var body: some View {
        let level = meter.value
        TimelineView(.animation) { t in
            let time = t.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<28, id: \.self) { i in
                    let center = 1 - abs(CGFloat(i) - 13.5) / 14          // giữa cao, hai bên thấp
                    let wobble = (sin(time * 9 + Double(i) * 0.7) + 1) / 2  // dao động nhẹ cho tự nhiên
                    let h = 0.12 + 1.25 * level * center * (0.55 + 0.45 * CGFloat(wobble))   // ×1,25: nói thường đã gần đỉnh
                    Capsule().fill(Palette.cta.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(4, 56 * min(h, 1)))
                }
            }
            .animation(.easeOut(duration: 0.12), value: level)
        }
    }
}

/// Chấm đỏ nhấp nháy cạnh chữ "Đang nghe".
private struct PulseDot: View {
    @State private var on = false

    var body: some View {
        Circle().fill(Color.red).frame(width: 9, height: 9)
            .opacity(on ? 1 : 0.35)
            .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever()) { on = true } }
    }
}
