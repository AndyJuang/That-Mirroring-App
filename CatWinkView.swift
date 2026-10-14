import SwiftUI

// 彩蛋：圖示在 2 秒內被點 5 次時，trigger 從 0 起每次加 1。
// 貓咪右眼被眼皮蓋住、換成闔眼的弧線，周圍 7 顆小星星飄散，1 秒後回到原圖，無音效。
// 系統開啟「減少動態效果」時只淡入淡出一次。
struct CatWinkEffect: ViewModifier {
    var trigger: Int

    @ViewState private var start: Date?
    @ViewState private var dimmed = false
    @ViewState private var played = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let duration: TimeInterval = 1.0
    private static let spread: CGFloat = 40

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: start == nil)) { timeline in
            let p = progress(at: timeline.date)
            content
                .scaleEffect(1 + 0.05 * sin(.pi * min(1, p / 0.45)))
                .overlay {
                    if p < 1 {
                        Canvas { context, size in
                            CatWinkDrawing.draw(in: &context, size: size, inset: Self.spread, progress: p)
                        }
                        .padding(-Self.spread)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
        }
        .opacity(dimmed ? 0.35 : 1)
        .task(id: trigger) {
            // 視窗關閉後重開也會重跑 task，只播放還沒播過的 trigger。
            guard trigger > played else { return }
            played = trigger
            if reduceMotion {
                start = nil
                withAnimation(.easeInOut(duration: 0.3)) { dimmed = true }
                try? await Task.sleep(for: .seconds(0.3))
                withAnimation(.easeInOut(duration: 0.3)) { dimmed = false }
            } else {
                dimmed = false
                start = .now
                try? await Task.sleep(for: .seconds(Self.duration))
                if !Task.isCancelled { start = nil }
            }
        }
    }

    private func progress(at date: Date) -> Double {
        guard let start else { return 1 }
        return min(1, max(0, date.timeIntervalSince(start) / Self.duration))
    }
}

// 座標以 1024×1024 的 AppIcon 為準（icon/AppIcon-1024.png）。
private enum CatWinkDrawing {
    static let face = Color(red: 8 / 255, green: 8 / 255, blue: 6 / 255)
    static let yellow = Color(red: 253 / 255, green: 220 / 255, blue: 51 / 255)
    static let red = Color(red: 229 / 255, green: 53 / 255, blue: 43 / 255)
    static let amber = Color(red: 245 / 255, green: 165 / 255, blue: 20 / 255)

    // 右眼弧線約在 x 585–681、y 495–545；眼皮蓋住稍大的範圍，避開左下方的嘴巴。
    static let eyelid = CGRect(x: 578, y: 482, width: 114, height: 72)
    static let starCount = 7

    static func draw(in context: inout GraphicsContext, size: CGSize, inset: CGFloat, progress p: Double) {
        let side = min(size.width, size.height) - inset * 2
        guard side > 0 else { return }
        let unit = side / 1024
        let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * unit, y: origin.y + y * unit)
        }

        // 眼皮：0.10–0.30 由上往下蓋住，維持到 0.55，再於 0.75 前掀開。
        let closed = ramp(p, 0.10, 0.30) - ramp(p, 0.55, 0.75)
        if closed > 0 {
            let lid = CGRect(origin: point(eyelid.minX, eyelid.minY),
                             size: CGSize(width: eyelid.width * unit, height: eyelid.height * unit))
            var layer = context
            layer.clip(to: Path(CGRect(x: lid.minX, y: lid.minY, width: lid.width, height: lid.height * closed)))
            layer.fill(Path(roundedRect: lid, cornerRadius: 14 * unit), with: .color(face))

            var wink = Path()
            wink.move(to: point(592, 520))
            wink.addQuadCurve(to: point(674, 520), control: point(633, 548))
            layer.opacity = max(0, closed * 2 - 1)
            layer.stroke(wink, with: .color(yellow),
                         style: StrokeStyle(lineWidth: 24 * unit, lineCap: .round))
        }

        // 星星：從圖示中心往外飄散，依序錯開出發。
        let center = point(512, 512)
        for i in 0..<starCount {
            let q = ramp(p, 0.12 + 0.035 * Double(i), 0.72 + 0.035 * Double(i))
            guard q > 0, q < 1 else { continue }
            let angle = (-64 + Double(i) * 360 / Double(starCount) + (i.isMultiple(of: 2) ? 8 : -8)) * .pi / 180
            let eased = 1 - pow(1 - q, 3)
            // 往上飛的星星縮短距離，免得被視窗標題列切掉。
            let distance = side * (0.30 + 0.50 * eased) * (1 - 0.4 * max(0, -sin(angle)))
            let radius = (i.isMultiple(of: 3) ? 7.0 : 5.0) * sin(.pi * min(1, q * 1.4))
            let opacity = q < 0.2 ? q / 0.2 : 1 - (q - 0.2) / 0.8

            var layer = context
            layer.opacity = opacity
            layer.translateBy(x: center.x + distance * cos(angle), y: center.y + distance * sin(angle))
            layer.rotate(by: .degrees(q * 90))
            layer.fill(sparkle(radius: max(0, radius)), with: .color(i.isMultiple(of: 2) ? red : amber))
        }
    }

    private static func sparkle(radius r: CGFloat) -> Path {
        let k = r * 0.18
        var path = Path()
        path.move(to: CGPoint(x: 0, y: -r))
        path.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: k, y: -k))
        path.addQuadCurve(to: CGPoint(x: 0, y: r), control: CGPoint(x: k, y: k))
        path.addQuadCurve(to: CGPoint(x: -r, y: 0), control: CGPoint(x: -k, y: k))
        path.addQuadCurve(to: CGPoint(x: 0, y: -r), control: CGPoint(x: -k, y: -k))
        path.closeSubpath()
        return path
    }

    private static func ramp(_ p: Double, _ from: Double, _ to: Double) -> Double {
        let t = min(1, max(0, (p - from) / (to - from)))
        return t * t * (3 - 2 * t)
    }
}
