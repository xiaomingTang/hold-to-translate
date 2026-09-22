import AppKit

extension Notification.Name {
  static let requestOpenMainPanel = Notification.Name("requestOpenMainPanel")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var appState: TranslationAppState?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    configureMainMenu()
    appState = TranslationAppState()
  }

  private func configureMainMenu() {
    let mainMenu = NSMenu()
    let applicationItem = NSMenuItem()
    let applicationMenu = NSMenu(title: "Hold to Translate")
    applicationItem.submenu = applicationMenu
    mainMenu.addItem(applicationItem)

    let openItem = applicationMenu.addItem(
      withTitle: "Open Main Panel", action: #selector(openMainPanel), keyEquivalent: ",")
    openItem.target = self
    applicationMenu.addItem(.separator())
    applicationMenu.addItem(
      withTitle: "Hide Hold to Translate", action: #selector(NSApplication.hide(_:)),
      keyEquivalent: "h")
    applicationMenu.addItem(
      withTitle: "Quit Hold to Translate", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")

    let editItem = NSMenuItem()
    let editMenu = NSMenu(title: "Edit")
    editItem.submenu = editMenu
    mainMenu.addItem(editItem)
    editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    let redoItem = editMenu.addItem(
      withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
    redoItem.keyEquivalentModifierMask = [.command, .shift]
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(
      withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    NSApp.mainMenu = mainMenu
  }

  @objc private func openMainPanel() {
    appState?.openOrFocusMainPanel()
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
