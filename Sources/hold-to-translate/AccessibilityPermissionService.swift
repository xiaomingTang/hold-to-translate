import AppKit
import ApplicationServices

private let axTrustedCheckOptionPromptKey = "AXTrustedCheckOptionPrompt"

enum AccessibilityStatus: String {
  case granted
  case denied

  var displayName: String {
    switch self {
    case .granted:
      return "已授权"
    case .denied:
      return "未授权"
    }
  }
}

final class AccessibilityPermissionService {
  func currentStatus() -> AccessibilityStatus {
    AXIsProcessTrusted() ? .granted : .denied
  }

  @discardableResult
  func requestAccess(prompt: Bool) -> Bool {
    if !prompt {
      return AXIsProcessTrusted()
    }
    let options = [axTrustedCheckOptionPromptKey: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  func openSystemSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    else {
      return
    }
    NSWorkspace.shared.open(url)
  }
}
