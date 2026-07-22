import Foundation
import WoorisaiAPI

enum RuntimeConfigurationError: Error, Equatable, Sendable {
  case missingAPIHost
  case invalidAPIHost
}

struct RuntimeConfiguration: Equatable, Sendable {
  static let apiHostInfoKey = "WoorisaiAPIHost"

  let apiBaseURL: URL

  init(bundle: Bundle = .main) throws {
    guard let apiHost = bundle.object(forInfoDictionaryKey: Self.apiHostInfoKey) as? String,
      !apiHost.isEmpty
    else {
      throw RuntimeConfigurationError.missingAPIHost
    }

    try self.init(apiHost: apiHost)
  }

  init(apiHost: String) throws {
    guard Self.isValidDNSHost(apiHost) else {
      throw RuntimeConfigurationError.invalidAPIHost
    }

    var components = URLComponents()
    components.scheme = "https"
    components.host = apiHost

    guard let apiBaseURL = components.url,
      apiBaseURL.scheme == "https",
      apiBaseURL.host?.caseInsensitiveCompare(apiHost) == .orderedSame,
      apiBaseURL.user == nil,
      apiBaseURL.password == nil,
      apiBaseURL.port == nil,
      apiBaseURL.query == nil,
      apiBaseURL.fragment == nil
    else {
      throw RuntimeConfigurationError.invalidAPIHost
    }

    self.apiBaseURL = apiBaseURL
  }

  func makeAPIClient(
    credentialStore: InMemoryCredentialStore
  ) throws -> WoorisaiAPIClient {
    try WoorisaiAPIClient(
      baseURL: apiBaseURL,
      credentialStore: credentialStore
    )
  }

  private static func isValidDNSHost(_ value: String) -> Bool {
    guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
      value.count <= 253
    else {
      return false
    }

    let labels = value.split(separator: ".", omittingEmptySubsequences: false)
    guard labels.count >= 2 else {
      return false
    }

    let allowedCharacters = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"
    )
    return labels.allSatisfy { label in
      !label.isEmpty
        && label.count <= 63
        && label.first != "-"
        && label.last != "-"
        && label.unicodeScalars.allSatisfy(allowedCharacters.contains)
    }
  }
}
