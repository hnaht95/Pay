import SwiftUI

// Khung giao diện dùng chung: thanh tiêu đề, dải nút ở đáy, mép mờ trên / dưới vùng cuộn.
//
// Mọi phần ở đây do app tự vẽ, giống nhau trên iOS 18, 26 và 27. Hiệu ứng mép cuộn của hệ thống (iOS 26+) bị tắt ở mọi chỗ
// dùng các hàm này: mỗi bản iOS (và mỗi SDK lúc dựng) vẽ nó một khác — iOS 26 nhẹ, iOS 27 đậm, bản dựng bằng SDK 26 chạy trên
// iOS 27 thì không có — nên trước đây giao diện lệch nhau giữa các máy. Các nhánh #available chỉ còn trong tệp này.

extension View {
    /// Tắt hiệu ứng mép cuộn của hệ thống (iOS 26+) ở các cạnh cho trước; app tự vẽ mép mờ bằng EdgeFade
    @ViewBuilder func noSystemEdge(_ edges: VerticalEdge.Set = .all) -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: edges.contains(.top) && edges.contains(.bottom) ? .all : edges.contains(.top) ? .top : .bottom)
        } else { self }
    }
}

/// Dải mờ ở mép vùng cuộn: kính mờ làm nhoè nội dung trôi qua, cộng màu nền đặc ở sát mép, nhạt dần vào trong.
/// solid: phần (0…1) tính từ mép còn gần như đặc — vd chiều cao thanh trạng thái trên tổng chiều cao dải
struct EdgeFade: View {
    let edge: VerticalEdge
    var color: Color = Palette.bg
    var solid: CGFloat = 0.35

    var body: some View {
        let (from, to): (UnitPoint, UnitPoint) = edge == .top ? (.top, .bottom) : (.bottom, .top)
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(stops: [.init(color: color.opacity(edge == .top ? 1 : 0.9), location: 0),
                                   .init(color: color.opacity(edge == .top ? 0.8 : 0.7), location: solid),
                                   .init(color: color.opacity(0), location: 1)], startPoint: from, endPoint: to)
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: solid),
                                     .init(color: .clear, location: 1)], startPoint: from, endPoint: to))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Mép trên trang chủ / Nhóm chung (không có thanh tiêu đề): dải mờ phủ vùng thanh trạng thái (đồng hồ, pin), ló xuống
    /// dưới 26 điểm, để nội dung cuộn lên không đè thẳng vào đồng hồ
    @ViewBuilder func statusBarEdge(on: Bool, color: Color = Palette.bg) -> some View {
        if on {
            noSystemEdge(.top).overlay(alignment: .top) {
                GeometryReader { g in
                    let bar = g.safeAreaInsets.top, tail: CGFloat = 26
                    EdgeFade(edge: .top, color: color, solid: bar / (bar + tail))
                        .frame(height: bar + tail)
                        .offset(y: -bar)
                }
            }
        } else { self }
    }

    /// Gắn dải nút nổi ở đáy màn (trang chủ, Nhóm chung): phủ lên nội dung, phía sau là dải mờ cao 150 từ mép dưới màn. Nội dung
    /// cuộn phải chừa 120 điểm ở cuối. Dải nút tự lùi xuống (padding âm) cho sát vạch Home.
    /// fallbackBlur: lớp mờ dùng khi dựng phim (FilmFade); ngoài phim dùng EdgeFade.
    /// above: lớp nằm trên lớp mờ, dưới hai nút, sát mép trên dải nút (vd thanh "Đã xoá · Hoàn tác"): trồi lên từ sau dải nút,
    /// ẩn thì chui xuống lại sau đó, không bao giờ đè lên nút
    func withDock<D: View, B: View, A: View>(dock: D, fallbackBlur: B, film: Bool = false,
                                             @ViewBuilder above: () -> A = { EmptyView() }) -> some View {
        let attached = dock.background(alignment: .top) { above().alignmentGuide(.top) { $0[.bottom] + 8 } }
        return noSystemEdge(.bottom).overlay(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                if film {
                    fallbackBlur
                    attached.padding(.bottom, FilmScreen<EmptyView>.insets.bottom)
                } else {
                    // Đặc tới ngang mép trên hai nút (~92 điểm từ đáy màn), tan dần ở đoạn phía trên
                    EdgeFade(edge: .bottom, solid: 0.6)
                        .frame(height: 150)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .ignoresSafeArea()
                    attached
                }
            }
        }
    }

    /// Thanh nút ở đáy một tấm (Lưu, Thêm…): chừa chỗ ở đáy vùng cuộn, phía sau là dải mờ như dải nút trang chủ.
    /// Bàn phím hiện lên thì hai nút nằm yên ở đáy, bị bàn phím che (không bị đẩy lên đè vào nội dung)
    func bottomBar<B: View>(@ViewBuilder _ bar: () -> B) -> some View {
        noSystemEdge(.bottom)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bar().background(alignment: .bottom) {
                    EdgeFade(edge: .bottom, color: Color(.systemGroupedBackground))
                        .frame(height: 120).offset(y: 34)
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    /// Các tấm có thanh tiêu đề (Thống kê, Cài đặt, Thông báo, sửa nhóm / thành viên / danh mục, chọn ngân hàng…): thanh tiêu đề
    /// do app tự vẽ (xem screenTitle), nền đặc đúng màu trang, một vạch mảnh bên dưới, nội dung cuộn lên cắt gọn ở vạch, không
    /// nhoè. Ở đây chỉ tắt hiệu ứng mép cuộn của hệ thống và báo màu nền cho screenTitle.
    /// back: trang được đẩy vào trong một tấm (có nút quay lại ở thanh tiêu đề)
    func softTopEdge(fade: Color? = nil, back: Bool = false) -> some View {
        noSystemEdge(.top).preference(key: TitleBarKey.self, value: TitleBarStyle(color: fade ?? Palette.bg, back: back))
    }

    /// Ghim tiêu đề tự vẽ ở mép trên vùng cuộn (Lịch sử, Khoản chung): nền đặc suốt thanh, nội dung cuộn lên cắt gọn ở chân
    /// thanh (thanh tự vẽ vạch ngăn nếu cần)
    func softTitleBar<T: View>(@ViewBuilder _ title: () -> T) -> some View {
        noSystemEdge(.top).safeAreaInset(edge: .top, spacing: 0) {
            title().background { Palette.surface.padding(.horizontal, -18).allowsHitTesting(false) }
        }
    }

    /// Tiêu đề màn hình: cỡ 21 đậm, bằng "Sửa / Lưu khoản chi" (tiêu đề mặc định của iOS nhỏ quá)
    func screenTitle(_ title: String) -> some View { modifier(ScreenTitle(title: title)) }
}

/// Kiểu thanh tiêu đề tự vẽ của một tấm: màu nền (màu trang) và có nút quay lại hay không. softTopEdge báo lên
struct TitleBarStyle: Equatable {
    var color: Color
    var back = false
}

struct TitleBarKey: PreferenceKey {
    static let defaultValue: TitleBarStyle? = nil
    static func reduce(value: inout TitleBarStyle?, nextValue: () -> TitleBarStyle?) { value = value ?? nextValue() }
}

/// Tiêu đề màn. Tấm có softTopEdge: ẩn thanh tiêu đề của hệ thống, tự vẽ thanh ghim trên vùng cuộn — chữ 21 đậm ở giữa, cách
/// mép trên tấm 20 và cách vạch 20, vạch mảnh lùi 16 hai bên, nền đặc màu trang tràn lên mép trên tấm — nên iOS 18, 26, 27 ra
/// cùng một hình. Màn khác: tiêu đề nằm trong thanh của hệ thống như trước
private struct ScreenTitle: ViewModifier {
    let title: String
    @State private var bar: TitleBarStyle?
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(TitleBarKey.self) { bar = $0 }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let bar {
                    VStack(spacing: 0) {
                        ZStack {
                            Text(title).font(.system(size: 21, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                                .padding(.horizontal, bar.back ? 60 : 20)
                            if bar.back {
                                HStack {
                                    Button { dismiss() } label: {
                                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                                            .frame(width: 40, height: 40)
                                            .background(Color.primary.opacity(0.06), in: Circle())
                                            .contentShape(Circle())
                                    }
                                    .buttonStyle(Pressable()).foregroundStyle(.primary)
                                    .accessibilityLabel(L("Quay lại"))
                                    Spacer()
                                }
                                .padding(.leading, 12)
                            }
                        }
                        // Cao cố định theo dòng chữ: nút quay lại (40) tràn ra trên dưới chứ không làm thanh cao thêm, nên trang có nút
                        // và trang không có nút cao bằng nhau
                        .frame(maxWidth: .infinity).frame(height: 26)
                        .padding(.top, 20).padding(.bottom, 20)
                        Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1).padding(.horizontal, 16)
                    }
                    .background { bar.color.ignoresSafeArea(edges: .top) }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .principal) { Text(title).font(.system(size: 21, weight: .bold)).lineLimit(1) }
            }
            .toolbar(bar == nil ? .automatic : .hidden, for: .navigationBar)
    }
}
