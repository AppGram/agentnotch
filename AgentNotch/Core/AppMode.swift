import Foundation

public enum AppMode {
    case agentNotch
}

public enum AppModeConfig {
    public static var current: AppMode = .agentNotch
}

public protocol SettingsWindowProvider {
    func showSettingsWindow()
}
