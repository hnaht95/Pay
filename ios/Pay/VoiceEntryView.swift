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
    /// Thẻ đã bị đóng (xem `cancel`): từ đây không ghi gì nữa, không bật lại micro
    private var cancelled = false

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
        guard !cancelled else { return }   // đóng thẻ khi micro chưa kịp bật: không bật nữa
        guard speechOK, micOK else { phase = .denied; return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: Lang.isEnglish ? "en-US" : "vi-VN")), recognizer.isAvailable else {
            phase = .failed(L("iPhone chưa nhận được giọng tiếng Việt lúc này. Thử lại sau, hoặc quét QR."))
            return
        }
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
                stop()
                phase = .failed(L("Không dùng được micro lúc này. Thử lại, hoặc quét QR."))
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
            waitForSilence()
        } catch {
            stop()
            phase = .failed(L("Không bật được micro."))
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
                card.padding(.horizontal, 12).padding(.bottom, 34).offset(y: ((1 - v.shown) * 460).rounded())
            }
        } else { live }
    }

    private var live: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(shown ? 0.35 : 0).ignoresSafeArea()
                .onTapGesture { close() }
            if let from {
                // Khối biến hình: từ khung và màu của nút tới khung và màu của thẻ
                GeometryReader { g in
                    let o = g.frame(in: .global).origin
                    let to = cardRect == .zero ? from : cardRect
                    let r = CGRect(x: from.minX + (to.minX - from.minX) * morph, y: from.minY + (to.minY - from.minY) * morph,
                                   width: from.width + (to.width - from.width) * morph, height: from.height + (to.height - from.height) * morph)
                    let shape = RoundedRectangle(cornerRadius: from.height / 2 + (42 - from.height / 2) * morph, style: .continuous)
                    shape.fill(Palette.cta)
                        // Đổi màu nhanh ở đầu (xong khi khối mới lớn được 40%): đổi đều suốt quãng thì khối cứ xám lửng lơ, trông như khựng
                        .overlay(shape.fill(Palette.surface).opacity(Double(min(1, max(0, morph) * 2.5))))
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
                        .padding(.horizontal, 12).padding(.bottom, 34)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global).insetBy(dx: 12, dy: 0).divided(atDistance: 34, from: .maxYEdge).remainder } action: { cardRect = $0 }
                        // Chỉ mờ dần, không scaleEffect: scaleEffect gom cả thẻ thành một khối có toạ độ riêng, làm lúc nghe xong
                        // khung thẻ nhảy tức thì còn các nút cũ rơi xuống dưới mép thẻ (cách mở từ nút Tác vụ không bị vì không có nó)
                        .opacity(filled ? 1 : 0)
                        .transition(.identity)
                }
            } else if shown {
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
            if from != nil {
                // Chờ một nhịp cho thẻ được đo xong khung rồi mới biến hình tới đúng khung đó
                try? await Task.sleep(for: .milliseconds(30))
                withAnimation(.easeOut(duration: 0.1)) { faced = false }
                withAnimation(.spring(response: 0.44, dampingFraction: 0.84)) { morph = 1 }
                withAnimation(.easeOut(duration: 0.2).delay(0.24)) { filled = true }   // chữ hiện khi khối đã lớn gần đủ, không tràn ra ngoài khối
                Task { try? await Task.sleep(for: .milliseconds(560)); if filled { blob = false } }
                // Bật micro (dựng phiên âm thanh, chạy engine) chiếm luồng chính vài chục tới vài trăm mili giây: để nó chạy
                // đúng lúc nút đang biến thành thẻ thì hiệu ứng bị khựng. Chờ hiệu ứng xong rồi mới bật.
                try? await Task.sleep(for: .milliseconds(470))
                guard !Task.isCancelled else { return }
            }
            await mic.start()
            starting = false
        }
        .onDisappear { mic.cancel() }
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
        .background(Palette.surface.opacity(bare ? 0 : 1), in: RoundedRectangle(cornerRadius: 42, style: .continuous))
        // Viền mảnh cho thẻ tách khỏi nền phía sau (chế độ tối thẻ và nền gần cùng màu)
        .overlay(RoundedRectangle(cornerRadius: 42, style: .continuous).strokeBorder(Color.primary.opacity(bare ? 0 : 0.08), lineWidth: 1))
        .shadow(color: .black.opacity(bare ? 0 : 0.18), radius: 24, y: 8)
        // Nghe xong thẻ thu gọn: đặt animation ngoài cùng để nền và nội dung cùng chuyển động. (Đặt trước nền thì nền đổi cỡ
        // tức thì trong khi tiêu đề còn đang hạ xuống, lòi ra ngoài thẻ. Cũng không dùng geometryGroup: nó làm các nút cũ rơi
        // xuống dưới mép thẻ rồi mới mờ đi.) Nội dung đi cùng khung lúc bật lên là nhờ thẻ có đủ nội dung từ đầu (xem `starting`).
        .animation(Self.settle, value: isListening)
    }

    /// Phần đổi theo trạng thái (dòng trạng thái, sóng âm, hàng nút): cái cũ biến mất và cái mới hiện ra gần như tức thì, tại chỗ.
    /// Mờ dần chậm thì chữ cũ và mới chồng lên nhau, sóng âm còn nằm lại trong lúc phần trên đã hạ xuống đè lên nó.
    private static let swap: AnyTransition = .opacity.animation(.easeOut(duration: 0.09))
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
            Button { close() } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30).background(Palette.pill, in: Circle())
            }
            .buttonStyle(Pressable())
            .foregroundStyle(.primary)
            .accessibilityLabel(L("Đóng"))
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
            ?? (undone ? nil : QuickParse.spoken(heard)).map { (amount: $0.amount, note: $0.note, cat: store.guessCategory($0.note)) }
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
                        number(now, dim: live == nil)
                    }
                }
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
                        .foregroundStyle(c.ink)
                        if !l.note.isEmpty {
                            Text(l.note.capFirst).font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    // Câu nhắc tới nhiều danh mục ("mua cát cho mèo"): hiện các danh mục còn lại, chạm là đổi
                    let others = Category.matches(l.note).filter { $0 != l.cat }.prefix(3)
                    if !others.isEmpty {
                        HStack(spacing: 6) {
                            Text(L("Hay là")).font(.system(size: 14)).foregroundStyle(.secondary)
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
                // Cùng một dòng chữ, chỉ đổi nội dung ("Đã nghe: …" -> "Nói ví dụ: …"): mờ sang chữ mới trong lúc trượt lên cùng thẻ
                Text(hint).font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(2)
                    .contentTransition(.opacity)
            }
        }
    }

    private func number(_ s: String, dim: Bool) -> some View {
        Text(s).font(.system(size: 46, weight: .bold)).kerning(-1.5)
            .foregroundStyle(dim ? Color.secondary.opacity(0.5) : .primary)
            .contentTransition(.numericText())
            .minimumScaleFactor(0.5).lineLimit(1)
    }

    /// Phim: con số đang chuyển, từng chữ số một (xem FilmFrame.Voice.previous)
    private func digits(_ s: String, dim: Bool, elapsed: Double, leaving: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: -2) {
            ForEach(Array(s.enumerated()), id: \.offset) { i, ch in
                let p = FilmFrame.spring((elapsed - 0.035 * Double(i)) / 0.42)
                Text(String(ch)).font(.system(size: 46, weight: .bold))
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
        if notUnderstood { return mic.text.isEmpty ? L("Không nghe thấy gì.") : L("Đã nghe: \"%@\"", mic.text) }
        if isListening { return heard.isEmpty ? L("Nói ví dụ: \"ba lăm nghìn cà phê\"") : heard }
        if mic.phase == .denied { return L("Vào Cài đặt › Pay để bật Micro và Nhận dạng giọng nói.") }
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
        if isListening { return (L("Xong"), heard.isEmpty, { mic.finish() }) }          // ngừng nghe ngay, không chờ im lặng
        if mic.phase == .denied {
            return (L("Mở Cài đặt"), false, { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } })
        }
        if notUnderstood || undone || mic.phase != .idle { return (L("Nói lại"), false, { retry() }) }
        return nil
    }

    /// Nút chính là cùng một nút qua mọi trạng thái (nghe xong nó chỉ hẹp lại, không biến mất rồi hiện lại);
    /// chỉ các nút phụ bên trái đổi: "Quét QR" khi chưa ghi, "Hoàn tác" + "Sửa" khi đã ghi.
    @ViewBuilder private var buttons: some View {
        HStack(spacing: 10) {
            Group {
                if let e = savedNow {
                    // Hoàn tác nằm ngay trong thẻ (không hiện thanh "Đã lưu" bên ngoài nữa)
                    pill(L("Hoàn tác"), primary: false) { undo(e) }
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
            Text(title).font(.system(size: 18, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 64)   // cao cho dễ nhấn
                .foregroundStyle(primary ? Palette.ctaInk : .primary)
                .background(primary ? Palette.cta : Palette.pill, in: Capsule())
        }
        .buttonStyle(Pressable())
        .filmPressed(primary ? film?.pressed["voice-primary"] ?? 0 : 0)
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

    /// Sang dạng "Đang nghe" như lúc mới mở thẻ (`starting`): micro chưa kịp bật cũng đã hiện như đang nghe. Không thì có một
    /// nhịp thẻ không ở trạng thái nào: mất sóng âm và cả hàng nút, co lại rồi lại nở ra khi micro chạy.
    /// Mọi thứ đổi trong cùng một nhịp hiệu ứng: thẻ giãn ra cho sóng âm, dòng trạng thái và dòng gợi ý vừa mờ sang chữ mới
    /// vừa trượt lên theo thẻ, sóng âm hiện dần.
    private func retry() {
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

/// Sóng âm: dải sáng gradient mờ (vài đốm màu nhoè, trôi qua lại), kiểu giao diện giọng nói AI. Nói to thì các đốm nở
/// to và đậm lên theo độ to thật của giọng; im lặng chỉ còn vệt sáng nhỏ thở nhẹ để biết vẫn đang nghe.
private struct Waveform: View {
    @ObservedObject var meter: MicLevel
    /// Dựng phim: độ to và thời điểm lấy từ phim
    var film: FilmFrame? = nil
    @State private var smooth = Smoother()

    var body: some View {
        if let film, let v = film.voice { glow(level: v.level, time: film.time) }
        else {
            TimelineView(.animation) { t in
                glow(level: smooth.step(to: meter.value, at: t.date), time: t.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    /// Các đốm màu: màu, vị trí ngang (0…1), tốc độ trôi, lệch pha
    private static let blobs: [(color: Color, x: Double, speed: Double, phase: Double)] = [
        (Color(hex: 0x8EE6B0), 0.30, 0.9, 0.0),    // xanh bạc hà
        (Color(hex: 0x5FD08C), 0.50, 1.3, 2.1),    // xanh lá
        (Color(hex: 0x8CC8FF), 0.70, 1.1, 4.2),    // xanh trời
        (Color(hex: 0xB8A6FF), 0.42, 0.7, 5.3),    // tím nhạt
    ]

    private func glow(level: CGFloat, time: Double) -> some View {
        Canvas { ctx, size in
            let lv: CGFloat = 0.12 + 0.88 * min(level, 1)   // im lặng vẫn còn vệt sáng nhỏ
            // Nhoè theo chiều cao dải; đốm không cao quá ~60% dải để phần nhoè không bị cắt phẳng ở mép trên dưới
            ctx.addFilter(.blur(radius: size.height * 0.26))
            for b in Self.blobs {
                let drift: Double = sin(time * b.speed + b.phase)
                let breathe: Double = sin(time * 2.1 + b.phase * 1.7)
                let w: CGFloat = size.width * (0.22 + 0.2 * lv) * CGFloat(1 + 0.08 * breathe)
                // Giữ cả đốm (kèm phần nhoè) trong khung: trôi ra sát mép thì phần nhoè bị cắt thành mép thẳng
                let margin: CGFloat = w / 2 + size.height * 0.4
                let cx: CGFloat = min(max(size.width * CGFloat(b.x + 0.12 * drift), margin), size.width - margin)
                let h: CGFloat = size.height * (0.18 + 0.42 * lv) * CGFloat(1 + 0.12 * breathe)
                let rect = CGRect(x: cx - w / 2, y: (size.height - h) / 2, width: w, height: h)
                ctx.fill(Path(ellipseIn: rect), with: .color(b.color.opacity(Double(0.45 + 0.5 * lv))))
            }
        }
        // Phần nhoè tràn khỏi khung vẽ bị cắt phẳng ở mép trên dưới (thành dải chữ nhật): mờ dần hai mép cho vệt sáng tan vào nền
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.32),
                                     .init(color: .black, location: 0.68), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.15),
                                     .init(color: .black, location: 0.85), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
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
