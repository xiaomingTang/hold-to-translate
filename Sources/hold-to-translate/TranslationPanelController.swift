import AppKit
import SwiftUI

final class TranslationPanelController: NSWindowController, NSWindowDelegate {
  private unowned let appState: TranslationAppState
  private var outsideClickMonitor: Any?
  private var keyMonitor: Any?
  private let pinButton = NSButton()

  init(appState: TranslationAppState) {
    self.appState = appState
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 220), styleMask: [.titled],
      backing: .buffered, defer: false)
    panel.titleVisibility = .hidden
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
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func showNearCursor(activateApp: Bool = true, makeKey: Bool = true) {
    if !Thread.isMainThread {
      DispatchQueue.main.async { [weak self] in
        self?.showNearCursor(activateApp: activateApp, makeKey: makeKey)
      }
      return
    }
    guard let window else { return }
    applyPinning(to: window)
    position(window: window, near: NSEvent.mouseLocation)
    if activateApp {
      NSApp.unhide(nil)
      NSRunningApplication.current.activate(options: [.activateAllWindows])
      NSApp.activate(ignoringOtherApps: true)
    }
    window.orderFrontRegardless()
    if makeKey { window.makeKeyAndOrderFront(nil) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
      self.applyPinning(to: window)
      if activateApp { NSRunningApplication.current.activate(options: [.activateAllWindows]) }
      window.orderFrontRegardless()
      if makeKey { window.makeKeyAndOrderFront(nil) }
    }
    installDismissMonitors()
  }

  func hide() {
    tearDownDismissMonitors()
    window?.orderOut(nil)
  }
  func windowWillClose(_ notification: Notification) { tearDownDismissMonitors() }

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
      accessibilityDescription: pinned ? "取消钉住" : "钉住面板")
    pinButton.contentTintColor = .labelColor
    pinButton.toolTip = pinned ? "取消钉住" : "钉住面板"
  }

  @objc private func handlePinButtonTap() { appState.togglePinned() }

  private func position(window: NSWindow, near point: CGPoint) {
    let frame = window.frame
    let screen =
      NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main
    let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let x = min(max(point.x + 14, visible.minX + 12), visible.maxX - frame.width - 12)
    let y = max(
      visible.minY + 12, min(point.y - frame.height - 18, visible.maxY - frame.height - 12))
    window.setFrameOrigin(NSPoint(x: x, y: y))
  }

  private func installDismissMonitors() {
    tearDownDismissMonitors()
    outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
      .leftMouseDown, .rightMouseDown, .otherMouseDown,
    ]) { [weak self] _ in
      let point = NSEvent.mouseLocation
      Task { @MainActor in self?.handleOutsideInteraction(at: point) }
    }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
      self?.handleKeyDown(event: event) ?? event
    }
  }

  private func tearDownDismissMonitors() {
    if let monitor = outsideClickMonitor {
      NSEvent.removeMonitor(monitor)
      outsideClickMonitor = nil
    }
    if let monitor = keyMonitor {
      NSEvent.removeMonitor(monitor)
      keyMonitor = nil
    }
  }

  @MainActor private func handleOutsideInteraction(at point: NSPoint) {
    guard appState.windowState.isOutsideClickDismissEnabled, !appState.windowState.isPinned else {
      return
    }
    guard let window, !window.frame.contains(point) else { return }
    appState.closeTranslationWindowIfAllowed()
  }

  private func handleKeyDown(event: NSEvent) -> NSEvent? {
    let escape = event.keyCode == 53
    let commandEnter =
      (event.keyCode == 36 || event.keyCode == 76) && event.modifierFlags.contains(.command)
    let commandW = event.keyCode == 13 && event.modifierFlags.contains(.command)
    if commandW {
      appState.closeTranslationWindowIfAllowed()
      return nil
    }
    if appState.windowState.draft?.isEditing == true {
      if let textView = window?.firstResponder as? NSTextView, textView.hasMarkedText() {
        return event
      }
      if escape {
        appState.cancelEditing()
        return nil
      }
      if commandEnter {
        let text =
          (window?.firstResponder as? NSTextView)?.string ?? appState.windowState.draft?.editText
          ?? ""
        appState.submitEditedOriginal(text)
        return nil
      }
    }
    if escape, appState.handleEscapeRequest() { return nil }
    return event
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    appState.closeTranslationWindowIfAllowed()
    return false
  }
}
