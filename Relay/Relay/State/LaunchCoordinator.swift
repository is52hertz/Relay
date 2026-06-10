//
//  LaunchCoordinator.swift
//  Relay
//
//  启动来源协调器：在 AppDelegate（非 SwiftUI 环境）与 SwiftUI 的 openWindow 之间架桥。
//  由 AppDelegate 持有并注入（非单例），常驻视图监听其标志位以程序化开窗。
//

import Foundation
import Observation

@MainActor
@Observable
final class LaunchCoordinator {
    /// 置 true 表示「应当打开主窗口」（显式启动 / reopen）；视图开窗后回置 false。
    var shouldShowMainWindow = false
}
