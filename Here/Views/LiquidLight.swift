import SwiftUI

// MARK: - 会动的光（第四版）
// 第一版在真机上是脏的：白纸上叠了几团比纸更深、更黄的色块，各自乱跑，上面还有一层纸纹颗粒。
// 光不可能比周围暗——比周围暗的"光"在浅底上只会读成污渍（StarryBackgroundView 里早就写过这一条）。
//
// 规则：
//   1. 暖色只从屏幕底边升起来，不做成悬在页面中间的色块。
//   2. 屏幕上面大半保持干净，那里是标签和标题。
//   3. 不叠纸纹。
//
// 全部状态都是"光的钟"（LiquidLight.clock）的纯函数，一个 Canvas，每秒 30 帧；
// 任何一个实例在同一时刻画出的都是同一幅画面，所以入口两页和 Feed 共用一片光。
//
// 只用在"看"的页面：品牌页、确认页、Feed。其余页面是纸与光，不动。
//
// 构图只有一种：底边一片淡金色的光，上半屏是干净的纸色。
// （11-20 在真机上比较过三种：底边一道光、整页淡淡一层、完全不要金色。
// 结论：有颜色比没有好；前两种看不出区别。所以只留这一种。）
//
// 关于"流动"，走过的弯路（都是量出来的，单位：屏幕下半截里变得最快的那 5% 的像素，每秒变几级，满级 255）：
//   第二版：约 0.1。她说希望再流动一点。
//   第三版：0.3，调到 3 倍是 0.85。她说 1 和 3 看不出区别。
//     原因：为了让颜色不偏到一边，我把三片"涌"排成了重心不动的样子——三片叠起来几乎是一片匀的，
//     等于把流动自己抵消掉了。颜色又淡，这点变化眼睛根本看不见。
//   第四版（现在）：2.0，3 倍是 5.5；滑杆调到 0.2 就是第三版的样子。
//     做法：底下留一片几乎不动的底色；上面三个"浪"各走各的，从底边升起来、横着滑过去，
//     所以颜色真的会从左边挪到右边；再加两道柔的白光斜着穿过去。平均的浓淡和原来差不多。
// 结论：流动就是"此刻左边多一点、过几秒右边多一点"。要它看得见，就不能同时要求它每一刻都左右一样。

/// 金色的浓淡。0.8：她在真机上说"最多能接受 1"，定在 1 以下留一点余量。
/// （11-21 用滑杆试过 0.4–1.8。颜色这一层已经定稿，滑杆收起来了。）
enum LightStrength {
    static let designValue = 0.8
}

/// 流动的快慢：1 是设计值，2 是快一倍，0.2 几乎不动。
/// 动效是最后一步才定的事（见 claude/here-design-process.md），到那时再比较；现在先固定在 1。
enum LightFlow {
    static let designValue = 1.0
}

struct LiquidLightBackground: View {
    /// 文字所在的位置（占屏高的比例）。这里始终留一片白，光不会压到字。
    var focusY: CGFloat = 0.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let gold = LightStrength.designValue
        let speed = LightFlow.designValue

        ZStack {
            Theme.paper

            if reduceMotion {
                // 系统开了"减弱动态效果"：停在第一帧
                Canvas { context, size in
                    LiquidLight.draw(in: &context, size: size, time: 0, focusY: focusY, strength: gold)
                }
            } else {
                // 30fps 足够：设计速度下最快的一片每秒挪 50pt 左右，而且没有任何清晰的边
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    let time = LiquidLight.clock(timeline.date, speed: speed)
                    Canvas { context, size in
                        LiquidLight.draw(in: &context, size: size, time: time, focusY: focusY, strength: gold)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 纸与光（不动的页面用）
/// 暖白的纸，顶部一片白光。发帖、聊天、聊天列表、个人页用这个。
struct PaperBackground: View {
    var body: some View {
        ZStack {
            Theme.paper
            GeometryReader { geo in
                EllipticalGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: Color.white.opacity(0), location: 0.72)
                    ],
                    center: .top,
                    startRadiusFraction: 0,
                    endRadiusFraction: 0.5
                )
                // 椭圆的横向半径是屏宽的 130%，纵向是屏高的 55%（半径 = 这个框的一半）
                .frame(width: geo.size.width * 2.6, height: geo.size.height * 1.1)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.55)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 光的画法
enum LiquidLight {
    // 光自己的钟。从 0 开始走，所以每次打开 app 的第一帧都是同一幅画面。
    // 它按"流动"的倍数走：调快慢的时候画面不会跳，只是从这一刻起走得快一点或慢一点。
    // app 退到后台再回来，光从停下的地方接着走，不会一下子跳到别处。
    // 只在主线程上用（TimelineView 的内容是在主线程上算的）。
    private static var lastTick: Date?
    private static var elapsed: Double = 0

    /// 这一帧该画的时刻。同一帧里被几个实例各叫一次也没关系：钟只往前走一次。
    static func clock(_ date: Date, speed: Double) -> Double {
        if let last = lastTick {
            let step = date.timeIntervalSince(last)
            if step > 0 {
                elapsed += min(step, 0.5) * speed
                lastTick = date
            }
        } else {
            lastTick = date
        }
        return elapsed
    }

    private struct Piece {
        let gold: Bool          // 淡金色；false = 白色的光
        let cx: CGFloat         // 中心：占屏宽的比例
        let cy: CGFloat         // 中心：占屏高的比例
        let rx: CGFloat         // 横向半径：占屏宽的比例
        let ry: CGFloat         // 纵向半径：占屏高的比例
        let peak: Double        // 中心的不透明度
        let dx: CGFloat         // 左右各摆多远：占屏宽的比例
        let dy: CGFloat         // 上下各摆多远：占屏高的比例
        let tx: Double          // 左右摆一次要几秒
        let ty: Double          // 上下摆一次要几秒
        let tm: Double          // 形状和亮度变一次要几秒
        let px: Double          // 三个节奏各自的起步时间（秒），决定第一帧的样子
        let py: Double
        let pm: Double
        let tilt: Double        // 向两边各倾斜多少度
        let stretchA: CGSize    // 形状节奏两端的拉伸
        let stretchB: CGSize
        let dimA: Double        // 形状节奏两端的亮度
        let dimB: Double
    }

    // 底边一片光。
    //
    // 第 1 片（底色）：很宽的淡金色贴着底边，向上慢慢淡到屏幕中间偏下。几乎不动，只是很慢地呼吸。
    //          有它在，颜色不会在某一刻整个消失。
    // 第 2–4 片（三个浪）：中心都在屏幕底边以下，所以看到的只是它们升上来的那一截。
    //          各自横着来回滑（10、14、8.5 秒一趟，互不成倍数），同时一起一伏。
    //          流动主要是它们：颜色的"鼓包"在底边上慢慢挪。
    // 第 5–6 片（两道白光）：又宽又扁，略微倾斜，从暖色里穿过去，经过的地方亮一下。
    //
    // 屏幕上面大半什么颜色都没有。
    private static let pieces: [Piece] = [
        Piece(gold: true, cx: 0.50, cy: 1.12, rx: 1.10, ry: 0.50, peak: 0.58, dx: 0.02, dy: 0.02,
              tx: 31, ty: 21, tm: 17, px: 9, py: 5, pm: 3, tilt: 2,
              stretchA: CGSize(width: 1.00, height: 1.00), stretchB: CGSize(width: 1.04, height: 0.94),
              dimA: 1.0, dimB: 0.9),

        Piece(gold: true, cx: 0.50, cy: 1.03, rx: 0.40, ry: 0.30, peak: 0.44, dx: 0.42, dy: 0.05,
              tx: 10, ty: 7, tm: 9, px: 3, py: 2, pm: 0, tilt: 6,
              stretchA: CGSize(width: 0.90, height: 1.12), stretchB: CGSize(width: 1.15, height: 0.86),
              dimA: 0.7, dimB: 1.0),
        Piece(gold: true, cx: 0.50, cy: 1.05, rx: 0.34, ry: 0.26, peak: 0.38, dx: 0.40, dy: 0.04,
              tx: 14, ty: 9, tm: 11, px: 19, py: 7, pm: 6, tilt: 6,
              stretchA: CGSize(width: 1.15, height: 0.88), stretchB: CGSize(width: 0.92, height: 1.08),
              dimA: 0.7, dimB: 1.0),
        Piece(gold: true, cx: 0.50, cy: 1.06, rx: 0.30, ry: 0.22, peak: 0.32, dx: 0.44, dy: 0.035,
              tx: 8.5, ty: 6, tm: 7, px: 2.5, py: 4, pm: 2, tilt: 5,
              stretchA: CGSize(width: 1.00, height: 1.00), stretchB: CGSize(width: 1.20, height: 0.90),
              dimA: 0.7, dimB: 1.0),

        Piece(gold: false, cx: 0.50, cy: 0.90, rx: 0.55, ry: 0.07, peak: 0.30, dx: 0.50, dy: 0.035,
              tx: 9, ty: 7, tm: 5, px: 2, py: 1, pm: 0, tilt: 8,
              stretchA: CGSize(width: 1.00, height: 1.00), stretchB: CGSize(width: 1.25, height: 0.85),
              dimA: 0.6, dimB: 1.0),
        Piece(gold: false, cx: 0.50, cy: 0.80, rx: 0.45, ry: 0.06, peak: 0.24, dx: 0.50, dy: 0.03,
              tx: 12, ty: 8, tm: 7, px: 16, py: 5, pm: 3, tilt: 10,
              stretchA: CGSize(width: 1.20, height: 0.90), stretchB: CGSize(width: 1.00, height: 1.10),
              dimA: 1.0, dimB: 0.5)
    ]

    /// 从中心到边缘缓入缓出地淡出（smoothstep），这样一片光没有看得见的边。
    private static func falloff(_ color: Color, peak: Double) -> Gradient {
        var stops: [Gradient.Stop] = []
        for i in 0...10 {
            let p = Double(i) / 10
            let strength = 1 - (3 * p * p - 2 * p * p * p)
            stops.append(Gradient.Stop(color: color.opacity(peak * strength), location: CGFloat(p)))
        }
        return Gradient(stops: stops)
    }

    /// `strength`：金色的浓淡，1 是设计值，0 是没有金色。只影响金色，不影响白光。
    static func draw(
        in context: inout GraphicsContext,
        size: CGSize,
        time: Double,
        focusY: CGFloat,
        strength: Double
    ) {
        guard size.width > 0, size.height > 0 else { return }
        let w = size.width
        let h = size.height
        // 单位圆；每一片光都是把它平移、旋转、拉成椭圆后画出来的
        let unit = Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2))

        for piece in pieces {
            // 左右、上下：各自一条余弦，来回摆
            let swingX = cos(Double.pi * (time + piece.px) / piece.tx)
            let swingY = cos(Double.pi * (time + piece.py) / piece.ty)
            let x = piece.cx * w - piece.dx * w * CGFloat(swingX)
            let y = piece.cy * h - piece.dy * h * CGFloat(swingY)

            // 形状和亮度：0…1 之间来回
            let m = (1 - cos(Double.pi * (time + piece.pm) / piece.tm)) / 2
            let tilt = piece.tilt * (2 * m - 1)
            let stretchX = piece.stretchA.width + (piece.stretchB.width - piece.stretchA.width) * CGFloat(m)
            let stretchY = piece.stretchA.height + (piece.stretchB.height - piece.stretchA.height) * CGFloat(m)
            let dim = piece.dimA + (piece.dimB - piece.dimA) * m

            let peak: Double = piece.gold ? min(1, piece.peak * strength) : piece.peak
            if peak <= 0 { continue }

            var layer = context
            layer.translateBy(x: x, y: y)
            layer.rotate(by: Angle.degrees(tilt))
            layer.scaleBy(x: piece.rx * w * stretchX, y: piece.ry * h * stretchY)
            layer.opacity = dim
            let color: Color = piece.gold ? Theme.champagne : Color.white
            layer.fill(
                unit,
                with: .radialGradient(falloff(color, peak: peak), center: .zero, startRadius: 0, endRadius: 1)
            )
        }

        // 文字处的白：不动
        var calm = context
        calm.translateBy(x: w / 2, y: h * focusY)
        calm.scaleBy(x: 0.78 * w, y: 0.42 * h)
        calm.fill(
            unit,
            with: .radialGradient(falloff(Color.white, peak: 0.9), center: .zero, startRadius: 0, endRadius: 1)
        )
    }
}
