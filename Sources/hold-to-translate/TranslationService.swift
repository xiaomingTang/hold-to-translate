import Foundation

struct TranslationDraft: Equatable {
  var originalText: String
  var translatedText: String?
  var isTranslating: Bool = false
  var isEditing: Bool = false
  var editText: String = ""

  var normalizedCacheKey: String {
    originalText.normalizedCacheKey()
  }
}

struct AzureTranslationItem: Decodable {
  let text: String
}

struct AzureTranslationResponse: Decodable {
  let translations: [AzureTranslationItem]
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
  private var storage: [String: String] = [:]

  func value(for key: String) -> String? {
    storage[key]
  }

  func insert(_ value: String, for key: String) {
    storage[key] = value
  }
}

final class AzureTranslationService: Sendable {
  func translate(
    text: String, settings: TranslationSettings, apiKey: String,
    targetLanguageOverride: String? = nil
  ) async throws -> String {
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
    guard let text = decoded.first?.translations.first?.text, !text.isEmpty else {
      throw TranslationServiceError.invalidResponse
    }

    return text
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
}

func translationWarningMessage(characterCount: Int) -> String {
  "选中文本较长（\(characterCount) 个字符），继续翻译可能需要更久。仍要继续吗？"
}

func translationHardLimitMessage(characterCount: Int, limit: Int) -> String {
  "文本长度为 \(characterCount) 个字符，已超过上限 \(limit) 个字符，暂不支持翻译。请缩短后重试。"
}
