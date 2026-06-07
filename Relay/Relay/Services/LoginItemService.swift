//
//  LoginItemService.swift
//  Relay
//
//  登录启动：SMAppService.mainApp 注册/注销。把 OS 状态同步到我方设置（幂等）。
//  失败仅记录——无付费账号/未正式签名时可能受限，属已知限制，非关键路径。
//

import ServiceManagement
import Foundation

@MainActor
final class LoginItemService {
    func setEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
        } catch {
            NSLog("Relay: login item update failed: \(error.localizedDescription)")
        }
    }
}
