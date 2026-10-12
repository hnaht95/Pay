import SwiftUI

/// Form của các màn cài đặt / chỉnh sửa. iOS 26+ và iOS 17: Form như thường (iOS 26+ có mép cuộn mềm của hệ thống).
/// iOS 18–25: vẫn là Form (giữ chevron, chọn hàng, Picker, Toggle… của hệ thống) nhưng nền từng ô tự vẽ thay cho nền ô của
/// UIKit, để nội dung lẫn nền ô trôi lên dưới thanh tiêu đề nhoè dần theo từng điểm ảnh như mép trên trang chủ (nền ô của
/// UIKit không làm nhoè được: chữ nhoè còn khung ô vẫn sắc). Đi kèm softTopEdge(home: true).
struct BlurForm<Content: View>: View {
    @ViewBuilder var content: Content
    /// Chân thanh tiêu đề, toạ độ toàn màn (đỉnh vùng an toàn của Form)
    @State private var edge: CGFloat = 0

    var body: some View {
        if #available(iOS 26.0, *) {
            Form { content }
        } else if #available(iOS 18.0, *) {
            Form {
                ForEach(sections: content) { sec in
                    let plain = sec.containerValues.cardless
                    Section {
                        Group(subviews: sec.content) { rows in
                            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                                let rowPlain = plain || row.containerValues.cardless
                                row
                                    .titleEdgeBlur(edge)
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(rowPlain ? nil : CellBackground(first: i == 0, last: i == rows.count - 1).titleEdgeBlur(edge))
                            }
                        }
                    } header: {
                        // Viết thường như iOS 26+ (iOS 18 tự viết hoa tiêu đề mục; textCase của Form không tới được đây)
                        sec.header.textCase(nil).titleEdgeBlur(edge)
                    } footer: {
                        sec.footer.titleEdgeBlur(edge)
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { edge = $0 }
        } else {
            Form { content }
        }
    }
}

/// Nền ô của Form kiểu nhóm bo góc (như UIKit trên iOS 18: bo 10, vạch ngăn mảnh giữa các ô lùi vào 20)
private struct CellBackground: View {
    let first: Bool, last: Bool

    var body: some View {
        UnevenRoundedRectangle(topLeadingRadius: first ? 10 : 0, bottomLeadingRadius: last ? 10 : 0,
                               bottomTrailingRadius: last ? 10 : 0, topTrailingRadius: first ? 10 : 0, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
            .overlay(alignment: .bottom) {
                if !last { Rectangle().fill(Color(.separator)).frame(height: 1 / 3).padding(.leading, 20) }
            }
    }
}

@available(iOS 18.0, *)
extension ContainerValues {
    /// Mục / hàng không có nền ô (vd thẻ xem trước nằm trên nền trang)
    @Entry var cardless: Bool = false
}

extension View {
    /// Đánh dấu mục / hàng không vẽ nền ô trong BlurForm (đi cùng listRowBackground(Color.clear) cho iOS 26+ / 17)
    @ViewBuilder func cardless() -> some View {
        if #available(iOS 18.0, *) { containerValue(\.cardless, true) } else { self }
    }

    /// iOS cũ hơn 26: nhoè dần khi trôi lên dưới thanh tiêu đề (edge: chân thanh, toạ độ toàn màn), như mép trên trang chủ:
    /// nhoè hết mức (7) ở mép trên tấm (thanh tiêu đề trong tấm cao 56), hết nhoè 14 pt dưới chân thanh. Xem EdgeBlurRow
    @ViewBuilder func titleEdgeBlur(_ edge: CGFloat) -> some View {
        if #available(iOS 26.0, *) { self } else { EdgeBlurRow(edge: edge) { self } }
    }
}

/// Hàng thấp: nhoè cả hàng một mức theo vị trí giữa hàng (blur thường) — shader từng điểm ảnh không vẽ được nút gạt, chọn
/// giờ, ô nhập… của hệ thống (hiện ô vàng gạch chéo). Hàng cao (vd bảng màu của Sửa danh mục, chỉ có nút tự vẽ): nhoè cả hàng
/// thì phần còn ở giữa màn cũng mờ theo, nên nhoè theo từng điểm ảnh (shader topEdgeBlur) như trang chủ
private struct EdgeBlurRow<Content: View>: View {
    let edge: CGFloat
    @ViewBuilder let content: Content
    @State private var tall = false

    var body: some View {
        Group {
            if tall {
                content.visualEffect { c, g in
                    let y = g.frame(in: .global).minY
                    return c.layerEffect(ShaderLibrary.topEdgeBlur(.float(edge - 56 - y), .float(70), .float(7)),
                                         maxSampleOffset: CGSize(width: 11, height: 11), isEnabled: edge > 0 && y < edge + 14)
                }
            } else {
                content.visualEffect { c, g in
                    let y = g.frame(in: .global).midY
                    var t = edge > 0 ? min(1, max(0, (edge + 14 - y) / 70)) : 0
                    t = t * t * (3 - 2 * t)
                    return c.blur(radius: 7 * t)
                }
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.height > 120 } action: { tall = $0 }
    }
}
