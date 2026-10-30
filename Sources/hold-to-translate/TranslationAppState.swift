import AppKit
import Combine
import ServiceManagement

@MainActor
final class TranslationAppState: NSObject, ObservableObject {
  static weak var shared: TranslationAppState?

  @Published var settings = TranslationSettings() {
    didSet {
      holdMonitor.configure(
        triggerButton: settings.triggerButton,
        minimumHoldDuration: settings.longPressMilliseconds / 1000)
      settingsStore.saveSettings(settings)
    }
  }
  @Published var apiKey = "" {
    didSet { if shouldPersistApiKey { keychainStore.saveApiKey(apiKey) } }
  }
  @Published var windowState = TranslationWindowState()
  @Published var accessibilityStatus: AccessibilityStatus
  @Published var lastTriggerStatusMessage = "等待触发"
  @Published var loginAtLaunchEnabled = false

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
    translationCache: TranslationCache = .init(), settingsStore: SettingsStore = .init(),
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
    holdMonitor.configure(
      triggerButton: settings.triggerButton,
      minimumHoldDuration: settings.longPressMilliseconds / 1000)
    holdMonitor.onTriggered = { [weak self] in Task { @MainActor in self?.handleLongPressTrigger() }
    }
    holdMonitor.onPressBegan = { [weak self] in
      Task { @MainActor in self?.captureSelectionOnPressBegan() }
    }
    NotificationCenter.default.addObserver(
      self, selector: #selector(handleRequestOpenMainPanelNotification),
      name: .requestOpenMainPanel, object: nil)
    holdMonitor.start()
    loginAtLaunchEnabled = isLoginItemEnabled()
    statusItemController = StatusItemController(appState: self)
    DispatchQueue.main.async { [weak self] in self?.openOrFocusMainPanel() }
  }

  deinit {
    NotificationCenter.default.removeObserver(self, name: .requestOpenMainPanel, object: nil)
  }

  @objc private func handleRequestOpenMainPanelNotification() { openOrFocusMainPanel() }

  func openOrFocusMainPanel() {
    if mainPanelController == nil {
      mainPanelController = MainPanelController(appState: self)
    }
    mainPanelController?.showAndFocus()
  }

  var statusBarIcon: NSImage {
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size)
    image.lockFocus()
    let bounds = NSRect(origin: .zero, size: size).insetBy(dx: 2.2, dy: 2.2)
    NSColor.black.setStroke()
    let outer = NSBezierPath(ovalIn: bounds)
    outer.lineWidth = 1.6
    outer.stroke()
    let horizontal = NSBezierPath()
    horizontal.lineWidth = 1.2
    horizontal.move(to: NSPoint(x: bounds.minX + 1, y: bounds.midY))
    horizontal.line(to: NSPoint(x: bounds.maxX - 1, y: bounds.midY))
    horizontal.stroke()
    let vertical = NSBezierPath()
    vertical.lineWidth = 1.2
    vertical.move(to: NSPoint(x: bounds.midX, y: bounds.minY + 1))
    vertical.line(to: NSPoint(x: bounds.midX, y: bounds.maxY - 1))
    vertical.stroke()
    image.unlockFocus()
    image.isTemplate = true
    return image
  }

  func refreshLoginItemStatus() { loginAtLaunchEnabled = isLoginItemEnabled() }

  func setLoginAtLaunchEnabled(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
        lastTriggerStatusMessage = "已开启开机自启动"
      } else {
        try SMAppService.mainApp.unregister()
        lastTriggerStatusMessage = "已关闭开机自启动"
      }
      loginAtLaunchEnabled = isLoginItemEnabled()
    } catch {
      loginAtLaunchEnabled = isLoginItemEnabled()
      presentInfoAlert(title: "开机自启动设置失败", message: error.localizedDescription)
    }
  }

  func requestAccessibilityAccess(prompt: Bool = true) {
    let granted = permissionService.requestAccess(prompt: prompt)
    accessibilityStatus = granted ? .granted : .denied
    lastTriggerStatusMessage = granted ? "辅助功能权限已授权" : "辅助功能权限未授权"
  }

  func refreshAccessibilityStatus() {
    accessibilityStatus = permissionService.currentStatus()
    lastTriggerStatusMessage = accessibilityStatus == .granted ? "辅助功能权限已授权" : "请先授权辅助功能权限"
  }

  func recheckAccessibilityStatus() { refreshAccessibilityStatus() }
  func openAccessibilitySettings() { permissionService.openSystemSettings() }
  func beginEditingOriginal() { windowState.beginEditFromOriginal() }
  func cancelEditing() { windowState.cancelEditing() }

  func submitEditedOriginal(_ text: String) {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      cancelEditing()
      return
    }
    windowState.draft?.editText = text
    windowState.commitEditing()
    startTranslation(for: text)
  }

  func closeTranslationWindowIfAllowed() {
    let wasVisible = windowState.isVisible
    windowState.closeIfAllowed()
    pinnedEscapeFirstPressedAt = nil
    if wasVisible, !windowState.isVisible { panelController?.hide() }
  }

  func handleEscapeRequest() -> Bool {
    if isCurrentTextCompositionActive() { return false }
    if windowState.isPinned {
      let now = Date()
      if let first = pinnedEscapeFirstPressedAt, now.timeIntervalSince(first) <= 0.45 {
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

  func simulateTriggerForCurrentSelection() { handleLongPressTrigger() }

  private func handleLongPressTrigger() {
    guard !shouldIgnoreTriggerForInternalAppInteraction() else { return }
    guard permissionService.currentStatus() == .granted else {
      accessibilityStatus = .denied
      lastTriggerStatusMessage = "触发失败：缺少辅助功能权限"
      presentPermissionAlert()
      return
    }
    accessibilityStatus = .granted
    lastTriggerStatusMessage = "已触发，正在读取选中文本"
    let selectedText: String
    switch Self.readSelectionForLongPress(
      triggerButton: settings.triggerButton,
      preCapturedSelection: currentPreCapturedSelection(),
      readSelectedText: { self.selectionReader.readSelectedText(includeClipboardFallback: $0) })
    {
    case .success(let text): selectedText = text
    case .failure(let reason):
      lastTriggerStatusMessage = "触发已忽略：\(reason)"
      return
    }
    let count = selectedText.count
    if count > settings.thresholds.hardLimit {
      lastTriggerStatusMessage = "触发失败：文本超过拒绝阈值"
      presentInfoAlert(
        title: "文本过长",
        message: translationHardLimitMessage(
          characterCount: count, limit: settings.thresholds.hardLimit))
      return
    }
    if count > settings.thresholds.warnLimit
      && !presentConfirmationAlert(
        title: "是否继续翻译", message: translationWarningMessage(characterCount: count),
        confirmTitle: "继续翻译", cancelTitle: "取消")
    {
      lastTriggerStatusMessage = "已取消：长文本翻译"
      return
    }
    windowState.show(with: selectedText)
    let panel = ensurePanelController()
    panel.showNearCursor(activateApp: settings.triggerButton != .right, makeKey: false)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      panel.window?.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
    lastTriggerStatusMessage = "已触发翻译请求"
    startTranslation(for: selectedText)
  }

  static func readSelectionForLongPress(
    triggerButton: TriggerButton, preCapturedSelection: String?,
    readSelectedText: (Bool) -> SelectionReadResult
  ) -> SelectionReadResult {
    if triggerButton == .right, let preCapturedSelection {
      return .success(preCapturedSelection)
    }
    let result = readSelectedText(true)
    if case .failure = result, let preCapturedSelection {
      return .success(preCapturedSelection)
    }
    return result
  }

  private func captureSelectionOnPressBegan() {
    guard !shouldIgnoreTriggerForInternalAppInteraction(),
      permissionService.currentStatus() == .granted
    else { return }
    switch selectionReader.readSelectedText(includeClipboardFallback: false) {
    case .success(let text):
      preCapturedSelection = text
      preCaptureAt = Date()
    case .failure:
      preCapturedSelection = nil
      preCaptureAt = nil
    }
  }

  private func currentPreCapturedSelection() -> String? {
    guard let text = preCapturedSelection, let date = preCaptureAt else { return nil }
    guard Date().timeIntervalSince(date) <= max(1.5, settings.longPressMilliseconds / 1000 + 0.8)
    else {
      preCapturedSelection = nil
      preCaptureAt = nil
      return nil
    }
    return text
  }

  private func isCurrentTextCompositionActive() -> Bool {
    (panelController?.window?.firstResponder as? NSTextView)?.hasMarkedText() == true
  }

  private func shouldIgnoreTriggerForInternalAppInteraction() -> Bool {
    if statusItemController?.isMenuOpen == true { return true }
    let ownWindow = NSApp.windows.contains { $0.isVisible && $0.isKeyWindow }
    if NSApp.isActive
      && (panelController?.window?.isVisible == true
        || mainPanelController?.window?.isVisible == true || ownWindow)
    {
      return true
    }
    return NSWorkspace.shared.frontmostApplication?.processIdentifier
      == ProcessInfo.processInfo.processIdentifier
  }

  private func ensurePanelController() -> TranslationPanelController {
    if let panelController, panelController.window != nil { return panelController }
    let controller = TranslationPanelController(appState: self)
    panelController = controller
    return controller
  }

  private func isLoginItemEnabled() -> Bool { SMAppService.mainApp.status == .enabled }

  private func startTranslation(for text: String) {
    let target = resolvedTargetLanguage(for: text)
    let key = target + "::" + text.normalizedCacheKey()
    if let cached = translationCache.value(for: key) {
      windowState.setTranslatedText(cached.translatedText, alternatives: cached.alternatives)
      lastTriggerStatusMessage = "命中缓存，已展示译文"
      return
    }
    windowState.draft?.isTranslating = true
    Task { @MainActor in
      do {
        let result = try await translationService.translate(
          text: text, settings: settings, apiKey: effectiveApiKey(), targetLanguageOverride: target)
        translationCache.insert(result, for: key)
        guard windowState.draft?.originalText == text else { return }
        windowState.setTranslatedText(result.translatedText, alternatives: result.alternatives)
        lastTriggerStatusMessage = "翻译完成"
      } catch {
        windowState.setTranslationFailed()
        lastTriggerStatusMessage = "翻译失败：\(error.localizedDescription)"
        presentInfoAlert(title: "翻译失败", message: error.localizedDescription)
      }
    }
  }

  private func resolvedTargetLanguage(for text: String) -> String {
    let primary = normalizedLanguageCode(settings.targetLanguage, fallback: "zh-Hans")
    let alternate = normalizedLanguageCode(settings.alternateLanguage, fallback: "en")
    return primary.caseInsensitiveCompare(alternate) == .orderedSame
      ? primary
      : (primary.lowercased().hasPrefix("zh") && text.containsHanScript() ? alternate : primary)
  }

  private func normalizedLanguageCode(_ raw: String, fallback: String) -> String {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return fallback }
    return supportedLanguageOptions.first {
      $0.code.caseInsensitiveCompare(value) == .orderedSame
        || $0.name.caseInsensitiveCompare(value) == .orderedSame
        || $0.displayLabel.caseInsensitiveCompare(value) == .orderedSame
    }?.code ?? value
  }

  private func effectiveApiKey() -> String {
    let current = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    if !current.isEmpty { return current }
    let stored = keychainStore.loadApiKey().trimmingCharacters(in: .whitespacesAndNewlines)
    if !stored.isEmpty {
      shouldPersistApiKey = false
      apiKey = stored
      shouldPersistApiKey = true
    }
    return stored
  }

  private func presentPermissionAlert() {
    if presentConfirmationAlert(
      title: "需要辅助功能权限", message: "当前版本仅通过辅助功能读取选中文本。请先授权后再使用。", confirmTitle: "打开系统设置",
      cancelTitle: "稍后再说")
    {
      openAccessibilitySettings()
    }
  }

  private func presentInfoAlert(title: String, message: String, secondaryTitle: String? = "关闭") {
    _ = presentModalAlert(
      title: title, message: message, style: .informational, primaryTitle: "知道了",
      secondaryTitle: secondaryTitle)
  }

  private func presentConfirmationAlert(
    title: String, message: String, confirmTitle: String, cancelTitle: String
  ) -> Bool {
    presentModalAlert(
      title: title, message: message, style: .warning, primaryTitle: confirmTitle,
      secondaryTitle: cancelTitle) == .alertFirstButtonReturn
  }

  private func presentModalAlert(
    title: String, message: String, style: NSAlert.Style, primaryTitle: String,
    secondaryTitle: String?
  ) -> NSApplication.ModalResponse {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = style
    alert.messageText = title
    alert.informativeText = message
    _ = alert.addButton(withTitle: primaryTitle)
    if let secondaryTitle {
      let secondary = alert.addButton(withTitle: secondaryTitle)
      secondary.keyEquivalent = "\u{1b}"
    }
    alert.window.level = .modalPanel
    alert.window.collectionBehavior.insert(.canJoinAllSpaces)
    alert.window.collectionBehavior.insert(.fullScreenAuxiliary)
    alert.window.makeKeyAndOrderFront(nil)
    return alert.runModal()
  }
}
