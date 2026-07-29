import XCTest

@testable import hold_to_translate

final class hold_to_translateTests: XCTestCase {
  func testRightClickStillInvokesEarlyPressBeganHook() {
    let monitor = GlobalMouseHoldMonitor()
    monitor.configure(triggerButton: .right, minimumHoldDuration: 0.45)

    XCTAssertTrue(monitor.shouldInvokePressBeganHook())
  }

  func testLeftClickStillInvokesEarlyPressBeganHook() {
    let monitor = GlobalMouseHoldMonitor()
    monitor.configure(triggerButton: .left, minimumHoldDuration: 0.45)

    XCTAssertTrue(monitor.shouldInvokePressBeganHook())
  }
}
