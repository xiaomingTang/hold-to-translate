import Foundation

@discardableResult
func runHoldToTranslateSelfChecks() -> Bool {
  let rightMonitor = GlobalMouseHoldMonitor()
  rightMonitor.configure(triggerButton: .right, minimumHoldDuration: 0.2)

  let leftMonitor = GlobalMouseHoldMonitor()
  leftMonitor.configure(triggerButton: .left, minimumHoldDuration: 0.2)

  return rightMonitor.effectiveHoldDuration() == 0.2
    && leftMonitor.effectiveHoldDuration() == 0.2
}
