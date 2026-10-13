import SwiftUI

/// Form của các màn cài đặt / chỉnh sửa: vẫn là Form (giữ chevron, chọn hàng, Picker, Toggle… của hệ thống) nhưng nền từng ô,
/// tiêu đề mục, lề và chiều cao hàng do app tự đặt theo kiểu Form của iOS 26, để iOS 18, 26, 27 ra cùng một hình.
/// iOS 17: Form như thường (chưa có ForEach(sections:))
struct BlurForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 18.0, *) {
            Form {
                ForEach(sections: content) { sec in
                    let plain = sec.containerValues.cardless
                    Section {
                        Group(subviews: sec.content) { rows in
                            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                                let rowPlain = plain || row.containerValues.cardless
                                // Hàng không nền ô: dựng lại ở đây làm mất listRowInsets / listRowBackground gắn trên mục hay hàng, nên
                                // gắn lại: sát mép, nền trong suốt (các mục cardless đều như vậy)
                                if rowPlain {
                                    row.listRowSeparator(.hidden)
                                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                                } else {
                                    row
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(CellBackground(first: i == 0, last: i == rows.count - 1))
                                }
                            }
                        }
                    } header: {
                        // Viết thường như iOS 26+ (iOS 18 tự viết hoa tiêu đề mục; textCase của Form không tới được đây)
                        // Như tiêu đề mục của iOS 26: chữ thường, 17 đậm vừa, xám (iOS 18 tự viết hoa, chữ 13)
                        sec.header.textCase(nil).font(.system(size: 17, weight: .semibold)).foregroundStyle(.secondary)
                    } footer: {
                        sec.footer
                    }
                    .headerProminence(.increased)
                }
            }
            .textCase(nil)
            // Lề hai bên 16 và hàng cao tối thiểu 52 như Form của iOS 26 (iOS 18: lề 20, hàng 44)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .environment(\.defaultMinListRowHeight, 52)
        } else {
            Form { content }
        }
    }
}

/// Nền ô của Form kiểu nhóm bo góc, như Form của iOS 26: bo 26, vạch ngăn mảnh giữa các ô lùi vào 16 hai bên
private struct CellBackground: View {
    let first: Bool, last: Bool

    var body: some View {
        UnevenRoundedRectangle(topLeadingRadius: first ? 26 : 0, bottomLeadingRadius: last ? 26 : 0,
                               bottomTrailingRadius: last ? 26 : 0, topTrailingRadius: first ? 26 : 0, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
            .overlay(alignment: .bottom) {
                if !last { Rectangle().fill(Color(.separator)).frame(height: 1 / 3).padding(.horizontal, 16) }
            }
    }
}

@available(iOS 18.0, *)
extension ContainerValues {
    /// Mục / hàng không có nền ô (vd thẻ xem trước nằm trên nền trang)
    @Entry var cardless: Bool = false
}

extension View {
    /// Đánh dấu mục / hàng không vẽ nền ô trong BlurForm (đi cùng listRowBackground(Color.clear) cho iOS 17)
    @ViewBuilder func cardless() -> some View {
        if #available(iOS 18.0, *) { containerValue(\.cardless, true) } else { self }
    }
}
