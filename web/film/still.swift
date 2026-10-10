// Ảnh tĩnh -> phim .mov dài <giây> (30 khung/giây), để ghép như một bản quay:  swift still.swift ảnh.png ra.mov 3
import AVFoundation
import AppKit

let a = CommandLine.arguments
let img = NSImage(contentsOfFile: a[1])!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let out = URL(fileURLWithPath: a[2]); try? FileManager.default.removeItem(at: out)
let seconds = Double(a[3]) ?? 3
let w = img.width, h = img.height
let writer = try! AVAssetWriter(outputURL: out, fileType: .mov)
let wi = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 40_000_000]])
let ad = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: wi, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h])
writer.add(wi); writer.startWriting(); writer.startSession(atSourceTime: .zero)
var px: CVPixelBuffer?
CVPixelBufferPoolCreatePixelBuffer(nil, ad.pixelBufferPool!, &px)
CVPixelBufferLockBaseAddress(px!, [])
let ctx = CGContext(data: CVPixelBufferGetBaseAddress(px!), width: w, height: h, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(px!),
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
CVPixelBufferUnlockBaseAddress(px!, [])
for i in 0...Int(seconds * 30) {
    while !wi.isReadyForMoreMediaData { usleep(2000) }
    ad.append(px!, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 30))
}
wi.markAsFinished()
let sem = DispatchSemaphore(value: 0)
writer.finishWriting { sem.signal() }
sem.wait()
print("ok")
