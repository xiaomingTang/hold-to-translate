import AppKit
import SwiftUI

struct MenuBarView: View {
  @ObservedObject var state: TranslationAppState

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("辅助功能：\(state.accessibilityStatus.displayName)")
        .font(.caption)
        .foregroundStyle(.secondary)
      Button("打开主面板") { state.openOrFocusMainPanel() }
      Button("退出") { NSApp.terminate(nil) }
    }
    .padding(12)
    .frame(width: 180)
    .onAppear { state.refreshAccessibilityStatus() }
  }
}
