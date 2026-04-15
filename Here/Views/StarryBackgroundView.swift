import SwiftUI

// MARK: - 清爽金色渐变背景的纯白星空
struct StarryBackgroundView: View {
    @State private var stars: [Star] = []

    // 改这里切换配色：.rose / .champagne / .lemon / .cool
    let style: GoldStyle = .champagne

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(stars) { star in
                    StarView(star: star)
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

    private func generateStars(in size: CGSize) {
        let starCount = 60
        var generatedStars: [Star] = []

        for i in 0..<starCount {
            let randomY = CGFloat.random(in: 0...(size.height * 0.5))
            let normalizedY = randomY / (size.height * 0.5)
            let densityFactor = pow(1.0 - normalizedY, 2.0)

            if Double.random(in: 0...1) < densityFactor {
                let star = Star(
                    id: i,
                    x: CGFloat.random(in: 0...size.width),
                    y: randomY,
                    size: CGFloat.random(in: 2.0...4.5),
                    color: .white,
                    duration: Double.random(in: 0.8...2.2),
                    delay: Double.random(in: 0...3)
                )
                generatedStars.append(star)
            }
        }

        self.stars = generatedStars
    }
}

// MARK: - 单个星星
struct StarView: View {
    let star: Star
    @State private var isShining = false

    var body: some View {
        Circle()
            .fill(star.color)
            .frame(width: star.size, height: star.size)
            .shadow(color: .white.opacity(isShining ? 0.9 : 0.3), radius: isShining ? 6 : 2)
            .opacity(isShining ? 1.0 : 0.4)
            .scaleEffect(isShining ? 1.0 : 0.7)
            .position(x: star.x, y: star.y)
            .onAppear {
                withAnimation(
                    Animation
                        .easeInOut(duration: star.duration)
                        .repeatForever(autoreverses: true)
                        .delay(star.delay)
                ) {
                    isShining = true
                }
            }
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
    let id: Int
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let color: Color
    let duration: Double
    let delay: Double
}
