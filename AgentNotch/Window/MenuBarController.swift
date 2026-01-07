import AppKit
import SwiftUI
import Combine

@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var settingsCancellable: AnyCancellable?

    func setup() {
        updateMenuBarVisibility()
        settingsCancellable = AppSettings.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMenuBarVisibility()
            }

        // Update icon based on state
        if AppModeConfig.current == .agentNotch {
            TelemetryCoordinator.shared.$state
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    self?.updateIcon(for: state)
                }
                .store(in: &cancellables)
        } else {
            MCPCoordinator.shared.$state
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    self?.updateIcon(for: state)
                }
                .store(in: &cancellables)
        }
    }

    private func updateMenuBarVisibility() {
        if AppSettings.shared.showMenuBarItem {
            if statusItem == nil {
                setupStatusItemAndPopover()
                updateIconForCurrentState()
            }
        } else if let statusItem {
            closePopover()
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
            popover = nil
        }
    }

    private func setupStatusItemAndPopover() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            if AppModeConfig.current == .agentNotch {
                button.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "AgentNotch")
            } else {
                button.image = NSImage(systemSymbolName: "hammer.fill", accessibilityDescription: "AgentNotch")
            }
            button.action = #selector(togglePopover)
            button.target = self
        }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 400)
        popover.behavior = .transient
        popover.animates = true
        let rootView: AnyView = {
            if AppModeConfig.current == .agentNotch {
                return AnyView(
                    AgentMenuBarContentView()
                        .environmentObject(TelemetryCoordinator.shared)
                        .environmentObject(UICoordinator.shared)
                )
            }
            return AnyView(
                MenuBarContentView()
                    .environmentObject(MCPCoordinator.shared)
                    .environmentObject(UICoordinator.shared)
            )
        }()
        popover.contentViewController = NSHostingController(rootView: rootView)
        self.popover = popover

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func updateIconForCurrentState() {
        if AppModeConfig.current == .agentNotch {
            updateIcon(for: TelemetryCoordinator.shared.state)
        } else {
            updateIcon(for: MCPCoordinator.shared.state)
        }
    }

    private func updateIcon(for state: TelemetryState) {
        guard let button = statusItem?.button else { return }

        let symbolName: String
        let color: NSColor

        switch state {
        case .stopped:
            symbolName = "waveform.path.ecg"
            color = .secondaryLabelColor
        case .starting:
            symbolName = "waveform.path.ecg"
            color = .systemYellow
        case .running:
            symbolName = "waveform.path.ecg"
            color = .systemGreen
        case .error:
            symbolName = "waveform.path.ecg"
            color = .systemRed
        }

        var config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        config = config.applying(.init(paletteColors: [color]))
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "AgentNotch")?
            .withSymbolConfiguration(config)
    }

    private func updateIcon(for state: MCPServerState) {
        guard let button = statusItem?.button else { return }

        let symbolName: String
        let color: NSColor

        switch state {
        case .stopped:
            symbolName = "hammer"
            color = .secondaryLabelColor
        case .starting, .stopping:
            symbolName = "hammer.fill"
            color = .systemYellow
        case .running:
            symbolName = "hammer.fill"
            color = .systemGreen
        case .crashed, .error:
            symbolName = "hammer.fill"
            color = .systemRed
        }

        var config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        config = config.applying(.init(paletteColors: [color]))
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "AgentNotch")?
            .withSymbolConfiguration(config)
    }

    @objc private func togglePopover() {
        guard let popover = popover, let button = statusItem?.button else { return }

        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
