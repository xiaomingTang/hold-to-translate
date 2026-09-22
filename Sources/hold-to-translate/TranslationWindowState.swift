struct TranslationWindowState: Equatable {
  var draft: TranslationDraft?
  var isVisible: Bool = false
  var isOutsideClickDismissEnabled: Bool = true
  var isEscToCloseEnabled: Bool = true
  var isPinned: Bool = false

  mutating func show(with text: String) {
    draft = TranslationDraft(originalText: text, translatedText: nil, isTranslating: true)
    isVisible = true
  }

  mutating func beginEditing() {
    guard let draft else { return }
    self.draft = TranslationDraft(
      originalText: draft.originalText,
      translatedText: draft.translatedText,
      isEditing: true,
      editText: draft.originalText
    )
  }

  mutating func commitEditing() {
    guard let draft else { return }
    let editedText = draft.editText.trimmingCharacters(in: .whitespacesAndNewlines)
    self.draft = TranslationDraft(
      originalText: editedText, translatedText: nil, isTranslating: true)
    self.draft?.isEditing = false
  }

  mutating func cancelEditing() {
    guard let draft else { return }
    self.draft = TranslationDraft(
      originalText: draft.originalText,
      translatedText: draft.translatedText,
      isEditing: false,
      editText: draft.originalText
    )
  }

  mutating func closeIfAllowed() {
    guard isVisible, draft?.isEditing != true else { return }
    isVisible = false
    draft = nil
  }

  mutating func beginEditFromOriginal() {
    beginEditing()
  }

  mutating func setTranslatedText(_ text: String) {
    draft?.translatedText = text
    draft?.isTranslating = false
  }

  mutating func setTranslationFailed() {
    draft?.isTranslating = false
  }
}
