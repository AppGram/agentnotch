import Foundation
import IOKit.ps

@MainActor
public final class PowerStateMonitor: ObservableObject {
    public static let shared = PowerStateMonitor()

    @Published public private(set) var isCharging: Bool = false

    private var runLoopSource: CFRunLoopSource?

    public init() {
        updatePowerState()
        startMonitoring()
    }


    private func updatePowerState() {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array

        for source in sources {
            if let info = IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue() as? [String: Any] {
                if let powerSource = info[kIOPSPowerSourceStateKey] as? String {
                    isCharging = (powerSource == kIOPSACPowerValue)
                    return
                }
            }
        }
        // Default to charging (plugged in) if we can't determine - safer for desktop Macs
        isCharging = true
    }

    private func startMonitoring() {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        runLoopSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context = context else { return }
            let monitor = Unmanaged<PowerStateMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                monitor.updatePowerState()
            }
        }, context).takeRetainedValue()

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    private func stopMonitoring() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }
}
