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
}
