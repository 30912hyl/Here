import SwiftUI

// MARK: - 星空
// 设计目标:环境动效只在余光里存在——稀疏、缓慢、不可预测,不和正文抢注意力。
//
// 做法:没有"一批固定位置、一直在闪的星星"。只有少数几个"星位"(slot),每个星位按
// 自己的节奏循环:大部分时间是空的,偶尔有一颗星慢慢亮起、停一会儿、慢慢熄灭;
// 下一轮它出现在全新的随机位置。各星位的周期长度互不相同,所以整体永不重复。
//
// 全部状态都是时间的纯函数(不存任何 @State),用 TimelineView + Canvas 单层绘制。
struct StarryBackgroundView: View {
    /// 星位数量。每个星位约 40% 的时间可见,所以同一时刻平均只有 3~4 颗星。
    private static let slotCount = 10

    var body: some View {
        // 30fps 足够:亮灭过程以秒计,没必要按屏幕刷新率重绘
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                drawStars(context: context, size: size, time: time)
                drawShootingStar(context: context, size: size, time: time)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: 星星

    private func drawStars(context: GraphicsContext, size: CGSize, time: TimeInterval) {
        guard size.width > 0, size.height > 0 else { return }

        for slot in 0..<Self.slotCount {
            // 每个星位有自己的周期(7~16 秒)和相位,互不成整数比 → 整体不会出现可察觉的节拍
            let cycleLength = 7.0 + 9.0 * Self.random(slot, 0, 1)
            let shifted = time + cycleLength * Self.random(slot, 0, 2)
            let cycle = Int(floor(shifted / cycleLength))
            let progress = shifted / cycleLength - Double(cycle)   // 0..<1

            // 一轮里只有前 30%~55% 的时间有星,其余时间这个星位是空的
            let visibleFraction = 0.30 + 0.25 * Self.random(slot, cycle, 3)
            guard progress < visibleFraction else { continue }

            // 平滑的钟形包络:慢慢亮起 → 停留 → 慢慢熄灭(2~9 秒一次)
            let envelope = sin(.pi * progress / visibleFraction)
            let brightness = envelope * envelope * (0.65 + 0.35 * Self.random(slot, cycle, 4))

            // 位置每一轮都重新抽;只落在顶部 36%——再往下天已经接近白色,白星星在那里看不见
            let x = size.width * Self.random(slot, cycle, 5)
            let y = size.height * 0.36 * pow(Self.random(slot, cycle, 6), 1.6)

            let kindRoll = Self.random(slot, cycle, 7)
            let isDot = kindRoll > 0.72
            let baseSize: CGFloat = isDot
                ? 1.4 + 1.4 * Self.random(slot, cycle, 8)
                : 6 + 8 * Self.random(slot, cycle, 8)
            let drawSize = baseSize * (0.7 + 0.3 * envelope)

            // 白光晕:光必须比周围亮才是光,所以星星是白的,而它背后的天(FeedSkyBackground
            // 的渐变顶部)是香槟金。别把光晕或星体换成金色——浅底上比周围暗的"光"只会读成斑点。
            let glowRadius = drawSize * (isDot ? 3.4 : 1.7)
            let glowRect = CGRect(x: x - glowRadius, y: y - glowRadius,
                                  width: glowRadius * 2, height: glowRadius * 2)
            context.fill(
                Circle().path(in: glowRect),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.75 * brightness), .clear]),
                    center: CGPoint(x: x, y: y), startRadius: 0, endRadius: glowRadius)
            )

            var body = context
            body.translateBy(x: x, y: y)
            body.opacity = brightness
            let rect = CGRect(x: -drawSize / 2, y: -drawSize / 2, width: drawSize, height: drawSize)

            if isDot {
                body.fill(Circle().path(in: rect), with: .color(.white))
            } else {
                // 四角星在亮灭过程中缓缓转一点;一部分斜着放(✧),形态不单调
                let tilt = kindRoll > 0.5 ? 45.0 : 0.0
                body.rotate(by: .degrees(tilt + (envelope - 0.5) * 24))
                body.fill(SparkleShape().path(in: rect), with: .color(.white))
            }
        }
    }

    // MARK: 流星
    // 每 24 秒一个窗口,只有约 45% 的窗口有流星;出现时刻、起点、方向、角度、长度全部随机。

    private func drawShootingStar(context: GraphicsContext, size: CGSize, time: TimeInterval) {
        guard size.width > 0, size.height > 0 else { return }

        let window: TimeInterval = 24
        let index = Int(floor(time / window))
        let slot = 1000   // 和星位的随机序列错开

        guard Self.random(slot, index, 1) < 0.45 else { return }

        let flight = 0.9 + 0.5 * Self.random(slot, index, 2)
        let startTime = (window - flight) * Self.random(slot, index, 3)
        let local = time - Double(index) * window - startTime
        guard local >= 0, local < flight else { return }
        let progress = local / flight

        let goesLeft = Self.random(slot, index, 4) < 0.35
        let startX = size.width * (goesLeft ? 0.45 + 0.5 * Self.random(slot, index, 5)
                                            : 0.05 + 0.5 * Self.random(slot, index, 5))
        let startY = size.height * (0.04 + 0.22 * Self.random(slot, index, 6))
        let slope = Angle.degrees(14 + 24 * Self.random(slot, index, 7)).radians
        let angle = goesLeft ? .pi - slope : slope
        let travel = 170 + 150 * Self.random(slot, index, 8)
        let tail = 50 + 40 * Self.random(slot, index, 9)

        let x = startX + cos(angle) * travel * progress
        let y = startY + sin(angle) * travel * progress
        let opacity = progress < 0.3 ? progress / 0.3 : (1 - progress) / 0.7

        var ctx = context
        ctx.translateBy(x: x, y: y)
        ctx.rotate(by: .radians(angle))
        ctx.opacity = opacity * 0.9

        let tailRect = CGRect(x: -tail, y: -0.8, width: tail, height: 1.6)
        ctx.fill(
            Capsule().path(in: tailRect),
            with: .linearGradient(
                Gradient(colors: [.clear, .white.opacity(0.85), .white]),
                startPoint: CGPoint(x: -tail, y: 0),
                endPoint: CGPoint(x: 0, y: 0)
            )
        )
    }

    // MARK: 随机数

    /// 由 (星位, 轮次, 用途) 决定的 0..<1 伪随机数:同一轮内稳定,换一轮就完全不同。
    /// 必须用真正的位混合(splitmix64)。之前用的线性同余在相邻轮次之间只差约 4%,
    /// 结果就是"流星几乎总在同一个地方"。
    private static func random(_ slot: Int, _ cycle: Int, _ salt: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: slot) &* 0x9E37_79B9_7F4A_7C15
        x ^= UInt64(truncatingIfNeeded: cycle) &* 0xBF58_476D_1CE4_E5B9
        x ^= UInt64(truncatingIfNeeded: salt) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 30
        x &*= 0xBF58_476D_1CE4_E5B9
        x ^= x >> 27
        x &*= 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return Double(x >> 11) / Double(1 << 53)
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
