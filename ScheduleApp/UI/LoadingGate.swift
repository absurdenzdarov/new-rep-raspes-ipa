import SwiftUI

/// Орбитальный загрузчик: планета, орбиты и спутники.
struct OrbitLoader: View {
    var failed: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let cx = size.width / 2
                let cy = size.height / 2
                let base = Double(min(size.width, size.height)) / 2
                let hot: Color = failed ? Color(hex: 0xFF8A5C) : Theme.cyan
                let cool: Color = failed ? Color(hex: 0xFF5C7A) : Theme.accent

                // Свечение за планетой
                let pulse = 0.85 + 0.15 * sin(t * 2.0)
                let glowR = base * 0.62 * pulse
                let glowRect = CGRect(x: cx - glowR, y: cy - glowR, width: glowR * 2, height: glowR * 2)
                gc.fill(Path(ellipseIn: glowRect),
                        with: .radialGradient(Gradient(colors: [cool.opacity(0.55), cool.opacity(0.0)]),
                                              center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: glowR))

                // Орбиты и спутники
                let orbits: [(Double, Double, Double, Double, Double)] = [
                    (0.92, 0.34, 0.5, 1.1, 0.0),
                    (0.78, 0.30, -0.9, -0.8, 2.0),
                    (0.62, 0.24, 2.0, 1.6, 4.0)
                ]
                for (i, o) in orbits.enumerated() {
                    let rx = base * o.0
                    let ry = base * o.1
                    let tilt = o.2 + t * 0.12 * (i % 2 == 0 ? 1 : -1)
                    var c = gc
                    c.translateBy(x: cx, y: cy)
                    c.rotate(by: .radians(tilt))
                    let ell = Path(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
                    c.stroke(ell, with: .color(Color.white.opacity(0.16)), lineWidth: 1)

                    let speed = failed ? 0.35 : o.3
                    let theta = t * speed + o.4
                    let sx = rx * cos(theta)
                    let sy = ry * sin(theta)
                    let sr = 4.5 + Double(i)
                    let halo = CGRect(x: sx - sr * 2.6, y: sy - sr * 2.6, width: sr * 5.2, height: sr * 5.2)
                    c.fill(Path(ellipseIn: halo), with: .color(hot.opacity(0.28)))
                    let dot = CGRect(x: sx - sr, y: sy - sr, width: sr * 2, height: sr * 2)
                    c.fill(Path(ellipseIn: dot), with: .color(i == 1 ? Color.white : hot))
                }

                // Планета
                let pr = base * 0.34
                let planet = CGRect(x: cx - pr, y: cy - pr, width: pr * 2, height: pr * 2)
                gc.fill(Path(ellipseIn: planet),
                        with: .radialGradient(
                            Gradient(colors: [Color.white.opacity(0.95), hot, cool, Color(hex: 0x050B2A)]),
                            center: CGPoint(x: cx - pr * 0.35, y: cy - pr * 0.4),
                            startRadius: 1, endRadius: pr * 1.5))
                gc.stroke(Path(ellipseIn: planet), with: .color(Color.white.opacity(0.35)), lineWidth: 1)
            }
        }
    }
}

struct LoadingGate: View {
    @EnvironmentObject private var store: ScheduleStore

    private var failedMessage: String? {
        if case .failed(let m) = store.gate { return m }
        return nil
    }

    private var stepIndex: Int {
        let f = store.progress.fraction
        if f < 0.1 { return 0 }
        if f < 0.9 { return 1 }
        return 2
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 26) {
                Spacer()

                OrbitLoader(failed: failedMessage != nil)
                    .frame(width: 260, height: 260)

                VStack(spacing: 8) {
                    Text(failedMessage == nil ? "Обновляем расписание" : "Не получилось обновить")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.titleGradient)
                        .multilineTextAlignment(.center)

                    Text(failedMessage ?? store.progress.message)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                        .id(failedMessage ?? store.progress.message)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                .animation(.smooth(duration: 0.35), value: store.progress.message)

                if failedMessage == nil {
                    progressArea
                } else {
                    failureButtons
                }

                Spacer()

                Text("Данные берутся с Яндекс.Диска колледжа")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .padding(.bottom, 24)
            }
        }
    }

    private var progressArea: some View {
        VStack(spacing: 16) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(Theme.gradient)
                        .frame(width: max(14, geo.size.width * CGFloat(min(max(store.progress.fraction, 0), 1))))
                        .shadow(color: Theme.cyan.opacity(0.7), radius: 8)
                }
                .animation(.smooth(duration: 0.5), value: store.progress.fraction)
            }
            .frame(height: 10)
            .padding(.horizontal, 48)

            Text("\(Int((store.progress.fraction * 100).rounded()))%")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.85))
                .contentTransition(.numericText())
                .animation(.smooth, value: store.progress.fraction)

            GlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    stepChip("Поиск", index: 0, icon: "magnifyingglass")
                    stepChip("Загрузка", index: 1, icon: "arrow.down.circle")
                    stepChip("Разбор", index: 2, icon: "sparkles")
                }
            }
        }
    }

    private func stepChip(_ title: String, index: Int, icon: String) -> some View {
        let active = stepIndex >= index
        return HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(active ? Color.white : Color.white.opacity(0.4))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glass(Capsule(), tint: active ? Theme.accent : nil)
        .animation(.smooth(duration: 0.4), value: stepIndex)
    }

    private var failureButtons: some View {
        VStack(spacing: 12) {
            Button("Повторить") {
                Haptics.tap()
                Task { await store.refresh(force: true) }
            }
            .buttonStyle(GlassPrimaryButtonStyle())

            if !store.lessons.isEmpty {
                Button("Открыть сохранённое расписание") {
                    Haptics.tap()
                    store.dismissGate()
                }
                .buttonStyle(GlassSecondaryButtonStyle())
            }
        }
    }
}
