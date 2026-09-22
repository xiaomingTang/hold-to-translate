import AppKit
import SwiftUI

private final class MainPanelWindow: NSWindow {
  var onCommandW: (() -> Void)?

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.keyCode == 13 && event.modifierFlags.contains(.command) {
      onCommandW?()
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
}

final class MainPanelController: NSWindowController, NSWindowDelegate {
  private unowned let appState: TranslationAppState

  init(appState: TranslationAppState) {
    self.appState = appState

    let hostingView = NSHostingView(rootView: LaunchControlView(state: appState))
    let window = MainPanelWindow(
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 550),
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
    window.onCommandW = { [weak self, weak window] in
      guard let self, let window else { return }
      _ = self.windowShouldClose(window)
    }
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

    center(window: window, on: activeScreen())

    NSApp.setActivationPolicy(.regular)
    NSApp.unhide(nil)
    NSRunningApplication.current.activate(options: [.activateAllWindows])
    NSApp.activate(ignoringOtherApps: true)
    window.orderFrontRegardless()
    window.makeKeyAndOrderFront(nil)
  }

  private func activeScreen() -> NSScreen? {
    let mouseLocation = NSEvent.mouseLocation
    if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
    {
      return screen
    }
    return NSScreen.main ?? NSScreen.screens.first
  }

  private func center(window: NSWindow, on screen: NSScreen?) {
    let visibleFrame =
      screen?.visibleFrame ?? NSScreen.main?.visibleFrame
      ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let frame = window.frame

    let originX = visibleFrame.minX + (visibleFrame.width - frame.width) / 2
    let originY = visibleFrame.minY + (visibleFrame.height - frame.height) / 2

    window.setFrameOrigin(NSPoint(x: originX, y: originY))
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
