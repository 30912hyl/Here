import SwiftUI

// MARK: - 毛玻璃背景
// 几团很大、很淡的暖色光在底下缓慢漂移,上面盖一层磨砂颗粒——像隔着磨砂玻璃看到的暖光。
// 光团必须足够大、对比足够低:小而清晰的金色光斑在浅底上会读成污渍。
struct FrostedBackgroundView: View {
    struct Blob {
        let color: Color
        let radius: CGFloat        // fraction of screen width
        let base: CGPoint          // fraction of the sky area
        let drift: CGSize          // fraction of the sky area
        let period: Double         // seconds per loop
        let phase: Double
    }

    var blobs: [Blob]
    var grainOpacity: Double = 0.05

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 20)) { timeline in
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let sky = CGSize(width: size.width, height: size.height * 0.55)
                    for b in blobs {
                        let a = 2 * .pi * (t / b.period + b.phase)
                        // Lissajous drift: never quite repeats the same path
                        let c = CGPoint(x: (b.base.x + b.drift.width * sin(a)) * sky.width,
                                        y: (b.base.y + b.drift.height * sin(a * 0.73 + 1.1)) * sky.height)
                        let r = b.radius * size.width
                        context.fill(
                            Circle().path(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                            with: .radialGradient(Gradient(colors: [b.color, b.color.opacity(0)]),
                                                  center: c, startRadius: 0, endRadius: r))
                    }
                }
            }
            // Frosted grain
            Image(uiImage: FrostedBackgroundView.grain)
                .resizable(resizingMode: .tile)
                .opacity(grainOpacity)
                .blendMode(.multiply)
        }
        // Everything fades out by mid-screen: the reading area stays pure white
        // (grain over white reads as grey)
        .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                     .init(color: .black, location: 0.22),
                                     .init(color: .clear, location: 0.58)],
                             startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
    }

    /// 128×128 mono noise tile, generated once
    static let grain: UIImage = {
        let side = 128
        var pixels = [UInt8](repeating: 0, count: side * side)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for i in 0..<pixels.count {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            pixels[i] = UInt8(truncatingIfNeeded: seed >> 56)
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let cg = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side,
                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                         provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return UIImage(cgImage: cg, scale: 2, orientation: .up)
    }()
}
