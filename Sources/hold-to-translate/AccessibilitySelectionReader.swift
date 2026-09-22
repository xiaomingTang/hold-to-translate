import AppKit
import ApplicationServices

public enum SelectionReadResult {
  case success(String)
  case failure(String)
}

private struct ClipboardSnapshot {
  let items: [[(NSPasteboard.PasteboardType, Data)]]
  let changeCount: Int
  let plainText: String?
}

final class AccessibilitySelectionReader {
  func readSelectedText(includeClipboardFallback: Bool = true) -> SelectionReadResult {
    let systemWideElement = AXUIElementCreateSystemWide()
    guard var focusedAppElement = focusedApplicationElement(from: systemWideElement) else {
      return .failure("无法获取焦点应用，请确认目标应用仍在前台后重试")
    }

    var focusedPid: pid_t = 0
    AXUIElementGetPid(focusedAppElement, &focusedPid)
    if Int(focusedPid) == ProcessInfo.processInfo.processIdentifier {
      if let frontmost = NSWorkspace.shared.frontmostApplication {
        let frontmostPid = frontmost.processIdentifier
        if Int(frontmostPid) != ProcessInfo.processInfo.processIdentifier {
          focusedAppElement = AXUIElementCreateApplication(frontmostPid)
        } else if includeClipboardFallback, let text = readSelectedTextFromClipboardFallback() {
          return .success(text)
        } else {
          return .failure("当前焦点在本应用窗口，请先点回目标应用后再长按触发")
        }
      } else if includeClipboardFallback, let text = readSelectedTextFromClipboardFallback() {
        return .success(text)
      } else {
        return .failure("当前焦点在本应用窗口，请先点回目标应用后再长按触发")
      }
    }

    guard
      let focusedElement = focusedUIElement(from: focusedAppElement, fallback: systemWideElement)
    else {
      if let discovered = discoverTextElement(from: focusedAppElement, fallback: systemWideElement)
      {
        if let text = readSelectedTextAttribute(from: discovered) { return .success(text) }
        if let text = readSelectedTextFromRange(from: discovered) { return .success(text) }
      }
      if includeClipboardFallback, let text = readSelectedTextFromClipboardFallback() {
        return .success(text)
      }
      return .failure("无法获取焦点控件（目标应用可能未暴露可访问焦点，剪贴板兜底也未成功）")
    }

    if let text = readSelectedTextAttribute(from: focusedElement) { return .success(text) }
    if let text = readSelectedTextFromRange(from: focusedElement) { return .success(text) }
    if let discovered = discoverTextElement(
      from: focusedAppElement, fallback: systemWideElement, preferred: focusedElement)
    {
      if let text = readSelectedTextAttribute(from: discovered) { return .success(text) }
      if let text = readSelectedTextFromRange(from: discovered) { return .success(text) }
    }
    if includeClipboardFallback, let text = readSelectedTextFromClipboardFallback() {
      return .success(text)
    }

    let supported = supportedAttributeNames(of: focusedElement)
    if supported.isEmpty { return .failure("焦点控件未暴露可读选区（无可访问属性，剪贴板兜底也未成功）") }
    if includeClipboardFallback {
      return .failure("焦点控件未暴露可读选区（可用属性：\(supported.joined(separator: ", "))，剪贴板兜底也未成功）")
    }
    return .failure("焦点控件未暴露可读选区（可用属性：\(supported.joined(separator: ", "))）")
  }

  private func focusedUIElement(from app: AXUIElement, fallback: AXUIElement) -> AXUIElement? {
    var object: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(
      app, kAXFocusedUIElementAttribute as CFString, &object)
    if result == .success, let object {
      guard CFGetTypeID(object) == AXUIElementGetTypeID() else { return nil }
      return object as! AXUIElement
    }
    var fallbackObject: CFTypeRef?
    let fallbackResult = AXUIElementCopyAttributeValue(
      fallback, kAXFocusedUIElementAttribute as CFString, &fallbackObject)
    guard fallbackResult == .success, let fallbackObject,
      CFGetTypeID(fallbackObject) == AXUIElementGetTypeID()
    else { return nil }
    return fallbackObject as! AXUIElement
  }

  private func discoverTextElement(
    from app: AXUIElement, fallback: AXUIElement, preferred: AXUIElement? = nil
  ) -> AXUIElement? {
    if let preferred, let result = findTextElement(in: preferred) { return result }
    if let result = findTextElement(in: app) { return result }
    return findTextElement(in: fallback)
  }

  private func findTextElement(in root: AXUIElement) -> AXUIElement? {
    var stack = [root]
    while let current = stack.popLast() {
      if hasReadableSelection(on: current) { return current }
      if let children = childElements(of: current) { stack.append(contentsOf: children) }
    }
    return nil
  }

  private func childElements(of element: AXUIElement) -> [AXUIElement]? {
    var childrenRef: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(
      element, kAXChildrenAttribute as CFString, &childrenRef)
    guard result == .success, let childrenRef, CFGetTypeID(childrenRef) == CFArrayGetTypeID() else {
      return nil
    }
    let array = childrenRef as! CFArray
    var children: [AXUIElement] = []
    children.reserveCapacity(CFArrayGetCount(array))
    for index in 0..<CFArrayGetCount(array) {
      guard let rawValue = CFArrayGetValueAtIndex(array, index) else { continue }
      children.append(unsafeBitCast(rawValue, to: AXUIElement.self))
    }
    return children.isEmpty ? nil : children
  }

  private func hasReadableSelection(on element: AXUIElement) -> Bool {
    if readSelectedTextAttribute(from: element) != nil
      || readSelectedTextFromRange(from: element) != nil
    {
      return true
    }
    let supported = supportedAttributeNames(of: element)
    return supported.contains {
      $0 == kAXSelectedTextAttribute as String || $0 == kAXSelectedTextRangeAttribute as String
        || $0 == kAXValueAttribute as String
    }
  }

  private func supportedAttributeNames(of element: AXUIElement) -> [String] {
    var names: CFArray?
    let result = AXUIElementCopyAttributeNames(element, &names)
    guard result == .success, let names else { return [] }
    let allNames = (names as [AnyObject]).compactMap { $0 as? String }
    let attrs = allNames.filter {
      $0 == kAXSelectedTextAttribute as String || $0 == kAXSelectedTextRangeAttribute as String
        || $0 == kAXValueAttribute as String
    }
    return attrs.isEmpty ? Array(allNames.prefix(6)) : attrs
  }

  private func focusedApplicationElement(from systemWide: AXUIElement) -> AXUIElement? {
    var object: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(
      systemWide, kAXFocusedApplicationAttribute as CFString, &object)
    if result == .success, let object, CFGetTypeID(object) == AXUIElementGetTypeID() {
      return object as! AXUIElement
    }
    guard let frontmost = NSWorkspace.shared.frontmostApplication else { return nil }
    guard frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
      return nil
    }
    return AXUIElementCreateApplication(frontmost.processIdentifier)
  }

  private func readSelectedTextAttribute(from element: AXUIElement) -> String? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(
      element, kAXSelectedTextAttribute as CFString, &value)
    guard result == .success, let text = value as? String else { return nil }
    return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
  }

  private func readSelectedTextFromRange(from element: AXUIElement) -> String? {
    var rangeValue: CFTypeRef?
    let rangeResult = AXUIElementCopyAttributeValue(
      element, kAXSelectedTextRangeAttribute as CFString, &rangeValue)
    guard rangeResult == .success, let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID()
    else { return nil }
    let axValue = rangeValue as! AXValue
    guard AXValueGetType(axValue) == .cfRange else { return nil }
    var selectedRange = CFRange()
    guard AXValueGetValue(axValue, .cfRange, &selectedRange), selectedRange.length > 0 else {
      return nil
    }
    var fullValue: CFTypeRef?
    let valueResult = AXUIElementCopyAttributeValue(
      element, kAXValueAttribute as CFString, &fullValue)
    guard valueResult == .success, let fullText = fullValue as? String else { return nil }
    let nsText = fullText as NSString
    guard selectedRange.location >= 0,
      selectedRange.location + selectedRange.length <= nsText.length
    else { return nil }
    let selectedText = nsText.substring(
      with: NSRange(location: selectedRange.location, length: selectedRange.length))
    return selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : selectedText
  }

  private func readSelectedTextFromClipboardFallback() -> String? {
    let snapshot = captureClipboardSnapshot()
    guard sendCopyShortcut() else { return nil }
    let deadline = Date().addingTimeInterval(1.0)
    let pasteboard = NSPasteboard.general
    while Date() < deadline {
      let count = pasteboard.changeCount
      if count > snapshot.changeCount, let text = pasteboard.string(forType: .string),
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        restoreClipboardSnapshotIfUnchanged(
          snapshot, expectedChangeCount: count, expectedPlainText: text)
        return trimmed
      }
      RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    return nil
  }

  private func captureClipboardSnapshot() -> ClipboardSnapshot {
    let pasteboard = NSPasteboard.general
    let items = (pasteboard.pasteboardItems ?? []).map { item in
      item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
        guard let data = item.data(forType: type) else { return nil }
        return (type, data)
      }
    }
    return ClipboardSnapshot(
      items: items, changeCount: pasteboard.changeCount,
      plainText: pasteboard.string(forType: .string))
  }

  private func restoreClipboardSnapshot(_ snapshot: ClipboardSnapshot) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    let restored = snapshot.items.compactMap { values -> NSPasteboardItem? in
      let item = NSPasteboardItem()
      var wrote = false
      for (type, data) in values { wrote = item.setData(data, forType: type) || wrote }
      return wrote ? item : nil
    }
    if !restored.isEmpty { pasteboard.writeObjects(restored) }
  }

  private func restoreClipboardSnapshotIfUnchanged(
    _ snapshot: ClipboardSnapshot, expectedChangeCount: Int, expectedPlainText: String
  ) {
    let pasteboard = NSPasteboard.general
    guard pasteboard.changeCount == expectedChangeCount,
      pasteboard.string(forType: .string) == expectedPlainText
    else { return }
    restoreClipboardSnapshot(snapshot)
  }

  @discardableResult
  private func sendCopyShortcut() -> Bool {
    guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
    let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true)
    let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
    guard let down, let up else { return false }
    down.flags = .maskCommand
    up.flags = .maskCommand
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
    return true
  }
}
