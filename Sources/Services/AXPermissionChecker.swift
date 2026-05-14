// AccessibilityPermissionChecker protocol 준수 — AXIsProcessTrustedWithOptions thin wrapper
import ApplicationServices

struct AXPermissionChecker: AccessibilityPermissionChecker {
    func isTrusted(promptUserIfNeeded: Bool) -> Bool {
        // "AXTrustedCheckOptionPrompt" = kAXTrustedCheckOptionPrompt raw value
        let options = ["AXTrustedCheckOptionPrompt": promptUserIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
