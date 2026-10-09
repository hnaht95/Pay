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

let sem = DispatchSemaphore(value: 0)
Task {
  do {
    // Máy ảo chỉ ghi khung hình khi màn hình đổi; cắt ghép thẳng trên bản đó dễ lệch đoạn, nên đổi về 30 khung/giây trước
    let cfr = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".mov")
    let norm = AVAssetExportSession(asset: src, presetName: AVAssetExportPresetHighestQuality)!
    norm.videoComposition = try await AVVideoComposition.videoComposition(withPropertiesOf: src)
    let nc = norm.videoComposition!.mutableCopy() as! AVMutableVideoComposition
    nc.frameDuration = CMTime(value: 1, timescale: 30)
    norm.videoComposition = nc
    try await norm.export(to: cfr, as: .mov)
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
        let r = CMTimeRange(start: CMTime(seconds: range[0], preferredTimescale: 600),
                            end: CMTime(seconds: range[1], preferredTimescale: 600))
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
