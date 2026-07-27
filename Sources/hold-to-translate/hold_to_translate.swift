import AppKit
import ApplicationServices
import Security
import ServiceManagement
import SwiftUI

private let axTrustedCheckOptionPromptKey = "AXTrustedCheckOptionPrompt"

extension Notification.Name {
  static let requestOpenMainPanel = Notification.Name("requestOpenMainPanel")
}

private let integerInputFormatter: NumberFormatter = {
  let formatter = NumberFormatter()
  formatter.numberStyle = .none
  formatter.allowsFloats = false
  formatter.minimum = 0
  return formatter
}()

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    NotificationCenter.default.post(name: .requestOpenMainPanel, object: nil)
    // We handle reopen ourselves to avoid AppKit's default reopen creating duplicate windows.
    return false
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }
}

enum TriggerButton: String, CaseIterable, Codable, Identifiable {
  case left
  case right
  case middle

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .left:
      return "左键"
    case .right:
      return "右键"
    case .middle:
      return "中键"
    }
  }
}

struct TranslationThresholds: Codable, Equatable {
  var warnLimit: Int = 2000
  var hardLimit: Int = 5000
}

struct TranslationSettings: Codable, Equatable {
  var endpoint: String = ""
  var region: String = ""
  var targetLanguage: String = "zh-Hans"
  var alternateLanguage: String = "en"
  var triggerButton: TriggerButton = .right
  var longPressMilliseconds: Double = 450
  var thresholds: TranslationThresholds = .init()

  enum CodingKeys: String, CodingKey {
    case endpoint
    case region
    case targetLanguage
    case alternateLanguage
    case triggerButton
    case longPressMilliseconds
    case thresholds
  }

  init() {}

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
    region = try container.decodeIfPresent(String.self, forKey: .region) ?? ""
    targetLanguage =
      try container.decodeIfPresent(String.self, forKey: .targetLanguage) ?? "zh-Hans"
    alternateLanguage =
      try container.decodeIfPresent(String.self, forKey: .alternateLanguage) ?? "en"
    triggerButton =
      try container.decodeIfPresent(TriggerButton.self, forKey: .triggerButton) ?? .right
    longPressMilliseconds =
      try container.decodeIfPresent(Double.self, forKey: .longPressMilliseconds) ?? 450
    thresholds =
      try container.decodeIfPresent(TranslationThresholds.self, forKey: .thresholds) ?? .init()
  }
}

struct LanguageOption: Identifiable, Hashable {
  let code: String
  let name: String

  var id: String { code }
  var displayLabel: String { "\(name) (\(code))" }
}

private let supportedLanguageOptions: [LanguageOption] = [
  .init(code: "zh-Hans", name: "简体中文"),
  .init(code: "zh-Hant", name: "繁體中文"),
  .init(code: "en", name: "English"),
  .init(code: "ja", name: "日本語"),
  .init(code: "ko", name: "한국어"),
  .init(code: "fr", name: "Français"),
  .init(code: "de", name: "Deutsch"),
  .init(code: "es", name: "Español"),
  .init(code: "it", name: "Italiano"),
  .init(code: "pt", name: "Português"),
  .init(code: "pt-BR", name: "Português (Brasil)"),
  .init(code: "ru", name: "Русский"),
  .init(code: "ar", name: "العربية"),
  .init(code: "hi", name: "हिन्दी"),
  .init(code: "th", name: "ไทย"),
  .init(code: "vi", name: "Tiếng Việt"),
  .init(code: "id", name: "Bahasa Indonesia"),
  .init(code: "tr", name: "Türkçe"),
  .init(code: "nl", name: "Nederlands"),
  .init(code: "pl", name: "Polski"),
  .init(code: "cs", name: "Čeština"),
  .init(code: "sv", name: "Svenska"),
  .init(code: "da", name: "Dansk"),
  .init(code: "fi", name: "Suomi"),
  .init(code: "uk", name: "Українська"),
  .init(code: "ro", name: "Română"),
  .init(code: "hu", name: "Magyar"),
  .init(code: "el", name: "Ελληνικά"),
  .init(code: "he", name: "עברית"),
  .init(code: "ms", name: "Bahasa Melayu"),
]

final class KeychainStore {
  private let service = "hold-to-translate"
  private let account = "azure-api-key"
  private let fallbackApiKey = "azure-api-key-fallback"
  private let defaults = UserDefaults.standard

  func loadApiKey() -> String {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecSuccess, let data = item as? Data,
      let value = String(data: data, encoding: .utf8)
    {
      if !value.isEmpty {
        defaults.set(value, forKey: fallbackApiKey)
      }
      return value
    }

    return defaults.string(forKey: fallbackApiKey) ?? ""
  }

  func saveApiKey(_ value: String) {
    defaults.set(value, forKey: fallbackApiKey)

    let data = Data(value.utf8)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]

    let attributes: [String: Any] = [
      kSecValueData as String: data
    ]

    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecItemNotFound {
      var addQuery = query
      addQuery[kSecValueData as String] = data
      _ = SecItemAdd(addQuery as CFDictionary, nil)
    }
  }
}

final class SettingsStore {
  private let settingsKey = "translation.settings"
  private let defaults = UserDefaults.standard

  func loadSettings() -> TranslationSettings {
    guard let data = defaults.data(forKey: settingsKey) else {
      return TranslationSettings()
    }
    return (try? JSONDecoder().decode(TranslationSettings.self, from: data))
      ?? TranslationSettings()
  }

  func saveSettings(_ settings: TranslationSettings) {
    guard let data = try? JSONEncoder().encode(settings) else { return }
    defaults.set(data, forKey: settingsKey)
  }
}

struct TranslationDraft: Equatable {
  var originalText: String
  var translatedText: String?
  var isTranslating: Bool = false
  var isEditing: Bool = false
  var editText: String = ""

  var normalizedCacheKey: String {
    originalText.normalizedCacheKey()
  }
}

struct AzureTranslationItem: Decodable {
  let text: String
}

struct AzureTranslationResponse: Decodable {
  let translations: [AzureTranslationItem]
}

enum TranslationServiceError: LocalizedError {
  case missingConfiguration
  case invalidEndpoint
  case invalidResponse
  case httpError(Int, String)

  var errorDescription: String? {
    switch self {
    case .missingConfiguration:
      return "请先在设置中填写 Azure Endpoint、API Key 和 Region。"
    case .invalidEndpoint:
      return "Azure Endpoint 格式无效，请检查后重试。"
    case .invalidResponse:
      return "翻译服务返回了无法识别的结果。"
    case .httpError(let statusCode, let message):
      return "翻译请求失败（HTTP \(statusCode)）。\(message)"
    }
  }
}

final class TranslationCache: @unchecked Sendable {
  private var storage: [String: String] = [:]

  func value(for key: String) -> String? {
    storage[key]
  }

  func insert(_ value: String, for key: String) {
    storage[key] = value
  }
}

final class AzureTranslationService: Sendable {
  func translate(
    text: String, settings: TranslationSettings, apiKey: String,
    targetLanguageOverride: String? = nil
  ) async throws -> String {
    let endpoint = normalizedEndpoint(settings.endpoint)
    let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let region = settings.region.trimmingCharacters(in: .whitespacesAndNewlines)
    let targetLanguage = (targetLanguageOverride ?? settings.targetLanguage).trimmingCharacters(
      in: .whitespacesAndNewlines)

    guard !endpoint.isEmpty, !apiKey.isEmpty, !region.isEmpty, !targetLanguage.isEmpty else {
      throw TranslationServiceError.missingConfiguration
    }

    guard var components = URLComponents(string: endpoint + "/translate") else {
      throw TranslationServiceError.invalidEndpoint
    }

    components.queryItems = [
      URLQueryItem(name: "api-version", value: "3.0"),
      URLQueryItem(name: "to", value: targetLanguage),
    ]

    guard let url = components.url else {
      throw TranslationServiceError.invalidEndpoint
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
    request.setValue(region, forHTTPHeaderField: "Ocp-Apim-Subscription-Region")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: [["Text": text]])

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw TranslationServiceError.invalidResponse
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      let message = String(data: data, encoding: .utf8) ?? ""
      throw TranslationServiceError.httpError(httpResponse.statusCode, message)
    }

    let decoded = try JSONDecoder().decode([AzureTranslationResponse].self, from: data)
    guard let text = decoded.first?.translations.first?.text, !text.isEmpty else {
      throw TranslationServiceError.invalidResponse
    }

    return text
  }

  private func normalizedEndpoint(_ endpoint: String) -> String {
    let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return trimmed
    }

    let prefixed = trimmed.contains("://") ? trimmed : "https://" + trimmed
    return prefixed.hasSuffix("/") ? String(prefixed.dropLast()) : prefixed
  }
}

extension String {
  func normalizedCacheKey() -> String {
    let collapsedWhitespace = replacingOccurrences(
      of: "\\s+",
      with: " ",
      options: .regularExpression
    )

    return
      collapsedWhitespace
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
  }

  func containsHanScript() -> Bool {
    unicodeScalars.contains { scalar in
      switch scalar.value {
      case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2CEAF:
        return true
      default:
        return false
      }
    }
  }
}

func translationWarningMessage(characterCount: Int) -> String {
  "选中文本较长（\(characterCount) 个字符），继续翻译可能需要更久。仍要继续吗？"
}

func translationHardLimitMessage(characterCount: Int, limit: Int) -> String {
  "文本长度为 \(characterCount) 个字符，已超过上限 \(limit) 个字符，暂不支持翻译。请缩短后重试。"
}

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

enum SelectionReadResult {
  case success(String)
  case failure(String)
}

private struct ClipboardSnapshot {
  let items: [[(NSPasteboard.PasteboardType, Data)]]
  let changeCount: Int
}

final class AccessibilitySelectionReader {
  func readSelectedText() -> SelectionReadResult {
    let systemWideElement = AXUIElementCreateSystemWide()

    guard var focusedAppElement = focusedApplicationElement(from: systemWideElement) else {
      return .failure("无法获取焦点应用，请确认目标应用仍在前台后重试")
    }

    var focusedPid: pid_t = 0
    AXUIElementGetPid(focusedAppElement, &focusedPid)
    if Int(focusedPid) == ProcessInfo.processInfo.processIdentifier {
      // After system/keychain prompts, AX focus can temporarily stick to this app.
      // Fall back to the real frontmost app instead of failing immediately.
      if let frontmost = NSWorkspace.shared.frontmostApplication {
        let frontmostPid = frontmost.processIdentifier
        if Int(frontmostPid) != ProcessInfo.processInfo.processIdentifier {
          focusedAppElement = AXUIElementCreateApplication(frontmostPid)
        } else if let clipboardSelectedText = readSelectedTextFromClipboardFallback() {
          return .success(clipboardSelectedText)
        } else {
          return .failure("当前焦点在本应用窗口，请先点回目标应用后再长按触发")
        }
      } else if let clipboardSelectedText = readSelectedTextFromClipboardFallback() {
        return .success(clipboardSelectedText)
      } else {
        return .failure("当前焦点在本应用窗口，请先点回目标应用后再长按触发")
      }
    }

    guard
      let focusedElement = focusedUIElement(from: focusedAppElement, fallback: systemWideElement)
    else {
      if let clipboardSelectedText = readSelectedTextFromClipboardFallback() {
        return .success(clipboardSelectedText)
      }
      return .failure("无法获取焦点控件（目标应用可能未暴露可访问焦点，剪贴板兜底也未成功）")
    }

    if let selectedText = readSelectedTextAttribute(from: focusedElement) {
      return .success(selectedText)
    }

    if let selectedText = readSelectedTextFromRange(from: focusedElement) {
      return .success(selectedText)
    }

    if let clipboardSelectedText = readSelectedTextFromClipboardFallback() {
      return .success(clipboardSelectedText)
    }

    let supported = supportedAttributeNames(of: focusedElement)
    if supported.isEmpty {
      return .failure("焦点控件未暴露可读选区（无可访问属性，剪贴板兜底也未成功）")
    }
    return .failure("焦点控件未暴露可读选区（可用属性：\(supported.joined(separator: ", "))，剪贴板兜底也未成功）")
  }

  private func focusedUIElement(
    from focusedAppElement: AXUIElement, fallback systemWideElement: AXUIElement
  ) -> AXUIElement? {
    var focusedObject: CFTypeRef?
    let focusedResult = AXUIElementCopyAttributeValue(
      focusedAppElement,
      kAXFocusedUIElementAttribute as CFString,
      &focusedObject
    )

    if focusedResult == .success, let focusedObject {
      guard CFGetTypeID(focusedObject) == AXUIElementGetTypeID() else {
        return nil
      }
      return (focusedObject as! AXUIElement)
    }

    var fallbackObject: CFTypeRef?
    let fallbackResult = AXUIElementCopyAttributeValue(
      systemWideElement,
      kAXFocusedUIElementAttribute as CFString,
      &fallbackObject
    )
    guard fallbackResult == .success, let fallbackObject else {
      return nil
    }
    guard CFGetTypeID(fallbackObject) == AXUIElementGetTypeID() else {
      return nil
    }
    return (fallbackObject as! AXUIElement)
  }

  private func supportedAttributeNames(of element: AXUIElement) -> [String] {
    var names: CFArray?
    let result = AXUIElementCopyAttributeNames(element, &names)
    guard result == .success, let names else {
      return []
    }

    let allNames = (names as [AnyObject]).compactMap { $0 as? String }
    let attrs = allNames.filter {
      $0 == kAXSelectedTextAttribute as String || $0 == kAXSelectedTextRangeAttribute as String
        || $0 == kAXValueAttribute as String
    }

    if attrs.isEmpty {
      let firstFew = allNames.prefix(6)
      return Array(firstFew)
    }
    return attrs
  }

  private func focusedApplicationElement(from systemWideElement: AXUIElement) -> AXUIElement? {
    var focusedAppObject: CFTypeRef?
    let focusedAppResult = AXUIElementCopyAttributeValue(
      systemWideElement,
      kAXFocusedApplicationAttribute as CFString,
      &focusedAppObject
    )

    if focusedAppResult == .success, let focusedAppObject,
      CFGetTypeID(focusedAppObject) == AXUIElementGetTypeID()
    {
      return (focusedAppObject as! AXUIElement)
    }

    guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else {
      return nil
    }

    let frontmostPid = frontmostApplication.processIdentifier
    guard frontmostPid != ProcessInfo.processInfo.processIdentifier else {
      return nil
    }

    return AXUIElementCreateApplication(frontmostPid)
  }

  private func readSelectedTextAttribute(from element: AXUIElement) -> String? {
    var selectedValue: CFTypeRef?
    let selectedResult = AXUIElementCopyAttributeValue(
      element,
      kAXSelectedTextAttribute as CFString,
      &selectedValue
    )

    guard selectedResult == .success, let selectedText = selectedValue as? String else {
      return nil
    }

    let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : selectedText
  }

  private func readSelectedTextFromRange(from element: AXUIElement) -> String? {
    var rangeValue: CFTypeRef?
    let rangeResult = AXUIElementCopyAttributeValue(
      element,
      kAXSelectedTextRangeAttribute as CFString,
      &rangeValue
    )

    guard rangeResult == .success, let rangeAXValue = rangeValue else {
      return nil
    }

    guard CFGetTypeID(rangeAXValue) == AXValueGetTypeID() else {
      return nil
    }

    let axValue = rangeAXValue as! AXValue
    guard AXValueGetType(axValue) == .cfRange else {
      return nil
    }

    var selectedRange = CFRange()
    guard AXValueGetValue(axValue, .cfRange, &selectedRange) else {
      return nil
    }

    guard selectedRange.length > 0 else {
      return nil
    }

    var fullValue: CFTypeRef?
    let valueResult = AXUIElementCopyAttributeValue(
      element,
      kAXValueAttribute as CFString,
      &fullValue
    )

    guard valueResult == .success, let fullText = fullValue as? String else {
      return nil
    }

    let nsText = fullText as NSString
    let location = selectedRange.location
    let length = selectedRange.length
    guard location >= 0, length > 0, location + length <= nsText.length else {
      return nil
    }

    let selectedText = nsText.substring(with: NSRange(location: location, length: length))
    let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : selectedText
  }

  private func readSelectedTextFromClipboardFallback() -> String? {
    let clipboardSnapshot = captureClipboardSnapshot()
    sendCopyShortcut()

    let deadline = Date().addingTimeInterval(0.35)
    while Date() < deadline {
      let pasteboard = NSPasteboard.general
      if pasteboard.changeCount != clipboardSnapshot.changeCount,
        let selectedText = pasteboard.string(forType: .string)?.trimmingCharacters(
          in: .whitespacesAndNewlines),
        !selectedText.isEmpty
      {
        restoreClipboardSnapshot(clipboardSnapshot)
        return selectedText
      }
      RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }

    restoreClipboardSnapshot(clipboardSnapshot)
    return nil
  }

  private func captureClipboardSnapshot() -> ClipboardSnapshot {
    let pasteboard = NSPasteboard.general
    let items: [[(NSPasteboard.PasteboardType, Data)]] = (pasteboard.pasteboardItems ?? []).map {
      item in
      item.types.compactMap { pasteboardType -> (NSPasteboard.PasteboardType, Data)? in
        guard let data = item.data(forType: pasteboardType) else {
          return nil
        }
        return (pasteboardType, data)
      }
    }
    return ClipboardSnapshot(items: items, changeCount: pasteboard.changeCount)
  }

  private func restoreClipboardSnapshot(_ snapshot: ClipboardSnapshot) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()

    let restoredItems: [NSPasteboardItem] = snapshot.items.compactMap { itemData in
      let item = NSPasteboardItem()
      var wroteAny = false
      for (pasteboardType, data) in itemData {
        wroteAny = item.setData(data, forType: pasteboardType) || wroteAny
      }
      return wroteAny ? item : nil
    }

    if !restoredItems.isEmpty {
      pasteboard.writeObjects(restoredItems)
    }
  }

  private func sendCopyShortcut() {
    guard let source = CGEventSource(stateID: .hidSystemState) else {
      return
    }

    let keyCodeForC: CGKeyCode = 8
    let copyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForC, keyDown: true)
    let copyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForC, keyDown: false)

    copyDown?.flags = .maskCommand
    copyUp?.flags = .maskCommand
    copyDown?.post(tap: .cghidEventTap)
    copyUp?.post(tap: .cghidEventTap)
  }
}

final class GlobalMouseHoldMonitor {
  var onTriggered: (() -> Void)?
  var onPressBegan: (() -> Void)?

  private var triggerButton: TriggerButton = .right
  private var minimumHoldDuration: TimeInterval = 0.45
  private var monitors: [Any] = []
  private var pendingWorkItem: DispatchWorkItem?
  private var safetyResetWorkItem: DispatchWorkItem?
  private var hasTriggeredCurrentPress = false

  func configure(triggerButton: TriggerButton, minimumHoldDuration: TimeInterval) {
    self.triggerButton = triggerButton
    self.minimumHoldDuration = minimumHoldDuration
  }

  func start() {
    guard monitors.isEmpty else { return }

    let downEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    let upEvents: NSEvent.EventTypeMask = [.leftMouseUp, .rightMouseUp, .otherMouseUp]

    if let downMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: downEvents,
      handler: { [weak self] event in
        self?.handle(event: event, isMouseDown: true)
      })
    {
      monitors.append(downMonitor)
    }

    if let downLocalMonitor = NSEvent.addLocalMonitorForEvents(
      matching: downEvents,
      handler: { [weak self] event in
        self?.handle(event: event, isMouseDown: true)
        return event
      })
    {
      monitors.append(downLocalMonitor)
    }

    if let upMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: upEvents,
      handler: { [weak self] event in
        self?.handle(event: event, isMouseDown: false)
      })
    {
      monitors.append(upMonitor)
    }

    if let upLocalMonitor = NSEvent.addLocalMonitorForEvents(
      matching: upEvents,
      handler: { [weak self] event in
        self?.handle(event: event, isMouseDown: false)
        return event
      })
    {
      monitors.append(upLocalMonitor)
    }

  }

  func stop() {
    cancelPendingTrigger()
    cancelSafetyReset()
    for monitor in monitors {
      NSEvent.removeMonitor(monitor)
    }
    monitors.removeAll()
  }

  private func handle(event: NSEvent, isMouseDown: Bool) {
    guard matchesConfiguredButton(event: event) else { return }

    if isMouseDown {
      // Keychain/auth prompts may swallow the matching mouse-up event.
      // Reset on every new press so the next long-press can always arm.
      hasTriggeredCurrentPress = false
      onPressBegan?()
      scheduleTriggerIfNeeded()
      scheduleSafetyReset()
    } else {
      cancelPendingTrigger()
      cancelSafetyReset()
      hasTriggeredCurrentPress = false
    }
  }

  private func matchesConfiguredButton(event: NSEvent) -> Bool {
    switch triggerButton {
    case .left:
      return event.type == .leftMouseDown || event.type == .leftMouseUp
    case .right:
      return event.type == .rightMouseDown || event.type == .rightMouseUp
    case .middle:
      return (event.type == .otherMouseDown || event.type == .otherMouseUp)
        && event.buttonNumber == 2
    }
  }

  private func scheduleTriggerIfNeeded() {
    cancelPendingTrigger()
    guard !hasTriggeredCurrentPress else { return }

    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.hasTriggeredCurrentPress = true
      self.onTriggered?()
    }

    pendingWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + minimumHoldDuration, execute: workItem)
  }

  private func scheduleSafetyReset() {
    cancelSafetyReset()
    let timeout = max(2.5, minimumHoldDuration * 4)
    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.cancelPendingTrigger()
      self.hasTriggeredCurrentPress = false
    }
    safetyResetWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)
  }

  private func cancelSafetyReset() {
    safetyResetWorkItem?.cancel()
    safetyResetWorkItem = nil
  }

  private func cancelPendingTrigger() {
    pendingWorkItem?.cancel()
    pendingWorkItem = nil
  }
}

final class TranslationPanelController: NSWindowController, NSWindowDelegate {
  private unowned let appState: TranslationAppState
  private var outsideClickMonitor: Any?
  private var keyMonitor: Any?
  private let pinButton = NSButton()

  init(appState: TranslationAppState) {
    self.appState = appState

    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 220),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = false
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.isReleasedWhenClosed = false
    panel.standardWindowButton(.closeButton)?.isHidden = true
    panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
    panel.standardWindowButton(.zoomButton)?.isHidden = true

    super.init(window: panel)

    panel.delegate = self
    panel.contentView = NSHostingView(rootView: TranslationWindowView(appState: appState))
    configurePinAccessory(on: panel)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func showNearCursor() {
    if !Thread.isMainThread {
      DispatchQueue.main.async { [weak self] in
        self?.showNearCursor()
      }
      return
    }

    guard let window else { return }
    applyPinning(to: window)
    NSApp.unhide(nil)
    NSRunningApplication.current.activate(options: [.activateAllWindows])
    NSApp.activate(ignoringOtherApps: true)
    position(window: window, near: NSEvent.mouseLocation)
    window.orderFrontRegardless()
    window.makeKeyAndOrderFront(nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
      self.applyPinning(to: window)
      NSRunningApplication.current.activate(options: [.activateAllWindows])
      window.orderFrontRegardless()
      window.makeKeyAndOrderFront(nil)
    }
    installDismissMonitors()
  }

  func hide() {
    tearDownDismissMonitors()
    window?.orderOut(nil)
  }

  func windowWillClose(_ notification: Notification) {
    tearDownDismissMonitors()
  }

  func updatePinning(isPinned _: Bool) {
    guard let window else { return }
    applyPinning(to: window)
    refreshPinButtonAppearance()
    if appState.windowState.isPinned {
      window.orderFrontRegardless()
      window.makeKeyAndOrderFront(nil)
    }
  }

  private func applyPinning(to window: NSWindow) {
    window.level = appState.windowState.isPinned ? .screenSaver : .statusBar
  }

  private func configurePinAccessory(on panel: NSPanel) {
    pinButton.isBordered = false
    pinButton.bezelStyle = .regularSquare
    pinButton.imagePosition = .imageOnly
    pinButton.setButtonType(.momentaryChange)
    pinButton.target = self
    pinButton.action = #selector(handlePinButtonTap)

    let container = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 22))
    container.translatesAutoresizingMaskIntoConstraints = false
    pinButton.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(pinButton)

    NSLayoutConstraint.activate([
      pinButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
      pinButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      pinButton.widthAnchor.constraint(equalToConstant: 16),
      pinButton.heightAnchor.constraint(equalToConstant: 16),
      container.widthAnchor.constraint(equalToConstant: 28),
      container.heightAnchor.constraint(equalToConstant: 22),
    ])

    let accessory = NSTitlebarAccessoryViewController()
    accessory.layoutAttribute = .right
    accessory.view = container
    panel.addTitlebarAccessoryViewController(accessory)
    refreshPinButtonAppearance()
  }

  private func refreshPinButtonAppearance() {
    let pinned = appState.windowState.isPinned
    pinButton.image = NSImage(
      systemSymbolName: pinned ? "pin.fill" : "pin",
      accessibilityDescription: pinned ? "取消钉住" : "钉住面板"
    )
    pinButton.contentTintColor = .labelColor
    pinButton.toolTip = pinned ? "取消钉住" : "钉住面板"
  }

  @objc
  private func handlePinButtonTap() {
    appState.togglePinned()
  }

  private func position(window: NSWindow, near point: CGPoint) {
    let frame = window.frame
    let screen =
      NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main
    let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let horizontalPadding: CGFloat = 14
    let verticalPadding: CGFloat = 18

    let originX = min(
      max(point.x + horizontalPadding, visibleFrame.minX + 12),
      visibleFrame.maxX - frame.width - 12
    )
    let originY = max(
      visibleFrame.minY + 12,
      min(point.y - frame.height - verticalPadding, visibleFrame.maxY - frame.height - 12)
    )

    window.setFrameOrigin(NSPoint(x: originX, y: originY))
  }

  private func installDismissMonitors() {
    tearDownDismissMonitors()

    outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
      .leftMouseDown, .rightMouseDown, .otherMouseDown,
    ]) { [weak self] _ in
      let clickPoint = NSEvent.mouseLocation
      Task { @MainActor in
        self?.handleOutsideInteraction(at: clickPoint)
      }
    }

    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
      return self?.handleKeyDown(event: event) ?? event
    }
  }

  private func tearDownDismissMonitors() {
    if let outsideClickMonitor {
      NSEvent.removeMonitor(outsideClickMonitor)
      self.outsideClickMonitor = nil
    }
    if let keyMonitor {
      NSEvent.removeMonitor(keyMonitor)
      self.keyMonitor = nil
    }
  }

  @MainActor
  private func handleOutsideInteraction(at point: NSPoint) {
    guard appState.windowState.isOutsideClickDismissEnabled else { return }
    guard !appState.windowState.isPinned else { return }

    if let window, window.frame.contains(point) {
      return
    }

    appState.closeTranslationWindowIfAllowed()
  }

  private func handleKeyDown(event: NSEvent) -> NSEvent? {
    let isEscape = event.keyCode == 53
    let isCommandEnter =
      (event.keyCode == 36 || event.keyCode == 76) && event.modifierFlags.contains(.command)
    let isCommandW = event.keyCode == 13 && event.modifierFlags.contains(.command)

    if isCommandW {
      appState.closeTranslationWindowIfAllowed()
      return nil
    }

    if appState.windowState.draft?.isEditing == true {
      if let textView = window?.firstResponder as? NSTextView, textView.hasMarkedText() {
        return event
      }

      if isEscape {
        appState.cancelEditing()
        return nil
      }

      if isCommandEnter {
        let textFromResponder = (window?.firstResponder as? NSTextView)?.string
        let textToSubmit = textFromResponder ?? appState.windowState.draft?.editText ?? ""
        appState.submitEditedOriginal(textToSubmit)
        return nil
      }
    }

    if isEscape, appState.handleEscapeRequest() {
      return nil
    }
    return event
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    appState.closeTranslationWindowIfAllowed()
    return false
  }
}

struct TranslationWindowState: Equatable {
  var draft: TranslationDraft?
  var isVisible: Bool = false
  var isOutsideClickDismissEnabled: Bool = true
  var isEscToCloseEnabled: Bool = true
  var isPinned: Bool = false

  mutating func show(with text: String) {
    draft = TranslationDraft(originalText: text, translatedText: nil, isTranslating: true)
    isVisible = true
  }

  mutating func beginEditing() {
    guard let draft else { return }
    self.draft = TranslationDraft(
      originalText: draft.originalText,
      translatedText: draft.translatedText,
      isEditing: true,
      editText: draft.originalText
    )
  }

  mutating func commitEditing() {
    guard let draft else { return }
    let editedText = draft.editText.trimmingCharacters(in: .whitespacesAndNewlines)
    self.draft = TranslationDraft(
      originalText: editedText, translatedText: nil, isTranslating: true)
    self.draft?.isEditing = false
  }

  mutating func cancelEditing() {
    guard let draft else { return }
    self.draft = TranslationDraft(
      originalText: draft.originalText,
      translatedText: draft.translatedText,
      isEditing: false,
      editText: draft.originalText
    )
  }

  mutating func closeIfAllowed() {
    guard isVisible, draft?.isEditing != true else { return }
    isVisible = false
    draft = nil
  }

  mutating func beginEditFromOriginal() {
    beginEditing()
  }

  mutating func setTranslatedText(_ text: String) {
    draft?.translatedText = text
    draft?.isTranslating = false
  }

  mutating func setTranslationFailed() {
    draft?.isTranslating = false
  }
}

@main
struct HoldToTranslateApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var appState = TranslationAppState()

  var body: some Scene {
    Settings {
      EmptyView()
    }
  }
}

struct LaunchControlView: View {
  @ObservedObject var state: TranslationAppState

  var body: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 16) {
        GroupBox("辅助功能") {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("辅助功能")
                .foregroundStyle(.secondary)
              Spacer()
              HStack(spacing: 8) {
                Button {
                  state.openAccessibilitySettings()
                } label: {
                  Text(state.accessibilityStatus.displayName)
                    .underline()
                }
                .buttonStyle(.plain)
                .foregroundStyle(state.accessibilityStatus == .granted ? .green : .orange)
                .help("打开辅助功能系统设置")

                Button {
                  state.recheckAccessibilityStatus()
                } label: {
                  Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 12, height: 12)
                }
                .frame(width: 14, height: 14)
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .help("重新检测权限")
                .accessibilityLabel("重新检测权限")
              }
            }

            Text(state.lastTriggerStatusMessage)
              .font(.callout)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .padding(.vertical, 4)
        }

        GroupBox("应用设置") {
          VStack(alignment: .leading, spacing: 10) {
            Toggle(
              "登录启动",
              isOn: Binding(
                get: { state.loginAtLaunchEnabled },
                set: { state.setLoginAtLaunchEnabled($0) }
              ))

            TextField(
              "Endpoint",
              text: Binding(
                get: { state.settings.endpoint },
                set: { state.settings.endpoint = $0 }
              ))

            SecureField(
              "API Key",
              text: Binding(
                get: { state.apiKey },
                set: { state.apiKey = $0 }
              ))

            TextField(
              "Region",
              text: Binding(
                get: { state.settings.region },
                set: { state.settings.region = $0 }
              ))

            HStack {
              Text("目标语言")
                .foregroundStyle(.secondary)
              Spacer()
              SearchableLanguageDropdown(
                options: supportedLanguageOptions,
                selectedCode: Binding(
                  get: { state.settings.targetLanguage },
                  set: { state.settings.targetLanguage = $0 }
                )
              )
              .frame(width: 220)
            }

            HStack {
              Text("备选语言")
                .foregroundStyle(.secondary)
              Spacer()
              SearchableLanguageDropdown(
                options: supportedLanguageOptions,
                selectedCode: Binding(
                  get: { state.settings.alternateLanguage },
                  set: { state.settings.alternateLanguage = $0 }
                )
              )
              .frame(width: 220)
            }

            Picker(
              "触发键",
              selection: Binding(
                get: { state.settings.triggerButton },
                set: { state.settings.triggerButton = $0 }
              )
            ) {
              ForEach(TriggerButton.allCases) { button in
                Text(button.displayName).tag(button)
              }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading) {
              Text("长按时长：\(Int(state.settings.longPressMilliseconds)) ms")
              Slider(
                value: Binding(
                  get: { state.settings.longPressMilliseconds },
                  set: { state.settings.longPressMilliseconds = $0 }
                ), in: 200...1200, step: 50)
            }

            HStack {
              Text("警告阈值")
                .foregroundStyle(.secondary)
              Button {
                state.showWarnThresholdHelp()
              } label: {
                Image(systemName: "questionmark.circle")
              }
              .buttonStyle(.plain)
              .foregroundStyle(.secondary)
              .help("查看警告阈值说明")
              Spacer()
              TextField(
                "警告阈值",
                value: Binding(
                  get: { state.settings.thresholds.warnLimit },
                  set: { state.settings.thresholds.warnLimit = max(1, min(9999, $0)) }
                ), formatter: integerInputFormatter
              )
              .frame(width: 120)
            }

            HStack {
              Text("拒绝阈值")
                .foregroundStyle(.secondary)
              Button {
                state.showHardThresholdHelp()
              } label: {
                Image(systemName: "questionmark.circle")
              }
              .buttonStyle(.plain)
              .foregroundStyle(.secondary)
              .help("查看拒绝阈值说明")
              Spacer()
              TextField(
                "拒绝阈值",
                value: Binding(
                  get: { state.settings.thresholds.hardLimit },
                  set: { state.settings.thresholds.hardLimit = max(1, min(20000, $0)) }
                ), formatter: integerInputFormatter
              )
              .frame(width: 120)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 4)
        }

        Spacer(minLength: 0)
      }
    }
    .padding(20)
    .onAppear {
      state.refreshLoginItemStatus()
    }
  }
}

final class MainPanelController: NSWindowController, NSWindowDelegate {
  private unowned let appState: TranslationAppState

  init(appState: TranslationAppState) {
    self.appState = appState

    let hostingView = NSHostingView(rootView: LaunchControlView(state: appState))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Hold to Translate"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = false
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.contentView = hostingView

    super.init(window: window)

    window.delegate = self
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func showAndFocus() {
    guard let window else { return }

    if window.isMiniaturized {
      window.deminiaturize(nil)
    }

    NSApp.setActivationPolicy(.regular)
    NSApp.unhide(nil)
    NSRunningApplication.current.activate(options: [.activateAllWindows])
    NSApp.activate(ignoringOtherApps: true)
    window.orderFrontRegardless()
    window.makeKeyAndOrderFront(nil)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    NSApp.setActivationPolicy(.accessory)
    sender.orderOut(nil)
    return false
  }
}

@MainActor
final class StatusItemController: NSObject {
  private unowned let appState: TranslationAppState
  private let statusItem: NSStatusItem
  private let menu = NSMenu()
  private(set) var isMenuOpen = false

  init(appState: TranslationAppState) {
    self.appState = appState
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    super.init()
    configureStatusItem()
    configureMenu()
  }

  private func configureStatusItem() {
    guard let button = statusItem.button else { return }
    button.image = appState.statusBarIcon
    button.imagePosition = .imageOnly
    button.isBordered = false
    button.target = self
    button.action = #selector(handleStatusItemClick(_:))
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
  }

  private func configureMenu() {
    menu.delegate = self
  }

  @objc
  private func handleStatusItemClick(_ sender: Any?) {
    let event = NSApp.currentEvent
    let isRightClick =
      event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true

    if isRightClick {
      showMenu()
    } else {
      appState.openOrFocusMainPanel()
    }
  }

  private func showMenu() {
    menu.removeAllItems()

    let accessibilityItem = NSMenuItem(
      title: "辅助功能：\(appState.accessibilityStatus.displayName)",
      action: nil,
      keyEquivalent: ""
    )
    accessibilityItem.isEnabled = false
    menu.addItem(accessibilityItem)
    menu.addItem(.separator())

    let openItem = NSMenuItem(
      title: "打开主面板", action: #selector(handleOpenMainPanel), keyEquivalent: "")
    openItem.target = self
    menu.addItem(openItem)

    let quitItem = NSMenuItem(title: "退出", action: #selector(handleQuit), keyEquivalent: "")
    quitItem.target = self
    menu.addItem(quitItem)

    statusItem.menu = menu
    statusItem.button?.performClick(nil)
  }

  @objc
  private func handleOpenMainPanel() {
    appState.openOrFocusMainPanel()
  }

  @objc
  private func handleQuit() {
    NSApp.terminate(nil)
  }
}

extension StatusItemController: NSMenuDelegate {
  func menuWillOpen(_ menu: NSMenu) {
    isMenuOpen = true
    menu.items.forEach { item in
      if item.title.hasPrefix("辅助功能：") {
        item.title = "辅助功能：\(appState.accessibilityStatus.displayName)"
      }
    }
  }

  func menuDidClose(_ menu: NSMenu) {
    isMenuOpen = false
    statusItem.menu = nil
  }
}

@MainActor
final class TranslationAppState: NSObject, ObservableObject {
  static weak var shared: TranslationAppState?

  @Published var settings = TranslationSettings() {
    didSet {
      holdMonitor.configure(
        triggerButton: settings.triggerButton,
        minimumHoldDuration: settings.longPressMilliseconds / 1000
      )
      settingsStore.saveSettings(settings)
    }
  }
  @Published var apiKey: String = "" {
    didSet {
      guard shouldPersistApiKey else { return }
      keychainStore.saveApiKey(apiKey)
    }
  }
  @Published var windowState = TranslationWindowState()
  @Published var accessibilityStatus: AccessibilityStatus
  @Published var lastTriggerStatusMessage: String = "等待触发"
  @Published var loginAtLaunchEnabled: Bool = false

  private let permissionService: AccessibilityPermissionService
  private let selectionReader: AccessibilitySelectionReader
  private let holdMonitor: GlobalMouseHoldMonitor
  private let translationService: AzureTranslationService
  private let translationCache: TranslationCache
  private let settingsStore: SettingsStore
  private let keychainStore: KeychainStore
  private var shouldPersistApiKey = true
  private var preCapturedSelection: String?
  private var preCaptureAt: Date?
  private var pinnedEscapeFirstPressedAt: Date?
  private var panelController: TranslationPanelController?
  private var mainPanelController: MainPanelController?
  private var statusItemController: StatusItemController?
  private var accessibilityStatusRefreshWorkItem: DispatchWorkItem?

  init(
    permissionService: AccessibilityPermissionService = .init(),
    selectionReader: AccessibilitySelectionReader = .init(),
    holdMonitor: GlobalMouseHoldMonitor = .init(),
    translationService: AzureTranslationService = .init(),
    translationCache: TranslationCache = .init(),
    settingsStore: SettingsStore = .init(),
    keychainStore: KeychainStore = .init()
  ) {
    self.permissionService = permissionService
    self.selectionReader = selectionReader
    self.holdMonitor = holdMonitor
    self.translationService = translationService
    self.translationCache = translationCache
    self.settingsStore = settingsStore
    self.keychainStore = keychainStore
    self.accessibilityStatus = permissionService.currentStatus()
    self.settings = settingsStore.loadSettings()
    super.init()
    Self.shared = self

    self.holdMonitor.configure(
      triggerButton: settings.triggerButton,
      minimumHoldDuration: settings.longPressMilliseconds / 1000
    )

    self.holdMonitor.onTriggered = { [weak self] in
      Task { @MainActor in
        self?.handleLongPressTrigger()
      }
    }
    self.holdMonitor.onPressBegan = { [weak self] in
      Task { @MainActor in
        self?.captureSelectionOnPressBegan()
      }
    }
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleRequestOpenMainPanelNotification),
      name: .requestOpenMainPanel,
      object: nil
    )
    self.holdMonitor.start()
    self.loginAtLaunchEnabled = isLoginItemEnabled()
    self.statusItemController = StatusItemController(appState: self)

    DispatchQueue.main.async { [weak self] in
      self?.openOrFocusMainPanel()
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self, name: .requestOpenMainPanel, object: nil)
  }

  @objc
  private func handleRequestOpenMainPanelNotification() {
    openOrFocusMainPanel()
  }

  func openOrFocusMainPanel() {
    ensureMainPanelController().showAndFocus()
  }

  var statusBarIcon: NSImage {
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size)
    image.lockFocus()

    let bounds = NSRect(origin: .zero, size: size).insetBy(dx: 2.2, dy: 2.2)
    let strokeColor = NSColor.black

    strokeColor.setStroke()

    let outerCircle = NSBezierPath(ovalIn: bounds)
    outerCircle.lineWidth = 1.6
    outerCircle.stroke()

    let horizontal = NSBezierPath()
    horizontal.lineWidth = 1.2
    horizontal.move(to: NSPoint(x: bounds.minX + 1.0, y: bounds.midY))
    horizontal.line(to: NSPoint(x: bounds.maxX - 1.0, y: bounds.midY))
    horizontal.stroke()

    let vertical = NSBezierPath()
    vertical.lineWidth = 1.2
    vertical.move(to: NSPoint(x: bounds.midX, y: bounds.minY + 1.0))
    vertical.line(to: NSPoint(x: bounds.midX, y: bounds.maxY - 1.0))
    vertical.stroke()

    let leftArc = NSBezierPath()
    leftArc.lineWidth = 1.0
    leftArc.move(to: NSPoint(x: bounds.midX, y: bounds.minY + 0.8))
    leftArc.curve(
      to: NSPoint(x: bounds.midX, y: bounds.maxY - 0.8),
      controlPoint1: NSPoint(
        x: bounds.minX + bounds.width * 0.18, y: bounds.minY + bounds.height * 0.22),
      controlPoint2: NSPoint(
        x: bounds.minX + bounds.width * 0.18, y: bounds.maxY - bounds.height * 0.22)
    )
    leftArc.stroke()

    let rightArc = NSBezierPath()
    rightArc.lineWidth = 1.0
    rightArc.move(to: NSPoint(x: bounds.midX, y: bounds.minY + 0.8))
    rightArc.curve(
      to: NSPoint(x: bounds.midX, y: bounds.maxY - 0.8),
      controlPoint1: NSPoint(
        x: bounds.maxX - bounds.width * 0.18, y: bounds.minY + bounds.height * 0.22),
      controlPoint2: NSPoint(
        x: bounds.maxX - bounds.width * 0.18, y: bounds.maxY - bounds.height * 0.22)
    )
    rightArc.stroke()

    image.unlockFocus()
    image.isTemplate = true
    return image
  }

  func refreshLoginItemStatus() {
    loginAtLaunchEnabled = isLoginItemEnabled()
  }

  func setLoginAtLaunchEnabled(_ enabled: Bool) {
    let service = SMAppService.mainApp
    do {
      if enabled {
        try service.register()
        lastTriggerStatusMessage = "已开启登录启动"
      } else {
        try service.unregister()
        lastTriggerStatusMessage = "已关闭登录启动"
      }
      loginAtLaunchEnabled = isLoginItemEnabled()
    } catch {
      loginAtLaunchEnabled = isLoginItemEnabled()
      presentInfoAlert(
        title: "登录启动设置失败",
        message: error.localizedDescription
      )
    }
  }

  func requestAccessibilityAccess(prompt: Bool = true) {
    let granted = permissionService.requestAccess(prompt: prompt)
    accessibilityStatus = granted ? .granted : .denied
    lastTriggerStatusMessage = granted ? "辅助功能权限已授权" : "辅助功能权限未授权"
  }

  func handleAccessibilityButtonTap() {
    refreshAccessibilityStatus()
    guard accessibilityStatus != .granted else {
      lastTriggerStatusMessage = "辅助功能权限已授权"
      return
    }
    requestAccessibilityAccess(prompt: true)
  }

  func refreshAccessibilityStatus() {
    accessibilityStatus = permissionService.currentStatus()
    lastTriggerStatusMessage = accessibilityStatus == .granted ? "辅助功能权限已授权" : "请先授权辅助功能权限"
  }

  func scheduleDeferredAccessibilityStatusRefresh(after delay: TimeInterval = 1.0) {
    accessibilityStatusRefreshWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      self?.refreshAccessibilityStatus()
    }
    accessibilityStatusRefreshWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
  }

  func recheckAccessibilityStatus() {
    refreshAccessibilityStatus()
  }

  private func ensureMainPanelController() -> MainPanelController {
    if let mainPanelController {
      return mainPanelController
    }

    let controller = MainPanelController(appState: self)
    mainPanelController = controller
    return controller
  }

  func openAccessibilitySettings() {
    permissionService.openSystemSettings()
  }

  func showWarnThresholdHelp() {
    presentInfoAlert(
      title: "警告阈值说明",
      message: "当选中文本长度超过该阈值时，会先弹出确认框，确认后才继续翻译。"
    )
  }

  func showHardThresholdHelp() {
    presentInfoAlert(
      title: "拒绝阈值说明",
      message: "当选中文本长度超过该阈值时，将直接拒绝翻译，避免超长文本导致耗时或成本升高。"
    )
  }

  func beginEditingOriginal() {
    windowState.beginEditFromOriginal()
  }

  func cancelEditing() {
    windowState.cancelEditing()
  }

  func submitEditedOriginal(_ text: String) {
    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedText.isEmpty else {
      cancelEditing()
      return
    }

    windowState.draft?.editText = trimmedText
    windowState.commitEditing()
    startTranslation(for: trimmedText)
  }

  func closeTranslationWindowIfAllowed() {
    let wasVisible = windowState.isVisible
    windowState.closeIfAllowed()
    pinnedEscapeFirstPressedAt = nil
    if wasVisible, !windowState.isVisible {
      panelController?.hide()
    }
  }

  func handleEscapeRequest() -> Bool {
    if isCurrentTextCompositionActive() {
      return false
    }

    if windowState.isPinned {
      let now = Date()
      let threshold: TimeInterval = 0.45

      if let first = pinnedEscapeFirstPressedAt,
        now.timeIntervalSince(first) <= threshold
      {
        pinnedEscapeFirstPressedAt = nil
        closeTranslationWindowIfAllowed()
        return true
      }

      pinnedEscapeFirstPressedAt = now
      lastTriggerStatusMessage = "面板已钉住：短时间内再按一次 ESC 关闭"
      return true
    }

    if windowState.draft?.isEditing == true {
      cancelEditing()
    } else {
      closeTranslationWindowIfAllowed()
    }
    return true
  }

  func togglePinned() {
    windowState.isPinned.toggle()
    pinnedEscapeFirstPressedAt = nil
    panelController?.updatePinning(isPinned: windowState.isPinned)
    lastTriggerStatusMessage = windowState.isPinned ? "面板已钉住" : "已取消钉住"
  }

  func simulateTriggerForCurrentSelection() {
    handleLongPressTrigger()
  }

  private func handleLongPressTrigger() {
    guard !shouldIgnoreTriggerForInternalAppInteraction() else {
      return
    }

    guard permissionService.currentStatus() == .granted else {
      accessibilityStatus = .denied
      lastTriggerStatusMessage = "触发失败：缺少辅助功能权限"
      presentPermissionAlert()
      return
    }

    accessibilityStatus = .granted
    lastTriggerStatusMessage = "已触发，正在读取选中文本"

    let selectedText: String
    switch selectionReader.readSelectedText() {
    case .success(let text):
      selectedText = text
    case .failure(let reason):
      if let preCapturedSelection = currentPreCapturedSelection() {
        selectedText = preCapturedSelection
        lastTriggerStatusMessage = "焦点已变化，使用按下瞬间的选区"
      } else {
        lastTriggerStatusMessage = "触发已忽略：\(reason)"
        return
      }
    }

    let characterCount = selectedText.count
    if characterCount > settings.thresholds.hardLimit {
      lastTriggerStatusMessage = "触发失败：文本超过拒绝阈值"
      presentInfoAlert(
        title: "文本过长",
        message: translationHardLimitMessage(
          characterCount: characterCount,
          limit: settings.thresholds.hardLimit
        )
      )
      return
    }

    if characterCount > settings.thresholds.warnLimit {
      let shouldContinue = presentConfirmationAlert(
        title: "是否继续翻译",
        message: translationWarningMessage(characterCount: characterCount),
        confirmTitle: "继续翻译",
        cancelTitle: "取消"
      )

      guard shouldContinue else {
        lastTriggerStatusMessage = "已取消：长文本翻译"
        return
      }
    }

    windowState.show(with: selectedText)
    NSApp.activate(ignoringOtherApps: true)
    let panelController = ensurePanelController()
    panelController.showNearCursor()
    lastTriggerStatusMessage = "已触发翻译请求"
    startTranslation(for: selectedText)
  }

  private func captureSelectionOnPressBegan() {
    guard !shouldIgnoreTriggerForInternalAppInteraction() else { return }
    guard permissionService.currentStatus() == .granted else { return }
    switch selectionReader.readSelectedText() {
    case .success(let text):
      preCapturedSelection = text
      preCaptureAt = Date()
    case .failure:
      preCapturedSelection = nil
      preCaptureAt = nil
    }
  }

  private func currentPreCapturedSelection() -> String? {
    guard let preCapturedSelection, let preCaptureAt else {
      return nil
    }
    let elapsed = Date().timeIntervalSince(preCaptureAt)
    guard elapsed <= 1.5 else {
      self.preCapturedSelection = nil
      self.preCaptureAt = nil
      return nil
    }
    return preCapturedSelection
  }

  private func isCurrentTextCompositionActive() -> Bool {
    guard let textView = panelController?.window?.firstResponder as? NSTextView else {
      return false
    }
    return textView.hasMarkedText()
  }

  private func shouldIgnoreTriggerForInternalAppInteraction() -> Bool {
    if statusItemController?.isMenuOpen == true {
      return true
    }

    if NSApp.isActive {
      return true
    }

    if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
      frontmostApplication.processIdentifier == ProcessInfo.processInfo.processIdentifier
    {
      return true
    }

    return false
  }

  private func ensurePanelController() -> TranslationPanelController {
    if let panelController, panelController.window != nil {
      return panelController
    }

    let controller = TranslationPanelController(appState: self)
    panelController = controller
    return controller
  }

  private func isLoginItemEnabled() -> Bool {
    SMAppService.mainApp.status == .enabled
  }

  private func startTranslation(for text: String) {
    let resolvedApiKey = effectiveApiKey()
    let resolvedTargetLanguage = resolvedTargetLanguage(for: text)
    let cacheKey = cacheKey(for: text, targetLanguage: resolvedTargetLanguage)
    if let cachedText = translationCache.value(for: cacheKey) {
      windowState.setTranslatedText(cachedText)
      lastTriggerStatusMessage = "命中缓存，已展示译文"
      return
    }

    windowState.draft?.isTranslating = true

    Task { @MainActor in
      do {
        let translatedText = try await translationService.translate(
          text: text,
          settings: settings,
          apiKey: resolvedApiKey,
          targetLanguageOverride: resolvedTargetLanguage
        )
        translationCache.insert(translatedText, for: cacheKey)
        guard windowState.draft?.originalText == text else { return }
        windowState.setTranslatedText(translatedText)
        lastTriggerStatusMessage = "翻译完成"
      } catch {
        windowState.setTranslationFailed()
        lastTriggerStatusMessage = "翻译失败：\(error.localizedDescription)"
        presentInfoAlert(
          title: "翻译失败",
          message: error.localizedDescription
        )
      }
    }
  }

  private func cacheKey(for text: String, targetLanguage: String) -> String {
    targetLanguage + "::" + text.normalizedCacheKey()
  }

  private func resolvedTargetLanguage(for text: String) -> String {
    let primary = normalizedLanguageCode(settings.targetLanguage, fallback: "zh-Hans")
    let alternate = normalizedLanguageCode(settings.alternateLanguage, fallback: "en")

    guard primary.caseInsensitiveCompare(alternate) != .orderedSame else {
      return primary
    }

    if primary.lowercased().hasPrefix("zh"), text.containsHanScript() {
      return alternate
    }

    return primary
  }

  private func normalizedLanguageCode(_ raw: String, fallback: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return fallback }

    if let matched = supportedLanguageOptions.first(where: {
      $0.code.caseInsensitiveCompare(trimmed) == .orderedSame
        || $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        || $0.displayLabel.caseInsensitiveCompare(trimmed) == .orderedSame
    }) {
      return matched.code
    }

    return trimmed
  }

  private func effectiveApiKey() -> String {
    let inMemory = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    if !inMemory.isEmpty {
      return inMemory
    }

    let stored = keychainStore.loadApiKey().trimmingCharacters(in: .whitespacesAndNewlines)
    if !stored.isEmpty {
      shouldPersistApiKey = false
      apiKey = stored
      shouldPersistApiKey = true
    }
    return stored
  }

  private func presentPermissionAlert() {
    let shouldOpenSettings = presentConfirmationAlert(
      title: "需要辅助功能权限",
      message: "当前版本仅通过辅助功能读取选中文本。请先授权后再使用。",
      confirmTitle: "打开系统设置",
      cancelTitle: "稍后再说"
    )

    if shouldOpenSettings {
      openAccessibilitySettings()
    }
  }

  private func presentInfoAlert(title: String, message: String) {
    let _ = presentModalAlert(
      title: title,
      message: message,
      style: .informational,
      primaryTitle: "知道了",
      secondaryTitle: "关闭"
    )
  }

  private func presentConfirmationAlert(
    title: String,
    message: String,
    confirmTitle: String,
    cancelTitle: String
  ) -> Bool {
    return presentModalAlert(
      title: title,
      message: message,
      style: .warning,
      primaryTitle: confirmTitle,
      secondaryTitle: cancelTitle
    ) == .alertFirstButtonReturn
  }

  private func presentModalAlert(
    title: String,
    message: String,
    style: NSAlert.Style,
    primaryTitle: String,
    secondaryTitle: String
  ) -> NSApplication.ModalResponse {
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.alertStyle = style
    alert.messageText = title
    alert.informativeText = message

    _ = alert.addButton(withTitle: primaryTitle)
    let secondaryButton = alert.addButton(withTitle: secondaryTitle)
    secondaryButton.keyEquivalent = "\u{1b}"
    alert.window.level = .modalPanel
    alert.window.collectionBehavior.insert(.canJoinAllSpaces)
    alert.window.collectionBehavior.insert(.fullScreenAuxiliary)
    alert.window.makeKeyAndOrderFront(nil)
    return alert.runModal()
  }
}

struct TranslationWindowView: View {
  @ObservedObject var appState: TranslationAppState

  var body: some View {
    let draft = appState.windowState.draft

    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 8) {
        if let draft, appState.windowState.isVisible {
          if draft.isEditing {
            EditingPanel(
              text: Binding(
                get: { appState.windowState.draft?.editText ?? "" },
                set: { appState.windowState.draft?.editText = $0 }
              )
            )
          } else {
            TranslationDisplayPanel(
              draft: draft,
              onBeginEditing: {
                appState.beginEditingOriginal()
              }
            )
          }
        } else {
          Text("尚未捕获选中文本")
            .foregroundStyle(.secondary)
        }
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(minWidth: 420, idealWidth: 480, minHeight: 180, idealHeight: 260, maxHeight: 360)
  }
}

struct TranslationDisplayPanel: View {
  let draft: TranslationDraft
  let onBeginEditing: () -> Void
  @State private var isCopyConfirmed = false
  @State private var copyFeedbackToken = UUID()

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      VStack(alignment: .leading, spacing: 4) {
        Text("原文（双击原文即可编辑）")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        Text(draft.originalText)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(8)
          .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 1)
          )
          .help("双击即可编辑")
      }
      .contentShape(Rectangle())
      .simultaneousGesture(
        TapGesture(count: 2)
          .onEnded { onBeginEditing() }
      )

      VStack(alignment: .leading, spacing: 4) {
        Text("译文")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 8) {
          if draft.isTranslating {
            ProgressView("正在翻译")
              .controlSize(.small)
          }

          if let translatedText = draft.translatedText {
            Text(translatedText)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          } else {
            Text(draft.isTranslating ? "" : "等待翻译结果")
              .frame(maxWidth: .infinity, alignment: .leading)
              .foregroundStyle(.secondary)
          }

          if let translatedText = draft.translatedText, !translatedText.isEmpty {
            HStack {
              Spacer()
              Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(translatedText, forType: .string)

                isCopyConfirmed = true
                let token = UUID()
                copyFeedbackToken = token
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                  guard copyFeedbackToken == token else { return }
                  isCopyConfirmed = false
                }
              } label: {
                Image(systemName: isCopyConfirmed ? "checkmark.circle.fill" : "doc.on.doc")
                  .font(.system(size: isCopyConfirmed ? 12 : 10, weight: .semibold))
                  .frame(width: 14, height: 14)
              }
              .frame(width: 18, height: 18)
              .buttonStyle(.borderless)
              .foregroundStyle(isCopyConfirmed ? .green : .primary)
              .help(isCopyConfirmed ? "复制成功" : "复制译文")
              .accessibilityLabel(isCopyConfirmed ? "复制成功" : "复制译文")
            }
          }
        }
        .padding(8)
        .background(
          Color(nsColor: .textBackgroundColor),
          in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
        )
      }
    }
  }
}

struct EditingPanel: View {
  @Binding var text: String
  @FocusState private var isEditorFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("编辑原文（ESC 取消，Cmd+Enter 提交）")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      TextEditor(text: $text)
        .font(.body)
        .focused($isEditorFocused)
        .frame(minHeight: 8 * 22)
        .padding(8)
        .background(
          Color(nsColor: .textBackgroundColor),
          in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
          DispatchQueue.main.async {
            isEditorFocused = true
          }
        }
    }
  }
}

struct SearchableLanguageDropdown: View {
  let options: [LanguageOption]
  @Binding var selectedCode: String
  @State private var isPresented = false
  @State private var query = ""
  @State private var highlightedCode: String?
  @State private var focusSearchFieldToken = UUID()

  private var selectedLabel: String {
    options.first(where: { $0.code.caseInsensitiveCompare(selectedCode) == .orderedSame })?
      .displayLabel ?? selectedCode
  }

  private var filteredOptions: [LanguageOption] {
    let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !keyword.isEmpty else { return options }
    return options.filter {
      $0.code.lowercased().contains(keyword) || $0.name.lowercased().contains(keyword)
        || $0.displayLabel.lowercased().contains(keyword)
    }
  }

  var body: some View {
    Button {
      if !isPresented {
        query = ""
        highlightedCode = selectedCode
      }
      isPresented.toggle()
    } label: {
      HStack(spacing: 6) {
        Text(selectedLabel)
          .lineLimit(1)
        Spacer(minLength: 4)
        Image(systemName: "chevron.down")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(Color(nsColor: .textBackgroundColor))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .popover(isPresented: $isPresented, arrowEdge: .bottom) {
      ScrollViewReader { proxy in
        VStack(alignment: .leading, spacing: 8) {
          SearchCommandField(
            text: $query,
            focusToken: $focusSearchFieldToken,
            onMoveUp: { moveHighlight(direction: .up) },
            onMoveDown: { moveHighlight(direction: .down) },
            onSubmit: { commitHighlightedOrFirst() },
            onEscape: { isPresented = false }
          )
          .frame(height: 24)

          ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
              ForEach(filteredOptions) { option in
                Button {
                  commit(option: option)
                } label: {
                  HStack {
                    Text(option.displayLabel)
                    Spacer()
                    if option.code.caseInsensitiveCompare(selectedCode) == .orderedSame {
                      Image(systemName: "checkmark")
                        .foregroundStyle(.secondary)
                    }
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(.horizontal, 8)
                  .padding(.vertical, 6)
                  .background(
                    (option.code.caseInsensitiveCompare(highlightedCode ?? "") == .orderedSame)
                      ? Color.accentColor.opacity(0.15)
                      : Color.clear
                  )
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(option.code)
              }
            }
          }
          .frame(height: 220)
          .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
              .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
          )
        }
        .padding(10)
        .frame(width: 300)
        .onAppear {
          if highlightedCode == nil
            || !options.contains(where: {
              $0.code.caseInsensitiveCompare(highlightedCode ?? "") == .orderedSame
            })
          {
            highlightedCode = selectedCode
          }
          if !filteredOptions.contains(where: {
            $0.code.caseInsensitiveCompare(highlightedCode ?? "") == .orderedSame
          }) {
            highlightedCode = filteredOptions.first?.code
          }
          focusSearchFieldToken = UUID()
          if let highlightedCode {
            DispatchQueue.main.async {
              proxy.scrollTo(highlightedCode)
            }
          }
        }
        .onChange(of: query) { _, _ in
          if !filteredOptions.contains(where: {
            $0.code.caseInsensitiveCompare(highlightedCode ?? "") == .orderedSame
          }) {
            highlightedCode = filteredOptions.first?.code
          }
        }
        .onChange(of: highlightedCode) { _, newValue in
          guard let newValue else { return }
          proxy.scrollTo(newValue)
        }
        .onExitCommand {
          isPresented = false
        }
      }
    }
  }

  private func moveHighlight(direction: MoveCommandDirection) {
    guard !filteredOptions.isEmpty else { return }

    let currentIndex: Int = {
      if let highlightedCode,
        let idx = filteredOptions.firstIndex(where: {
          $0.code.caseInsensitiveCompare(highlightedCode) == .orderedSame
        })
      {
        return idx
      }
      return 0
    }()

    let nextIndex: Int
    switch direction {
    case .down:
      nextIndex = min(currentIndex + 1, filteredOptions.count - 1)
    case .up:
      nextIndex = max(currentIndex - 1, 0)
    default:
      return
    }

    highlightedCode = filteredOptions[nextIndex].code
  }

  private func commitHighlightedOrFirst() {
    if let highlightedCode,
      let option = filteredOptions.first(where: {
        $0.code.caseInsensitiveCompare(highlightedCode) == .orderedSame
      })
    {
      commit(option: option)
      return
    }

    if let first = filteredOptions.first {
      commit(option: first)
    }
  }

  private func commit(option: LanguageOption) {
    selectedCode = option.code
    highlightedCode = option.code
    isPresented = false
  }
}

struct SearchCommandField: NSViewRepresentable {
  @Binding var text: String
  @Binding var focusToken: UUID
  let onMoveUp: () -> Void
  let onMoveDown: () -> Void
  let onSubmit: () -> Void
  let onEscape: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> NSSearchField {
    let field = NSSearchField(frame: .zero)
    field.placeholderString = "搜索语言"
    field.delegate = context.coordinator
    field.sendsSearchStringImmediately = true
    field.stringValue = text
    context.coordinator.searchField = field
    return field
  }

  func updateNSView(_ nsView: NSSearchField, context: Context) {
    context.coordinator.parent = self
    if nsView.stringValue != text {
      nsView.stringValue = text
    }
    if context.coordinator.lastFocusToken != focusToken {
      context.coordinator.lastFocusToken = focusToken
      DispatchQueue.main.async {
        nsView.window?.makeFirstResponder(nsView)
      }
    }
  }

  @MainActor
  final class Coordinator: NSObject, NSSearchFieldDelegate {
    var parent: SearchCommandField
    weak var searchField: NSSearchField?
    var lastFocusToken: UUID?

    init(parent: SearchCommandField) {
      self.parent = parent
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSSearchField else { return }
      parent.text = field.stringValue
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector)
      -> Bool
    {
      if commandSelector == #selector(NSResponder.moveUp(_:)) {
        parent.onMoveUp()
        return true
      }
      if commandSelector == #selector(NSResponder.moveDown(_:)) {
        parent.onMoveDown()
        return true
      }
      if commandSelector == #selector(NSResponder.insertNewline(_:)) {
        parent.onSubmit()
        return true
      }
      if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
        parent.onEscape()
        return true
      }
      return false
    }
  }
}

struct MenuBarView: View {
  @ObservedObject var state: TranslationAppState

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("辅助功能：\(state.accessibilityStatus.displayName)")
        .font(.caption)
        .foregroundStyle(.secondary)
      Button("打开主面板") {
        state.openOrFocusMainPanel()
      }
      Button("退出") { NSApp.terminate(nil) }
    }
    .padding(12)
    .frame(width: 180)
    .onAppear {
      state.refreshAccessibilityStatus()
    }
  }
}
