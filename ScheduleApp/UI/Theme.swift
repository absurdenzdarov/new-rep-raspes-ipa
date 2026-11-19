import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

enum Theme {
    static let accent = Color(hex: 0x3D7BFF)
    static let cyan = Color(hex: 0x35D6FF)
    static let violet = Color(hex: 0x7A5CFF)
    static let deepSpace = Color(hex: 0x010208)

    static let gradient = LinearGradient(
        colors: [Color(hex: 0x3D7BFF), Color(hex: 0x35D6FF)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let titleGradient = LinearGradient(
        colors: [Color.white, Color(hex: 0xA9D4FF)],
        startPoint: .leading, endPoint: .trailing)

    static let glassEdge = LinearGradient(
        colors: [Color.white.opacity(0.65), Color.white.opacity(0.10),
                 Color(hex: 0x35D6FF).opacity(0.06), Color(hex: 0x35D6FF).opacity(0.40)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    private static let palettes: [(UInt32, UInt32)] = [
        (0x3D7BFF, 0x7FAEFF),
        (0x35D6FF, 0x8DF1FF),
        (0x7A5CFF, 0xB8A4FF),
        (0x2DE0C4, 0x86F7E3),
        (0x5B8CFF, 0xAAC4FF),
        (0x9B6BFF, 0xD3B8FF),
        (0x00B7FF, 0x6CDBFF),
        (0x4D5BFF, 0x939BFF)
    ]

    static func subjectColors(_ subject: String) -> (Color, Color) {
        let p = palettes[Presenter.stableHash(subject) % palettes.count]
        return (Color(hex: p.0), Color(hex: p.1))
    }

    static func subjectGradient(_ subject: String) -> LinearGradient {
        let c = subjectColors(subject)
        return LinearGradient(colors: [c.0, c.1], startPoint: .top, endPoint: .bottom)
    }
}

enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Звёзды

struct SeededRNG {
    var state: UInt64

    mutating func next01() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
}

struct Star {
    let x: Double
    let y: Double
    let size: Double
    let phase: Double
    let speed: Double
    let drift: Double
    let bluish: Bool
}

enum StarField {
    static let stars: [Star] = {
        var g = SeededRNG(state: 20261114)
        var list: [Star] = []
        for _ in 0..<150 {
            let big = g.next01() > 0.9
            let s = Star(x: g.next01(),
                         y: g.next01(),
                         size: big ? 2.2 + g.next01() * 1.4 : 0.8 + g.next01() * 1.1,
                         phase: g.next01() * 6.28,
                         speed: 0.6 + g.next01() * 2.2,
                         drift: 0.0015 + g.next01() * 0.004,
                         bluish: g.next01() > 0.55)
            list.append(s)
        }
        return list
    }()
}

struct StarCanvas: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                for s in StarField.stars {
                    let tw = (sin(t * s.speed + s.phase) + 1) / 2
                    let alpha = 0.22 + 0.78 * tw
                    var y = (s.y + t * s.drift).truncatingRemainder(dividingBy: 1)
                    if y < 0 { y += 1 }
                    let px = s.x * Double(size.width)
                    let py = y * Double(size.height)
                    let color = s.bluish ? Color(hex: 0xBFE0FF) : Color.white
                    if s.size > 2.0 {
                        let gr = s.size * 4
                        let glow = CGRect(x: px - gr / 2, y: py - gr / 2, width: gr, height: gr)
                        gc.fill(Path(ellipseIn: glow), with: .color(Color(hex: 0x4F9DFF).opacity(alpha * 0.25)))
                    }
                    let rect = CGRect(x: px - s.size / 2, y: py - s.size / 2, width: s.size, height: s.size)
                    gc.fill(Path(ellipseIn: rect), with: .color(color.opacity(alpha)))
                }

                let period = 7.0
                let dur = 1.1
                let cycle = t.truncatingRemainder(dividingBy: period)
                if cycle < dur {
                    let idx = Int(t / period)
                    var rng = SeededRNG(state: UInt64(truncatingIfNeeded: idx &* 7919 &+ 13))
                    let sx = (0.15 + rng.next01() * 0.7) * Double(size.width)
                    let sy = (0.04 + rng.next01() * 0.3) * Double(size.height)
                    let p = cycle / dur
                    let angle = 0.55
                    let dist = 260.0
                    let hx = sx + p * dist * cos(angle)
                    let hy = sy + p * dist * sin(angle)
                    let len = 110.0
                    let tx = hx - len * cos(angle)
                    let ty = hy - len * sin(angle)
                    let fade = sin(p * Double.pi)
                    var path = Path()
                    path.move(to: CGPoint(x: tx, y: ty))
                    path.addLine(to: CGPoint(x: hx, y: hy))
                    gc.stroke(path,
                              with: .linearGradient(
                                Gradient(colors: [Color.white.opacity(0), Color(hex: 0xBFE6FF).opacity(fade)]),
                                startPoint: CGPoint(x: tx, y: ty),
                                endPoint: CGPoint(x: hx, y: hy)),
                              style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Фон: живая сетка-градиент + звёзды + горизонт планеты

private let meshColors: [Color] = [
    Color(hex: 0x010208), Color(hex: 0x04103A), Color(hex: 0x02030F),
    Color(hex: 0x061A5C), Color(hex: 0x1241C8), Color(hex: 0x3A24A8),
    Color(hex: 0x01030E), Color(hex: 0x05154A), Color(hex: 0x0A5BE0)
]

private func meshPoints(_ t: Double) -> [SIMD2<Float>] {
    func p(_ x: Double, _ y: Double, _ ax: Double, _ ay: Double, _ ph: Double) -> SIMD2<Float> {
        let px = x + ax * sin(t * 0.35 + ph)
        let py = y + ay * cos(t * 0.30 + ph)
        return SIMD2<Float>(Float(px), Float(py))
    }
    return [
        SIMD2<Float>(0, 0), p(0.5, 0, 0.10, 0, 0.5), SIMD2<Float>(1, 0),
        p(0, 0.5, 0, 0.10, 1.0), p(0.5, 0.5, 0.14, 0.14, 2.0), p(1, 0.5, 0, 0.10, 3.0),
        SIMD2<Float>(0, 1), p(0.5, 1, 0.10, 0, 4.0), SIMD2<Float>(1, 1)
    ]
}

struct AppBackground: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.deepSpace

                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    MeshGradient(width: 3, height: 3, points: meshPoints(t), colors: meshColors)
                }

                StarCanvas()

                Circle()
                    .fill(Theme.deepSpace)
                    .frame(width: 1000, height: 1000)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(colors: [Color(hex: 0x6CB6FF), Color(hex: 0x2F4BFF).opacity(0.0)],
                                               startPoint: .top, endPoint: .center),
                                lineWidth: 3)
                            .blur(radius: 1.5)
                    )
                    .shadow(color: Color(hex: 0x2F6BFF).opacity(0.65), radius: 46, y: -12)
                    .offset(y: geo.size.height * 0.4 + 500)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
    }
}

// MARK: - Liquid Glass

struct GlassFill<S: InsettableShape>: View {
    let shape: S
    var tint: Color? = nil

    var body: some View {
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(Color(hex: 0x1B3BFF).opacity(0.10))
            shape.fill(
                LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.02)],
                               startPoint: .topLeading, endPoint: .bottomTrailing))
            if let tint = tint {
                shape.fill(tint.opacity(0.30))
            }
        }
    }
}

#if compiler(>=6.2)
@available(iOS 26.0, *)
private func makeGlass(tint: Color?, interactive: Bool) -> Glass {
    var g: Glass = .regular
    if let t = tint { g = g.tint(t) }
    if interactive { g = g.interactive() }
    return g
}
#endif

extension View {
    /// Настоящее стекло Liquid Glass на iOS 26+ (когда проект собран новым Xcode),
    /// на остальных — похожее стекло, нарисованное вручную.
    @ViewBuilder
    func glass<S: InsettableShape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(makeGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            self.fallbackGlass(shape, tint: tint)
        }
        #else
        self.fallbackGlass(shape, tint: tint)
        #endif
    }

    func glass(radius: CGFloat = 22, tint: Color? = nil, interactive: Bool = false) -> some View {
        glass(RoundedRectangle(cornerRadius: radius, style: .continuous), tint: tint, interactive: interactive)
    }

    fileprivate func fallbackGlass<S: InsettableShape>(_ shape: S, tint: Color?) -> some View {
        self
            .background { GlassFill(shape: shape, tint: tint) }
            .overlay(shape.strokeBorder(Theme.glassEdge, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.35), radius: 14, y: 7)
    }

    @ViewBuilder
    func tabBarGlassBehavior() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// Контейнер, в котором стеклянные элементы красиво «перетекают» друг в друга (iOS 26+).
struct GlassGroup<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

struct GlassCard<Content: View>: View {
    private let content: Content
    private let radius: CGFloat

    init(radius: CGFloat = 24, @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.content = content()
    }

    var body: some View {
        content.glass(radius: radius)
    }
}

struct GlassIconButton: View {
    let systemName: String
    var tint: Color? = nil
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: size, height: size)
                .glass(Circle(), tint: tint, interactive: true)
        }
        .buttonStyle(.plain)
    }
}

struct SpinningBorder<S: InsettableShape>: View {
    let shape: S
    var lineWidth: CGFloat = 2
    @State private var angle: Double = 0

    var body: some View {
        shape
            .strokeBorder(
                AngularGradient(colors: [Theme.cyan, Theme.accent, Color.clear, Color.clear, Theme.cyan],
                                center: .center, angle: .degrees(angle)),
                lineWidth: lineWidth)
            .onAppear {
                withAnimation(.linear(duration: 3.5).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }
}

// MARK: - Прочее

struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(colors: [Color.clear, Color(hex: 0x9CCBFF).opacity(0.28), Color.clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width * 1.6)
                }
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}

struct SkeletonCard: View {
    var height: CGFloat = 96
    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .frame(height: height)
            .shimmer()
    }
}

struct GlassPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .glass(Capsule(), tint: Theme.accent, interactive: true)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct GlassSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
            .glass(Capsule(), interactive: true)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
