//
//  PermissionNeededIndicator.swift
//  AgentNotch
//
//  Pulsing indicator shown when Claude is waiting for user permission
//

import SwiftUI

/// Full-size pulsing indicator with exclamation mark
struct PermissionNeededIndicator: View {
    let toolName: String?
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Outer pulsing ring
            Circle()
                .stroke(Color.orange.opacity(0.5), lineWidth: 2)
                .frame(width: 16, height: 16)
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .opacity(isPulsing ? 0 : 0.8)

            // Inner solid circle
            Circle()
                .fill(Color.orange)
                .frame(width: 10, height: 10)

            // Exclamation mark
            Image(systemName: "exclamationmark")
                .font(.system(size: 6, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 20, height: 20)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

/// Compact pulsing dot for minimal views
struct PermissionNeededIndicatorCompact: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.orange)
            .frame(width: 8, height: 8)
            .scaleEffect(isPulsing ? 1.2 : 0.9)
            .opacity(isPulsing ? 1.0 : 0.6)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

/// Inline permission indicator with tool name
struct PermissionNeededBadge: View {
    let toolName: String?
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
                .scaleEffect(isPulsing ? 1.2 : 0.9)
                .opacity(isPulsing ? 1.0 : 0.6)

            if let tool = toolName {
                Text(tool)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.orange)
            }

            Text("needs permission")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.orange.opacity(0.8))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.15))
        .cornerRadius(6)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        PermissionNeededIndicator(toolName: "Bash")
        PermissionNeededIndicatorCompact()
        PermissionNeededBadge(toolName: "Bash")
    }
    .padding()
    .background(Color.black.opacity(0.8))
}
