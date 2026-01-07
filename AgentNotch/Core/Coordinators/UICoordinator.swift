import AppKit
import SwiftUI
import Combine

@MainActor
public final class UICoordinator: ObservableObject {
    public static let shared = UICoordinator()

    @Published var isExpanded: Bool = false
    @Published private(set) var hasNotch: Bool = false
    @Published private(set) var isVisible: Bool = true

    private var notchPanel: NotchPanel?
    private var menuBarController: MenuBarController?
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    public func setupUI() {
        // Check for notch or force mode
        hasNotch = NotchDetector.hasNotch() || AppSettings.shared.forceNotchMode

        if hasNotch {
            setupNotchPanel()
        }

        // Always setup menu bar as fallback/additional control
        setupMenuBar()
    }

    private func setupNotchPanel() {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.frame

        // Window is fixed size, positioned at top center
        let windowX = screenFrame.origin.x + (screenFrame.width - windowSize.width) / 2
        let windowY = screenFrame.origin.y + screenFrame.height - windowSize.height

        let frame = NSRect(
            x: windowX,
            y: windowY,
            width: windowSize.width,
            height: windowSize.height
        )

        let panel = NotchPanel(contentRect: frame)
        panel.setContent {
            if AppModeConfig.current == .agentNotch {
                AgentNotchContentView()
                    .environmentObject(TelemetryCoordinator.shared)
            } else {
                NotchContentView()
                    .environmentObject(MCPCoordinator.shared)
            }
        }

        // Add to the notch space for proper layering
        panel.addToNotchSpace()

        // Show the panel
        panel.orderFrontRegardless()

        notchPanel = panel
    }

    private func setupMenuBar() {
        menuBarController = MenuBarController()
        menuBarController?.setup()
    }

    public func show() {
        isVisible = true
        notchPanel?.orderFront(nil)
    }

    public func hide() {
        isVisible = false
        notchPanel?.orderOut(nil)
    }

    public func cleanup() {
        notchPanel?.removeFromNotchSpace()
        notchPanel?.close()
        notchPanel = nil
    }
}
