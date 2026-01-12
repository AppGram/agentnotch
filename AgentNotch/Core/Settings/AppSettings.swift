import Foundation
import SwiftUI

@MainActor
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    @AppStorage("mcpBinaryPath") public var mcpBinaryPath: String = "/usr/local/bin/bridge4simulator-xcauto"
    @AppStorage("mcpHttpPort") public var mcpHttpPort: Int = 8765
    @AppStorage("mcpUseHTTP") public var mcpUseHTTP: Bool = true
    @AppStorage("autoStartMCP") public var autoStartMCP: Bool = true
    @AppStorage("autoRestartOnCrash") public var autoRestartOnCrash: Bool = true
    @AppStorage("maxRestartAttempts") public var maxRestartAttempts: Int = 5
    @AppStorage("showBuildNotifications") public var showBuildNotifications: Bool = true
    @AppStorage("recentToolCallsLimit") public var recentToolCallsLimit: Int = 10
    @AppStorage("forceNotchMode") public var forceNotchMode: Bool = true  // Force notch UI for testing
    @AppStorage("telemetryOtlpPort") public var telemetryOtlpPort: Int = 4318
    @AppStorage("telemetryAutoStart") public var telemetryAutoStart: Bool = true
    @AppStorage("showMenuBarItem") public var showMenuBarItem: Bool = false
    @AppStorage("showNotchTokenCount") public var showNotchTokenCount: Bool = true
    @AppStorage("showNotchTokenBreakdown") public var showNotchTokenBreakdown: Bool = true
    @AppStorage("showNotchCost") public var showNotchCost: Bool = true
    @AppStorage("showMemeVideo") public var showMemeVideo: Bool = false
    @AppStorage("memeGraceSeconds") public var memeGraceSeconds: Int = 30
    @AppStorage("memeVideoURL") public var memeVideoURL: String = "https://redirector.googlevideo.com/videoplayback?expire=1767662856&ei=qBBcaYLtCYfgkucP_IGzqAo&ip=2601%3A147%3Ac280%3A2560%3A1000%3A7015%3Aa0fb%3Ad52&id=o-AAq-x9phMxCBKChFBVwPrAso8jm3QBVyMdaKABvrZ8pL&itag=18&source=youtube&requiressl=yes&xpc=EgVo2aDSNQ%3D%3D&met=1767641256%2C&mh=wn&mm=31%2C29&mn=sn-bvvbaxivnuxqjvhj5nu-p5qs%2Csn-p5qlsnrr&ms=au%2Crdu&mv=m&mvi=7&pl=34&rms=au%2Cau&initcwndbps=4082500&bui=AYUSA3BHZSEijFaP0Tk-u6BkffHfKn-3pPyBowcl5-f4MxDK2EIqCPJCfS_ttPNOzOB8TrJd2hiqK1Pm&spc=wH4Qq4xydJfon-mJOufeHUhdgGa9oJ00w8WY8ly4jfSRQI5c4Pm2Eit0rx5F2Uhjqcm_Ew&vprv=1&svpuc=1&mime=video%2Fmp4&ns=U8oR9ExcbREfgkjShqUohp8R&rqh=1&cnr=14&ratebypass=yes&dur=193.097&lmt=1754699202410235&mt=1767640653&fvip=3&fexp=51552689%2C51565116%2C51565682%2C51580968&c=WEB_EMBEDDED_PLAYER&sefc=1&txp=6308224&n=Kvyo8qR7M2oAyg&sparams=expire%2Cei%2Cip%2Cid%2Citag%2Csource%2Crequiressl%2Cxpc%2Cbui%2Cspc%2Cvprv%2Csvpuc%2Cmime%2Cns%2Crqh%2Ccnr%2Cratebypass%2Cdur%2Clmt&sig=AJfQdSswRQIhALTTylNrbL1dTFXSpvXrk3a4ObUc-R_Vu-98EsIDfxAbAiBpvBZJ4K9Z2Bk6hFnDhiCSfwP7rq-6qcGR4V9LLHEvDQ%3D%3D&lsparams=met%2Cmh%2Cmm%2Cmn%2Cms%2Cmv%2Cmvi%2Cpl%2Crms%2Cinitcwndbps&lsig=APaTxxMwRQIgUIiqcY9nQ3LdggxnB3YsC-CVhp1fJXI0qij9vEFvmoMCIQDBqWJ5Dj9gcnVD403yXyBA2wjRzMPbGVkqmCw73DFGvw%3D%3D"
    @AppStorage("showSourceCodex") public var showSourceCodex: Bool = true
    @AppStorage("showSourceClaudeCode") public var showSourceClaudeCode: Bool = true
    @AppStorage("showSourceUnknown") public var showSourceUnknown: Bool = false

    // Battery saver: 15 FPS on battery, 25 FPS when charging
    @AppStorage("batterySaverEnabled") public var batterySaverEnabled: Bool = true

    // Claude Code JSONL Session Tracking
    @AppStorage("enableClaudeCodeJSONL") public var enableClaudeCodeJSONL: Bool = true
    @AppStorage("showSessionDots") public var showSessionDots: Bool = true
    @AppStorage("showPermissionIndicator") public var showPermissionIndicator: Bool = true
    @AppStorage("showTodoList") public var showTodoList: Bool = true
    @AppStorage("showThinkingState") public var showThinkingState: Bool = true

    // Codex JSONL Session Tracking
    @AppStorage("enableCodexJSONL") public var enableCodexJSONL: Bool = true

    // Context and Display Settings
    @AppStorage("contextTokenLimit") public var contextTokenLimit: Int = 200_000
    @AppStorage("showContextProgress") public var showContextProgress: Bool = true
    /// Display mode: "list" for recent events list, "singular" for single detailed event
    @AppStorage("toolDisplayMode") public var toolDisplayMode: String = "list"

    // Claude Usage Quota Tracking
    @AppStorage("enableClaudeUsage") public var enableClaudeUsage: Bool = false
    @AppStorage("claudeUsageRefreshMode") public var claudeUsageRefreshMode: String = "smart"  // "smart" or "fixed"
    @AppStorage("claudeUsageRefreshInterval") public var claudeUsageRefreshInterval: Int = 180  // seconds
    @AppStorage("showClaudeUsageInClosedNotch") public var showClaudeUsageInClosedNotch: Bool = true

    public var mcpConfiguration: MCPConfiguration {
        MCPConfiguration(
            binaryPath: mcpBinaryPath,
            httpPort: mcpHttpPort,
            transport: mcpUseHTTP ? .http : .stdio
        )
    }

    public init() {}
}
