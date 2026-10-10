// Nén lại phim với bitrate cố định cho nhẹ web:  swift shrink.swift vào.mp4 ra.mp4 [kbps=900]
import AVFoundation

let a = CommandLine.arguments
let kbps = a.count > 3 ? Int(a[3])! : 900
let asset = AVURLAsset(url: URL(fileURLWithPath: a[1]))
let out = URL(fileURLWithPath: a[2])
try? FileManager.default.removeItem(at: out)

let sem = DispatchSemaphore(value: 0)
Task {
  do {
    let track = try await asset.loadTracks(withMediaType: .video)[0]
    let size = try await track.load(.naturalSize)
    let reader = try AVAssetReader(asset: asset)
    let ro = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
    reader.add(ro)
    let writer = try AVAssetWriter(outputURL: out, fileType: .mp4)
    let wi = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: kbps * 1000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                          AVVideoMaxKeyFrameIntervalKey: 60]])
    wi.expectsMediaDataInRealTime = false
    writer.add(wi)
    writer.shouldOptimizeForNetworkUse = true   // moov đầu tệp: phát được ngay khi đang tải
    reader.startReading(); writer.startWriting(); writer.startSession(atSourceTime: .zero)
    while let b = ro.copyNextSampleBuffer() {
        while !wi.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
        wi.append(b)
    }
    wi.markAsFinished()
    await writer.finishWriting()
    print("ok", (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int).flatMap { $0 }.map { "\($0 / 1024) KB" } ?? "")
  } catch { print("lỗi:", error) }
  sem.signal()
}
sem.wait()
