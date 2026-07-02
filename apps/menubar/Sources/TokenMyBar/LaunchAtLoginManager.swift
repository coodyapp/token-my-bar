#if os(macOS)
import Foundation
import ServiceManagement
import TokenMyBarCore

/// Thin wrapper over `SMAppService.mainApp` for launch-at-login control.
///
/// All calls are defensive: status checks and register/unregister are wrapped
/// so a sandbox/permission failure never crashes the app.
struct LaunchAtLoginManager {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            Log.app.error("launch-at-login update failed: \(error.localizedDescription)")
        }
    }
}
#endif
