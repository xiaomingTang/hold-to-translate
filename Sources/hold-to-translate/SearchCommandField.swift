import AppKit
import SwiftUI

struct SearchCommandField: NSViewRepresentable {
  @Binding var text: String
  @Binding var focusToken: UUID
  let onMoveUp: () -> Void
  let onMoveDown: () -> Void
  let onSubmit: () -> Void
  let onEscape: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

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
    if nsView.stringValue != text { nsView.stringValue = text }
    if context.coordinator.lastFocusToken != focusToken {
      context.coordinator.lastFocusToken = focusToken
      DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
    }
  }

  @MainActor
  final class Coordinator: NSObject, NSSearchFieldDelegate {
    var parent: SearchCommandField
    weak var searchField: NSSearchField?
    var lastFocusToken: UUID?

    init(parent: SearchCommandField) { self.parent = parent }

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
