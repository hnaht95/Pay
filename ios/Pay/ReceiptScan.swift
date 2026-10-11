import SwiftUI
import Vision
import VisionKit

/// Chụp hoá đơn bằng máy quét tài liệu của iOS (tự bắt khung, làm phẳng giấy)
struct ReceiptCamera: UIViewControllerRepresentable {
    var done: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let done: (UIImage?) -> Void
        init(done: @escaping (UIImage?) -> Void) { self.done = done }

        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            done(scan.pageCount > 0 ? scan.imageOfPage(at: 0) : nil)
        }
        func documentCameraViewControllerDidCancel(_ c: VNDocumentCameraViewController) { done(nil) }
        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFailWithError error: Error) { done(nil) }
    }
}

/// Đọc chữ trên hoá đơn ngay trên máy (Vision, không gửi ảnh đi đâu) rồi lấy ra tổng tiền và tên quán
enum ReceiptReader {
    struct Result { var amount: Int?; var merchant: String? }

    static func read(_ image: UIImage) async -> Result {
        guard let cg = image.cgImage else { return Result() }
        let rows: [String] = await withCheckedContinuation { c in
            let req = VNRecognizeTextRequest { r, _ in
                let obs = (r.results as? [VNRecognizedTextObservation]) ?? []
                c.resume(returning: Self.rows(obs))
            }
            req.recognitionLevel = .accurate
            req.recognitionLanguages = ["vi-VN", "en-US"]
            req.usesLanguageCorrection = true
            do { try VNImageRequestHandler(cgImage: cg).perform([req]) } catch { c.resume(returning: []) }
        }
        return parse(rows)
    }

    /// Ghép các mẩu chữ cùng một hàng (hoá đơn hay để chữ "Tổng cộng" và số tiền ở hai cột) thành từng dòng, trên xuống dưới
    private static func rows(_ obs: [VNRecognizedTextObservation]) -> [String] {
        let items = obs.compactMap { o in o.topCandidates(1).first.map { (box: o.boundingBox, text: $0.string) } }
            .sorted { $0.box.midY > $1.box.midY }
        var out: [[(box: CGRect, text: String)]] = []
        for it in items {
            if let last = out.last?.first, abs(last.box.midY - it.box.midY) < max(last.box.height, it.box.height) * 0.6 {
                out[out.count - 1].append(it)
            } else { out.append([it]) }
        }
        return out.map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
    }

    /// Tổng tiền: số trên dòng có chữ "tổng / thanh toán / total" (ưu tiên dòng dưới cùng), không có thì số lớn nhất hợp lý.
    /// Tên quán: dòng chữ đầu tiên đủ dài, không phải tiêu đề kiểu "Hoá đơn".
    static func parse(_ rows: [String]) -> Result {
        let keys = ["tong thanh toan", "thanh toan", "tong cong", "tong tien", "can thanh toan", "total", "tong"]
        let skip = ["tien thua", "tien khach", "khach dua", "change", "cash", "giam gia", "discount", "vat", "thue"]
        var best: Int?
        for (i, r) in rows.enumerated().reversed() {
            let k = Store.noteKey(r)
            guard keys.contains(where: { k.contains($0) }), !skip.contains(where: { k.contains($0) }) else { continue }
            if let a = amounts(r).last ?? (i + 1 < rows.count ? amounts(rows[i + 1]).first : nil) { best = a; break }
        }
        if best == nil {
            // Bỏ dòng ngày giờ ("11/10/2026 18:30") để năm không bị lấy làm số tiền
            best = rows.filter { r in !skip.contains(where: { Store.noteKey(r).contains($0) }) && !r.contains("/") && !r.contains(":") }
                .flatMap(amounts).filter { $0 < 50_000_000 }.max()
        }
        let titles = ["hoa don", "phieu", "receipt", "invoice", "bill", "ban le", "thanh toan"]
        let merchant = rows.first { r in
            let k = Store.noteKey(r)
            return r.filter(\.isLetter).count >= 3 && !titles.contains(where: { k.contains($0) }) && amounts(r).isEmpty
        }
        return Result(amount: best, merchant: merchant?.trimmingCharacters(in: .whitespaces).capitalized)
    }

    /// Các số tiền trong một dòng: "125.000", "1,250,000", "125000đ", "125.000 VND". Bỏ số quá ngắn (< 1.000) và số dài như số điện thoại
    static func amounts(_ s: String) -> [Int] {
        // Chặn hai đầu: một dãy số dài hơn (số điện thoại, mã hoá đơn) không bị cắt ra thành một "số tiền"
        let re = try! NSRegularExpression(pattern: #"(?<![\d.,])(?:\d{1,3}(?:[.,]\d{3})+|\d{4,9})(?![\d])"#)
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { m in
            guard let r = Range(m.range, in: s) else { return nil }
            let n = Int(s[r].filter(\.isNumber)) ?? 0
            return n >= 1000 && n < 1_000_000_000 ? n : nil
        }
    }
}
