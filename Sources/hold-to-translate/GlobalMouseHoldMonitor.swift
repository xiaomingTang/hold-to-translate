import AppKit

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
    if let monitor = NSEvent.addGlobalMonitorForEvents(
      matching: downEvents,
      handler: { [weak self] event in
        self?.handle(event: event, isMouseDown: true)
      })
    {
      monitors.append(monitor)
    }
    if let monitor = NSEvent.addLocalMonitorForEvents(
      matching: downEvents,
      handler: { [weak self] event in
        self?.handle(event: event, isMouseDown: true)
        return event
      })
    {
      monitors.append(monitor)
    }
    if let monitor = NSEvent.addGlobalMonitorForEvents(
      matching: upEvents,
      handler: { [weak self] event in
        self?.handle(event: event, isMouseDown: false)
      })
    {
      monitors.append(monitor)
    }
    if let monitor = NSEvent.addLocalMonitorForEvents(
      matching: upEvents,
      handler: { [weak self] event in
        self?.handle(event: event, isMouseDown: false)
        return event
      })
    {
      monitors.append(monitor)
    }
  }

  func stop() {
    cancelPendingTrigger()
    cancelSafetyReset()
    monitors.forEach { NSEvent.removeMonitor($0) }
    monitors.removeAll()
  }

  private func handle(event: NSEvent, isMouseDown: Bool) {
    guard matchesConfiguredButton(event: event) else { return }
    if isMouseDown {
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

  func shouldInvokePressBeganHook() -> Bool { true }
  func effectiveHoldDuration() -> TimeInterval { minimumHoldDuration }

  private func matchesConfiguredButton(event: NSEvent) -> Bool {
    switch triggerButton {
    case .left: return event.type == .leftMouseDown || event.type == .leftMouseUp
    case .right: return event.type == .rightMouseDown || event.type == .rightMouseUp
    case .middle:
      return (event.type == .otherMouseDown || event.type == .otherMouseUp)
        && event.buttonNumber == 2
    }
  }

  private func scheduleTriggerIfNeeded() {
    cancelPendingTrigger()
    guard !hasTriggeredCurrentPress else { return }
    let workItem = DispatchWorkItem { [weak self] in
      guard let self, self.isConfiguredButtonCurrentlyPressed() else { return }
      self.hasTriggeredCurrentPress = true
      self.onTriggered?()
    }
    pendingWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + effectiveHoldDuration(), execute: workItem)
  }

  private func scheduleSafetyReset() {
    cancelSafetyReset()
    let workItem = DispatchWorkItem { [weak self] in
      self?.cancelPendingTrigger()
      self?.hasTriggeredCurrentPress = false
    }
    safetyResetWorkItem = workItem
    DispatchQueue.main.asyncAfter(
      deadline: .now() + max(2.5, minimumHoldDuration * 4), execute: workItem)
  }

  private func cancelSafetyReset() {
    safetyResetWorkItem?.cancel()
    safetyResetWorkItem = nil
  }

  private func cancelPendingTrigger() {
    pendingWorkItem?.cancel()
    pendingWorkItem = nil
  }

  private func isConfiguredButtonCurrentlyPressed() -> Bool {
    let button: CGMouseButton
    switch triggerButton {
    case .left: button = .left
    case .right: button = .right
    case .middle: button = CGMouseButton(rawValue: 2) ?? .center
    }
    return CGEventSource.buttonState(.combinedSessionState, button: button)
  }
}
