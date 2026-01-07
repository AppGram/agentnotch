import SwiftUI

struct BuildTimeView: View {
    let duration: TimeInterval
    let result: XcodeBuildResult?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Build Time")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    if let result = result {
                        if result.success {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.red)
                        }
                    }
                }

                Text(formattedDuration)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
            }

            Spacer()

            if let result = result {
                VStack(alignment: .trailing, spacing: 2) {
                    if let warnings = result.warnings, warnings > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.yellow)
                            Text("\(warnings)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }

                    if let errors = result.errors, errors > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.red)
                            Text("\(errors)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var formattedDuration: String {
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return String(format: "%dm %02ds", minutes, seconds)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        BuildTimeView(
            duration: 12.345,
            result: XcodeBuildResult(
                success: true,
                appPath: nil,
                bundleId: nil,
                configuration: "Debug",
                sdk: nil,
                durationMs: 12345,
                warnings: 2,
                errors: 0,
                errorOutput: nil
            )
        )

        BuildTimeView(
            duration: 0.5,
            result: nil
        )
    }
    .padding()
    .frame(width: 300)
}
