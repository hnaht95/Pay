import Foundation

/// Các phần của bảng Việt -> Anh, mỗi phần một file EN+<tên>.swift trong thư mục này
extension English {
    static var parts: [[String: String]] { [home, settings, house, stats, voice] }
}
