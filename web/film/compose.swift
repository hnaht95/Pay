// Ghép bản quay màn hình máy ảo vào khung iPhone thành phim MP4 cho trang giới thiệu.
//
//   swift compose.swift <bản quay.mov> <khung.png> <ra.mp4> <đoạn>...
//
// <khung.png>: khung máy của Apple đã phủ nền (chỉ chừa lỗ màn hình), cỡ 1350x2760.
// Mỗi <đoạn> là "từ-đến" hoặc "từ-đến@tốc độ" (giây trong bản quay), ví dụ 1.2-4.8 hay 5-9@2;
// các đoạn nối liền nhau, bỏ phần chờ giữa các lần bấm.
import AVFoundation
import AppKit

let a = CommandLine.arguments
guard a.count >= 5 else { print("swift compose.swift in.mov frame.png out.mp4 0-3 4-8@2 ..."); exit(1) }
let src = AVURLAsset(url: URL(fileURLWithPath: a[1]))
let frameImage = NSImage(contentsOfFile: a[2])!
let out = URL(fileURLWithPath: a[3])
try? FileManager.default.removeItem(at: out)

let scale: CGFloat = 0.5                       // khung 1350x2760 -> 675x1380
let render = CGSize(width: 676, height: 1380)  // H.264 cần cạnh chẵn
let hole = CGPoint(x: 72, y: 69)               // góc trên trái của màn hình trong khung (điểm ảnh khung)

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
    let cfr = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".mov")
    try await constantRate(src, to: cfr)
    defer { try? FileManager.default.removeItem(at: cfr) }
    let src = AVURLAsset(url: cfr)
    let track = try await src.loadTracks(withMediaType: .video)[0]
    let natural = try await track.load(.naturalSize)
    let comp = AVMutableComposition()
    let vt = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
    var at = CMTime.zero
    for spec in a[4...] {
        let parts = spec.split(separator: "@")
        let range = parts[0].split(separator: "-").map { Double($0)! }
        let speed = parts.count > 1 ? Double(parts[1])! : 1
        // không quá cuối bản quay: phần thừa sẽ là màn đen
        let r = CMTimeRange(start: CMTime(seconds: range[0], preferredTimescale: 600),
                            end: min(CMTime(seconds: range[1], preferredTimescale: 600), try await track.load(.timeRange).end))
        try vt.insertTimeRange(r, of: track, at: at)
        if speed != 1 {
            vt.scaleTimeRange(CMTimeRange(start: at, duration: r.duration),
                              toDuration: CMTime(seconds: r.duration.seconds / speed, preferredTimescale: 600))
        }
        at = comp.duration
    }

    // Màn hình máy ảo (1206x2622) thu nhỏ đặt vào lỗ của khung
    let s = (1206 * scale) / natural.width
    let li = AVMutableVideoCompositionLayerInstruction(assetTrack: vt)
    li.setTransform(CGAffineTransform(scaleX: s, y: s)
        .concatenating(CGAffineTransform(translationX: hole.x * scale, y: hole.y * scale)), at: .zero)
    let ins = AVMutableVideoCompositionInstruction()
    ins.timeRange = CMTimeRange(start: .zero, duration: comp.duration)
    ins.layerInstructions = [li]
    ins.backgroundColor = CGColor(gray: 0.96, alpha: 1)

    let parent = CALayer(), video = CALayer(), overlay = CALayer()
    for l in [parent, video, overlay] { l.frame = CGRect(origin: .zero, size: render) }
    overlay.contents = frameImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    overlay.frame = CGRect(origin: .zero, size: render)   // khung 675 giãn đủ 676: không chừa cột nào trống ở mép phải
    parent.addSublayer(video); parent.addSublayer(overlay)

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
