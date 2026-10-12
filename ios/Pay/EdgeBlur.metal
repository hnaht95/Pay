#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// Nhoè hai mép trái / phải như mép cuộn mềm của iOS: độ nhoè tăng dần theo từng điểm ảnh khi lại gần mép
/// (0 ở cách mép `zone` pt, tối đa `maxRadius` pt sát mép), liền một vùng qua mọi phần tử nằm trong đó.
/// `edges`: x = 1 thì nhoè mép trái, y = 1 thì nhoè mép phải (phía không còn nội dung bị che thì không nhoè).
[[ stitchable ]] half4 edgeBlur(float2 pos, SwiftUI::Layer layer, float width, float zone, float maxRadius, float2 edges, float offset) {
    // pos là toạ độ trong phần tử; offset = vị trí phần tử trong khung dải, để tính khoảng cách tới mép dải
    float x = pos.x + offset;
    float dl = edges.x > 0.5 ? x : 1e6;
    float dr = edges.y > 0.5 ? width - x : 1e6;
    float t = clamp(1.0 - min(dl, dr) / zone, 0.0, 1.0);
    t = t * t * (3.0 - 2.0 * t);
    float r = maxRadius * t;
    if (r < 0.4) { return layer.sample(pos); }
    half4 acc = half4(0.0);
    float wsum = 0.0;
    for (int i = -4; i <= 4; i++) {
        for (int j = -4; j <= 4; j++) {
            float w = exp(-float(i * i + j * j) / 8.0);
            acc += layer.sample(pos + float2(i, j) * (r / 4.0)) * half(w);
            wsum += w;
        }
    }
    return acc / half(wsum);
}

/// Như edgeBlur nhưng theo chiều dọc, cho mép trên màn hình (iOS cũ không có mép cuộn mềm của hệ thống): nhoè tối đa ở
/// mép trên (`top` pt kể từ đỉnh lớp là mép trên màn hình, tức lớp đang cuộn lệch bao nhiêu), giảm dần tới hết `zone` pt.
[[ stitchable ]] half4 topEdgeBlur(float2 pos, SwiftUI::Layer layer, float top, float zone, float maxRadius) {
    float d = pos.y - top;
    float t = clamp(1.0 - d / zone, 0.0, 1.0);
    t = t * t * (3.0 - 2.0 * t);
    float r = maxRadius * t;
    if (r < 0.4) { return layer.sample(pos); }
    half4 acc = half4(0.0);
    float wsum = 0.0;
    for (int i = -4; i <= 4; i++) {
        for (int j = -4; j <= 4; j++) {
            float w = exp(-float(i * i + j * j) / 8.0);
            acc += layer.sample(pos + float2(i, j) * (r / 4.0)) * half(w);
            wsum += w;
        }
    }
    return acc / half(wsum);
}

// Như topEdgeBlur nhưng ở đáy: nhoè dần khi điểm ảnh xuống dưới đường (bottom - zone), hết mức ở bottom
[[ stitchable ]] half4 bottomEdgeBlur(float2 pos, SwiftUI::Layer layer, float bottom, float zone, float maxRadius) {
    float d = bottom - pos.y;
    float t = clamp(1.0 - d / zone, 0.0, 1.0);
    t = t * t * (3.0 - 2.0 * t);
    float r = maxRadius * t;
    if (r < 0.4) { return layer.sample(pos); }
    half4 acc = half4(0.0);
    float wsum = 0.0;
    for (int i = -4; i <= 4; i++) {
        for (int j = -4; j <= 4; j++) {
            float w = exp(-float(i * i + j * j) / 8.0);
            acc += layer.sample(pos + float2(i, j) * (r / 4.0)) * half(w);
            wsum += w;
        }
    }
    return acc / half(wsum);
}
