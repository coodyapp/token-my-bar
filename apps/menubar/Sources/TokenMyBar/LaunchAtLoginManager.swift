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

    /// Returns whether the change took, so callers can tell the user instead
    /// of silently reverting the toggle.
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
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
            return true
        } catch {
            Log.app.error("launch-at-login update failed: \(error.localizedDescription)")
            return false
        }
    }
}
#endif
