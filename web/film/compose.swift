// Ghép bản quay màn hình máy ảo vào khung iPhone thành phim MP4 cho trang giới thiệu.
//
//   swift compose.swift <bản quay.mov> <khung.png> <ra.mp4> <đoạn>...
//
// <khung.png>: khung máy của Apple đã phủ nền trắng (chỉ chừa lỗ màn hình), cỡ 1350x2760.
// Mỗi <đoạn> là "từ-đến" hoặc "từ-đến@tốc độ" (giây trong bản quay), ví dụ 1.2-4.8 hay 5-9@2;
// các đoạn nối liền nhau, bỏ phần chờ giữa các lần bấm. Đoạn lấy từ bản quay khác: "tệp.mov:từ-đến".
//
// PRESS=<giây> (biến môi trường): vạch xanh lá hiện cạnh nút Tác vụ (Action) lúc đó, trượt vào sát nút và giữ,
// như ngón tay nhấn giữ — cho phim "Nói là ghi" bắt đầu từ màn hình khoá. Phim chừa lề hai bên cho vạch này.
// UNLOCK=<giây>: đoạn đầu (màn hình khoá) mở khoá sang phần sau trong ngần ấy giây, kiểu iOS: màn hình khoá
// trượt lên và mờ dần, app bên dưới hiện ra hơi to rồi thu về đúng cỡ.
import AVFoundation
import AppKit

let a = CommandLine.arguments
guard a.count >= 5 else { print("swift compose.swift in.mov frame.png out.mp4 0-3 4-8@2 ..."); exit(1) }
let src = AVURLAsset(url: URL(fileURLWithPath: a[1]))
let frameImage = NSImage(contentsOfFile: a[2])!
let out = URL(fileURLWithPath: a[3])
try? FileManager.default.removeItem(at: out)

let scale: CGFloat = 0.5                       // khung 1350x2760 -> 675x1380
let pad: CGFloat = 40                          // lề mỗi bên, chỗ cho vạch nhấn nút cạnh máy
let render = CGSize(width: 676 + 2 * pad, height: 1380)  // H.264 cần cạnh chẵn
let hole = CGPoint(x: 72, y: 69)               // góc trên trái của màn hình trong khung (điểm ảnh khung)
let actionButton = (x: 20.0, top: 581.0, bottom: 706.0)   // nút Tác vụ ở cạnh trái khung (điểm ảnh khung)
let paper = CGColor(red: 1, green: 1, blue: 1, alpha: 1)   // nền trắng tinh: trang web hoà video vào nền (mix-blend-mode: multiply), khỏi phải khớp màu

func constantRate(_ asset: AVAsset, to url: URL) async throws {
    let track = try await asset.loadTracks(withMediaType: .video)[0]
    let size = try await track.load(.naturalSize)
    let end = try await asset.load(.duration)
    let reader = try AVAssetReader(asset: asset)
    let ro = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(ro)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let wi = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 40_000_000]])
    let ad = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: wi, sourcePixelBufferAttributes: nil)
    writer.add(wi)
    reader.startReading(); writer.startWriting(); writer.startSession(atSourceTime: .zero)
    let step = CMTime(value: 1, timescale: 30)
    var t = CMTime.zero, last: CVPixelBuffer?
    var pending = ro.copyNextSampleBuffer()
    while t < end {
        // hình mới nhất có thời điểm <= t
        while let b = pending, CMSampleBufferGetPresentationTimeStamp(b) <= t {
            if let px = CMSampleBufferGetImageBuffer(b) { last = px }
            pending = ro.copyNextSampleBuffer()
        }
        if let px = last {
            while !wi.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            ad.append(px, withPresentationTime: t)
        }
        t = t + step
    }
    wi.markAsFinished()
    await writer.finishWriting()
}

let sem = DispatchSemaphore(value: 0)
Task {
  do {
    // Máy ảo chỉ ghi khung hình khi màn hình đổi, giữa hai lần đổi không có khung nào. Đổi về 30 khung/giây,
    // mỗi khung là hình mới nhất tính tới lúc đó (đoạn đứng yên giữ nguyên hình, không đen), rồi mới cắt ghép.
    var tracks: [String: AVAssetTrack] = [:], temps: [URL] = [], assets: [AVURLAsset] = []
    defer { temps.forEach { try? FileManager.default.removeItem(at: $0) } }
    func track(_ path: String) async throws -> AVAssetTrack {
        if let t = tracks[path] { return t }
        let cfr = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".mov")
        try await constantRate(AVURLAsset(url: URL(fileURLWithPath: path)), to: cfr)
        temps.append(cfr)
        let asset = AVURLAsset(url: cfr)
        assets.append(asset)   // giữ bản quay sống tới khi xuất xong: tự giải phóng thì track hỏng (-12780)
        let t = try await asset.loadTracks(withMediaType: .video)[0]
        tracks[path] = t
        return t
    }
    let natural = try await track(a[1]).load(.naturalSize)
    let comp = AVMutableComposition()
    let vt = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
    let unlock = ProcessInfo.processInfo.environment["UNLOCK"].flatMap(Double.init).map { CMTime(seconds: $0, preferredTimescale: 600) }
    let lockTrack = unlock == nil ? nil : comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
    var lockEnd = CMTime.zero
    var at = CMTime.zero
    for (n, whole) in a[4...].enumerated() {
        let file = whole.contains(":") ? String(whole.split(separator: ":")[0]) : a[1]
        let spec = whole.contains(":") ? String(whole.split(separator: ":")[1]) : whole
        let track = try await track(file)
        let parts = spec.split(separator: "@")
        let range = parts[0].split(separator: "-").map { Double($0)! }
        let speed = parts.count > 1 ? Double(parts[1])! : 1
        // không quá cuối bản quay: phần thừa sẽ là màn đen
        let r = CMTimeRange(start: CMTime(seconds: range[0], preferredTimescale: 600),
                            end: min(CMTime(seconds: range[1], preferredTimescale: 600), try await track.load(.timeRange).end))
        if n == 0, let lockTrack, let unlock {
            // màn hình khoá nằm trên rãnh riêng, phần sau bắt đầu sớm hơn `unlock` giây để hai bên chồng lên nhau
            try lockTrack.insertTimeRange(r, of: track, at: .zero)
            lockEnd = r.duration
            at = r.duration - unlock
            continue
        }
        try vt.insertTimeRange(r, of: track, at: at)
        if speed != 1 {
            vt.scaleTimeRange(CMTimeRange(start: at, duration: r.duration),
                              toDuration: CMTime(seconds: r.duration.seconds / speed, preferredTimescale: 600))
        }
        at = vt.timeRange.end
    }

    // Màn hình máy ảo (1206x2622) thu nhỏ đặt vào lỗ của khung
    let s = (1206 * scale) / natural.width
    let li = AVMutableVideoCompositionLayerInstruction(assetTrack: vt)
    let tx = hole.x * scale + pad, ty = hole.y * scale
    let base = CGAffineTransform(scaleX: s, y: s).concatenating(CGAffineTransform(translationX: tx, y: ty))
    li.setTransform(base, at: .zero)
    var layers = [li]
    if let lockTrack, let unlock {
        let during = CMTimeRange(start: lockEnd - unlock, duration: unlock)
        let w = natural.width * s, h = natural.height * s
        // app: to hơn 7% quanh tâm rồi thu về
        let z: CGFloat = 1.07
        let big = CGAffineTransform(scaleX: s * z, y: s * z)
            .concatenating(CGAffineTransform(translationX: tx - (z - 1) * w / 2, y: ty - (z - 1) * h / 2))
        li.setTransformRamp(fromStart: big, toEnd: base, timeRange: during)
        li.setOpacityRamp(fromStartOpacity: 0.6, toEndOpacity: 1, timeRange: during)
        // màn hình khoá: trượt lên 40% chiều cao và mờ hẳn
        let lock = AVMutableVideoCompositionLayerInstruction(assetTrack: lockTrack)
        lock.setTransform(base, at: .zero)
        lock.setTransformRamp(fromStart: base, toEnd: base.concatenating(CGAffineTransform(translationX: 0, y: -0.4 * h)), timeRange: during)
        lock.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: during)
        lock.setOpacity(0, at: lockEnd)
        layers = [lock, li]
    }
    let ins = AVMutableVideoCompositionInstruction()
    ins.timeRange = CMTimeRange(start: .zero, duration: comp.duration)
    ins.layerInstructions = layers
    ins.backgroundColor = paper

    let parent = CALayer(), video = CALayer(), overlay = CALayer()
    for l in [parent, video, overlay] { l.frame = CGRect(origin: .zero, size: render) }
    overlay.contents = frameImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    overlay.frame = CGRect(x: pad, y: 0, width: 676, height: 1380)   // khung 675 giãn đủ 676: không chừa cột nào trống ở mép phải
    parent.addSublayer(video); parent.addSublayer(overlay)

    // Vạch xanh lá nhấn giữ nút Tác vụ (toạ độ lớp: gốc ở dưới trái)
    if let t0 = ProcessInfo.processInfo.environment["PRESS"].flatMap(Double.init) {
        let h = (actionButton.bottom - actionButton.top) * scale + 8, w: CGFloat = 7
        let midY = render.height - (actionButton.top + actionButton.bottom) / 2 * scale
        let touchX = pad + actionButton.x * scale - w / 2 - 9     // dừng cách nút một đoạn, không chạm vào
        let pill = CALayer()
        pill.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        pill.cornerRadius = w / 2
        pill.backgroundColor = CGColor(red: 0.18, green: 0.75, blue: 0.35, alpha: 1)
        pill.position = CGPoint(x: touchX - 22, y: midY)
        pill.opacity = 0
        func anim(_ key: String, _ times: [Double], _ values: [Any]) -> CAKeyframeAnimation {
            let k = CAKeyframeAnimation(keyPath: key)
            k.beginTime = AVCoreAnimationBeginTimeAtZero + t0
            let total = times.last!
            k.duration = total
            k.keyTimes = times.map { NSNumber(value: $0 / total) }
            k.values = values
            k.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: times.count - 1)
            k.fillMode = .both; k.isRemovedOnCompletion = false
            return k
        }
        // hiện ra (0,3s), chờ, trượt lại gần nút (0,35s), giữ (1,3s), mờ đi
        pill.add(anim("opacity", [0, 0.3, 2.25, 2.55], [0.0, 1.0, 1.0, 0.0]), forKey: "o")
        pill.add(anim("position.x", [0, 0.6, 0.95, 2.55], [touchX - 22, touchX - 22, touchX, touchX]), forKey: "x")
        // lúc chạm: vạch dày lên một chút như ngón tay ấn xuống
        pill.add(anim("transform.scale.x", [0, 0.9, 1.05, 2.55], [1.0, 1.0, 1.35, 1.35]), forKey: "s")
        parent.addSublayer(pill)
    }

    let vc = AVMutableVideoComposition()
    vc.renderSize = render
    vc.frameDuration = CMTime(value: 1, timescale: 30)
    vc.instructions = [ins]
    vc.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: video, in: parent)

    let ex = AVAssetExportSession(asset: comp, presetName: ProcessInfo.processInfo.environment["PRESET"] ?? AVAssetExportPresetHighestQuality)!
    ex.videoComposition = vc
    try await ex.export(to: out, as: .mp4)
    print("ok", String(format: "%.1fs", comp.duration.seconds))
  } catch { print("lỗi:", error) }
    sem.signal()
}
sem.wait()
