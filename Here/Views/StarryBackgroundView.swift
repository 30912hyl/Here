import SwiftUI

// MARK: - 清爽金色渐变背景的星空
// 用 TimelineView + Canvas 单层绘制所有星星,避免几十个 view 各自跑动画导致的卡顿。
struct StarryBackgroundView: View {
    @State private var stars: [Star] = []

    // 改这里切换配色：.rose / .champagne / .lemon / .cool
    let style: GoldStyle = .champagne

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    drawStars(context: context, time: time)
                    drawShootingStar(context: context, size: size, time: time)
                }
            }
            .onAppear {
                generateStars(in: geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in
                generateStars(in: newSize)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: 星星绘制

    private func drawStars(context: GraphicsContext, time: TimeInterval) {
        for star in stars {
            // 0...1 的闪烁相位
            let phase = (sin(2 * .pi * time / star.duration + star.phaseOffset) + 1) / 2
            let brightness = 0.25 + 0.75 * phase
            let scale = 0.65 + 0.35 * phase
            let drawSize = star.size * scale

            // 光晕:柔和的径向渐变,代替昂贵的 shadow
            let glowRadius = drawSize * (star.kind == .dot ? 2.6 : 1.6)
            let glowRect = CGRect(
                x: star.x - glowRadius, y: star.y - glowRadius,
                width: glowRadius * 2, height: glowRadius * 2
            )
            context.fill(
                Circle().path(in: glowRect),
                with: .radialGradient(
                    Gradient(colors: [star.color.opacity(0.38 * brightness), .clear]),
                    center: CGPoint(x: star.x, y: star.y),
                    startRadius: 0,
                    endRadius: glowRadius
                )
            )

            // 星星本体
            var body = context
            body.translateBy(x: star.x, y: star.y)
            let rect = CGRect(x: -drawSize / 2, y: -drawSize / 2, width: drawSize, height: drawSize)

            switch star.kind {
            case .dot:
                body.opacity = brightness
                body.fill(Circle().path(in: rect), with: .color(star.color))
            case .sparkle:
                body.rotate(by: .degrees((phase - 0.5) * 32))
                body.opacity = brightness
                body.fill(SparkleShape().path(in: rect), with: .color(star.color))
            case .cross:
                body.rotate(by: .degrees(45))
                body.opacity = brightness
                let crossRect = rect.insetBy(dx: drawSize * 0.18, dy: drawSize * 0.18)
                body.fill(SparkleShape().path(in: crossRect), with: .color(star.color))
            }
        }
    }

    // MARK: 流星
    // 以 12 秒为一个周期,用周期序号生成伪随机参数;约 1/3 的周期没有流星,节奏不呆板。

    private func drawShootingStar(context: GraphicsContext, size: CGSize, time: TimeInterval) {
        guard size.width > 0, size.height > 0 else { return }

        let cycle: TimeInterval = 12
        let cycleIndex = Int(time / cycle)
        let localTime = time.truncatingRemainder(dividingBy: cycle)

        func seeded(_ salt: Int) -> Double {
            let n = (cycleIndex &* 9301 &+ salt &* 49297) % 233280
            return Double(abs(n)) / 233280.0
        }

        guard seeded(1) > 0.33 else { return }  // 这个周期没有流星

        let flightDuration: TimeInterval = 1.1
        guard localTime < flightDuration else { return }
        let progress = localTime / flightDuration

        let startX = size.width * (0.05 + 0.6 * seeded(2))
        let startY = 24 + (size.height * 0.24) * seeded(3)
        let angle = Angle.degrees(16 + 18 * seeded(4)).radians
        let travel: CGFloat = 260

        let x = startX + cos(angle) * travel * progress
        let y = startY + sin(angle) * travel * progress
        let opacity = progress < 0.3 ? progress / 0.3 : (1 - progress) / 0.7

        var ctx = context
        ctx.translateBy(x: x, y: y)
        ctx.rotate(by: .radians(angle))
        ctx.opacity = opacity * 0.9

        let tailRect = CGRect(x: -70, y: -0.8, width: 70, height: 1.6)
        ctx.fill(
            Capsule().path(in: tailRect),
            with: .linearGradient(
                Gradient(colors: [.clear, .white.opacity(0.85), .white]),
                startPoint: CGPoint(x: -70, y: 0),
                endPoint: CGPoint(x: 0, y: 0)
            )
        )
    }

    // MARK: 星星生成

    private func generateStars(in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }

        let fieldHeight = size.height * 0.62
        let attempts = 130
        var generatedStars: [Star] = []

        for i in 0..<attempts {
            let randomY = CGFloat.random(in: 0...fieldHeight)
            let normalizedY = randomY / fieldHeight
            let densityFactor = pow(1.0 - normalizedY, 1.8)
            guard Double.random(in: 0...1) < densityFactor else { continue }

            let kind: Star.Kind
            switch Double.random(in: 0...1) {
            case ..<0.16: kind = .sparkle
            case ..<0.28: kind = .cross
            default:      kind = .dot
            }

            generatedStars.append(Star(
                id: i,
                kind: kind,
                x: CGFloat.random(in: 0...size.width),
                y: randomY,
                size: kind == .dot
                    ? CGFloat.random(in: 1.5...3.5)
                    : CGFloat.random(in: 6...13),
                color: .white,
                duration: Double.random(in: 1.8...4.2),
                phaseOffset: Double.random(in: 0...(2 * .pi))
            ))
        }

        self.stars = generatedStars
    }
}

// MARK: - 四角星形状 ✦
struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        var path = Path()
        let top = CGPoint(x: center.x, y: center.y - radius)
        let right = CGPoint(x: center.x + radius, y: center.y)
        let bottom = CGPoint(x: center.x, y: center.y + radius)
        let left = CGPoint(x: center.x - radius, y: center.y)

        path.move(to: top)
        path.addQuadCurve(to: right, control: center)
        path.addQuadCurve(to: bottom, control: center)
        path.addQuadCurve(to: left, control: center)
        path.addQuadCurve(to: top, control: center)
        path.closeSubpath()
        return path
    }
}

// MARK: - 配色方案
enum GoldStyle {
    case rose, champagne, lemon, cool

    var colors: [Color] {
        switch self {
        case .rose:      // 1️⃣ 玫瑰金
            return [Color(hex: "#E8C4B8").opacity(0.65), Color(hex: "#F5D9CE").opacity(0.5),
                    Color(hex: "#FFF0E8").opacity(0.3),  Color(hex: "#FFFAF7").opacity(0.15), .clear]
        case .champagne: // 2️⃣ 香槟金
            return [Color(hex: "#F7E7CE").opacity(0.65), Color(hex: "#FFF3E0").opacity(0.5),
                    Color(hex: "#FFFBF0").opacity(0.3),  Color(hex: "#FFFFFA").opacity(0.15), .clear]
        case .lemon:     // 3️⃣ 柠檬金
            return [Color(hex: "#F4E4C1").opacity(0.65), Color(hex: "#FFF8E1").opacity(0.5),
                    Color(hex: "#FFFEF5").opacity(0.3),  Color(hex: "#FFFFF9").opacity(0.15), .clear]
        case .cool:      // 4️⃣ 冷金色
            return [Color(hex: "#E8E3D3").opacity(0.65), Color(hex: "#F5F1E1").opacity(0.5),
                    Color(hex: "#FAF8F0").opacity(0.3),  Color(hex: "#FEFEFC").opacity(0.15), .clear]
        }
    }
}

// MARK: - 星星数据模型
struct Star: Identifiable {
    enum Kind {
        case dot      // 圆点
        case sparkle  // 四角星 ✦
        case cross    // 斜十字小星
    }

    let id: Int
    let kind: Kind
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let color: Color
    let duration: Double
    let phaseOffset: Double
}
