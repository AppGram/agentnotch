// NotchViewModel.swift
// View model for notch state and animations

import SwiftUI
import Combine

enum NotchState {
    case closed
    case open
    case peeking
}

@MainActor
final class NotchViewModel: ObservableObject {
    @Published private(set) var notchState: NotchState = .closed
    @Published var notchSize: CGSize
    @Published var closedNotchSize: CGSize

    private let animationSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)
    private var peekTask: Task<Void, Never>?

    init() {
        let size = getClosedNotchSize()
        self.notchSize = size
        self.closedNotchSize = size
    }

    func open() {
        peekTask?.cancel()
        notchState = .open
        withAnimation(animationSpring) {
            notchSize = openNotchSize
        }
    }

    func close() {
        peekTask?.cancel()
        withAnimation(animationSpring) {
            notchSize = closedNotchSize
            notchState = .closed
        }
    }

    func toggle() {
        if notchState == .open {
            close()
        } else {
            open()
        }
    }

    /// Briefly expand the notch to show a notification, then return to closed state
    func peek(duration: TimeInterval = 2.0) {
        guard notchState == .closed else { return }

        peekTask?.cancel()
        notchState = .peeking

        // Expand to a smaller "peek" size
        let peekSize = CGSize(
            width: closedNotchSize.width + 200,
            height: closedNotchSize.height + 60
        )

        withAnimation(animationSpring) {
            notchSize = peekSize
        }

        peekTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(animationSpring) {
                    notchSize = closedNotchSize
                    notchState = .closed
                }
            }
        }
    }
}
