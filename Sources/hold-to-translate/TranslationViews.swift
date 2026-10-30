import AppKit
import SwiftUI

struct TranslationWindowView: View {
  @ObservedObject var appState: TranslationAppState
  var body: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 8) {
        if let draft = appState.windowState.draft, appState.windowState.isVisible {
          if draft.isEditing {
            EditingPanel(
              text: Binding(
                get: { appState.windowState.draft?.editText ?? "" },
                set: { appState.windowState.draft?.editText = $0 }))
          } else {
            TranslationDisplayPanel(draft: draft, onBeginEditing: appState.beginEditingOriginal)
          }
        } else {
          Text("尚未捕获选中文本").foregroundStyle(.secondary)
        }
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(minWidth: 420, idealWidth: 480, minHeight: 240, idealHeight: 320, maxHeight: 420)
  }
}

struct TranslationDisplayPanel: View {
  let draft: TranslationDraft
  let onBeginEditing: () -> Void
  @State private var isCopyConfirmed = false
  @State private var copyFeedbackToken = UUID()

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      VStack(alignment: .leading, spacing: 4) {
        Text("原文（双击原文即可编辑）").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        Text(draft.originalText)
          .frame(maxWidth: .infinity, alignment: .leading).padding(8)
          .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(
              Color.accentColor.opacity(0.18), lineWidth: 1)
          )
          .help("双击即可编辑")
      }
      .contentShape(Rectangle()).simultaneousGesture(TapGesture(count: 2).onEnded(onBeginEditing))
      VStack(alignment: .leading, spacing: 4) {
        Text("译文").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 8) {
          if draft.isTranslating { ProgressView("正在翻译").controlSize(.small) }
          if let text = draft.translatedText {
            Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
          } else {
            Text(draft.isTranslating ? "" : "等待翻译结果").foregroundStyle(.secondary)
          }
          if let text = draft.translatedText, !text.isEmpty {
            HStack {
              Spacer()
              Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                isCopyConfirmed = true
                let token = UUID()
                copyFeedbackToken = token
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                  if copyFeedbackToken == token { isCopyConfirmed = false }
                }
              } label: {
                Image(systemName: isCopyConfirmed ? "checkmark.circle.fill" : "doc.on.doc")
              }
              .buttonStyle(.borderless).foregroundStyle(isCopyConfirmed ? .green : .primary)
              .help(isCopyConfirmed ? "复制成功" : "复制译文")
            }
          }
          if !draft.alternatives.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 4) {
              Text("其他释义").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
              ForEach(draft.alternatives) { alternative in
                VStack(alignment: .leading, spacing: 1) {
                  HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if !alternative.posTag.isEmpty {
                      Text(alternative.posTag.lowercased())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(
                          Capsule().fill(Color.secondary.opacity(0.12))
                        )
                    }
                    Text(alternative.displayText).textSelection(.enabled)
                  }
                  if !alternative.backTranslations.isEmpty {
                    Text("回译：" + alternative.backTranslations.joined(separator: "、"))
                      .font(.caption2).foregroundStyle(.tertiary)
                  }
                }
              }
            }
          }
        }
        .padding(8)
        .background(
          Color(nsColor: .textBackgroundColor),
          in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(
            Color.secondary.opacity(0.12), lineWidth: 1))
      }
    }
  }
}

struct EditingPanel: View {
  @Binding var text: String
  @FocusState private var isEditorFocused: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("编辑原文（ESC 取消，Cmd+Enter 提交）").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      TextEditor(text: $text).font(.body).focused($isEditorFocused).frame(minHeight: 176).padding(8)
        .background(
          Color(nsColor: .textBackgroundColor),
          in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(
            Color.accentColor.opacity(0.2), lineWidth: 1)
        )
        .onAppear { DispatchQueue.main.async { isEditorFocused = true } }
    }
  }
}

struct SearchableLanguageDropdown: View {
  let options: [LanguageOption]
  @Binding var selectedCode: String
  @State private var isPresented = false
  @State private var query = ""
  @State private var highlightedCode: String?
  @State private var focusSearchFieldToken = UUID()

  private var selectedLabel: String {
    options.first { $0.code.caseInsensitiveCompare(selectedCode) == .orderedSame }?.displayLabel
      ?? selectedCode
  }
  private var filteredOptions: [LanguageOption] {
    let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return keyword.isEmpty
      ? options
      : options.filter {
        $0.code.lowercased().contains(keyword) || $0.name.lowercased().contains(keyword)
          || $0.displayLabel.lowercased().contains(keyword)
      }
  }

  var body: some View {
    Button {
      if !isPresented {
        query = ""
        highlightedCode = selectedCode
      }
      isPresented.toggle()
    } label: {
      HStack {
        Text(selectedLabel).lineLimit(1)
        Spacer()
        Image(systemName: "chevron.down").foregroundStyle(.secondary)
      }
      .padding(.horizontal, 8).padding(.vertical, 5)
      .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
      .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.25)))
    }
    .buttonStyle(.plain)
    .popover(isPresented: $isPresented) {
      ScrollViewReader { proxy in
        VStack(spacing: 8) {
          SearchCommandField(
            text: $query, focusToken: $focusSearchFieldToken, onMoveUp: { moveHighlight(-1) },
            onMoveDown: { moveHighlight(1) }, onSubmit: commitHighlightedOrFirst,
            onEscape: { isPresented = false }
          )
          .frame(height: 24)
          ScrollView {
            LazyVStack(spacing: 0) {
              ForEach(filteredOptions) { option in
                Button {
                  commit(option)
                } label: {
                  HStack {
                    Text(option.displayLabel)
                    Spacer()
                    if option.code.caseInsensitiveCompare(selectedCode) == .orderedSame {
                      Image(systemName: "checkmark")
                    }
                  }
                  .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                  .background(
                    option.code.caseInsensitiveCompare(highlightedCode ?? "") == .orderedSame
                      ? Color.accentColor.opacity(0.15) : .clear)
                }.buttonStyle(.plain).id(option.code)
              }
            }
          }.frame(height: 220)
        }
        .padding(10).frame(width: 300)
        .onAppear {
          highlightedCode = highlightedCode ?? selectedCode
          focusSearchFieldToken = UUID()
          if let code = highlightedCode { proxy.scrollTo(code) }
        }
        .onChange(of: query) { _, _ in
          if !filteredOptions.contains(where: { $0.code == highlightedCode }) {
            highlightedCode = filteredOptions.first?.code
          }
        }
        .onChange(of: highlightedCode) { _, code in if let code { proxy.scrollTo(code) } }
        .onExitCommand { isPresented = false }
      }
    }
  }

  private func moveHighlight(_ offset: Int) {
    guard !filteredOptions.isEmpty else { return }
    let index =
      filteredOptions.firstIndex {
        $0.code.caseInsensitiveCompare(highlightedCode ?? "") == .orderedSame
      } ?? 0
    highlightedCode = filteredOptions[max(0, min(filteredOptions.count - 1, index + offset))].code
  }
  private func commitHighlightedOrFirst() {
    commit(filteredOptions.first { $0.code == highlightedCode } ?? filteredOptions.first)
  }
  private func commit(_ option: LanguageOption?) {
    guard let option else { return }
    selectedCode = option.code
    highlightedCode = option.code
    isPresented = false
  }
}
