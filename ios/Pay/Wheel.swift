import SwiftUI

// Bánh xe số của app Peek (Sources/Peek/UI/SettingsControls.swift), mang sang iOS: năm hàng, hàng giữa to và rõ,
// càng ra ngoài càng nhỏ và mờ; kéo dọc hoặc chạm số kề để quay. Bỏ phần cuộn chuột và con trỏ bàn tay của macOS.

/// Dáng của một bánh xe số: bày mấy hàng, cỡ chữ và độ đậm theo khoảng cách tới hàng giữa.
/// Khoảng cách tính bằng hàng và nhận cả số lẻ: lúc bánh xe đang quay, hàng nằm giữa chừng hai nấc thì cỡ chữ cũng giữa chừng.
struct WheelStyle {
    /// Khoảng từ hàng này tới hàng kế.
    var pitch: CGFloat
    /// Số hàng nhìn thấy.
    var rows: Int
    /// Bề ngang cột. Đặt cứng, nên số nào cũng không xô cột.
    var width: CGFloat
    var ink: Color
    var font: (Double) -> Font
    var fade: (Double) -> Double

    var height: CGFloat { pitch * CGFloat(rows) }
}

/// Một cột của bánh xe. Kéo lên xuống hoặc chạm số kề để quay.
struct WheelColumn: View {
    let count: Int
    /// Nấc đang chọn, 0 ..< `count`. Đổi từ bên ngoài thì cột quay theo.
    let current: Int
    let style: WheelStyle
    let label: (Int) -> String
    let pick: (Int) -> Void

    /// Vị trí, không quay vòng: cứ cộng dồn theo từng nấc, âm cũng được. Nhờ vậy cú quay từ 23 sang 00 trượt đúng một hàng.
    @State private var pos: Int
    /// Phần quãng kéo đã tính thành nấc. Trừ dần khỏi quãng kéo để không đếm lại đoạn cũ.
    @State private var spent: CGFloat = 0

    init(count: Int, current: Int, style: WheelStyle, label: @escaping (Int) -> String, pick: @escaping (Int) -> Void) {
        _pos = State(initialValue: current)
        self.count = count; self.current = current; self.style = style; self.label = label; self.pick = pick
    }

    var body: some View {
        WheelStrip(pos: Double(pos), count: count, style: style, label: label)
            .contentShape(Rectangle())
            .gesture(drag)
            // Đọc chỗ chạm chứ không gắn cử chỉ lên từng hàng: hàng đang trượt, gắn lên thứ đang chạy thì bắt được hay không tuỳ lúc.
            .onTapGesture(count: 1, coordinateSpace: .local) { point in
                let row = ((point.y - style.height / 2) / style.pitch).rounded()
                if row != 0 { turn(Int(row)) }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.82), value: pos)
            // Giá trị đổi từ chỗ khác (vd bị kéo về hiện tại vì chọn giờ trong tương lai) thì quay tới đó theo đường ngắn nhất.
            .onChange(of: current) { _, value in
                let now = ((pos % count) + count) % count
                guard now != value else { return }
                var delta = (value - now) % count
                if delta > count / 2 { delta -= count } else if delta < -count / 2 { delta += count }
                pos += delta
            }
    }

    /// Kéo dọc. Cứ đủ một hàng thì nhích một nấc, phần lẻ để dành cho nấc sau nên kéo chậm vẫn đi được từng nấc một.
    /// Kéo xuống là số nhỏ lại: bánh xe đi theo tay.
    private var drag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let notches = Int((value.translation.height - spent) / style.pitch)
                guard notches != 0 else { return }
                spent += CGFloat(notches) * style.pitch
                turn(-notches)
            }
            .onEnded { _ in spent = 0 }
    }

    private func turn(_ step: Int) {
        pos += step
        UISelectionFeedbackGenerator().selectionChanged()
        pick(((pos % count) + count) % count)
    }
}

/// Dải số của một cột, vẽ theo vị trí liên tục. Khai `Animatable` để SwiftUI dựng lại dải ở từng khung hình của cú quay:
/// cả vị trí, cỡ chữ và nội dung từng hàng cùng trượt.
private struct WheelStrip: View, Animatable {
    var pos: Double
    var count: Int
    var style: WheelStyle
    var label: (Int) -> String

    var animatableData: Double {
        get { pos }
        set { pos = newValue }
    }

    var body: some View {
        // Vẽ dư mỗi đầu một hàng so với chỗ nhìn thấy, để lúc đang quay vẫn còn số chạy vào từ ngoài khung.
        let base = Int(pos.rounded())
        let reach = style.rows / 2 + 1
        ZStack {
            ForEach(base - reach...base + reach, id: \.self) { index in
                let distance = abs(Double(index) - pos)
                Text(label(((index % count) + count) % count))
                    .font(style.font(distance))
                    .foregroundStyle(style.ink)
                    .opacity(style.fade(distance))
                    .lineLimit(1)
                    .fixedSize()
                    .offset(y: CGFloat(Double(index) - pos) * style.pitch)
            }
        }
        .frame(width: style.width, height: style.height)
        .clipped()
    }
}

/// Bánh xe giờ : phút như ô hẹn giờ trong tab Lịch của Peek. Phút đi từng nấc năm phút.
struct TimeWheel: View {
    /// Phút tính từ nửa đêm
    let time: Int
    let set: (Int) -> Void

    /// Cỡ to hơn bản của Peek cho vừa ngón tay: năm hàng cách nhau 30
    static let style = WheelStyle(
        pitch: 30, rows: 5, width: 54, ink: .primary,
        font: { .system(size: 28 - 9 * min($0, 1), weight: $0 < 0.5 ? .semibold : .medium).monospacedDigit() },
        fade: { 1 - 0.4 * min($0, 1) })

    /// Tối dần ra hai mép, liên tục theo chiều dọc chứ không theo từng hàng (theo từng hàng thì nhìn thành bậc thang).
    private static let edgeFade = LinearGradient(
        stops: [.init(color: .black.opacity(0.06), location: 0), .init(color: .black, location: 0.4),
                .init(color: .black, location: 0.6), .init(color: .black.opacity(0.06), location: 1)],
        startPoint: .top, endPoint: .bottom)

    var body: some View {
        HStack(spacing: 6) {
            WheelColumn(count: 24, current: time / 60, style: Self.style,
                        label: { String(format: "%02d", $0) },
                        pick: { set($0 * 60 + time % 60) })
            Text(":").font(Self.style.font(0)).foregroundStyle(.secondary)
            WheelColumn(count: 12, current: (time % 60) / 5, style: Self.style,
                        label: { String(format: "%02d", $0 * 5) },
                        pick: { set((time / 60) * 60 + $0 * 5) })
        }
        .mask(Self.edgeFade)
    }
}
