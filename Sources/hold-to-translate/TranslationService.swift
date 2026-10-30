import Foundation

struct TranslationDraft: Equatable {
  var originalText: String
  var translatedText: String?
  var isTranslating: Bool = false
  var isEditing: Bool = false
  var editText: String = ""
  var alternatives: [DictionaryAlternative] = []

  var normalizedCacheKey: String {
    originalText.normalizedCacheKey()
  }
}

struct DictionaryAlternative: Equatable, Identifiable {
  var displayTarget: String
  var prefixWord: String
  var posTag: String
  var confidence: Double
  var backTranslations: [String]

  var id: String { "\(posTag)|\(prefixWord)|\(displayTarget)" }
  var displayText: String { prefixWord + displayTarget }
}

struct TranslationResult: Equatable {
  var translatedText: String
  var alternatives: [DictionaryAlternative]
}

struct AzureTranslationItem: Decodable {
  let text: String
}

struct AzureDetectedLanguage: Decodable {
  let language: String
  let score: Double?
}

struct AzureTranslationResponse: Decodable {
  let detectedLanguage: AzureDetectedLanguage?
  let translations: [AzureTranslationItem]
}

struct AzureDictionaryBackTranslation: Decodable {
  let displayText: String
  let frequencyCount: Int?
}

struct AzureDictionaryTranslation: Decodable {
  let displayTarget: String
  let posTag: String
  let confidence: Double
  let prefixWord: String
  let backTranslations: [AzureDictionaryBackTranslation]?
}

struct AzureDictionaryLookupResponse: Decodable {
  let translations: [AzureDictionaryTranslation]
}

enum TranslationServiceError: LocalizedError {
  case missingConfiguration
  case invalidEndpoint
  case invalidResponse
  case httpError(Int, String)

  var errorDescription: String? {
    switch self {
    case .missingConfiguration:
      return "请先在设置中填写 Azure Endpoint、API Key 和 Region。"
    case .invalidEndpoint:
      return "Azure Endpoint 格式无效，请检查后重试。"
    case .invalidResponse:
      return "翻译服务返回了无法识别的结果。"
    case .httpError(let statusCode, let message):
      return "翻译请求失败（HTTP \(statusCode)）。\(message)"
    }
  }
}

final class TranslationCache: @unchecked Sendable {
  private var storage: [String: TranslationResult] = [:]

  func value(for key: String) -> TranslationResult? {
    storage[key]
  }

  func insert(_ value: TranslationResult, for key: String) {
    storage[key] = value
  }
}

final class AzureTranslationService: Sendable {
  func translate(
    text: String, settings: TranslationSettings, apiKey: String,
    targetLanguageOverride: String? = nil
  ) async throws -> TranslationResult {
    let endpoint = normalizedEndpoint(settings.endpoint)
    let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let region = settings.region.trimmingCharacters(in: .whitespacesAndNewlines)
    let targetLanguage = (targetLanguageOverride ?? settings.targetLanguage).trimmingCharacters(
      in: .whitespacesAndNewlines)

    guard !endpoint.isEmpty, !apiKey.isEmpty, !region.isEmpty, !targetLanguage.isEmpty else {
      throw TranslationServiceError.missingConfiguration
    }

    guard var components = URLComponents(string: endpoint + "/translate") else {
      throw TranslationServiceError.invalidEndpoint
    }

    components.queryItems = [
      URLQueryItem(name: "api-version", value: "3.0"),
      URLQueryItem(name: "to", value: targetLanguage),
    ]

    guard let url = components.url else {
      throw TranslationServiceError.invalidEndpoint
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
    request.setValue(region, forHTTPHeaderField: "Ocp-Apim-Subscription-Region")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: [["Text": text]])

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw TranslationServiceError.invalidResponse
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      let message = String(data: data, encoding: .utf8) ?? ""
      throw TranslationServiceError.httpError(httpResponse.statusCode, message)
    }

    let decoded = try JSONDecoder().decode([AzureTranslationResponse].self, from: data)
    guard let translatedText = decoded.first?.translations.first?.text, !translatedText.isEmpty
    else {
      throw TranslationServiceError.invalidResponse
    }

    let alternatives = await dictionaryAlternatives(
      for: text,
      primaryTranslation: translatedText,
      sourceLanguage: decoded.first?.detectedLanguage?.language,
      targetLanguage: targetLanguage,
      settings: settings,
      apiKey: apiKey,
      region: region)

    return TranslationResult(translatedText: translatedText, alternatives: alternatives)
  }

  /// 对单词或短语额外调用 /dictionary/lookup，获取多个候选释义（词性、置信度、反向翻译）。
  /// 词典接口不支持的语言对或失败时返回空数组，不影响主翻译结果。
  private func dictionaryAlternatives(
    for text: String,
    primaryTranslation: String,
    sourceLanguage: String?,
    targetLanguage: String,
    settings: TranslationSettings,
    apiKey: String,
    region: String
  ) async -> [DictionaryAlternative] {
    guard text.isWordOrShortPhrase(),
      let sourceLanguage = sourceLanguage?.trimmingCharacters(in: .whitespacesAndNewlines),
      !sourceLanguage.isEmpty,
      sourceLanguage.caseInsensitiveCompare(targetLanguage) != .orderedSame,
      var components = URLComponents(
        string: normalizedEndpoint(settings.endpoint) + "/dictionary/lookup")
    else {
      return []
    }

    components.queryItems = [
      URLQueryItem(name: "api-version", value: "3.0"),
      URLQueryItem(name: "from", value: sourceLanguage),
      URLQueryItem(name: "to", value: targetLanguage),
    ]

    guard let url = components.url else { return [] }

    guard let body = try? JSONSerialization.data(withJSONObject: [["Text": text]]) else {
      return []
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
    request.setValue(region, forHTTPHeaderField: "Ocp-Apim-Subscription-Region")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse,
        (200..<300).contains(httpResponse.statusCode)
      else {
        return []
      }
      let decoded = try JSONDecoder().decode([AzureDictionaryLookupResponse].self, from: data)
      let normalizedPrimary = primaryTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
      let alternatives =
        (decoded.first?.translations ?? [])
        .map {
          DictionaryAlternative(
            displayTarget: $0.displayTarget,
            prefixWord: $0.prefixWord,
            posTag: $0.posTag,
            confidence: $0.confidence,
            backTranslations: Array(
              ($0.backTranslations ?? [])
                .sorted { ($0.frequencyCount ?? 0) > ($1.frequencyCount ?? 0) }
                .map(\.displayText)
                .prefix(3))
          )
        }
        .filter {
          !$0.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && $0.displayText.lowercased() != normalizedPrimary
        }
        .sorted { $0.confidence > $1.confidence }
      return Array(alternatives.prefix(8))
    } catch {
      return []
    }
  }

  private func normalizedEndpoint(_ endpoint: String) -> String {
    let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return trimmed
    }

    let prefixed = trimmed.contains("://") ? trimmed : "https://" + trimmed
    return prefixed.hasSuffix("/") ? String(prefixed.dropLast()) : prefixed
  }
}

extension String {
  func normalizedCacheKey() -> String {
    let collapsedWhitespace = replacingOccurrences(
      of: "\\s+",
      with: " ",
      options: .regularExpression
    )

    return
      collapsedWhitespace
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
  }

  func containsHanScript() -> Bool {
    unicodeScalars.contains { scalar in
      switch scalar.value {
      case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2CEAF:
        return true
      default:
        return false
      }
    }
  }

  /// 判断是否为单词或短语（适合调用词典接口补充多个释义），长句/多句不适用。
  func isWordOrShortPhrase() -> Bool {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.count <= 48, !trimmed.contains("\n") else { return false }
    if trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "。！？；…!?;")) != nil {
      return false
    }
    if trimmed.containsHanScript() {
      return trimmed.count <= 12
    }
    return trimmed.split(whereSeparator: { $0.isWhitespace }).count <= 4
  }
}

func translationWarningMessage(characterCount: Int) -> String {
  "选中文本较长（\(characterCount) 个字符），继续翻译可能需要更久。仍要继续吗？"
}

func translationHardLimitMessage(characterCount: Int, limit: Int) -> String {
  "文本长度为 \(characterCount) 个字符，已超过上限 \(limit) 个字符，暂不支持翻译。请缩短后重试。"
}
