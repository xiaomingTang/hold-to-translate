import Foundation
import Security

final class KeychainStore {
  private let service = "hold-to-translate"
  private let account = "azure-api-key"
  private let fallbackApiKey = "azure-api-key-fallback"
  private let defaults = UserDefaults.standard

  func loadApiKey() -> String {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecSuccess, let data = item as? Data,
      let value = String(data: data, encoding: .utf8)
    {
      if !value.isEmpty {
        defaults.set(value, forKey: fallbackApiKey)
      }
      return value
    }

    return defaults.string(forKey: fallbackApiKey) ?? ""
  }

  func saveApiKey(_ value: String) {
    defaults.set(value, forKey: fallbackApiKey)

    let data = Data(value.utf8)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]

    let attributes: [String: Any] = [
      kSecValueData as String: data
    ]

    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecItemNotFound {
      var addQuery = query
      addQuery[kSecValueData as String] = data
      _ = SecItemAdd(addQuery as CFDictionary, nil)
    }
  }
}

final class SettingsStore {
  private let settingsKey = "translation.settings"
  private let defaults = UserDefaults.standard

  func loadSettings() -> TranslationSettings {
    guard let data = defaults.data(forKey: settingsKey) else {
      return TranslationSettings()
    }
    return (try? JSONDecoder().decode(TranslationSettings.self, from: data))
      ?? TranslationSettings()
  }

  func saveSettings(_ settings: TranslationSettings) {
    guard let data = try? JSONEncoder().encode(settings) else { return }
    defaults.set(data, forKey: settingsKey)
  }
}
