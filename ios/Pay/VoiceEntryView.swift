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

    /// Tạo lại khi bật micro hỏng (xem start): engine cũ có thể giữ định dạng của lần trước (đổi tai nghe, có cuộc gọi…)
    private var engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silence: Task<Void, Never>?
    private var starting = false
    /// Thẻ đã bị đóng (xem `cancel`): từ đây không ghi gì nữa, không bật lại micro
    private var cancelled = false

    func start() async {
        // Bấm "Nói lại" liên tiếp: không bật micro hai lần (installTap lần hai làm app văng)
        guard !starting, phase != .listening else { return }
        starting = true
        defer { starting = false }
        cancelled = false   // lần bật mới: bỏ dấu "đã huỷ" của lần trước (xem isCancelled)
        text = ""
        // Bỏ trạng thái lỗi của lần trước: lần này lại thiếu quyền / lỗi thì phase đổi lần nữa, nơi theo dõi (nút micro ở màn
        // Nhập) mới biết mà thôi nghe. Không đổi thì nút kẹt ở trạng thái đang nghe, bấm gì cũng không được
        if phase != .idle { phase = .idle }
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
        guard !cancelled else { return }   // đóng thẻ khi micro chưa kịp bật: không bật nữa
        guard speechOK, micOK else { phase = .denied; return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: Lang.isEnglish ? "en-US" : "vi-VN")), recognizer.isAvailable else {
            phase = .failed(L("iPhone chưa nhận được giọng tiếng Việt lúc này. Thử lại sau, hoặc quét QR."))
            return
        }
        // Mở app bằng nút Tác vụ / quay lại app: thẻ bật micro khi app có thể chưa lên hẳn màn hình. iOS không cho app chưa ở
        // trước mặt giành micro (báo lỗi, thẻ hiện "Không bật được micro"). Đợi app lên hẳn (tối đa 2 giây) rồi mới bật
        for _ in 0..<20 where UIApplication.shared.applicationState != .active {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard !cancelled else { return }
        // Bật micro, hỏng thì thử lại tối đa 3 lần với engine mới: lần đầu sau khi app vừa quay lại, iOS hay chưa trả micro kịp
        // (app khác vừa nhả âm thanh, phiên âm thanh cũ chưa tắt hẳn)
        // Bật phiên âm thanh (phần chậm nhất, có khi vài trăm mili giây) trên luồng nền cho luồng chính rảnh vẽ thẻ; boot bật lại
        // cũng không sao (đã bật thì gần như tức thì)
        await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try? session.setActive(true, options: .notifyOthersOnDeactivation)
        }.value
        guard !cancelled else { return }
        var lastError: Error?
        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(for: .milliseconds(350))
                guard !cancelled else { return }
                engine = AVAudioEngine()
            }
            do {
                try boot(recognizer)
                lastError = nil
                break
            } catch {
                lastError = error
                stop()
            }
        }
        if let lastError {
            let code = (lastError as NSError).code
            phase = .failed(L("Không bật được micro (mã %@). Bấm Nói lại để thử lần nữa.", String(code)))
            return
        }
        guard phase == .listening else { return }
        waitForSilence()
    }

    /// Bật phiên âm thanh, gắn micro vào nhận dạng giọng nói và bắt đầu nghe. Ném lỗi nếu iOS không cho bật micro
    private func boot(_ recognizer: SFSpeechRecognizer) throws {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            // Báo trước những từ hay nói để nhận dạng số tiền chuẩn hơn
            req.contextualStrings = Lang.isEnglish
                ? ["thousand", "million", "hundred", "k", "half a million", "dong", "coffee", "lunch", "breakfast", "dinner",
                   "groceries", "gas", "parking", "grab", "rent", "shopee", "bubble tea", "pho"]
                : ["nghìn", "ngàn", "triệu", "trăm", "mươi", "rưỡi", "nửa triệu", "đồng", "củ",
                   "cà phê", "cafe", "trà sữa", "ăn sáng", "ăn trưa", "phở", "cơm", "grab", "xăng", "gửi xe", "shopee"]
            req.taskHint = .dictation
            if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }   // không gửi giọng lên mạng nếu máy tự làm được
            request = req

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            // Không có micro dùng được (vd máy ảo, micro đang bị app khác chiếm): báo lỗi thay vì để app văng
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw NSError(domain: "Pay.mic", code: -1)
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
                // Dải -52…-30 dB: nói bình thường đã gần mức cao nhất (dải rộng hơn thì phải nói rất to mới lên cao)
                let v = CGFloat(pow(min(max((db + 52) / 22, 0), 1), 0.6))
                Task { @MainActor in meter.value = v }   // làm mượt ở Waveform, theo từng khung hình
            }
            engine.prepare()
            try engine.start()
            phase = .listening

            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, !self.cancelled, self.phase == .listening else { return }
                    if let result {
                        self.text = result.bestTranscription.formattedString
                        if result.isFinal { self.finish() } else { self.waitForSilence() }
                    } else if error != nil {
                        self.finish()
                    }
                }
            }
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
        guard !cancelled, phase == .listening else { return }
        meter.value = 0
        stop()
        phase = .idle
        onFinish?(text)
    }

    /// Người dùng đóng thẻ (X, chạm nền tối, chuyển sang quét QR): dừng micro và bỏ luôn câu đang nghe.
    /// stop() không đủ: sau task.cancel() iOS vẫn gọi lại kết quả / báo lỗi một lần nữa, lúc đó `phase` còn là .listening
    /// nên khoản chi vẫn bị ghi âm thầm trong lúc thẻ đang đóng. Không đổi `phase` ở đây, để thẻ đang trượt đi
    /// giữ nguyên dạng "Đang nghe" chứ không nháy sang dạng khác.
    /// Lần bật gần nhất đã bị huỷ giữa chừng
    var isCancelled: Bool { cancelled }

    func cancel() {
        cancelled = true
        onFinish = nil   // closure này giữ view (và qua view giữ lại chính listener): gỡ ra để listener được giải phóng
        stop()
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
    /// Đang chụp ảnh cho khoản vừa ghi (nút camera trên thẻ đã ghi)
    @State private var shooting = false
    /// Khoản vừa ghi đã có ảnh chụp kèm
    @State private var attached = false
    /// Bấm Xong khi đang nghe: ghi xong thì đóng thẻ ngay
    @State private var closeAfterSave = false
    @State private var shown = false
    /// Thẻ vừa mở, micro chưa kịp chạy
    @State private var starting = true
    /// Mở bằng vuốt lên từ nút Quét QR: khung của nút (toạ độ màn hình). Thẻ biến hình từ chính nút đó ra
    /// (khối màu nút lớn dần thành khung thẻ, nội dung thẻ hiện dần lên) và thu về lại nút khi đóng
    var from: CGRect? = nil
    /// Mặt của nút đó (biểu tượng + chữ): vẽ trên khối khi khối còn là nút, mờ đi khi khối lớn thành thẻ
    var face: AnyView? = nil
    @State private var faced = true
    /// Thẻ đang nằm ngay trên màn hình chính (không qua fullScreenCover, để không dính hiệu ứng trượt lên của iOS):
    /// đóng thì gọi cái này thay cho dismiss
    var onClose: (() -> Void)? = nil
    /// Mức biến hình: 0 = còn là nút, 1 = đã thành thẻ
    @State private var morph: CGFloat = 0
    /// Nội dung thẻ đã hiện chưa (hiện sau khi khối đã lớn gần xong, ẩn trước khi khối thu về)
    @State private var filled = false
    /// Khối biến hình còn vẽ không (thành thẻ xong thì ẩn, để thẻ đổi cỡ về sau không lộ khối phía dưới)
    @State private var blob = true
    @State private var cardRect: CGRect = .zero
    /// Bấm "Quét QR": đóng thẻ này và mở camera quét mã.
    /// Thẻ này thay ngay cho một thẻ nói đang hiện (bấm nút Tác vụ khi thẻ cũ còn mở): hiện luôn tại chỗ, không trượt lên —
    /// trượt thì trông như thẻ đóng lại rồi mở ra lần nữa
    var instant = false
    var onScan: () -> Void
    /// Bấm "Sửa" sau khi ghi: đóng thẻ này và mở khoản vừa ghi để sửa.
    var onEdit: (Expense) -> Void = { _ in }
    /// Đang dựng phim giới thiệu (xem Film.swift): trạng thái lấy từ phim thay vì micro
    @Environment(\.film) private var film

    private var heard: String { film?.voice?.text ?? mic.text }
    /// Micro đang khởi động (vài phần mười giây đầu) cũng hiện như đang nghe: thẻ bật lên đã đủ nội dung, không đổi giữa chừng
    private var isListening: Bool { film?.voice.map { $0.saved == nil } ?? (mic.phase == .listening || starting) }
    private var savedNow: Expense? { film != nil ? film?.voice?.saved : saved }

    var body: some View {
        if let v = film?.voice {
            // Phim: nền tối dần và thẻ trượt lên theo mức `shown`
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.35 * Double(v.shown))
                card.padding(.horizontal, 16).padding(.bottom, 16).offset(y: ((1 - v.shown) * 460).rounded())
            }
        } else { live }
    }

    private var live: some View {
        ZStack(alignment: .bottom) {
            // Không phủ / nhoè nền: trang chủ để nguyên phía sau thẻ; lớp trong suốt chỉ để chạm ra ngoài là đóng
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
            .onTapGesture { close() }
            if let from {
                // Khối biến hình: từ khung và màu của nút tới khung và màu của thẻ
                GeometryReader { g in
                    let o = g.frame(in: .global).origin
                    let to = cardRect == .zero ? from : cardRect
                    let r = CGRect(x: from.minX + (to.minX - from.minX) * morph, y: from.minY + (to.minY - from.minY) * morph,
                                   width: from.width + (to.width - from.width) * morph, height: from.height + (to.height - from.height) * morph)
                    let shape = RoundedRectangle(cornerRadius: from.height / 2 + (Self.corner - from.height / 2) * morph, style: .circular)
                    // Đổi màu nhanh ở đầu (xong khi khối mới lớn được 40%): đổi đều suốt quãng thì khối cứ xám lửng lơ, trông như khựng.
                    // Lớp đen mờ dần đi đúng bằng lớp nền hiện lên: để lớp đen đặc nằm dưới thì mép bo (khử răng cưa, nửa trong suốt)
                    // của lớp nền để lộ một viền tối mảnh quanh góc thẻ
                    let t = Double(min(1, max(0, morph) * 2.5))
                    shape.fill(Palette.cta).opacity(1 - t)
                        .overlay(shape.fill(Palette.surface).opacity(t))
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX - o.x, y: r.midY - o.y)
                        .opacity(blob ? 1 : 0)
                    if let face {
                        face.frame(width: from.width, height: from.height)
                            .position(x: from.midX - o.x, y: from.midY - o.y)
                            .opacity(faced && blob ? 1 : 0)
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                if shown {
                    card
                        // Đo khung của chính thẻ (trước khi thêm lề), không tự trừ lề: trừ lề lệch vài điểm làm khối biến hình dừng
                        // to hơn thẻ, lúc thẻ thay chỗ khối thì trông như thẻ co thêm một nhịp
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { r in
                            // Thẻ đổi cỡ (nghe xong thu gọn…): khối làm nền co giãn theo, cùng nhịp với thẻ
                            if cardRect == .zero { cardRect = r } else { withAnimation(Self.settle) { cardRect = r } }
                        }
                        .padding(.horizontal, 16).padding(.bottom, 16)
                        // Chỉ mờ dần, không scaleEffect: scaleEffect gom cả thẻ thành một khối có toạ độ riêng, làm lúc nghe xong
                        // khung thẻ nhảy tức thì còn các nút cũ rơi xuống dưới mép thẻ (cách mở từ nút Tác vụ không bị vì không có nó)
                        .opacity(filled ? 1 : 0)
                        .transition(.identity)
                }
            } else if shown {
                // Nâng lên khỏi đáy để thẻ không dính vào góc bo màn hình và các ô phía sau
                card
                    // Đo khung thẻ cả khi mở từ nút Tác vụ / lối tắt: vùng nhoè phía trên co giãn theo thẻ (nghe xong thu gọn)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { r in
                        if cardRect == .zero { cardRect = r } else { withAnimation(Self.settle) { cardRect = r } }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 16)
                    // Chỉ trượt, không mờ dần: thẻ mờ nửa chừng đè lên các ô phía sau trông như bóng ma
                    .transition(.move(edge: .bottom))
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: shown)
        .presentationBackground(.clear)
        .task {
            if instant {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { shown = true }
            } else { shown = true }
            mic.onFinish = { said in handle(said) }
            if from != nil {
                // Chờ một nhịp cho thẻ được đo xong khung rồi mới biến hình tới đúng khung đó
                try? await Task.sleep(for: .milliseconds(30))
                withAnimation(.easeOut(duration: 0.1)) { faced = false }
                // Nảy nhẹ khi xuất hiện. Khối biến hình ở lại làm nền thẻ luôn, không đổi sang nền riêng của thẻ: đổi lớp thì khối và
                // nền thẻ lệch nhau vài điểm, lúc đổi trông như thẻ co thêm một nhịp (đổi mờ chéo thì nháy)
                withAnimation(Self.pop) { morph = 1 }
                withAnimation(.easeOut(duration: 0.2).delay(0.24)) { filled = true }   // chữ hiện khi khối đã lớn gần đủ, không tràn ra ngoài khối
                // Bật micro (dựng phiên âm thanh, chạy engine) chiếm luồng chính vài chục tới vài trăm mili giây: để nó chạy
                // đúng lúc nút đang biến thành thẻ thì hiệu ứng bị khựng: lò xo đang nảy đứng hình ở chỗ vọt quá, xong mới chạy
                // nốt, trông như thẻ co thêm một nhịp. Chờ lò xo dừng hẳn rồi mới bật.
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
            } else if !instant {
                // Mở từ nút Tác vụ / lối tắt: thẻ trượt lên từ đáy. Bật micro ngay lúc đó thì luồng chính bị chiếm, thẻ đứng hình giữa
                // chừng rồi mới hiện đủ (rõ nhất khi app vừa được mở từ đầu). Chờ thẻ trượt xong rồi mới bật
                try? await Task.sleep(for: .milliseconds(380))
                guard !Task.isCancelled else { return }
            }
            await mic.start()
            // Lần đầu dùng, iOS hiện hộp hỏi quyền micro / nhận dạng giọng nói đè lên thẻ: trên iOS 18 thẻ nhận onDisappear, micro bị
            // huỷ, cho phép xong thẻ quay lại thì đứng im ở "Đang bật micro…" không có nút nào. Thẻ vẫn còn đó mà micro bị huỷ
            // (không phải do người dùng đóng) thì bật lại
            if mic.isCancelled, shown {
                mic.onFinish = { said in handle(said) }
                await mic.start()
            }
            starting = false
        }
        .onDisappear { mic.cancel() }
        .fullScreenCover(isPresented: $shooting) {
            ReceiptCamera { img in
                shooting = false
                if let img, var e = saved {
                    ReceiptPhotos.save(img, id: e.id)
                    store.update(e)   // đổi dấu sửa: hàng ở Gần đây vẽ lại với ảnh, iCloud nhận bản mới
                    e = store.all.first { $0.id == e.id } ?? e
                    saved = e
                    withAnimation(.snappy) { attached = true }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                // Chụp xong (hoặc huỷ) thì lại để vài giây rồi tự đóng như sau khi ghi
                autoClose = Task {
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled else { return }
                    leave()
                }
            }
        }
    }

    // MARK: Thẻ

    /// Mở từ nút Quét QR và khối biến hình còn đang hiện: nền của thẻ do khối đó lo
    private var bare: Bool { from != nil && blob }

    private var card: some View {
        // Khoảng cách 18 giữa các phần tự đặt (không dùng spacing của VStack) để phần sóng âm co về 0 được cả khoảng cách
        // của nó: ghi xong thẻ thu gọn dần, nội dung phía trên hạ xuống theo (phim: theo `settle`; app: theo animation bên dưới)
        VStack(alignment: .leading, spacing: 0) {
            header
            // Một khối như dòng trạng thái: chữ gợi ý mới hiện ngay trong khối đang trượt cùng thẻ, không nhảy sẵn tới chỗ đích
            // trong lúc chữ cũ và số tiền còn đang trượt (hai dòng gợi ý chồng nhau, đè lên số tiền)
            amountBlock.geometryGroup().padding(.top, 18)
            let settle = film?.voice?.settle ?? 0
            if isListening || (film != nil && settle < 1) {
                // Điểm nguyên: khi vẽ ra PDF chữ luôn nằm ở toạ độ nguyên, hình thì không — dịch lẻ thì chữ và nền lệch nhau
                let room = (74 * (1 - settle)).rounded()   // 56 sóng âm + 18 khoảng cách
                Waveform(meter: mic.meter, film: film)
                    .frame(height: max(0, room - 18), alignment: .center).clipped()
                    .opacity(Double(1 - settle))
                    .padding(.top, min(18, room))
                    // Bấm Nói lại: hiện trễ một chút, đợi phần chữ phía trên trượt lên nhường chỗ (hiện ngay thì dòng gợi ý chưa kịp
                    // lên còn nằm đè lên nó). Nghe xong thì biến mất nhanh, kẻo phần trên hạ xuống đè lên nó
                    .transition(.asymmetric(insertion: .opacity.animation(Self.waveIn), removal: Self.swap))
            }
            buttons.padding(.top, 18)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Đang biến hình từ nút (bare): thẻ không vẽ nền, viền, bóng của riêng nó — khối biến hình chính là nền. Vẽ cả hai thì
        // lúc mở và lúc thu về thấy hai cửa sổ chồng nhau (nền thẻ mờ dần ở cỡ đầy đủ, khối thì đang lớn / đang co).
        // Không đổ bóng: khối biến hình không có bóng, nên lúc khối nhường chỗ cho thẻ thì bóng bật ra tức thì, trông như thẻ khựng
        .background(Palette.surface.opacity(bare ? 0 : 1), in: RoundedRectangle(cornerRadius: Self.corner, style: .circular))

        // Nghe xong thẻ thu gọn: đặt animation ngoài cùng để nền và nội dung cùng chuyển động. (Đặt trước nền thì nền đổi cỡ
        // tức thì trong khi tiêu đề còn đang hạ xuống, lòi ra ngoài thẻ. Cũng không dùng geometryGroup: nó làm các nút cũ rơi
        // xuống dưới mép thẻ rồi mới mờ đi.) Nội dung đi cùng khung lúc bật lên là nhờ thẻ có đủ nội dung từ đầu (xem `starting`).
        .animation(Self.settle, value: isListening)
    }

    /// Phần đổi theo trạng thái (dòng trạng thái, sóng âm, hàng nút): cái cũ biến mất và cái mới hiện ra gần như tức thì, tại chỗ.
    /// Mờ dần chậm thì chữ cũ và mới chồng lên nhau, sóng âm còn nằm lại trong lúc phần trên đã hạ xuống đè lên nó.
    private static let swap: AnyTransition = .opacity.animation(.easeOut(duration: 0.09))
    /// Nút Quét QR phình thành thẻ: nảy nhẹ, dừng hẳn trong ~0,6 giây (trước khi bật micro, xem chỗ dùng)
    /// Bo góc thẻ: đúng bằng góc nút Nhập ở đáy trang chủ (nút cao 78 nên bo 39, cung tròn như Capsule). Thẻ mở ra nằm đè lên
    /// nút ấy, cùng cách mép 16 điểm, nên mép thẻ trùng khít mép trái và góc dưới của nút — bo rộng hơn (42) thì mép nút ló ra
    /// thành một vệt cong ở góc dưới thẻ, nhìn như góc thẻ bị lõm
    private static let corner: CGFloat = 39
    private static let pop: Animation = .spring(duration: 0.42, bounce: 0.2)
    /// Nghe xong thẻ thu gọn; bấm Nói lại thẻ giãn ra
    private static let settle: Animation = .snappy(duration: 0.35 * pace)
    /// Sóng âm hiện ra khi bấm Nói lại (xem chỗ dùng)
    private static let waveIn: Animation = .easeOut(duration: 0.2 * pace).delay(0.15 * pace)
    /// Nhân thời gian hiệu ứng thẻ, để xem chậm khi chỉnh (để 1)
    private static let pace: Double = 1

    /// Dòng trạng thái là một dòng chữ duy nhất, chỉ đổi nội dung (mờ từ chữ cũ sang chữ mới) chứ không thay bằng dòng khác:
    /// nhờ vậy chữ đổi ngay trong lúc cả dòng di chuyển cùng thẻ (lên khi bấm Nói lại, xuống khi ghi xong). Thay bằng dòng
    /// khác thì dòng cũ nằm lại chỗ cũ trong lúc dòng mới đã ở chỗ mới, hai dòng chồng lên nhau.
    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                if savedNow != nil {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).transition(.opacity)
                } else if isListening {
                    PulseDot(time: film?.time).transition(.opacity)
                } else if undone {
                    Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(.secondary).transition(.opacity)
                } else if notUnderstood {
                    Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange).transition(.opacity)
                } else {
                    Image(systemName: "mic.fill").foregroundStyle(.secondary).transition(.opacity)
                }
            }
            .frame(minWidth: 18)
            Text(headerTitle).foregroundStyle(.secondary).lineLimit(2)
                .contentTransition(.opacity)
            Spacer()
            if let e = savedNow {
                // Đã ghi: góc này là Hoàn tác (đóng thẻ đã có nút Xong ở dưới), hàng nút dưới còn camera · Sửa · Xong cho rộng
                Button { undo(e) } label: {
                    Text(L("Hoàn tác")).font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 14).frame(height: 30).background(Palette.pill, in: Capsule())
                }
                .buttonStyle(Pressable())
                .foregroundStyle(.primary)
                .transition(.opacity)
            } else {
                Button { close() } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 30).background(Palette.pill, in: Circle())
                }
                .buttonStyle(Pressable())
                .foregroundStyle(.primary)
                .accessibilityLabel(L("Đóng"))
                .transition(.opacity)
            }
        }
        .font(.system(size: 15, weight: .medium))
        // Dòng trạng thái là một khối: chữ mới ("Đã ghi") hiện ra ngay trong dòng đang hạ xuống cùng thẻ,
        // không hiện sẵn ở chỗ đích rồi bị số tiền trôi ngang qua
        .geometryGroup()
    }

    private var headerTitle: String {
        if savedNow != nil { return L("Đã ghi") }
        if isListening { return L("Đang nghe") }
        if undone { return L("Đã hoàn tác, chưa ghi gì") }
        if notUnderstood { return L("Chưa nghe rõ số tiền") }
        return statusText
    }

    /// Số tiền to + danh mục đoán được + ghi chú, cập nhật ngay trong lúc nói.
    @ViewBuilder private var amountBlock: some View {
        // Vừa hoàn tác: không hiện lại số đã nghe, kẻo tưởng vẫn còn ghi
        let live = savedNow.map { (amount: $0.a, note: $0.n ?? "", cat: $0.c) }
            ?? (undone ? nil : QuickParse.spoken(heard)).map { (amount: $0.amount, note: $0.note, cat: store.guessEntry($0.note)) }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                // Số đổi: app dùng hiệu ứng số của iOS; phim tự vẽ số cũ trôi lên, số mới trồi lên
                let now = live.map { fmt($0.amount) } ?? "0"
                ZStack(alignment: .leading) {
                    if let prev = film?.voice?.previous, let t = film?.voice?.elapsed, t < 0.95 {
                        digits(prev, dim: prev == "0", elapsed: t, leaving: true)
                        digits(now, dim: live == nil, elapsed: t, leaving: false)
                    } else if film != nil {
                        // Phim: giữ cùng cách xếp chữ số như lúc đang chuyển, để chuyển xong con số không nhảy chỗ
                        digits(now, dim: live == nil, elapsed: 10, leaving: false)
                    } else {
                        // Khoản thu: mũi tên lên, chữ xanh như ở danh sách
                        let inc = live.map { Category.isIncome($0.cat) } ?? false
                        HStack(spacing: 4) {
                            if inc && live != nil { AmountArrow(up: true, size: 40).foregroundStyle(Palette.goodInk) }
                            number(now, dim: live == nil, income: inc)
                        }
                    }
                }
            }
            .animation(.snappy, value: live?.amount)
            if let l = live {
                let c = Category.get(l.cat)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            CategoryIcon(c: c, size: 18)
                            Text(c.name).font(.system(size: 15, weight: .semibold))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(c.color, in: Capsule())
                        .foregroundStyle(c.ink)
                        if !l.note.isEmpty {
                            Text(l.note.capFirst).font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    // Câu nhắc tới nhiều danh mục ("mua cát cho mèo"): hiện các danh mục còn lại, chạm là đổi
                    let others = Category.matches(l.note).filter { $0 != l.cat }.prefix(3)
                    if !others.isEmpty {
                        HStack(spacing: 6) {
                            Text(L("Hay là")).font(.system(size: 13)).foregroundStyle(.secondary)
                            ForEach(Array(others), id: \.self) { k in
                                let o = Category.get(k)
                                Button { switchCategory(to: k) } label: {
                                    HStack(spacing: 5) {
                                        CategoryIcon(c: o, size: 16)
                                        Text(o.name).font(.system(size: 15, weight: .medium))
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
                // Cùng một dòng chữ, chỉ đổi nội dung ("Đã nghe: …" -> "Nói ví dụ: …"): mờ sang chữ mới trong lúc trượt lên cùng thẻ
                Text(hint).font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(2)
                    .contentTransition(.opacity)
            }
        }
    }

    private func number(_ s: String, dim: Bool, income: Bool = false) -> some View {
        Text(s).font(.system(size: 40, weight: .bold)).kerning(-1.5)
            .foregroundStyle(dim ? Color.secondary.opacity(0.5) : income ? Palette.goodInk : .primary)
            .contentTransition(.numericText())
            .minimumScaleFactor(0.5).lineLimit(1)
    }

    /// Phim: con số đang chuyển, từng chữ số một (xem FilmFrame.Voice.previous)
    private func digits(_ s: String, dim: Bool, elapsed: Double, leaving: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: -2) {
            ForEach(Array(s.enumerated()), id: \.offset) { i, ch in
                let p = FilmFrame.spring((elapsed - 0.035 * Double(i)) / 0.42)
                Text(String(ch)).font(.system(size: 40, weight: .bold))
                    .padding(.horizontal, ch == "." || ch == "," ? -2 : 0)   // dấu chấm ôm sát hai số bên cạnh như khi viết liền
                    .foregroundStyle(dim ? Color.secondary.opacity(0.5) : .primary)
                    .scaleEffect(leaving ? 1 - 0.3 * min(1, p) : 0.7 + 0.3 * min(1, p))
                    .opacity(Double(leaving ? max(0, 1 - 2 * p) : min(1, 1.6 * p)))
                    .offset(y: (leaving ? -22 * p : 22 * (1 - p)).rounded())
            }
        }
        .lineLimit(1).fixedSize()
    }

    private var hint: String {
        if undone { return L("Bấm Nói lại để nói khoản khác.") }
        if notUnderstood { return mic.text.isEmpty ? L("Vui lòng nói số tiền để ghi, ví dụ: \"ba lăm nghìn cà phê\"") : L("Đã nghe: \"%@\"", mic.text) }
        if isListening { return heard.isEmpty ? L("Nói ví dụ: \"ba lăm nghìn cà phê\" hoặc \"nhận lương mười lăm triệu\"") : heard }
        if mic.phase == .denied { return L("Vào Cài đặt › Payso để bật Micro và Nhận dạng giọng nói.") }
        return ""
    }

    private var statusText: String {
        switch mic.phase {
        case .denied: return L("Cần quyền micro")
        case .failed(let why): return why
        default: return L("Đang bật micro…")
        }
    }

    // MARK: Nút

    /// Nút chính (bên phải) theo trạng thái: tên, việc làm, có đang tắt không
    private var primaryButton: (title: String, off: Bool, run: () -> Void)? {
        if savedNow != nil { return (L("Xong"), false, { autoClose?.cancel(); leave() }) }
        // Ngừng nghe ngay, không chờ im lặng; ghi xong là đóng thẻ luôn (không bắt bấm Xong lần nữa)
        if isListening { return (L("Xong"), heard.isEmpty, { closeAfterSave = true; mic.finish() }) }
        if mic.phase == .denied {
            return (L("Mở Cài đặt"), false, { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } })
        }
        // Mọi trạng thái còn lại đều có nút "Nói lại" (kể cả khi micro chưa bật được mà không rõ vì sao): thẻ không bao giờ
        // rơi vào cảnh không có nút nào để bấm
        return (L("Nói lại"), false, { mic.onFinish = { said in handle(said) }; retry() })
    }

    /// Nút chính là cùng một nút qua mọi trạng thái (nghe xong nó chỉ hẹp lại, không biến mất rồi hiện lại);
    /// chỉ các nút phụ bên trái đổi: "Quét QR" khi chưa ghi, camera + "Sửa" khi đã ghi (Hoàn tác ở góc trên phải thẻ).
    @ViewBuilder private var buttons: some View {
        HStack(spacing: 10) {
            Group {
                if let e = savedNow {
                    // Chụp ảnh hoá đơn gắn thẳng vào khoản vừa ghi (không phải mở màn sửa)
                    Button {
                        autoClose?.cancel()
                        if Pro.shared.allow(.photos) { shooting = true }
                    } label: {
                        Image(systemName: attached ? "checkmark" : "camera.fill").font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(attached ? Palette.goodInk : .primary)
                            .frame(width: 64, height: 64)
                            .background(Palette.pill, in: Circle())
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(Pressable())
                    .accessibilityLabel(attached ? L("Đã có ảnh") : L("Chụp ảnh hoá đơn"))
                    pill(L("Sửa"), primary: false) { autoClose?.cancel(); leave(); onEdit(e) }
                } else if primaryButton != nil {
                    pill(L("Quét QR"), primary: false) { mic.cancel(); leave(); onScan() }
                }
            }
            .transition(Self.swap)
            if let p = primaryButton {
                pill(p.title, primary: true, p.run).disabled(p.off).opacity(p.off ? 0.4 : 1)
            }
        }
    }

    private func pill(_ title: String, primary: Bool, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title).font(.system(size: 17, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 64)   // cao cho dễ nhấn
                .foregroundStyle(primary ? Palette.ctaInk : .primary)
                .background(primary ? Palette.cta : Palette.pill, in: Capsule())
        }
        .buttonStyle(Pressable())
        .filmPressed(primary ? film?.pressed["voice-primary"] ?? 0 : 0)
    }

    // MARK: Xử lý

    private func handle(_ said: String) {
        // Câu có nhắc tên nhóm ("300k đi chợ nhà mình"): ghi vào nhóm đó, mình trả, chia đều cả nhóm; phần của mình ghi vào
        // chi tiêu cá nhân. Xong đóng thẻ, báo ở màn chính
        if !said.isEmpty, let hit = House.shared.groupMentioned(in: said),
           let q = QuickParse.spoken(hit.rest) ?? QuickParse.expense(hit.rest) {
            let cat = store.guessCategory(q.note), note = q.note
            Task {
                guard let mine = await House.shared.quickSpend(in: hit.group, amount: q.amount, note: note, cat: cat) else {
                    notUnderstood = true
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    return
                }
                if mine > 0 { store.add(amount: mine, note: note.isEmpty ? hit.group.name : note, cat: cat, toast: false) }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                store.show(L("Đã ghi %@ vào %@ · bạn %@", fmt(q.amount), hit.group.name, fmt(mine)))
                leave()
            }
            return
        }
        guard !said.isEmpty, let e = store.quickAdd(said, spoken: true, toast: false) else {
            notUnderstood = true
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        saved = e
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if closeAfterSave {
            // Đã bấm Xong lúc đang nghe: ghi xong đóng thẻ, báo "Đã lưu" kèm Hoàn tác ở màn chính
            closeAfterSave = false
            store.show(L("Đã lưu %@", fmt(e.a))) { [store] in store.remove(id: e.id, toast: false) }
            leave()
            return
        }
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
        withAnimation(.snappy) { saved = nil; undone = true; attached = false }   // ảnh thuộc khoản vừa bỏ
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

    /// Sang dạng "Đang nghe" như lúc mới mở thẻ (`starting`): micro chưa kịp bật cũng đã hiện như đang nghe. Không thì có một
    /// nhịp thẻ không ở trạng thái nào: mất sóng âm và cả hàng nút, co lại rồi lại nở ra khi micro chạy.
    /// Mọi thứ đổi trong cùng một nhịp hiệu ứng: thẻ giãn ra cho sóng âm, dòng trạng thái và dòng gợi ý vừa mờ sang chữ mới
    /// vừa trượt lên theo thẻ, sóng âm hiện dần.
    private func retry() {
        closeAfterSave = false
        attached = false
        withAnimation(Self.settle) {
            notUnderstood = false
            undone = false
            starting = true
        }
        Task {
            await mic.start()
            starting = false
        }
    }

    private func close() {
        autoClose?.cancel()
        mic.cancel()
        leave()
    }

    /// Đóng thẻ: tự trượt thẻ xuống và mờ nền trước, xong mới gỡ màn hình (không hiệu ứng).
    /// Để hệ thống tự kéo cả màn hình xuống thì nền tối tắt phụt và bóng đổ của thẻ bị vệt.
    private func leave() {
        guard shown else { return }
        if from != nil {
            // Thu về nút: nội dung mờ đi trước, rồi khối co lại thành nút
            blob = true
            withAnimation(.easeIn(duration: 0.1)) { filled = false }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.9).delay(0.08)) { morph = 0 }
            withAnimation(.easeIn(duration: 0.3).delay(0.1)) { shown = false }
            // Khối co về gần xong thì mặt nút hiện lại trên khối: tới lúc gỡ lớp này, khối đã y hệt nút thật bên dưới
            withAnimation(.easeOut(duration: 0.14).delay(0.26)) { faced = true }
        } else {
            withAnimation(.easeIn(duration: 0.25)) { shown = false }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(from != nil ? 470 : 270))
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { if let onClose { onClose() } else { dismiss() } }
        }
    }
}

/// Sóng âm: dải thanh dọc mảnh cách đều, mỗi thanh cao thấp khác nhau và nhảy theo nhịp riêng (xen kẽ như sóng giọng nói,
/// không phồng thành một cục ở giữa). Độ cao chung theo độ to thật của giọng; im lặng chỉ còn các vạch ngắn.
private struct Waveform: View {
    @ObservedObject var meter: MicLevel
    /// Dựng phim: độ to và thời điểm lấy từ phim
    var film: FilmFrame? = nil
    @State private var smooth = Smoother()
    /// Lúc dải sóng hiện ra (thẻ vừa mở, hoặc bấm Nói lại)
    @State private var born = Date()

    var body: some View {
        if let film, let v = film.voice { dots(level: v.level, time: film.time) }
        else {
            TimelineView(.animation) { t in
                dots(level: max(smooth.step(to: meter.value, at: t.date), Self.hello(t.date.timeIntervalSince(born))),
                     time: t.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    /// Sóng nháy nhẹ một lần khi vừa hiện ra, để biết là app đang nghe (micro còn đang bật, chưa có tiếng thì sóng nằm im):
    /// đợi thẻ lên xong (0,35 giây) rồi dâng lên khoảng nửa chiều cao và hạ xuống trong 0,7 giây
    private static func hello(_ elapsed: TimeInterval) -> CGFloat {
        let x = (elapsed - 0.35) / 0.7
        guard x > 0, x < 1 else { return 0 }
        return 0.5 * CGFloat(sin(.pi * x))
    }

    private static let barWidth: CGFloat = 2
    /// Khoảng cách cố định giữa các thanh; số thanh tự tính theo bề ngang cho vừa khít
    private static let gap: CGFloat = 3

    /// Số giả ngẫu nhiên cố định 0…1 theo thứ tự thanh: dáng cao thấp riêng và nhịp nhảy riêng của từng thanh
    private static func hash(_ i: Int, _ salt: Double) -> Double {
        let v = sin(Double(i) * 12.9898 + salt * 78.233) * 43758.5453
        return v - v.rounded(.down)
    }

    /// Hai mép thấp dần (khoảng 1/5 dải mỗi bên), phần giữa giữ nguyên độ cao
    private static func taper(_ i: Int, of n: Int) -> Double {
        let ramp = max(1, Double(n) * 0.2)
        let t = min(1, Double(min(i, n - 1 - i)) / ramp)
        return 0.2 + 0.8 * t * t * (3 - 2 * t)
    }

    /// Lưới chấm: đường kính chấm, khoảng cách giữa các chấm, số hàng
    private static let dot: CGFloat = 5
    private static let dotGap: CGFloat = 3.5
    private static let rows = 7
    /// Xanh lá của icon app
    private static let green = Color(hex: 0x61BE6E)

    /// Ma trận chấm: mỗi cột sáng một số chấm đều từ hàng giữa ra trên dưới theo độ to (dáng cao thấp xen kẽ, hai mép thấp
    /// như dải thanh dọc trước đây); chấm không sáng vẫn hiện mờ để thấy cả lưới.
    private func dots(level: CGFloat, time: Double) -> some View {
        let lv: CGFloat = 0.1 + 0.9 * min(level, 1)   // im lặng vẫn sáng hàng giữa
        return Canvas { ctx, size in
            let step = Self.dot + Self.dotGap
            let n = max(1, Int((size.width + Self.dotGap) / step))
            let x0 = (size.width - (CGFloat(n) * step - Self.dotGap)) / 2
            let y0 = (size.height - (CGFloat(Self.rows) * step - Self.dotGap)) / 2
            let mid = Self.rows / 2
            for i in 0..<n {
                let shape: Double = (0.6 + 0.4 * Self.hash(i, 1)) * Self.taper(i, of: n)
                let speed: Double = 5 + 7 * Self.hash(i, 2)
                let jitter: Double = 0.5 + 0.5 * sin(time * speed + 6.283 * Self.hash(i, 3))
                // ×1,5: nói bình thường các cột giữa lên tới hàng trên cùng hoặc sát đó
                let h: Double = 1.5 * Double(lv) * shape * (0.6 + 0.4 * jitter)
                let reach = Int((min(h, 1) * Double(mid)).rounded())   // số chấm sáng mỗi phía hàng giữa
                for r in 0..<Self.rows {
                    let rect = CGRect(x: x0 + CGFloat(i) * step, y: y0 + CGFloat(r) * step, width: Self.dot, height: Self.dot)
                    let on = abs(r - mid) <= reach
                    // Chấm sáng xanh lá; chấm nền đen nhạt (chế độ tối thành trắng nhạt)
                    ctx.fill(Path(ellipseIn: rect), with: .color(on ? Self.green : Color.primary.opacity(0.1)))
                }
            }
        }
    }

    /// Độ to micro nhảy theo từng lần đo (~43 lần/giây, giọng nói lên xuống thất thường) và về 0 ngay khi ngừng nghe:
    /// vẽ thẳng theo đó thì sóng giật lúc nói và tụt phụt lúc nói xong. Ở mỗi khung hình, độ cao sóng chỉ trôi dần tới
    /// độ to mới: lên nhanh để bắt kịp giọng, xuống chậm cho êm.
    private final class Smoother {
        private var value: CGFloat = 0
        private var last: Date?

        func step(to target: CGFloat, at now: Date) -> CGFloat {
            let dt = last.map { min(now.timeIntervalSince($0), 0.1) } ?? 0
            last = now
            let rate: Double = target > value ? 12 : 3.5   // lên nhanh, xuống chậm
            value += (target - value) * CGFloat(1 - exp(-dt * rate))
            return value
        }
    }
}

/// Chấm đỏ nhấp nháy cạnh chữ "Đang nghe".
private struct PulseDot: View {
    @State private var on = false
    /// Dựng phim: nhấp nháy theo thời điểm của phim
    var time: Double? = nil

    var body: some View {
        Circle().fill(Color.red).frame(width: 9, height: 9)
            .opacity(time.map { 0.675 + 0.325 * sin($0 * .pi / 0.7) } ?? (on ? 1 : 0.35))
            .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever()) { on = true } }
    }
}
