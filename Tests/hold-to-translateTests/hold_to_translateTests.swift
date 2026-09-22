import AppKit
import XCTest

@testable import hold_to_translate

final class LongPressSelectionTests: XCTestCase {
  @MainActor
  func testRightLongPressAllowsClipboardFallbackWhenPreCaptureFails() {
    var readCount = 0
    let result = TranslationAppState.readSelectionForLongPress(
      triggerButton: .right, preCapturedSelection: nil
    ) { includeClipboardFallback in
      readCount += 1
      XCTAssertTrue(includeClipboardFallback)
      return includeClipboardFallback ? .success("Selected text") : .failure("No AX selection")
    }

    guard case .success(let text) = result else {
      return XCTFail("Confirmed right-button hold must allow clipboard fallback")
    }
    XCTAssertEqual(text, "Selected text")
    XCTAssertEqual(readCount, 1)
  }

  @MainActor
  func testRightLongPressPrefersPreCapturedSelectionWithoutCopying() {
    let result = TranslationAppState.readSelectionForLongPress(
      triggerButton: .right, preCapturedSelection: "Original selection"
    ) { _ in
      XCTFail("A captured selection must not trigger another read or copy")
      return .failure("Unexpected read")
    }

    guard case .success(let text) = result else {
      return XCTFail("Expected the pre-captured selection")
    }
    XCTAssertEqual(text, "Original selection")
  }

  @MainActor
  func testMissingSelectionStillReturnsFailure() {
    let result = TranslationAppState.readSelectionForLongPress(
      triggerButton: .right, preCapturedSelection: nil
    ) { _ in .failure("No selection") }

    guard case .failure(let reason) = result else {
      return XCTFail("An empty selection must not open a translation panel")
    }
    XCTAssertEqual(reason, "No selection")
  }

  @MainActor
  func testOtherButtonsRetainLiveReadAndPreCaptureFallback() {
    for button in [TriggerButton.left, .middle] {
      let result = TranslationAppState.readSelectionForLongPress(
        triggerButton: button, preCapturedSelection: "Original selection"
      ) { includeClipboardFallback in
        XCTAssertTrue(includeClipboardFallback)
        return .failure("No live selection")
      }

      guard case .success(let text) = result else {
        return XCTFail("Expected the pre-captured selection after a failed live read")
      }
      XCTAssertEqual(text, "Original selection")
    }
  }
}

final class MainPanelLifecycleTests: XCTestCase {
  @MainActor
  func testMainPanelCanReopenAfterClosing() throws {
    let application = NSApplication.shared
    let originalPolicy = application.activationPolicy()
    let originalMenu = application.mainMenu
    let existingWindows = Set(application.windows.map(ObjectIdentifier.init))
    let delegate = AppDelegate()
    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification, object: application))
    let startupCompleted = expectation(description: "Initial main panel presentation completed")
    DispatchQueue.main.async { startupCompleted.fulfill() }
    wait(for: [startupCompleted], timeout: 2)

    let window = try XCTUnwrap(
      application.windows.first { $0.title == "Hold to Translate" })
    defer {
      window.orderOut(nil)
      application.setActivationPolicy(originalPolicy)
      application.mainMenu = originalMenu
    }
    let state = try XCTUnwrap(TranslationAppState.shared)
    let newWindows = application.windows.filter {
      !existingWindows.contains(ObjectIdentifier($0)) && $0.styleMask.contains(.titled)
    }
    XCTAssertEqual(newWindows.count, 1)
    XCTAssertTrue(newWindows.first === window)
    let editMenu = try XCTUnwrap(application.mainMenu?.items.last?.submenu)
    XCTAssertTrue(editMenu.items.contains { $0.action == #selector(NSText.copy(_:)) })
    XCTAssertTrue(editMenu.items.contains { $0.action == #selector(NSText.paste(_:)) })

    for _ in 0..<3 {
      XCTAssertTrue(window.isVisible)
      XCTAssertEqual(application.activationPolicy(), .regular)

      window.performClose(nil)
      XCTAssertFalse(window.isVisible)
      XCTAssertEqual(application.activationPolicy(), .accessory)

      state.openOrFocusMainPanel()
      XCTAssertTrue(window.isVisible)
      XCTAssertEqual(application.activationPolicy(), .regular)
      XCTAssertEqual(
        application.windows.filter { $0.title == "Hold to Translate" && $0.isVisible }.count, 1)
    }

    let miniaturized = XCTNSNotificationExpectation(
      name: NSWindow.didMiniaturizeNotification, object: window)
    window.miniaturize(nil)
    wait(for: [miniaturized], timeout: 5)
    XCTAssertTrue(window.isMiniaturized)
    let restored = XCTNSNotificationExpectation(
      name: NSWindow.didDeminiaturizeNotification, object: window)
    state.openOrFocusMainPanel()
    wait(for: [restored], timeout: 5)
    XCTAssertFalse(window.isMiniaturized)
    XCTAssertTrue(window.isVisible)

    window.performClose(nil)
    XCTAssertFalse(delegate.applicationShouldHandleReopen(application, hasVisibleWindows: false))
    XCTAssertTrue(window.isVisible)
    XCTAssertEqual(application.activationPolicy(), .regular)
    XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(application))
  }
}

@discardableResult
func runHoldToTranslateSelfChecks() -> Bool {
  let rightMonitor = GlobalMouseHoldMonitor()
  rightMonitor.configure(triggerButton: .right, minimumHoldDuration: 0.2)

  let leftMonitor = GlobalMouseHoldMonitor()
  leftMonitor.configure(triggerButton: .left, minimumHoldDuration: 0.2)

  return rightMonitor.effectiveHoldDuration() == 0.2
    && leftMonitor.effectiveHoldDuration() == 0.2
}
