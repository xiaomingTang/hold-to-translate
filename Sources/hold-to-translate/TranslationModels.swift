import Foundation

enum TriggerButton: String, CaseIterable, Codable, Identifiable {
  case left
  case middle
  case right

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .left:
      return "左键"
    case .right:
      return "右键"
    case .middle:
      return "中键"
    }
  }
}

struct TranslationThresholds: Codable, Equatable {
  var warnLimit: Int = 2000
  var hardLimit: Int = 5000
}

struct TranslationSettings: Codable, Equatable {
  var endpoint: String = ""
  var region: String = ""
  var targetLanguage: String = "zh-Hans"
  var alternateLanguage: String = "en"
  var triggerButton: TriggerButton = .right
  var longPressMilliseconds: Double = 450
  var thresholds: TranslationThresholds = .init()

  enum CodingKeys: String, CodingKey {
    case endpoint
    case region
    case targetLanguage
    case alternateLanguage
    case triggerButton
    case longPressMilliseconds
    case thresholds
  }

  init() {}

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
    region = try container.decodeIfPresent(String.self, forKey: .region) ?? ""
    targetLanguage =
      try container.decodeIfPresent(String.self, forKey: .targetLanguage) ?? "zh-Hans"
    alternateLanguage =
      try container.decodeIfPresent(String.self, forKey: .alternateLanguage) ?? "en"
    triggerButton =
      try container.decodeIfPresent(TriggerButton.self, forKey: .triggerButton) ?? .right
    longPressMilliseconds =
      try container.decodeIfPresent(Double.self, forKey: .longPressMilliseconds) ?? 450
    thresholds =
      try container.decodeIfPresent(TranslationThresholds.self, forKey: .thresholds) ?? .init()
  }
}

struct LanguageOption: Identifiable, Hashable {
  let code: String
  let name: String

  var id: String { code }
  var displayLabel: String { "\(name) (\(code))" }
}

let supportedLanguageOptions: [LanguageOption] = [
  .init(code: "zh-Hans", name: "简体中文"),
  .init(code: "zh-Hant", name: "繁體中文"),
  .init(code: "en", name: "English"),
  .init(code: "ja", name: "日本語"),
  .init(code: "ko", name: "한국어"),
  .init(code: "fr", name: "Français"),
  .init(code: "de", name: "Deutsch"),
  .init(code: "es", name: "Español"),
  .init(code: "it", name: "Italiano"),
  .init(code: "pt", name: "Português"),
  .init(code: "pt-BR", name: "Português (Brasil)"),
  .init(code: "ru", name: "Русский"),
  .init(code: "ar", name: "العربية"),
  .init(code: "hi", name: "हिन्दी"),
  .init(code: "th", name: "ไทย"),
  .init(code: "vi", name: "Tiếng Việt"),
  .init(code: "id", name: "Bahasa Indonesia"),
  .init(code: "tr", name: "Türkçe"),
  .init(code: "nl", name: "Nederlands"),
  .init(code: "pl", name: "Polski"),
  .init(code: "cs", name: "Čeština"),
  .init(code: "sv", name: "Svenska"),
  .init(code: "da", name: "Dansk"),
  .init(code: "fi", name: "Suomi"),
  .init(code: "uk", name: "Українська"),
  .init(code: "ro", name: "Română"),
  .init(code: "hu", name: "Magyar"),
  .init(code: "el", name: "Ελληνικά"),
  .init(code: "he", name: "עברית"),
  .init(code: "ms", name: "Bahasa Melayu"),
]
