import AppKit
import CoreGraphics
import CoreText
import CryptoKit
import Foundation

/// A film's frames read back out of PDF — each drawn by the app's own views into a PDF page, see
/// `FilmExportTests` — as what a browser's canvas can draw again: shapes as paths, words as the
/// outlines of their letters, pictures as files, and every frame a list of the things drawn in it.
/// What frames have alike is kept once: the paths, the things drawn, the clips and the pictures are
/// tables the frames point into, so a film whose screen changes a little from one frame to the next
/// costs little more than its first frame.
///
/// Not every part of PDF: what SwiftUI writes — paths filled and stroked, clips, colours with their
/// alpha, the multiply the highlighter is laid on with, pictures with soft masks, linear and radial
/// shadings, groups made see-through as one, and TrueType words. Anything else is counted in
/// `unread`, for a film to say what it left out.
final class FilmVectors {
    /// How far a soft mask drawn here may reach: the film's screen and a little round it — set by the packer.
    static var maskBounds = CGRect(x: -50, y: -50, width: 4000, height: 3000)
    // MARK: Tables shared by every frame of a film

    private(set) var paths: [String] = []
    private var pathIDs: [String: Int] = [:]
    private(set) var clips: [[Any]] = []
    private var clipIDs: [String: Int] = [:]
    private(set) var chains: [[Int]] = []
    private var chainIDs: [String: Int] = [:]
    private(set) var shadings: [[String: Any]] = []
    private var shadingIDs: [String: Int] = [:]
    private(set) var commands: [[Any]] = []
    private var commandIDs: [String: Int] = [:]
    private(set) var images: [[Any]] = []
    private var imageIDs: [String: Int] = [:]
    private(set) var unread: [String: Int] = [:]

    /// Where the pictures are written, and the name each starts with.
    let folder: URL
    let prefix: String
    /// Pictures drawn in place of others, by their size — `"640x360"` — and the file each stands
    /// for: the large ones the films are set on, given to the views small for the PDF of every frame
    /// to be quick to write and read, and drawn on the website from their own files at their own size.
    var substitutes: [String: (file: String, width: Int, height: Int)] = [:]
    /// How far the film goes in at the most, for a picture as large as the screen to be written
    /// only as finely as it is ever shown — the wallpaper and the window are 2560 across.
    init(folder: URL, prefix: String) {
        self.folder = folder
        self.prefix = prefix
    }

    // MARK: A frame

    /// The things drawn in the PDF `data`'s first page, in the order they are drawn: their places in
    /// `commands`. `base` takes the page's own space — y up from its foot — to the one the frames
    /// are drawn in.
    func frame(pdf data: Data, base: CGAffineTransform) -> [Int] {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider),
              let page = document.page(at: 1) else { return [] }
        let stream = CGPDFContentStreamCreateWithPage(page)
        let machine = Machine(owner: self, base: base)
        machine.run(stream)
        // What this frame drew is what the next is held to — see `path(_:)` and `command(_:)`.
        lastPaths = framePaths
        framePaths = [:]
        lastCommands = frameCommands
        frameCommands = [:]
        return machine.drawn
    }

    // MARK: Standing still

    /// What SwiftUI draws is put on whole pixels where the camera has it, and with the camera taken
    /// off again that comes out a third of a point this way or that from one frame to the next: a
    /// shape no nearer than `steady` to where the last frame had it is the last frame's, and kept.
    /// Shown, it stands still as it does in the app rather than shivering by a fraction of a pixel.
    static let steady = 0.5

    private var lastPaths: [String: [(id: Int, numbers: [Double])]] = [:]
    private var framePaths: [String: [(id: Int, numbers: [Double])]] = [:]
    private var lastCommands: [String: [(id: Int, matrix: [Double])]] = [:]
    private var frameCommands: [String: [(id: Int, matrix: [Double])]] = [:]

    private static func shape(_ d: String) -> (signature: String, numbers: [Double]) {
        var letters = "", numbers: [Double] = []
        for part in d.split(separator: " ") {
            var token = Substring(part)
            if let first = token.first, first.isLetter {
                letters.append(first)
                token = token.dropFirst()
            }
            if !token.isEmpty, let value = Double(token) { numbers.append(value) }
        }
        return (letters, numbers)
    }

    // MARK: Keeping things once

    fileprivate func path(_ d: String) -> Int {
        let (signature, numbers) = Self.shape(d)
        func used(_ id: Int) -> Int {
            framePaths[signature, default: []].append((id, numbers))
            return id
        }
        if let id = pathIDs[d] { return used(id) }
        for last in lastPaths[signature] ?? [] where last.numbers.count == numbers.count {
            if zip(last.numbers, numbers).allSatisfy({ abs($0 - $1) <= Self.steady }) {
                framePaths[signature, default: []].append(last)
                return last.id
            }
        }
        paths.append(d)
        pathIDs[d] = paths.count - 1
        return used(paths.count - 1)
    }

    fileprivate func clip(_ entry: [Any]) -> Int {
        let key = Self.key(entry)
        if let id = clipIDs[key] { return id }
        clips.append(entry)
        clipIDs[key] = clips.count - 1
        return clips.count - 1
    }

    fileprivate func chain(_ entries: [Int]) -> Int {
        guard !entries.isEmpty else { return -1 }
        let key = entries.map(String.init).joined(separator: ",")
        if let id = chainIDs[key] { return id }
        chains.append(entries)
        chainIDs[key] = chains.count - 1
        return chains.count - 1
    }

    fileprivate func shading(_ spec: [String: Any]) -> Int {
        let key = Self.key(spec)
        if let id = shadingIDs[key] { return id }
        shadings.append(spec)
        shadingIDs[key] = shadings.count - 1
        return shadings.count - 1
    }

    fileprivate func command(_ command: [Any]) -> Int {
        let key = Self.key(command)
        // A picture, a letter, a shading: where it is, apart from the rest of it.
        let matrix = command.count > 2 ? command[2] as? [Double] : nil
        var loose = command
        if matrix != nil { loose[2] = "*" }
        let looseKey = matrix != nil ? Self.key(loose) : key
        func used(_ id: Int) -> Int {
            if let matrix { frameCommands[looseKey, default: []].append((id, matrix)) }
            return id
        }
        if let id = commandIDs[key] { return used(id) }
        if let matrix {
            for last in lastCommands[looseKey] ?? [] {
                let m = last.matrix
                let near = (0..<4).allSatisfy { abs(m[$0] - matrix[$0]) <= max(0.0005, abs(matrix[$0]) * 0.002) }
                    && abs(m[4] - matrix[4]) <= Self.steady && abs(m[5] - matrix[5]) <= Self.steady
                if near {
                    frameCommands[looseKey, default: []].append(last)
                    return last.id
                }
            }
        }
        commands.append(command)
        commandIDs[key] = commands.count - 1
        return used(commands.count - 1)
    }

    /// A picture, written once whatever frame draws it: by what is in it, not by where it came from.
    fileprivate func image(_ image: CGImage, opaque: Bool) -> Int {
        // Peek: ảnh bìa mà bộ vẽ chụp nhỏ (bo góc, theo độ nét của trang) thay bằng chính ảnh gốc, giữ
        // nguyên góc bo — xem `artSubstitute`.
        let image = artSubstitute(image) ?? image
        if let stand = substitutes["\(image.width)x\(image.height)"] {
            let key = "file:" + stand.file
            if let id = imageIDs[key] { return id }
            images.append([stand.file, stand.width, stand.height])
            imageIDs[key] = images.count - 1
            return images.count - 1
        }
        guard let pixels = Self.rgba(image) else { return -1 }
        let digest = SHA256.hash(data: pixels).prefix(10).map { String(format: "%02x", $0) }.joined()
        if let id = imageIDs[digest] { return id }
        // The same picture drawn again at another size — a shadow, a blur, drawn as fine as the
        // camera had gone in, every frame of a move — kept once, as the finest of them: what is
        // shown is the picture stretched to where it goes, which looks the same either way.
        let thumb = Self.thumbnail(image)
        let bucket = Int((Double(image.width) / Double(max(1, image.height)) * 50).rounded())
        // Drawn at the same size, it is not the same picture at another size: held to it more
        // finely — the dimmed screen round the spotlight, its hole a little larger each frame of the
        // drag, was kept as one of the frames before it, the hole short of the pointer.
        var fine: [UInt8]?? = nil
        for key in (Self.fuzzy ? [bucket, bucket - 1, bucket + 1] : []) {
            for index in (alike[key] ?? []).indices {
                let candidate = alike[key]![index]
                guard let thumb, Self.similar(thumb, candidate.thumb) else { continue }
                if image.width == candidate.width, image.height == candidate.height,
                   max(image.width, image.height) > Self.fineSide {
                    if fine == nil { fine = Self.fineThumbnail(image) }
                    guard let mine = fine ?? nil, let theirs = candidate.fine, Self.similar(mine, theirs) else { continue }
                }
                if image.width * image.height > candidate.area * 13 / 10 {
                    let name = write(image, digest: digest, opaque: opaque)
                    images[candidate.id] = [name, image.width, image.height]
                    alike[key]![index].area = image.width * image.height
                    alike[key]![index].width = image.width
                    alike[key]![index].height = image.height
                    alike[key]![index].fine = max(image.width, image.height) > Self.fineSide
                        ? (fine ?? Self.fineThumbnail(image)) : nil
                }
                imageIDs[digest] = candidate.id
                return candidate.id
            }
        }
        let name = write(image, digest: digest, opaque: opaque)
        images.append([name, image.width, image.height])
        imageIDs[digest] = images.count - 1
        if let thumb {
            let finer = max(image.width, image.height) > Self.fineSide ? (fine ?? Self.fineThumbnail(image)) : nil
            alike[bucket, default: []].append((images.count - 1, thumb, image.width * image.height,
                                               image.width, image.height, finer))
        }
        return images.count - 1
    }

    /// Whether pictures alike in shape are kept once — off for a look at what each frame drew.
    static var fuzzy = ProcessInfo.processInfo.environment["SHOT_FILM_NO_FUZZY"] == nil

    /// Pictures kept so far, by their shape — see `image(_:opaque:)` — and, those larger than
    /// `fineSide` across, more finely.
    private var alike: [Int: [(id: Int, thumb: [UInt8], area: Int, width: Int, height: Int, fine: [UInt8]?)]] = [:]

    /// How large a picture is, at the most, before two of it at the same size are held to each other
    /// at `fineSide` across as well — see `fineThumbnail(_:)`.
    private static let fineSide = 128

    /// The picture `fineSide` across, its colours premultiplied: fine enough for an edge moved a few
    /// points across a picture of the whole screen to tell.
    private static func fineThumbnail(_ image: CGImage) -> [UInt8]? {
        let width = min(fineSide, image.width)
        let height = max(1, Int((Double(width) * Double(image.height) / Double(image.width)).rounded()))
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? data : nil
    }

    /// `image` written into the shared folder, named by what is in it: a picture two films draw —
    /// the wallpaper, the window, a pointer — is written, and fetched, once. The large ones, which
    /// are photographs and have no clear parts, as JPEG; the rest, marks and pointers and shadows
    /// with their edges see-through, as PNG.
    private func write(_ image: CGImage, digest: String, opaque: Bool) -> String {
        let photo = opaque && image.width * image.height > 200_000
        let name = "\(prefix)\(digest).\(photo ? "jpg" : "png")"
        let file = folder.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: file.path) {
            let rep = NSBitmapImageRep(cgImage: image)
            let data = photo ? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.88])
                             : rep.representation(using: .png, properties: [:])
            try? data?.write(to: file, options: .atomic)
        }
        return name
    }

    /// The picture at 16 by 16, its colours premultiplied: what tells two drawings of one picture.
    private static func thumbnail(_ image: CGImage) -> [UInt8]? {
        var data = [UInt8](repeating: 0, count: 16 * 16 * 4)
        let drawn = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 16, height: 16, bitsPerComponent: 8,
                                          bytesPerRow: 64, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16))
            return true
        }
        return drawn ? data : nil
    }

    /// Alike in shape, not only in being faint: each measured against its own strongest value, a
    /// shadow at a tenth of its strength alike only to one of the same shape at the same strength.
    private static func similar(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        let topA = Int(a.max() ?? 0), topB = Int(b.max() ?? 0)
        // Faint ones — a shadow's far edge — by how far apart they are, not against so little.
        if topA <= 24 && topB <= 24 {
            var total = 0, most = 0
            for index in a.indices {
                let apart = abs(Int(a[index]) - Int(b[index]))
                total += apart
                most = max(most, apart)
            }
            return most <= 6 && Double(total) / Double(a.count) <= 1.5
        }
        guard abs(topA - topB) <= max(4, max(topA, topB) * 15 / 100) else { return false }
        let top = max(1, max(topA, topB))
        var total = 0, most = 0
        for index in a.indices {
            let apart = abs(Int(a[index]) - Int(b[index])) * 255 / top
            total += apart
            most = max(most, apart)
        }
        return most <= 32 && Double(total) / Double(a.count) <= 3
    }

    fileprivate func note(_ what: String) { unread[what, default: 0] += 1 }

    /// `image` drawn in sRGB at `width` by `height`.
    // MARK: Peek — ảnh bìa gốc

    /// Ảnh gốc của những ảnh bìa có trong phim (đường dẫn trong biến môi trường ART, phân cách bằng
    /// dấu phẩy), và hai chiều của mỗi tấm: thẳng và lật dọc (bộ vẽ hay ghi ảnh lộn ngược kèm ma trận lật).
    private lazy var artSources: [(image: CGImage, flipped: Bool, thumb: [UInt8])] = {
        let paths = (ProcessInfo.processInfo.environment["ART"] ?? "").split(separator: ",").map(String.init)
        var out: [(CGImage, Bool, [UInt8])] = []
        for path in paths {
            guard let ns = NSImage(contentsOfFile: path), let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            for flipped in [false, true] {
                if let t = Self.centreThumb(cg, flipped: flipped) { out.append((cg, flipped, t)) }
            }
        }
        return out
    }()
    private var artCache: [String: CGImage] = [:]

    /// 12×12 điểm RGB của phần giữa tấm ảnh (bỏ mép, chỗ góc bo trong suốt).
    static func centreThumb(_ image: CGImage, flipped: Bool) -> [UInt8]? {
        let n = 12
        guard let c = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.interpolationQuality = .high
        if flipped { c.translateBy(x: 0, y: CGFloat(n)); c.scaleBy(x: 1, y: -1) }
        // Phần giữa 70 %: vẽ cả tấm to ra 1/0,7 lần, lệch vào giữa.
        let k = CGFloat(n) / 0.7, o = (k - CGFloat(n)) / 2
        c.draw(image, in: CGRect(x: -o, y: -o, width: k, height: k))
        guard let data = c.data else { return nil }
        let p = data.assumingMemoryBound(to: UInt8.self)
        var out: [UInt8] = []
        for i in 0..<(n * n) { out += [p[i * 4], p[i * 4 + 1], p[i * 4 + 2]] }
        return out
    }

    /// Tấm ảnh này là ảnh bìa bị chụp nhỏ? Thì trả về ảnh gốc theo đúng chiều, cỡ 4 lần cỡ chụp (tối đa
    /// 512), độ trong lấy từ tấm chụp (góc bo) phóng lên.
    func artSubstitute(_ image: CGImage) -> CGImage? {
        guard !artSources.isEmpty, image.width >= 24, image.width <= 300,
              abs(image.width - image.height) <= 6 else { return nil }
        guard let thumb = Self.centreThumb(image, flipped: false) else { return nil }
        var best: (Int, Int)? = nil
        for (i, src) in artSources.enumerated() {
            var d = 0
            for j in 0..<thumb.count { d += abs(Int(thumb[j]) - Int(src.thumb[j])) }
            if best == nil || d < best!.1 { best = (i, d) }
        }
        guard let (i, d) = best, Double(d) / Double(thumb.count) < (Double(ProcessInfo.processInfo.environment["ARTMATCH"] ?? "") ?? 26) else { return nil }
        let src = artSources[i]
        let key = "\(i)|\(image.width)x\(image.height)"
        if let hit = artCache[key] { return hit }
        let scale = max(1, min(4, 512 / max(image.width, image.height)))
        let w = image.width * scale, h = image.height * scale
        guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let rgba = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Độ trong của tấm chụp (góc bo), phóng lên mịn, làm thành ảnh xám cho `clip(to:mask:)`.
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        rgba.interpolationQuality = .high
        rgba.draw(image, in: rect)
        guard let px = rgba.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h)
        for k in 0..<(w * h) { bytes[k] = px[k * 4 + 3] }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let alpha = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        c.interpolationQuality = .high
        c.clip(to: rect, mask: alpha)
        if src.flipped { c.translateBy(x: 0, y: CGFloat(h)); c.scaleBy(x: 1, y: -1) }
        c.draw(src.image, in: rect)
        guard let out = c.makeImage() else { return nil }
        artCache[key] = out
        return out
    }

    static func redrawn(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// `image` written whole into the shared folder — in sRGB, as JPEG — and a small copy of it
    /// `small` across for the views to draw in its place: see `substitutes`.
    func standIn(for image: CGImage, small: (width: Int, height: Int), name: String, png: Bool = false) -> CGImage? {
        guard let whole = Self.redrawn(image, width: image.width, height: image.height),
              let copy = Self.redrawn(image, width: small.width, height: small.height) else { return nil }
        let file = "\(prefix)\(name).\(png ? "png" : "jpg")"
        let url = folder.appendingPathComponent(file)
        if !FileManager.default.fileExists(atPath: url.path) {
            let rep = NSBitmapImageRep(cgImage: whole)
            let data = png ? rep.representation(using: .png, properties: [:])
                           : rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
            try? data?.write(to: url, options: .atomic)
        }
        substitutes["\(small.width)x\(small.height)"] = (file, image.width, image.height)
        return copy
    }

    private static func rgba(_ image: CGImage) -> Data? {
        var data = Data(count: image.width * image.height * 4)
        let drawn = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return drawn ? data : nil
    }

    static func key(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return "\(value)" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Words

    /// The outlines of the letters of the fonts met so far, by the font's stream and the letter's
    /// code: its path, in the font's own units scaled to a thousand to the em.
    fileprivate var letters: [String: [Int: Int]] = [:]
    fileprivate var fonts: [String: LetterSource] = [:]
}

/// A font embedded in the PDF, as its letters are drawn: its program, and how a code in the words
/// is turned into a letter of it.
final class LetterSource {
    let font: CTFont
    /// Code to glyph, from the font's own `cmap`: by the code itself, by the code in the private
    /// area, or by what the code stands for in Mac Roman.
    private var table: [Int: CGGlyph] = [:]
    let widths: [Int: CGFloat]

    init?(program: Data, widths: [Int: CGFloat]) {
        guard let provider = CGDataProvider(data: program as CFData), let cg = CGFont(provider) else { return nil }
        font = CTFontCreateWithGraphicsFont(cg, 1000, nil, nil)
        self.widths = widths
        table = Self.readCmap(font)
    }

    func glyph(_ code: Int) -> CGGlyph? {
        if let glyph = table[code] { return glyph }
        if let glyph = table[0xF000 + code] { return glyph }
        if let unicode = MacRoman.unicode(code), let glyph = table[unicode] { return glyph }
        return nil
    }

    func outline(_ glyph: CGGlyph) -> CGPath? {
        CTFontCreatePathForGlyph(font, glyph, nil)
    }

    /// The `cmap` subtables of formats 0, 4, 6 and 12, all into one table — codes are looked up in
    /// it as they are, in the private area, and as Unicode.
    private static func readCmap(_ font: CTFont) -> [Int: CGGlyph] {
        guard let data = CTFontCopyTable(font, CTFontTableTag(kCTFontTableCmap), []) as Data? else { return [:] }
        let bytes = [UInt8](data)
        func u16(_ at: Int) -> Int { at + 1 < bytes.count ? Int(bytes[at]) << 8 | Int(bytes[at + 1]) : 0 }
        func u32(_ at: Int) -> Int { u16(at) << 16 | u16(at + 2) }
        var table: [Int: CGGlyph] = [:]
        let count = u16(2)
        for index in 0..<count {
            let record = 4 + index * 8
            let offset = u32(record + 4)
            let format = u16(offset)
            switch format {
            case 0:
                for code in 0..<256 where offset + 6 + code < bytes.count {
                    let glyph = Int(bytes[offset + 6 + code])
                    if glyph != 0, table[code] == nil { table[code] = CGGlyph(glyph) }
                }
            case 4:
                let segments = u16(offset + 6) / 2
                let ends = offset + 14, starts = ends + segments * 2 + 2
                let deltas = starts + segments * 2, ranges = deltas + segments * 2
                for segment in 0..<segments {
                    let end = u16(ends + segment * 2), start = u16(starts + segment * 2)
                    let delta = u16(deltas + segment * 2), range = u16(ranges + segment * 2)
                    guard start <= end, end != 0xFFFF || start != 0xFFFF else { continue }
                    for code in start...end {
                        var glyph: Int
                        if range == 0 {
                            glyph = (code + delta) & 0xFFFF
                        } else {
                            let at = ranges + segment * 2 + range + (code - start) * 2
                            glyph = u16(at)
                            if glyph != 0 { glyph = (glyph + delta) & 0xFFFF }
                        }
                        if glyph != 0, table[code] == nil { table[code] = CGGlyph(glyph) }
                    }
                }
            case 6:
                let first = u16(offset + 6), entries = u16(offset + 8)
                for index in 0..<entries {
                    let glyph = u16(offset + 10 + index * 2)
                    if glyph != 0, table[first + index] == nil { table[first + index] = CGGlyph(glyph) }
                }
            case 12:
                let groups = u32(offset + 12)
                for group in 0..<groups {
                    let at = offset + 16 + group * 12
                    let start = u32(at), end = u32(at + 4), glyph = u32(at + 8)
                    guard end >= start, end - start < 70_000 else { continue }
                    for code in start...end where table[code] == nil { table[code] = CGGlyph(glyph + code - start) }
                }
            default:
                continue
            }
        }
        return table
    }
}

/// What a code of Mac Roman stands for, past ASCII — the words SwiftUI writes in a font with that
/// encoding are coded in it.
enum MacRoman {
    static func unicode(_ code: Int) -> Int? {
        guard code >= 0 else { return nil }
        if code < 128 { return code }
        guard code < 256, let scalar = String(bytes: [UInt8(code)], encoding: .macOSRoman)?.unicodeScalars.first else { return nil }
        return Int(scalar.value)
    }
}

// MARK: - Reading a page

/// The PDF read one operator at a time, its graphics state kept as PDF keeps it.
private final class Machine {
    struct State {
        var ctm: CGAffineTransform
        var fill: (r: CGFloat, g: CGFloat, b: CGFloat) = (0, 0, 0)
        var stroke: (r: CGFloat, g: CGFloat, b: CGFloat) = (0, 0, 0)
        var fillComponents = 3
        var strokeComponents = 3
        var fillAlpha: CGFloat = 1
        var strokeAlpha: CGFloat = 1
        var blend = "normal"
        var lineWidth: CGFloat = 1
        var cap = 0
        var join = 0
        var miter: CGFloat = 10
        var dash: [CGFloat] = []
        var dashPhase: CGFloat = 0
        var clip: [Int] = []
        var font: LetterSource?
        var fontKey = ""
        var fontSize: CGFloat = 12
        var charSpacing: CGFloat = 0
        var wordSpacing: CGFloat = 0
        var scale: CGFloat = 1
        var leading: CGFloat = 0
        var rise: CGFloat = 0
        var mode = 0
        /// A soft mask in force: its picture, as luminosity, and where the CTM had it as it was set.
        var softMask: (image: CGImage, ctm: CGAffineTransform)?
        /// Peek: soft masks begun as mask groups (["G", 1, "normal", chain, [picture, matrix]]) and
        /// not yet ended — ended as the state they were begun in is put down.
        var openMasks = 0
    }

    unowned let owner: FilmVectors
    var state: State
    var stack: [State] = []
    var drawn: [Int] = []
    /// The path being built, in the space it is given in, and whether it has anything in it.
    var path = ""
    var pathEmpty = true
    /// Where the path stands, and where its last piece began — for `v`, and for `h` to go back to.
    var current = CGPoint.zero
    var subpathStart = CGPoint.zero
    /// The same path, for what has to be drawn here rather than in the browser — see `paintMasked`.
    var cgPath = CGMutablePath()
    var pendingClip: Int32?  // 0 nonzero, 1 even-odd
    var textMatrix = CGAffineTransform.identity
    var lineMatrix = CGAffineTransform.identity
    var streams: [CGPDFContentStreamRef] = []
    /// Peek: drawing a soft mask here rather than reading it — see `rasterMask`. Its CTM takes the
    /// screen's points to its pixels; what is painted is drawn into it, nothing is written down.
    var raster: CGContext?
    /// Peek: a soft mask found to be a rectangle let wholly through — taken as a clip, see `maskPicture`.
    var pendingRectClip: CGAffineTransform?

    init(owner: FilmVectors, base: CGAffineTransform) {
        self.owner = owner
        state = State(ctm: base)
    }

    func run(_ stream: CGPDFContentStreamRef) {
        streams.append(stream)
        let table = Self.table
        let info = Unmanaged.passUnretained(self).toOpaque()
        let scanner = CGPDFScannerCreate(stream, table, info)
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
        streams.removeLast()
    }

    var stream: CGPDFContentStreamRef? { streams.last }

    // MARK: Numbers

    static func n(_ value: CGFloat, _ places: Int = 2) -> Double {
        let scale = pow(10, Double(places))
        let rounded = (Double(value) * scale).rounded() / scale
        return rounded == 0 ? 0 : rounded
    }

    static func text(_ value: CGFloat) -> String {
        // iOS writes a rectangle "without end" (±1.7e38) for a fill that covers everything: kept to what a
        // canvas can take, far past any screen
        let rounded = n(max(-1e6, min(1e6, value)), 2)
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        var string = String(format: "%.2f", rounded)
        while string.hasSuffix("0") { string.removeLast() }
        return string
    }

    static func matrix(_ m: CGAffineTransform) -> [Double] {
        [n(m.a, 5), n(m.b, 5), n(m.c, 5), n(m.d, 5), n(m.tx, 2), n(m.ty, 2)]
    }

    static func colour(_ c: (r: CGFloat, g: CGFloat, b: CGFloat)) -> String {
        func byte(_ v: CGFloat) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(c.r), byte(c.g), byte(c.b))
    }

    // MARK: Paths

    func add(_ op: String, _ values: [CGFloat]) {
        path += (path.isEmpty ? "" : " ") + op + values.map { Self.text($0) }.joined(separator: " ")
        pathEmpty = false
        switch op {
        case "M": cgPath.move(to: CGPoint(x: values[0], y: values[1]))
        case "L": cgPath.addLine(to: CGPoint(x: values[0], y: values[1]))
        case "C": cgPath.addCurve(to: CGPoint(x: values[4], y: values[5]), control1: CGPoint(x: values[0], y: values[1]),
                                  control2: CGPoint(x: values[2], y: values[3]))
        case "Z": cgPath.closeSubpath()
        default: break
        }
        if values.count >= 2 { current = CGPoint(x: values[values.count - 2], y: values[values.count - 1]) }
        if op == "M" { subpathStart = current }
        if op == "Z" { current = subpathStart }
    }

    func endPath() {
        path = ""
        pathEmpty = true
        cgPath = CGMutablePath()
    }

    /// The path made a clip, if `W` asked for it, as it is painted or put down with `n`.
    func applyClip() {
        guard let rule = pendingClip, !pathEmpty else { pendingClip = nil; return }
        if let r = raster {
            var ctm = state.ctm
            if let onScreen = cgPath.copy(using: &ctm) { r.addPath(onScreen); r.clip(using: rule == 1 ? .evenOdd : .winding) }
            pendingClip = nil
            return
        }
        let id = owner.path(onScreen())
        let entry = owner.clip([id, NSNull(), Int(rule)])
        state.clip.append(entry)
        pendingClip = nil
    }

    /// The path as it falls on the screen: written in the screen's points, the CTM applied, for a
    /// shape that stands still on the screen to be the same from one frame to the next whatever
    /// transforms it was drawn through — a film's camera put on and taken off again among them.
    func onScreen() -> String {
        var ctm = state.ctm
        return Self.pathString(cgPath.copy(using: &ctm) ?? cgPath)
    }

    /// How much the CTM scales a length — a line's width, a dash.
    var ctmScale: CGFloat { sqrt(abs(state.ctm.a * state.ctm.d - state.ctm.b * state.ctm.c)) }

    func paint(fill: Int32?, stroke: Bool) {
        guard !pathEmpty else { applyClip(); endPath(); return }
        if let r = raster {
            var ctm = state.ctm
            if let rule = fill, let onScreen = cgPath.copy(using: &ctm) {
                r.setFillColor(CGColor(srgbRed: state.fill.r, green: state.fill.g, blue: state.fill.b, alpha: state.fillAlpha))
                r.addPath(onScreen)
                r.fillPath(using: rule == 1 ? .evenOdd : .winding)
            }
            if stroke {
                r.saveGState()
                r.concatenate(state.ctm)
                r.setStrokeColor(CGColor(srgbRed: state.stroke.r, green: state.stroke.g, blue: state.stroke.b, alpha: state.strokeAlpha))
                r.setLineWidth(state.lineWidth)
                r.addPath(cgPath)
                r.strokePath()
                r.restoreGState()
            }
            applyClip()
            endPath()
            return
        }
        if state.softMask != nil {
            paintMasked(fill: fill, stroke: stroke)
            applyClip()
            endPath()
            return
        }
        let id = owner.path(onScreen())
        let chain = owner.chain(state.clip)
        let m: Any = NSNull()
        if let rule = fill, state.fillAlpha > 0 {
            drawn.append(owner.command(["f", id, m, chain, Int(rule), Self.colour(state.fill), Self.n(state.fillAlpha, 3), state.blend]))
        }
        if stroke, state.strokeAlpha > 0 {
            let k = ctmScale
            var command: [Any] = ["s", id, m, chain, Self.colour(state.stroke), Self.n(state.strokeAlpha, 3), state.blend,
                                  Self.n(state.lineWidth * k, 3), state.cap, state.join, Self.n(state.miter, 2)]
            if !state.dash.isEmpty { command.append([state.dash.map { Self.n($0 * k, 2) }, Self.n(state.dashPhase * k, 2)]) }
            drawn.append(owner.command(command))
        }
        applyClip()
        endPath()
    }

    // MARK: Operators

    static let table: CGPDFOperatorTableRef = {
        let table = CGPDFOperatorTableCreate()!
        func on(_ name: String, _ body: @escaping CGPDFOperatorCallback) { CGPDFOperatorTableSetCallback(table, name, body) }
        func me(_ info: UnsafeMutableRawPointer?) -> Machine { Unmanaged<Machine>.fromOpaque(info!).takeUnretainedValue() }

        on("q") { _, info in let m = me(info); m.stack.append(m.state); m.raster?.saveGState() }
        on("Q") { _, info in
            let m = me(info)
            if let last = m.stack.popLast() { m.closeMasks(down: last.openMasks); m.state = last; m.raster?.restoreGState() }
        }
        on("cm") { scanner, info in
            let m = me(info)
            let v = popNumbers(scanner, 6)
            m.state.ctm = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5]).concatenating(m.state.ctm)
        }
        on("w") { scanner, info in me(info).state.lineWidth = popNumbers(scanner, 1)[0] }
        on("J") { scanner, info in me(info).state.cap = Int(popNumbers(scanner, 1)[0]) }
        on("j") { scanner, info in me(info).state.join = Int(popNumbers(scanner, 1)[0]) }
        on("M") { scanner, info in me(info).state.miter = popNumbers(scanner, 1)[0] }
        on("d") { scanner, info in
            let m = me(info)
            var phase: CGPDFReal = 0
            CGPDFScannerPopNumber(scanner, &phase)
            var array: CGPDFArrayRef?
            CGPDFScannerPopArray(scanner, &array)
            var dash: [CGFloat] = []
            if let array {
                for index in 0..<CGPDFArrayGetCount(array) {
                    var value: CGPDFReal = 0
                    if CGPDFArrayGetNumber(array, index, &value) { dash.append(value) }
                }
            }
            m.state.dash = dash
            m.state.dashPhase = phase
        }
        on("ri") { _, _ in }
        on("i") { _, _ in }
        on("gs") { scanner, info in
            let m = me(info)
            guard let name = popName(scanner), let stream = m.stream,
                  let object = CGPDFContentStreamGetResource(stream, "ExtGState", name) else { return }
            var dict: CGPDFDictionaryRef?
            guard CGPDFObjectGetValue(object, .dictionary, &dict), let dict else { return }
            var value: CGPDFReal = 0
            if CGPDFDictionaryGetNumber(dict, "ca", &value) { m.state.fillAlpha = value }
            if CGPDFDictionaryGetNumber(dict, "CA", &value) { m.state.strokeAlpha = value }
            var blend: UnsafePointer<CChar>?
            if CGPDFDictionaryGetName(dict, "BM", &blend), let blend {
                let name = String(cString: blend)
                m.state.blend = Machine.blends[name] ?? { m.owner.note("blend \(name)"); return "normal" }()
            }
            var lineWidth: CGPDFReal = 0
            if CGPDFDictionaryGetNumber(dict, "LW", &lineWidth) { m.state.lineWidth = lineWidth }
            var smask: UnsafePointer<CChar>?
            if CGPDFDictionaryGetName(dict, "SMask", &smask) {
                // `/None` puts any soft mask down.
                m.state.softMask = nil
                m.closeMasks(down: m.stack.last?.openMasks ?? 0)
            } else {
                var maskDict: CGPDFDictionaryRef?
                if CGPDFDictionaryGetDictionary(dict, "SMask", &maskDict), let maskDict {
                    m.pendingRectClip = nil
                    var kind: UnsafePointer<CChar>?
                    CGPDFDictionaryGetName(maskDict, "S", &kind)
                    let alphaMask = kind.map { String(cString: $0) } == "Alpha"
                    // An alpha mask made of a picture is the picture's alpha, which `maskPicture`
                    // (luminosity) does not give: drawn here instead.
                    let picture = alphaMask ? nil : m.maskPicture(maskDict)
                    if let place = m.pendingRectClip {
                        m.pendingRectClip = nil
                        m.state.softMask = nil
                        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)].map { $0.applying(place) }
                        let d = "M" + corners.map { "\(Machine.text($0.x)) \(Machine.text($0.y))" }.joined(separator: " L") + " Z"
                        if m.raster == nil { m.state.clip.append(m.owner.clip([m.owner.path(d), NSNull(), 0])) }
                        return
                    }
                    // Pay: a mask inside a mask being drawn here — iOS writes an SF Symbol so, its outline a mask
                    // of its own inside the mask of what it is drawn through. Drawn too, and laid on this
                    // context as a clip by its luminosity, until the state it was set in is put down.
                    if picture == nil, let r = m.raster, let inner = m.rasterMask(maskDict, nested: true),
                       let grey = Machine.luminosity(inner.image) {
                        r.clip(to: CGRect(x: 0, y: 0, width: 1, height: 1).applying(inner.ctm), mask: grey)
                        m.state.softMask = nil
                        return
                    }
                    let mask = picture ?? m.rasterMask(maskDict)
                    if m.raster != nil { m.state.softMask = mask; if mask != nil { return } }
                    else if let mask {
                        // Peek: the mask a group of its own for the browser to lay over what is
                        // drawn in it — what is under it stays shapes and words.
                        m.beginMask(mask)
                        return
                    }
                    var group: CGPDFStreamRef?
                    var content = ""
                    if CGPDFDictionaryGetStream(maskDict, "G", &group), let group {
                        var format = CGPDFDataFormat.raw
                        if let data = CGPDFStreamCopyData(group, &format) as Data? {
                            content = String(decoding: data.prefix(600), as: UTF8.self).replacingOccurrences(of: "\n", with: " ")
                        }
                        if let gd = CGPDFStreamGetDictionary(group) { content = Machine.describe(gd) + " || " + content }
                    }
                    if m.owner.unread.keys.filter({ $0.hasPrefix("soft mask") }).count < 4 {
                        m.owner.note("soft mask " + Machine.describe(maskDict) + " :: " + content)
                    } else {
                        m.owner.note("soft mask")
                    }
                }
            }
        }

        // Paths
        on("m") { scanner, info in me(info).add("M", popNumbers(scanner, 2)) }
        on("l") { scanner, info in me(info).add("L", popNumbers(scanner, 2)) }
        on("c") { scanner, info in me(info).add("C", popNumbers(scanner, 6)) }
        on("v") { scanner, info in
            // The first control point on the current point: the path's last point, kept by the
            // string itself — taken from it.
            let m = me(info)
            let v = popNumbers(scanner, 4)
            let current = m.currentPoint()
            m.add("C", [current.x, current.y, v[0], v[1], v[2], v[3]])
        }
        on("y") { scanner, info in
            let v = popNumbers(scanner, 4)
            me(info).add("C", [v[0], v[1], v[2], v[3], v[2], v[3]])
        }
        on("h") { _, info in me(info).add("Z", []) }
        on("re") { scanner, info in
            let v = popNumbers(scanner, 4)
            let m = me(info)
            m.add("M", [v[0], v[1]])
            m.add("L", [v[0] + v[2], v[1]])
            m.add("L", [v[0] + v[2], v[1] + v[3]])
            m.add("L", [v[0], v[1] + v[3]])
            m.add("Z", [])
        }
        on("W") { _, info in me(info).pendingClip = 0 }
        on("W*") { _, info in me(info).pendingClip = 1 }
        on("n") { _, info in let m = me(info); m.applyClip(); m.endPath() }
        on("f") { _, info in me(info).paint(fill: 0, stroke: false) }
        on("F") { _, info in me(info).paint(fill: 0, stroke: false) }
        on("f*") { _, info in me(info).paint(fill: 1, stroke: false) }
        on("S") { _, info in me(info).paint(fill: nil, stroke: true) }
        on("s") { _, info in let m = me(info); m.add("Z", []); m.paint(fill: nil, stroke: true) }
        on("B") { _, info in me(info).paint(fill: 0, stroke: true) }
        on("B*") { _, info in me(info).paint(fill: 1, stroke: true) }
        on("b") { _, info in let m = me(info); m.add("Z", []); m.paint(fill: 0, stroke: true) }
        on("b*") { _, info in let m = me(info); m.add("Z", []); m.paint(fill: 1, stroke: true) }

        // Colours
        func colourSpace(_ m: Machine, _ name: String) -> Int {
            switch name {
            case "DeviceGray", "CalGray": return 1
            case "DeviceRGB", "CalRGB": return 3
            case "DeviceCMYK": return 4
            case "Pattern": m.owner.note("pattern colour"); return 0
            default:
                guard let stream = m.stream, let object = CGPDFContentStreamGetResource(stream, "ColorSpace", name) else { return 3 }
                return Machine.components(of: object)
            }
        }
        on("cs") { scanner, info in let m = me(info); if let name = popName(scanner) { m.state.fillComponents = colourSpace(m, name); m.state.fill = (0, 0, 0) } }
        on("CS") { scanner, info in let m = me(info); if let name = popName(scanner) { m.state.strokeComponents = colourSpace(m, name); m.state.stroke = (0, 0, 0) } }
        on("sc") { scanner, info in let m = me(info); m.state.fill = Machine.colour(popNumbers(scanner, m.state.fillComponents)) }
        on("scn") { scanner, info in let m = me(info); m.state.fill = Machine.colour(popNumbers(scanner, m.state.fillComponents)) }
        on("SC") { scanner, info in let m = me(info); m.state.stroke = Machine.colour(popNumbers(scanner, m.state.strokeComponents)) }
        on("SCN") { scanner, info in let m = me(info); m.state.stroke = Machine.colour(popNumbers(scanner, m.state.strokeComponents)) }
        on("g") { scanner, info in let m = me(info); m.state.fillComponents = 1; m.state.fill = Machine.colour(popNumbers(scanner, 1)) }
        on("G") { scanner, info in let m = me(info); m.state.strokeComponents = 1; m.state.stroke = Machine.colour(popNumbers(scanner, 1)) }
        on("rg") { scanner, info in let m = me(info); m.state.fillComponents = 3; m.state.fill = Machine.colour(popNumbers(scanner, 3)) }
        on("RG") { scanner, info in let m = me(info); m.state.strokeComponents = 3; m.state.stroke = Machine.colour(popNumbers(scanner, 3)) }
        on("k") { scanner, info in let m = me(info); m.state.fillComponents = 4; m.state.fill = Machine.colour(popNumbers(scanner, 4)) }
        on("K") { scanner, info in let m = me(info); m.state.strokeComponents = 4; m.state.stroke = Machine.colour(popNumbers(scanner, 4)) }

        // Pictures, groups and shadings
        on("Do") { scanner, info in
            let m = me(info)
            guard let name = popName(scanner), let stream = m.stream,
                  let object = CGPDFContentStreamGetResource(stream, "XObject", name) else { return }
            var xobject: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &xobject), let xobject,
                  let dict = CGPDFStreamGetDictionary(xobject) else { return }
            var subtype: UnsafePointer<CChar>?
            CGPDFDictionaryGetName(dict, "Subtype", &subtype)
            switch subtype.map({ String(cString: $0) }) {
            case "Image": m.drawImage(xobject, dict)
            case "Form": m.drawForm(xobject, dict)
            default: m.owner.note("xobject")
            }
        }
        on("sh") { scanner, info in
            let m = me(info)
            guard let name = popName(scanner), let stream = m.stream,
                  let object = CGPDFContentStreamGetResource(stream, "Shading", name) else { return }
            var dict: CGPDFDictionaryRef?
            if !CGPDFObjectGetValue(object, .dictionary, &dict) {
                var shadingStream: CGPDFStreamRef?
                if CGPDFObjectGetValue(object, .stream, &shadingStream), let shadingStream { dict = CGPDFStreamGetDictionary(shadingStream) }
            }
            guard let dict else { return }
            m.drawShading(dict)
        }
        on("BI") { _, info in me(info).owner.note("inline image") }

        // Words
        on("BT") { _, info in let m = me(info); m.textMatrix = .identity; m.lineMatrix = .identity }
        on("ET") { _, _ in }
        on("Tf") { scanner, info in
            let m = me(info)
            let size = popNumbers(scanner, 1)[0]
            guard let name = popName(scanner) else { return }
            m.state.fontSize = size
            m.setFont(name)
        }
        on("Tc") { scanner, info in me(info).state.charSpacing = popNumbers(scanner, 1)[0] }
        on("Tw") { scanner, info in me(info).state.wordSpacing = popNumbers(scanner, 1)[0] }
        on("Tz") { scanner, info in me(info).state.scale = popNumbers(scanner, 1)[0] / 100 }
        on("TL") { scanner, info in me(info).state.leading = popNumbers(scanner, 1)[0] }
        on("Ts") { scanner, info in me(info).state.rise = popNumbers(scanner, 1)[0] }
        on("Tr") { scanner, info in me(info).state.mode = Int(popNumbers(scanner, 1)[0]) }
        on("Tm") { scanner, info in
            let m = me(info)
            let v = popNumbers(scanner, 6)
            m.textMatrix = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
            m.lineMatrix = m.textMatrix
        }
        on("Td") { scanner, info in let m = me(info); let v = popNumbers(scanner, 2); m.nextLine(v[0], v[1]) }
        on("TD") { scanner, info in let m = me(info); let v = popNumbers(scanner, 2); m.state.leading = -v[1]; m.nextLine(v[0], v[1]) }
        on("T*") { _, info in let m = me(info); m.nextLine(0, -m.state.leading) }
        on("Tj") { scanner, info in let m = me(info); if let bytes = popString(scanner) { m.show(bytes) } }
        on("'") { scanner, info in let m = me(info); m.nextLine(0, -m.state.leading); if let bytes = popString(scanner) { m.show(bytes) } }
        on("\"") { scanner, info in
            let m = me(info)
            let bytes = popString(scanner)
            let v = popNumbers(scanner, 2)
            m.state.wordSpacing = v[0]; m.state.charSpacing = v[1]
            m.nextLine(0, -m.state.leading)
            if let bytes { m.show(bytes) }
        }
        on("TJ") { scanner, info in
            let m = me(info)
            var array: CGPDFArrayRef?
            guard CGPDFScannerPopArray(scanner, &array), let array else { return }
            for index in 0..<CGPDFArrayGetCount(array) {
                var string: CGPDFStringRef?
                var number: CGPDFReal = 0
                if CGPDFArrayGetString(array, index, &string), let string, let bytes = CGPDFStringGetBytePtr(string) {
                    m.show(Array(UnsafeBufferPointer(start: bytes, count: CGPDFStringGetLength(string))))
                } else if CGPDFArrayGetNumber(array, index, &number) {
                    let tx = -number / 1000 * m.state.fontSize * m.state.scale
                    m.textMatrix = CGAffineTransform(translationX: tx, y: 0).concatenating(m.textMatrix)
                }
            }
        }
        // Marked content and the rest that draws nothing.
        for name in ["BMC", "BDC", "EMC", "MP", "DP", "BX", "EX", "d0", "d1"] { on(name) { _, _ in } }
        return table
    }()

    static let blends: [String: String] = [
        "Normal": "normal", "Compatible": "normal", "Multiply": "multiply", "Screen": "screen", "Overlay": "overlay",
        "Darken": "darken", "Lighten": "lighten", "ColorDodge": "color-dodge", "ColorBurn": "color-burn",
        "HardLight": "hard-light", "SoftLight": "soft-light", "Difference": "difference", "Exclusion": "exclusion",
        "Hue": "hue", "Saturation": "saturation", "Color": "color", "Luminosity": "luminosity",
    ]

    static func colour(_ v: [CGFloat]) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        switch v.count {
        case 1: return (v[0], v[0], v[0])
        case 3: return (v[0], v[1], v[2])
        case 4: return ((1 - v[0]) * (1 - v[3]), (1 - v[1]) * (1 - v[3]), (1 - v[2]) * (1 - v[3]))
        default: return (0, 0, 0)
        }
    }

    static func components(of object: CGPDFObjectRef) -> Int {
        var name: UnsafePointer<CChar>?
        if CGPDFObjectGetValue(object, .name, &name), let name {
            switch String(cString: name) {
            case "DeviceGray", "CalGray": return 1
            case "DeviceCMYK": return 4
            default: return 3
            }
        }
        var array: CGPDFArrayRef?
        guard CGPDFObjectGetValue(object, .array, &array), let array else { return 3 }
        var kind: UnsafePointer<CChar>?
        CGPDFArrayGetName(array, 0, &kind)
        switch kind.map({ String(cString: $0) }) {
        case "ICCBased":
            var stream: CGPDFStreamRef?
            if CGPDFArrayGetStream(array, 1, &stream), let stream, let dict = CGPDFStreamGetDictionary(stream) {
                var n: CGPDFInteger = 3
                CGPDFDictionaryGetInteger(dict, "N", &n)
                return n
            }
            return 3
        case "CalGray": return 1
        case "Indexed": return 1
        default: return 3
        }
    }

    func currentPoint() -> CGPoint { current }

    // MARK: Pictures

    /// The most any pixel of `image` covers what is under it, 0 to 255.
    static func strongest(_ image: CGImage) -> Int {
        let width = min(image.width, 64), height = min(image.height, 64)
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 255 }
        return stride(from: 3, to: data.count, by: 4).map { Int(data[$0]) }.max() ?? 255
    }

    /// A soft mask that is one picture drawn into its group — as SwiftUI writes them — read as that
    /// picture and the CTM it is drawn with: the group's own matrix, then the picture's.
    /// Peek: a soft mask of anything else — shapes, words, shadings, forms in forms — drawn here with
    /// CoreGraphics, over its group's bounds on the screen, into a picture: its luminosity (or its
    /// alpha, for `/Alpha`) is the mask, as `maskPicture` gives it.
    func closeMasks(down to: Int) {
        guard raster == nil else { return }
        while state.openMasks > to {
            drawn.append(owner.command(["E"]))
            state.openMasks -= 1
        }
    }

    func beginMask(_ mask: (image: CGImage, ctm: CGAffineTransform)) {
        // A new mask in the same state takes the place of the last one begun in it.
        closeMasks(down: stack.last?.openMasks ?? 0)
        guard let alpha = Self.alphaFromLuminosity(mask.image) else { return }
        let id = owner.image(alpha, opaque: false)
        guard id >= 0 else { return }
        let unit = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 1)
        drawn.append(owner.command(["G", 1, "normal", owner.chain(state.clip), [id, Self.matrix(unit.concatenating(mask.ctm))]]))
        state.openMasks += 1
        state.softMask = nil
    }

    /// The mask's luminosity as the alpha of white, for the browser to lay on with `destination-in`.
    static func alphaFromLuminosity(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard let grey = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0),
              let out = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        grey.draw(image, in: rect)
        guard let lum = grey.makeImage() else { return nil }
        out.clip(to: rect, mask: lum)
        out.setFillColor(CGColor(gray: 1, alpha: 1))
        out.fill(rect)
        return out.makeImage()
    }

    static let rasterScale: CGFloat = 4
    /// A picture as grey with no alpha, what was clear black: what CoreGraphics takes for a clip's mask.
    static func luminosity(_ image: CGImage) -> CGImage? {
        guard let out = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        out.setFillColor(gray: 0, alpha: 1); out.fill(rect)
        out.draw(image, in: rect)
        return out.makeImage()
    }

    func rasterMask(_ mask: CGPDFDictionaryRef, nested: Bool = false) -> (image: CGImage, ctm: CGAffineTransform)? {
        guard raster == nil || nested else { return nil }
        var group: CGPDFStreamRef?
        guard CGPDFDictionaryGetStream(mask, "G", &group), let group, let dict = CGPDFStreamGetDictionary(group),
              let parent = self.stream else { return nil }
        var kind: UnsafePointer<CChar>?
        CGPDFDictionaryGetName(mask, "S", &kind)
        let alphaMask = kind.map { String(cString: $0) } == "Alpha"
        let ctm = formMatrix(dict).concatenating(state.ctm)
        var bbox = CGRect(x: -1e4, y: -1e4, width: 2e4, height: 2e4)
        var box: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(dict, "BBox", &box), let box, CGPDFArrayGetCount(box) == 4 {
            var v = [CGPDFReal](repeating: 0, count: 4)
            for index in 0..<4 { CGPDFArrayGetNumber(box, index, &v[index]) }
            bbox = CGRect(x: min(v[0], v[2]), y: min(v[1], v[3]), width: abs(v[2] - v[0]), height: abs(v[3] - v[1]))
        }
        // Pay: iOS gives some masks a box "without end"; kept to the screen (and a little round it), or the
        // picture drawn here would be too large to make
        var area = bbox.applying(ctm).intersection(FilmVectors.maskBounds)
        area = area.integral
        guard !area.isNull, area.width >= 1, area.height >= 1 else { return nil }
        let k = Self.rasterScale
        let width = Int(area.width * k), height = Int(area.height * k)
        guard width > 0, height > 0, width * height < 40_000_000,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // The backdrop: black unless the mask says, for luminosity; clear, for alpha.
        if !alphaMask {
            var backdrop: CGPDFArrayRef?
            var bc: [CGFloat] = [0, 0, 0]
            if CGPDFDictionaryGetArray(mask, "BC", &backdrop), let backdrop {
                bc = (0..<CGPDFArrayGetCount(backdrop)).map { i in var v: CGPDFReal = 0; CGPDFArrayGetNumber(backdrop, i, &v); return v }
            }
            let c = bc.count >= 3 ? bc : [bc.first ?? 0, bc.first ?? 0, bc.first ?? 0]
            context.setFillColor(CGColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        // The mask's unit square is `area` on the screen; its pixels y up from the square's foot.
        let unit = CGAffineTransform(a: area.width, b: 0, c: 0, d: area.height, tx: area.minX, ty: area.minY)
        context.scaleBy(x: CGFloat(width), y: CGFloat(height))
        context.concatenate(unit.inverted())
        let machine = Machine(owner: owner, base: ctm)
        machine.raster = context
        var resources: CGPDFDictionaryRef?
        CGPDFDictionaryGetDictionary(dict, "Resources", &resources)
        guard let resources else { return nil }
        let content = CGPDFContentStreamCreateWithStream(group, resources, parent)
        machine.run(content)
        CGPDFContentStreamRelease(content)
        guard var image = context.makeImage() else { return nil }
        if alphaMask {
            // The alpha as grey, for it to be read as luminosity like any other.
            guard let grey = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
                  let out = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return nil }
            grey.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let alpha = grey.makeImage() else { return nil }
            out.setFillColor(gray: 0, alpha: 1); out.fill(CGRect(x: 0, y: 0, width: width, height: height))
            out.clip(to: CGRect(x: 0, y: 0, width: width, height: height), mask: alpha)
            out.setFillColor(gray: 1, alpha: 1); out.fill(CGRect(x: 0, y: 0, width: width, height: height))
            guard let made = out.makeImage() else { return nil }
            image = made
        }
        return (image, unit)
    }

    func maskPicture(_ mask: CGPDFDictionaryRef) -> (image: CGImage, ctm: CGAffineTransform)? {
        var group: CGPDFStreamRef?
        guard CGPDFDictionaryGetStream(mask, "G", &group), let group else { return nil }
        return maskPicture(form: group, outer: .identity, depth: 0)
    }

    /// Peek: SwiftUI's CoreGraphics renderer writes some masks one form deeper — the group holds
    /// only a clip and `/Fm Do`, the picture is in that form. Followed down, the forms' matrices kept.
    static func white(_ w: Int, _ h: Int) -> CGImage? {
        let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)
        c?.setFillColor(gray: 1, alpha: 1); c?.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return c?.makeImage()
    }

    private func formMatrix(_ dict: CGPDFDictionaryRef) -> CGAffineTransform {
        var formMatrix: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(dict, "Matrix", &formMatrix), let formMatrix, CGPDFArrayGetCount(formMatrix) == 6 {
            var f = [CGPDFReal](repeating: 0, count: 6)
            for index in 0..<6 { CGPDFArrayGetNumber(formMatrix, index, &f[index]) }
            return CGAffineTransform(a: f[0], b: f[1], c: f[2], d: f[3], tx: f[4], ty: f[5])
        }
        return .identity
    }

    private func maskPicture(form group: CGPDFStreamRef, outer: CGAffineTransform, depth: Int) -> (image: CGImage, ctm: CGAffineTransform)? {
        guard let dict = CGPDFStreamGetDictionary(group) else { return nil }
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(group, &format) as Data? else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        // One `cm` and one `Do`: anything else is not this simple form.
        let pattern = #"([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+cm\s+/(\w+)\s+Do"#
        // Peek: a gradient mask (`.mask(LinearGradient)`), which CoreGraphics writes as a clip and a
        // shading of solid black — the gradient's alpha is lost on the way into PDF, and what is
        // left is the clip: the mask taken as that rectangle, wholly let through.
        if depth > 0, text.range(of: #"\ssh\b"#, options: .regularExpression) != nil, !text.contains("Do"),
           let rect = try? NSRegularExpression(pattern: #"([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+re\s+W\s+n"#),
           let m = rect.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            let v = (1...4).map { CGFloat(Double(String(text[Range(m.range(at: $0), in: text)!])) ?? 0) }
            let unit = CGAffineTransform(a: v[2], b: 0, c: 0, d: v[3], tx: v[0], ty: v[1])
            let place = unit.concatenating(formMatrix(dict)).concatenating(outer).concatenating(state.ctm)
            // Wholly let through over a rectangle: a clip, not a mask — what is under it stays shapes
            // and words rather than a picture a frame (a title running along under it, every frame).
            pendingRectClip = place
            return nil
        }
        guard text.components(separatedBy: "Do").count == 2 else {
            owner.note("mask: not one picture d\(depth) " + String(text.prefix(300)).replacingOccurrences(of: "\n", with: " ")); return nil
        }
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            // A form with no `cm` before its one `Do`: the picture is in the form it draws.
            if depth < 3, let nested = try? NSRegularExpression(pattern: #"/(\w+)\s+Do"#),
               let m = nested.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                let name = String(text[Range(m.range(at: 1), in: text)!])
                var resources: CGPDFDictionaryRef?, xobjects: CGPDFDictionaryRef?, inner: CGPDFStreamRef?
                if CGPDFDictionaryGetDictionary(dict, "Resources", &resources), let resources,
                   CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects), let xobjects,
                   CGPDFDictionaryGetStream(xobjects, name, &inner), let inner {
                    return maskPicture(form: inner, outer: formMatrix(dict).concatenating(outer), depth: depth + 1)
                }
            }
            owner.note("mask: no match"); return nil
        }
        func part(_ i: Int) -> String { String(text[Range(match.range(at: i), in: text)!]) }
        let v = (1...6).map { CGFloat(Double(part($0)) ?? 0) }
        var matrix = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
        matrix = matrix.concatenating(formMatrix(dict)).concatenating(outer)
        var resources: CGPDFDictionaryRef?, xobjects: CGPDFDictionaryRef?, picture: CGPDFStreamRef?
        guard CGPDFDictionaryGetDictionary(dict, "Resources", &resources), let resources,
              CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects), let xobjects,
              CGPDFDictionaryGetStream(xobjects, part(7), &picture), let picture,
              let pictureDict = CGPDFStreamGetDictionary(picture) else { owner.note("mask: no picture"); return nil }
        guard var image = Self.picture(picture, pictureDict) else { owner.note("mask: unreadable " + Self.describe(pictureDict)); return nil }
        // The mask's own picture with its own alpha: laid on the group's black backdrop, where it
        // is clear it is black — no light, nothing shown through it.
        var own: CGPDFStreamRef?
        if CGPDFDictionaryGetStream(pictureDict, "SMask", &own), let own, let ownDict = CGPDFStreamGetDictionary(own),
           let alpha = Self.picture(own, ownDict, gray: true), let laid = Self.masked(image, by: alpha) {
            image = laid
        }
        return (image, matrix.concatenating(state.ctm))
    }

    /// The path painted under a soft mask made of a picture: drawn here, on the mask's own pixels,
    /// the mask's luminosity laid over it as its alpha — and given to the browser as a picture.
    func paintMasked(fill: Int32?, stroke: Bool) {
        guard let mask = state.softMask else { return }
        let width = mask.image.width, height = mask.image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let grey = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        grey.draw(mask.image, in: rect)
        guard let alpha = grey.makeImage() else { return }
        context.clip(to: rect, mask: alpha)
        // The page into the mask's pixels: its unit square filling them.
        context.scaleBy(x: CGFloat(width), y: CGFloat(height))
        context.concatenate(mask.ctm.inverted())
        context.concatenate(state.ctm)
        if let rule = fill {
            context.setFillColor(CGColor(srgbRed: state.fill.r, green: state.fill.g, blue: state.fill.b, alpha: state.fillAlpha))
            context.addPath(cgPath)
            context.fillPath(using: rule == 1 ? .evenOdd : .winding)
        }
        if stroke {
            context.setStrokeColor(CGColor(srgbRed: state.stroke.r, green: state.stroke.g, blue: state.stroke.b, alpha: state.strokeAlpha))
            context.setLineWidth(state.lineWidth)
            context.addPath(cgPath)
            context.strokePath()
        }
        guard let picture = context.makeImage() else { return }
        let id = owner.image(picture, opaque: false)
        guard id >= 0 else { return }
        let unit = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 1)
        drawn.append(owner.command(["i", id, Self.matrix(unit.concatenating(mask.ctm)), owner.chain(state.clip), 1, state.blend]))
    }

    /// `image`, drawn with `ctm`, with the soft mask in force laid over it as its alpha — the mask's
    /// luminosity, where it falls on the picture.
    func masked(_ image: CGImage, ctm: CGAffineTransform) -> CGImage? {
        guard let mask = state.softMask else { return image }
        let width = image.width, height = image.height
        // The mask's unit square in the picture's pixels: mask unit → page → picture unit → pixels,
        // the picture's rows from its top.
        let toPixels = CGAffineTransform(a: CGFloat(width), b: 0, c: 0, d: CGFloat(height), tx: 0, ty: 0)
        let place = mask.ctm.concatenating(ctm.inverted()).concatenating(toPixels)
        guard let grey = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        grey.concatenate(place)
        grey.draw(mask.image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let alpha = grey.makeImage() else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.clip(to: rect, mask: alpha)
        context.draw(image, in: rect)
        return context.makeImage()
    }

    /// A picture, with its soft mask for its alpha, drawn in the unit square the CTM puts it in —
    /// row 0 at the square's top.
    func drawImage(_ stream: CGPDFStreamRef, _ dict: CGPDFDictionaryRef) {
        guard let image = Self.picture(stream, dict) else { owner.note("unreadable image " + Self.describe(dict)); return }
        var maskStream: CGPDFStreamRef?
        var opaque = true
        var picture = image
        if CGPDFDictionaryGetStream(dict, "SMask", &maskStream), let maskStream,
           let maskDict = CGPDFStreamGetDictionary(maskStream), let mask = Self.picture(maskStream, maskDict, gray: true),
           let masked = Self.masked(image, by: mask) {
            picture = masked
            opaque = false
        }
        if let r = raster {
            r.saveGState()
            r.concatenate(state.ctm)
            r.setAlpha(state.fillAlpha)
            r.draw(picture, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            r.restoreGState()
            return
        }
        if state.softMask != nil, let laid = masked(picture, ctm: state.ctm) {
            picture = laid
            opaque = false
        }
        // Nothing to see: a shadow so faint it changes no pixel by more than one part in a hundred.
        if !opaque, Self.strongest(picture) <= 2 { return }
        let id = owner.image(picture, opaque: opaque)
        guard id >= 0, state.fillAlpha > 0 else { return }
        let unit = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 1)
        let chain = owner.chain(state.clip)
        drawn.append(owner.command(["i", id, Self.matrix(unit.concatenating(state.ctm)), chain, Self.n(state.fillAlpha, 3), state.blend]))
    }

    static func describe(_ dict: CGPDFDictionaryRef) -> String {
        var parts: [String] = []
        CGPDFDictionaryApplyBlock(dict, { key, object, _ in
            let name = String(cString: key)
            var value = ""
            var number: CGPDFReal = 0
            var integer: CGPDFInteger = 0
            var cname: UnsafePointer<CChar>?
            var flag: CGPDFBoolean = 0
            if CGPDFObjectGetValue(object, .integer, &integer) { value = "\(integer)" }
            else if CGPDFObjectGetValue(object, .real, &number) { value = "\(number)" }
            else if CGPDFObjectGetValue(object, .name, &cname), let cname { value = "/" + String(cString: cname) }
            else if CGPDFObjectGetValue(object, .boolean, &flag) { value = flag != 0 ? "true" : "false" }
            else { value = "\(CGPDFObjectGetType(object).rawValue)" }
            parts.append("\(name)=\(value)")
            return true
        }, nil)
        return parts.sorted().joined(separator: " ")
    }

    static func describeFunction(_ object: CGPDFObjectRef) -> String {
        var dict: CGPDFDictionaryRef?
        if !CGPDFObjectGetValue(object, .dictionary, &dict) {
            var stream: CGPDFStreamRef?
            if CGPDFObjectGetValue(object, .stream, &stream), let stream { dict = CGPDFStreamGetDictionary(stream) }
        }
        return dict.map(describe) ?? "?"
    }

    static func picture(_ stream: CGPDFStreamRef, _ dict: CGPDFDictionaryRef, gray: Bool = false) -> CGImage? {
        var width: CGPDFInteger = 0, height: CGPDFInteger = 0, bits: CGPDFInteger = 8
        CGPDFDictionaryGetInteger(dict, "Width", &width)
        CGPDFDictionaryGetInteger(dict, "Height", &height)
        CGPDFDictionaryGetInteger(dict, "BitsPerComponent", &bits)
        var format = CGPDFDataFormat.raw
        guard width > 0, height > 0, let data = CGPDFStreamCopyData(stream, &format) as Data? else { return nil }
        if format != .raw {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        var components = gray ? 1 : 3
        if !gray {
            var object: CGPDFObjectRef?
            if CGPDFDictionaryGetObject(dict, "ColorSpace", &object), let object { components = Self.components(of: object) }
        }
        let bytes = bits / 8
        guard bits == 8 || bits == 16, data.count >= width * height * components * bytes,
              let provider = CGDataProvider(data: data as CFData) else { return nil }
        let space = components == 1 ? CGColorSpaceCreateDeviceGray() : CGColorSpace(name: CGColorSpace.sRGB)!
        // Sixteen bits a sample, as PDF keeps them: the high byte first.
        let info = bits == 16 ? CGBitmapInfo.byteOrder16Big : CGBitmapInfo(rawValue: 0)
        return CGImage(width: width, height: height, bitsPerComponent: bits, bitsPerPixel: bits * components,
                       bytesPerRow: width * components * bytes, space: space, bitmapInfo: info,
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// `image` with `mask`'s grey as its alpha: a grey picture clipped to is taken as alpha, white
    /// showing.
    static func masked(_ image: CGImage, by mask: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let grey = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return nil }
        grey.draw(mask, in: rect)
        guard let alpha = grey.makeImage() else { return nil }
        context.clip(to: rect, mask: alpha)
        context.draw(image, in: rect)
        return context.makeImage()
    }

    /// A form: drawn where it is, its own matrix and box, in a group made see-through as one where
    /// its alpha or blend asks for it.
    func drawForm(_ stream: CGPDFStreamRef, _ dict: CGPDFDictionaryRef) {
        stack.append(state)
        raster?.saveGState()
        defer { raster?.restoreGState() }
        var matrix: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(dict, "Matrix", &matrix), let matrix, CGPDFArrayGetCount(matrix) == 6 {
            var v = [CGPDFReal](repeating: 0, count: 6)
            for index in 0..<6 { CGPDFArrayGetNumber(matrix, index, &v[index]) }
            state.ctm = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5]).concatenating(state.ctm)
        }
        var box: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(dict, "BBox", &box), let box, CGPDFArrayGetCount(box) == 4 {
            var v = [CGPDFReal](repeating: 0, count: 4)
            for index in 0..<4 { CGPDFArrayGetNumber(box, index, &v[index]) }
            add("M", [v[0], v[1]]); add("L", [v[2], v[1]]); add("L", [v[2], v[3]]); add("L", [v[0], v[3]]); add("Z", [])
            pendingClip = 0
            applyClip()
            endPath()
        }
        var group: CGPDFDictionaryRef?
        let grouped = raster == nil && CGPDFDictionaryGetDictionary(dict, "Group", &group) && (state.fillAlpha < 1 || state.blend != "normal")
        if grouped {
            drawn.append(owner.command(["G", Self.n(state.fillAlpha, 3), state.blend, owner.chain(state.clip)]))
            state.fillAlpha = 1
            state.strokeAlpha = 1
            state.blend = "normal"
        }
        var resources: CGPDFDictionaryRef?
        CGPDFDictionaryGetDictionary(dict, "Resources", &resources)
        if let resources, let parent = self.stream {
            let content = CGPDFContentStreamCreateWithStream(stream, resources, parent)
            run(content)
            CGPDFContentStreamRelease(content)
        } else {
            owner.note("form without resources")
        }
        if grouped { drawn.append(owner.command(["E"])) }
        closeMasks(down: stack.last?.openMasks ?? 0)
        state = stack.removeLast()
    }

    // MARK: Shadings

    func drawShading(_ dict: CGPDFDictionaryRef) {
        if state.softMask != nil { owner.note("shading under a soft mask") }
        var type: CGPDFInteger = 0
        CGPDFDictionaryGetInteger(dict, "ShadingType", &type)
        guard type == 2 || type == 3 else { owner.note("shading \(type)"); return }
        var coordsArray: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dict, "Coords", &coordsArray), let coordsArray else { return }
        var coords: [Double] = []
        for index in 0..<CGPDFArrayGetCount(coordsArray) {
            var value: CGPDFReal = 0
            CGPDFArrayGetNumber(coordsArray, index, &value)
            coords.append(Self.n(value, 3))
        }
        var components = 3
        var space: CGPDFObjectRef?
        if CGPDFDictionaryGetObject(dict, "ColorSpace", &space), let space { components = Self.components(of: space) }
        var extend = [true, true]
        var extendArray: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(dict, "Extend", &extendArray), let extendArray {
            for index in 0..<min(2, CGPDFArrayGetCount(extendArray)) {
                var value: CGPDFBoolean = 0
                CGPDFArrayGetBoolean(extendArray, index, &value)
                extend[index] = value != 0
            }
        }
        var function: CGPDFObjectRef?
        guard CGPDFDictionaryGetObject(dict, "Function", &function), let function else { return }
        let stops = Self.stops(function, components: components, from: 0, to: 1)
        guard !stops.isEmpty else { owner.note("shading function " + Self.describeFunction(function)); return }
        if let r = raster {
            let colours = stops.compactMap { stop -> (CGFloat, CGColor)? in
                guard let at = stop.first as? Double, let hex = stop.last as? String, hex.count == 7,
                      let v = Int(hex.dropFirst(), radix: 16) else { return nil }
                return (CGFloat(at), CGColor(srgbRed: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255,
                                             blue: CGFloat(v & 255) / 255, alpha: 1))
            }
            guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colours.map(\.1) as CFArray,
                                            locations: colours.map(\.0)) else { return }
            var options: CGGradientDrawingOptions = []
            if extend[0] { options.insert(.drawsBeforeStartLocation) }
            if extend[1] { options.insert(.drawsAfterEndLocation) }
            r.saveGState()
            r.concatenate(state.ctm)
            r.setAlpha(state.fillAlpha)
            let c = coords.map { CGFloat($0) }
            if type == 2 { r.drawLinearGradient(gradient, start: CGPoint(x: c[0], y: c[1]), end: CGPoint(x: c[2], y: c[3]), options: options) }
            else { r.drawRadialGradient(gradient, startCenter: CGPoint(x: c[0], y: c[1]), startRadius: c[2],
                                        endCenter: CGPoint(x: c[3], y: c[4]), endRadius: c[5], options: options) }
            r.restoreGState()
            return
        }
        let id = owner.shading(["t": type, "c": coords, "s": stops, "e": extend])
        drawn.append(owner.command(["g", id, Self.matrix(state.ctm), owner.chain(state.clip), Self.n(state.fillAlpha, 3), state.blend]))
    }

    /// A shading's function as colour stops — exact for type 2 with N of 1, and type 3 stitching
    /// them; sampled otherwise.
    static func stops(_ object: CGPDFObjectRef, components: Int, from: Double, to: Double) -> [[Any]] {
        var dict: CGPDFDictionaryRef?
        if !CGPDFObjectGetValue(object, .dictionary, &dict) {
            var stream: CGPDFStreamRef?
            if CGPDFObjectGetValue(object, .stream, &stream), let stream { dict = CGPDFStreamGetDictionary(stream) }
        }
        guard let dict else { return [] }
        var type: CGPDFInteger = -1
        CGPDFDictionaryGetInteger(dict, "FunctionType", &type)
        func numbers(_ key: String) -> [CGFloat] {
            var array: CGPDFArrayRef?
            guard CGPDFDictionaryGetArray(dict, key, &array), let array else { return [] }
            return (0..<CGPDFArrayGetCount(array)).map { index in
                var value: CGPDFReal = 0
                CGPDFArrayGetNumber(array, index, &value)
                return value
            }
        }
        func stop(_ at: Double, _ v: [CGFloat]) -> [Any] {
            [n(CGFloat(at), 4), colour(colour(Array(v.prefix(components))))]
        }
        switch type {
        case 0:
            // Sampled: each sample a stop, evenly along the way.
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream else { return [] }
            var format = CGPDFDataFormat.raw
            guard let data = CGPDFStreamCopyData(stream, &format) as Data? else { return [] }
            let size = Int(numbers("Size").first ?? 0)
            var bits: CGPDFInteger = 8
            CGPDFDictionaryGetInteger(dict, "BitsPerSample", &bits)
            let range = numbers("Range")
            let samples = [UInt8](data)
            guard size > 1, bits == 8 || bits == 16 else { return [] }
            let width = bits / 8, top = bits == 8 ? 255.0 : 65535.0
            return (0..<size).compactMap { index -> [Any]? in
                var values: [CGFloat] = []
                for component in 0..<components {
                    let at = (index * components + component) * width
                    guard at + width - 1 < samples.count else { return nil }
                    let raw = width == 1 ? Double(samples[at]) : Double(Int(samples[at]) << 8 | Int(samples[at + 1]))
                    let low = range.count > component * 2 ? Double(range[component * 2]) : 0
                    let high = range.count > component * 2 + 1 ? Double(range[component * 2 + 1]) : 1
                    values.append(CGFloat(low + raw / top * (high - low)))
                }
                return stop(from + (to - from) * Double(index) / Double(size - 1), values)
            }
        case 2:
            var c0 = numbers("C0"), c1 = numbers("C1")
            if c0.isEmpty { c0 = [CGFloat](repeating: 0, count: components) }
            if c1.isEmpty { c1 = [CGFloat](repeating: 1, count: components) }
            var exponent: CGPDFReal = 1
            CGPDFDictionaryGetNumber(dict, "N", &exponent)
            let steps = exponent == 1 ? 1 : 8
            return (0...steps).map { step in
                let x = Double(step) / Double(steps)
                let f = pow(x, Double(exponent))
                return stop(from + (to - from) * x, zip(c0, c1).map { $0 + ($1 - $0) * CGFloat(f) })
            }
        case 3:
            var functions: CGPDFArrayRef?
            guard CGPDFDictionaryGetArray(dict, "Functions", &functions), let functions else { return [] }
            let bounds = numbers("Bounds").map(Double.init)
            let domain = numbers("Domain").map(Double.init)
            let start = domain.first ?? 0, end = domain.count > 1 ? domain[1] : 1
            let edges = [start] + bounds + [end]
            var all: [[Any]] = []
            for index in 0..<CGPDFArrayGetCount(functions) {
                var child: CGPDFObjectRef?
                guard CGPDFArrayGetObject(functions, index, &child), let child, index + 1 < edges.count else { continue }
                let a = (edges[index] - start) / (end - start), b = (edges[index + 1] - start) / (end - start)
                all += stops(child, components: components, from: from + (to - from) * a, to: from + (to - from) * b)
            }
            return all
        default:
            return []
        }
    }

    // MARK: Words

    func nextLine(_ tx: CGFloat, _ ty: CGFloat) {
        lineMatrix = CGAffineTransform(translationX: tx, y: ty).concatenating(lineMatrix)
        textMatrix = lineMatrix
    }

    func setFont(_ name: String) {
        guard let stream, let object = CGPDFContentStreamGetResource(stream, "Font", name) else { state.font = nil; return }
        var dict: CGPDFDictionaryRef?
        guard CGPDFObjectGetValue(object, .dictionary, &dict), let dict else { return }
        var descriptor: CGPDFDictionaryRef?
        var program: CGPDFStreamRef?
        guard CGPDFDictionaryGetDictionary(dict, "FontDescriptor", &descriptor), let descriptor,
              CGPDFDictionaryGetStream(descriptor, "FontFile2", &program), let program else {
            owner.note("font without TrueType program")
            state.font = nil
            return
        }
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(program, &format) as Data? else { return }
        let key = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
        state.fontKey = key
        if let known = owner.fonts[key] { state.font = known; return }
        var first: CGPDFInteger = 0
        CGPDFDictionaryGetInteger(dict, "FirstChar", &first)
        var widthsArray: CGPDFArrayRef?
        var widths: [Int: CGFloat] = [:]
        if CGPDFDictionaryGetArray(dict, "Widths", &widthsArray), let widthsArray {
            for index in 0..<CGPDFArrayGetCount(widthsArray) {
                var value: CGPDFReal = 0
                CGPDFArrayGetNumber(widthsArray, index, &value)
                widths[first + index] = value
            }
        }
        let source = LetterSource(program: data, widths: widths)
        owner.fonts[key] = source
        state.font = source
    }

    func show(_ bytes: [UInt8]) {
        let s = state
        // Peek: words under a soft mask, or drawn into one, are their letters' outlines as one path,
        // painted here — the browser has no soft masks.
        let here = raster != nil || s.softMask != nil
        let letters = CGMutablePath()
        defer {
            if here, !letters.isEmpty, s.fillAlpha > 0, s.mode != 3, s.mode != 7 {
                endPath()
                cgPath = letters
                pathEmpty = false
                let pending = pendingClip
                pendingClip = nil
                paint(fill: 0, stroke: false)
                pendingClip = pending
            }
        }
        for byte in bytes {
            let code = Int(byte)
            if let font = s.font, s.mode != 3, s.mode != 7, let glyph = font.glyph(code), let outline = font.outline(glyph) {
                var cache = owner.letters[s.fontKey] ?? [:]
                let id: Int
                if here {
                    id = -1
                } else if let known = cache[code] {
                    id = known
                } else {
                    id = owner.path(Self.pathString(outline))
                    cache[code] = id
                    owner.letters[s.fontKey] = cache
                }
                // The letter's own space — a thousand to the em — into the words', then the page's.
                let rendering = CGAffineTransform(a: s.fontSize * s.scale / 1000, b: 0, c: 0, d: s.fontSize / 1000,
                                                  tx: 0, ty: s.rise)
                let m = rendering.concatenating(textMatrix).concatenating(s.ctm)
                if here {
                    // In the words' user space, for `paint` to put the CTM on it as on any path.
                    letters.addPath(outline, transform: rendering.concatenating(textMatrix))
                } else if s.fillAlpha > 0 {
                    drawn.append(owner.command(["f", id, Self.matrix(m), owner.chain(s.clip), 0, Self.colour(s.fill),
                                                Self.n(s.fillAlpha, 3), s.blend]))
                }
            } else if s.font == nil || (s.font?.glyph(code) == nil && code != 32) {
                owner.note("letter not found")
            }
            let width = (s.font?.widths[code] ?? 0) / 1000
            let tx = (width * s.fontSize + s.charSpacing + (code == 32 ? s.wordSpacing : 0)) * s.scale
            textMatrix = CGAffineTransform(translationX: tx, y: 0).concatenating(textMatrix)
        }
    }

    static func pathString(_ path: CGPath) -> String {
        var parts: [String] = []
        func p(_ point: CGPoint) -> String { "\(text(point.x)) \(text(point.y))" }
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint: parts.append("M" + p(e.points[0]))
            case .addLineToPoint: parts.append("L" + p(e.points[0]))
            case .addQuadCurveToPoint: parts.append("Q" + p(e.points[0]) + " " + p(e.points[1]))
            case .addCurveToPoint: parts.append("C" + p(e.points[0]) + " " + p(e.points[1]) + " " + p(e.points[2]))
            case .closeSubpath: parts.append("Z")
            @unknown default: break
            }
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Operands

private func popNumbers(_ scanner: CGPDFScannerRef, _ count: Int) -> [CGFloat] {
    var values = [CGFloat](repeating: 0, count: count)
    for index in stride(from: count - 1, through: 0, by: -1) {
        var value: CGPDFReal = 0
        CGPDFScannerPopNumber(scanner, &value)
        values[index] = value
    }
    return values
}

private func popName(_ scanner: CGPDFScannerRef) -> String? {
    var name: UnsafePointer<CChar>?
    guard CGPDFScannerPopName(scanner, &name), let name else { return nil }
    return String(cString: name)
}

private func popString(_ scanner: CGPDFScannerRef) -> [UInt8]? {
    var string: CGPDFStringRef?
    guard CGPDFScannerPopString(scanner, &string), let string, let bytes = CGPDFStringGetBytePtr(string) else { return nil }
    return Array(UnsafeBufferPointer(start: bytes, count: CGPDFStringGetLength(string)))
}
