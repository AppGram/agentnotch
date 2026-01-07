import SwiftUI

struct NotchGlowBorder: View {
    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat
    let glowColor: Color
    let brightColor: Color

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var powerMonitor = PowerStateMonitor.shared

    // Battery saver: 15 FPS on battery, 25 FPS when charging or disabled
    private var frameInterval: Double {
        if settings.batterySaverEnabled && !powerMonitor.isCharging {
            return 1.0 / 15.0  // 15 FPS on battery
        }
        return 1.0 / 25.0  // 25 FPS when charging or battery saver off
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let rotation = (time.truncatingRemainder(dividingBy: 2.0)) / 2.0 * 360

            NotchShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius
            )
            .stroke(
                AngularGradient(
                    stops: [
                        .init(color: Color.clear, location: 0.0),
                        .init(color: glowColor.opacity(0.3), location: 0.1),
                        .init(color: glowColor, location: 0.2),
                        .init(color: brightColor, location: 0.3),
                        .init(color: glowColor, location: 0.4),
                        .init(color: glowColor.opacity(0.3), location: 0.5),
                        .init(color: Color.clear, location: 0.6),
                        .init(color: Color.clear, location: 1.0),
                    ],
                    center: .center,
                    startAngle: .degrees(rotation),
                    endAngle: .degrees(rotation + 360)
                ),
                lineWidth: 2.5
            )
            .shadow(color: glowColor.opacity(0.7), radius: 8)
            .shadow(color: glowColor.opacity(0.4), radius: 16)
            .shadow(color: glowColor.opacity(0.2), radius: 24)
            .mask(
                VStack(spacing: 0) {
                    Color.clear.frame(height: 4)
                    Color.white
                }
            )
        }
        .allowsHitTesting(false)
    }
}
