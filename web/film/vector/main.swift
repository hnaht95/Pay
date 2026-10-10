import AppKit

// vpack <take> <out> <name>
//
// Packs one of Pay's films for peakapp.vn's canvas player: the PDF pages the app writes when run with
// -filmExport (ios/Pay/FilmExport.swift: one per frame, the iPhone's screen in points) and its meta.json, read
// through Shot's FilmVectors into the vector-film format (vector-film.js). Then pack it smaller with
// peakapp.vn/tools/pack-films.py.
//
//   swiftc -O -o vpack FilmVectors.swift main.swift
//   ./vpack <take> <out> file.vi


let args = CommandLine.arguments
guard args.count >= 4 else { print("vpack <take> <out> <name>"); exit(1) }
let take = URL(fileURLWithPath: args[1], isDirectory: true)
let out = URL(fileURLWithPath: args[2], isDirectory: true)
let name = args[3]
try FileManager.default.createDirectory(at: out.appendingPathComponent("img"), withIntermediateDirectories: true)

let meta = try JSONSerialization.jsonObject(with: Data(contentsOf: take.appendingPathComponent("meta.json"))) as! [String: Any]
let log = meta["frames"] as! [[String: Any]]
let fps = meta["fps"] as! Double
let screen = meta["screen"] as! [Double]
let SCREEN = CGSize(width: screen[0], height: screen[1])
FilmVectors.maskBounds = CGRect(x: -20, y: -20, width: SCREEN.width + 40, height: SCREEN.height + 40)

let vectors = FilmVectors(folder: out.appendingPathComponent("img"), prefix: "\(name).")
// The page is y up from its foot; the film's screen is y down from its top.
let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: SCREEN.height)

var frames: [[Int]] = []
var camera: [[Double]] = []
let began = Date()
for (i, entry) in log.enumerated() {
    let url = take.appendingPathComponent(String(format: "p%05d.pdf", entry["page"] as! Int))
    guard let data = try? Data(contentsOf: url) else { continue }
    autoreleasepool { frames.append(vectors.frame(pdf: data, base: flip)) }
    camera.append((entry["camera"] as! [Double]).map { ($0 * 10000).rounded() / 10000 })
    if i % 50 == 0 { print("read \(i)/\(log.count)") }
}
print(String(format: "read %d pages in %.1fs", frames.count, Date().timeIntervalSince(began)))

let film: [String: Any] = [
    "fps": fps, "screen": [SCREEN.width, SCREEN.height], "start": 0, "opens": 0,
    "length": Double(frames.count - 1) / fps,
    "paths": vectors.paths, "clips": vectors.clips, "chains": vectors.chains, "shadings": vectors.shadings,
    "commands": vectors.commands, "images": vectors.images, "frames": frames,
    // The camera per frame as Shot's films keep it: [zoom, x, y], where the part it sees starts.
    "camera": camera,
]
let json = try JSONSerialization.data(withJSONObject: film, options: [])
try json.write(to: out.appendingPathComponent("\(name).json"))
print("\(name): \(frames.count) frames, \(vectors.commands.count) commands, \(vectors.paths.count) paths, " +
      "\(vectors.images.count) pictures, \(json.count / 1024) KB; unread \(vectors.unread)")
