import Foundation

/// Đọc câu nhập nhanh kiểu bản web: "35k cafe" -> 35000 + "cafe".
enum QuickParse {
    /// "35k" -> 35000, "1tr2" -> 1200000, "1.5tr" -> 1500000, "35.000" -> 35000, "35000" -> 35000
    static func amount(_ raw: String) -> Int? {
        let s = strip(raw).replacingOccurrences(of: " ", with: "")
        if let m = s.wholeMatch(of: #/(\d+(?:[.,]\d+)?)(tr|trieu|m|cu)(\d+)?/#) {
            var v = Double(m.1.replacingOccurrences(of: ",", with: "."))!
            if let extra = m.3 { v += Double("0." + extra)! }
            return Int((v * 1e6).rounded())
        }
        if let m = s.wholeMatch(of: #/(\d+(?:[.,]\d+)?)(k|nghin|ngan|ng|n)/#) {
            return Int((Double(m.1.replacingOccurrences(of: ",", with: "."))! * 1e3).rounded())
        }
        if s.wholeMatch(of: #/\d{1,3}(?:[.,]\d{3})+/#) != nil {
            return Int(s.filter(\.isNumber))
        }
        if s.wholeMatch(of: #/\d+/#) != nil { return Int(s) }
        return nil
    }

    /// "35k cafe sáng" -> (35000, "cafe sáng"); bỏ chữ "đồng" Siri hay thêm vào. Không thấy số tiền thì nil.
    static func expense(_ text: String) -> (amount: Int, note: String)? {
        let re = #/(?i)(^|\s)(\d+(?:[.,]\d+)*)\s*(k|tr|triệu|trieu|củ|cu|m|nghìn|ngàn|nghin|ngan)?(\d+)?(?:\s*(?:đồng|dong|vnđ|vnd|đ))?(?![\p{L}\d])/#
        guard let m = text.firstMatch(of: re),
              let a = amount(String(m.2) + String(m.3 ?? "") + String(m.4 ?? "")), a > 0 else { return nil }
        let note = (text[..<m.range.lowerBound] + " " + text[m.range.upperBound...])
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return (a, note)
    }

    // MARK: Giọng nói

    /// Câu nói (Siri / nhận dạng giọng nói) -> số tiền + ghi chú. Hiểu cả số bằng chữ và kiểu nói tắt:
    /// "ba mươi lăm nghìn cà phê", "ba lăm cafe", "hai trăm rưỡi", "một triệu hai", "nửa triệu", "2 lít", "3 củ".
    /// Không có đơn vị và số dưới 1.000 thì hiểu là nghìn ("35 cafe" = 35.000đ).
    static func spoken(_ text: String) -> (amount: Int, note: String)? {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let toks = words.map { tok(strip($0).trimmingCharacters(in: .punctuationCharacters)) }

        // Tìm các cụm số liền nhau; chọn cụm "chắc chắn" nhất (có đơn vị / hàng chục trăm / số ≥ 10), rồi lớn nhất
        var best: (range: Range<Int>, value: Double, strong: Bool)?
        var i = 0
        while i < toks.count {
            guard let t = toks[i], t.canStart else { i += 1; continue }
            var j = i + 1
            while j < toks.count, let u = toks[j] {
                j += 1
                if case .end = u { break }
            }
            let run = toks[i..<j].compactMap { $0 }
            let v = value(run)
            let strong = run.contains { $0.isStrong }
            if v > 0, best == nil || (strong && !best!.strong) || (strong == best!.strong && v > best!.value) {
                best = (i..<j, v, strong)
            }
            i = j
        }
        guard let b = best else { return nil }
        var amount = Int(b.value.rounded())
        if amount < 1000 { amount *= 1000 }
        let note = words.enumerated().filter { !b.range.contains($0.offset) }.map(\.element).joined(separator: " ")
        return (amount, note)
    }

    private enum Tok {
        case num(Double), tens, hundreds, linh, scale(Double), half, halfPrefix, end, full(Double)

        var canStart: Bool {
            // "triệu hai", "trăm hai", "chục rưỡi": cụm số có thể mở đầu bằng đơn vị (ngầm hiểu là một)
            switch self { case .num, .full, .halfPrefix, .tens, .hundreds, .scale: true; default: false }
        }
        var isStrong: Bool {
            switch self {
            case .scale, .full, .hundreds, .tens: true
            case .num(let v): v >= 10
            default: false
            }
        }
    }

    private static let digitWords: [String: Double] = [
        "khong": 0, "mot": 1, "hai": 2, "ba": 3, "bon": 4, "tu": 4, "nam": 5, "lam": 5, "nham": 5,
        "sau": 6, "bay": 7, "tam": 8, "chin": 9,
    ]

    private static func tok(_ k: String) -> Tok? {
        if let d = digitWords[k] { return .num(d) }
        switch k {
        case "muoi", "chuc": return .tens
        case "tram": return .hundreds
        case "linh", "le": return .linh
        case "nghin", "ngan", "k", "canh": return .scale(1e3)     // cành: tiếng lóng = nghìn
        case "trieu", "tr", "cu": return .scale(1e6)
        case "ty", "toi": return .scale(1e9)                   // tỏi: tiếng lóng = tỷ
        case "lit", "xi": return .scale(1e5)        // tiếng lóng: 1 lít / 1 xị = 100 nghìn
        case "ruoi": return .half
        case "nua": return .halfPrefix
        case "dong", "d", "vnd": return .end
        default: break
        }
        if k.wholeMatch(of: #/\d{1,3}(?:[.,]\d{3})+/#) != nil { return .num(siriShorthand(Double(k.filter(\.isNumber))!)) }
        if let m = k.wholeMatch(of: #/(\d+)(?:[.,](\d+))?/#) {
            let v = Double(String(m.1) + (m.2.map { "." + $0 } ?? ""))!
            return .num(m.2 == nil ? siriShorthand(v) : v)
        }
        if k.contains(where: \.isLetter), let a = amount(k) { return .full(Double(a)) }   // "35k", "1tr2"
        return nil
    }

    /// Siri hiểu "mười triệu hai" theo nghĩa đen và viết "10.000.002". Số tròn triệu/nghìn cộng 1–9 đồng
    /// thì không ai nói thật, nên hiểu là nói tắt: 10.000.002 -> 10.200.000, 1.002 -> 1.200.
    private static func siriShorthand(_ x: Double) -> Double {
        for scale in [1e9, 1e6, 1e3] where x >= scale {
            let d = x.truncatingRemainder(dividingBy: scale)
            if d >= 1 && d <= 9 { return x - d + d * scale / 10 }
            return x
        }
        return x
    }

    /// Đơn vị khi đọc thành lời: từ 1 triệu trở lên là "triệu", còn lại là "nghìn".
    private static func impliedScale(_ x: Double) -> Double { x >= 1e6 ? 1e6 : 1e3 }

    /// Đọc một cụm số tiếng Việt thành giá trị.
    private static func value(_ toks: [Tok]) -> Double {
        enum Last { case none, num, tens, hundreds, linh, scale }
        var total = 0.0, group = 0.0, lastScale = 0.0
        var pending: Double?
        var pendingAfter = Last.none, last = Last.none

        // "hai trăm năm" = 250 (nói tắt), "hai trăm linh năm" = 205
        func flush() -> Double {
            guard let p = pending else { return group }
            return group + (pendingAfter == .hundreds && p < 10 ? p * 10 : p)
        }

        loop: for t in toks {
            switch t {
            case .num(let v):
                if let p = pending, last == .num, p < 10, v < 10, pendingAfter != .hundreds, pendingAfter != .linh {
                    group += p * 10 + v          // "ba lăm" = 35
                    pending = nil; last = .tens
                } else if let p = pending, last == .num, p >= 1000, v < 10, p.truncatingRemainder(dividingBy: impliedScale(p)) == 0 {
                    // Siri hay viết "1 triệu 2" thành "1.000.000 2": số tròn nghìn/triệu + một chữ số = nói tắt
                    // -> 1.200.000; "10.000 5" (mười nghìn năm) -> 10.500
                    total += group + p; group = 0
                    lastScale = impliedScale(p)
                    pending = v; pendingAfter = .scale; last = .num
                } else {
                    if pending != nil { group = flush() }
                    pending = v; pendingAfter = last; last = .num
                }
            case .tens:
                if let p = pending { group += p * 10; pending = nil } else { group += 10 }
                last = .tens
            case .hundreds:
                group += (pending ?? 1) * 100; pending = nil; last = .hundreds
            case .linh:
                last = .linh
            case .scale(let s):
                let g = flush()
                total += (g == 0 ? 1 : g) * s
                group = 0; pending = nil; last = .scale; lastScale = s
            case .half:
                // rưỡi = nửa đơn vị đứng ngay trước: triệu rưỡi, trăm rưỡi, chục rưỡi
                if last == .scale { total += lastScale / 2 }
                else if last == .hundreds { group += 50 }
                else if last == .tens { group += 5 }
                else if let p = pending { pending = p + 0.5 }
                last = .none
            case .halfPrefix:
                if pending != nil { group = flush() }
                pending = 0.5; pendingAfter = last; last = .num
            case .full(let v):
                total += v; group = 0; pending = nil; last = .scale; lastScale = v >= 1e6 ? 1e6 : 1e3
            case .end:
                break loop
            }
        }

        // Phần đuôi sau đơn vị, nói tắt: "một triệu hai" = 1,2 triệu, "một triệu hai trăm" = 1,2 triệu, "ba nghìn hai" = 3.200
        if lastScale > 0 {
            if let p = pending, pendingAfter == .scale, group == 0, p < 10 { return total + p * lastScale / 10 }
            let rem = flush()
            if rem > 0 && rem < 1000 { return total + rem * max(lastScale / 1000, 1) }
            return total + rem
        }
        return total + flush()
    }
}

