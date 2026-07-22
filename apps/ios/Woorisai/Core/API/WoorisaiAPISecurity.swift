import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

public enum ParticipantSlot: Int, CaseIterable, Sendable {
  case one = 1
  case two = 2
}

public enum ParticipantCredentialError: Error, Equatable, Sendable {
  case invalidPIN
}

/// A participant credential kept in process memory only.
///
/// This type deliberately has no `Codable` conformance or persistence API. The app composition
/// root owns its lifetime and clears it on local sign-out or participant changes.
public struct ParticipantCredential: Equatable, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  public let slot: ParticipantSlot
  fileprivate let authorizationHeaderValue: String

  public init(slot: ParticipantSlot, pin: String) throws {
    let bytes = Array(pin.utf8)
    guard bytes.count == 4, bytes.allSatisfy({ (0x30...0x39).contains($0) }) else {
      throw ParticipantCredentialError.invalidPIN
    }

    self.slot = slot
    authorizationHeaderValue = "Basic "
      + Data("\(slot.rawValue):\(pin)".utf8).base64EncodedString()
  }

  public var description: String {
    "ParticipantCredential(slot: \(slot.rawValue), pin: [REDACTED])"
  }

  public var debugDescription: String { description }
}

/// The only credential store used by the API client. It never reads or writes disk, Keychain,
/// UserDefaults, logs, or analytics.
public actor InMemoryCredentialStore {
  struct Lease: Equatable, Sendable {
    fileprivate let revision: UInt64
  }

  private var credential: ParticipantCredential?
  private var revision: UInt64 = 0

  public init() {}

  public func replace(with credential: ParticipantCredential) {
    revision &+= 1
    self.credential = credential
  }

  func replaceAndLease(with credential: ParticipantCredential) -> Lease {
    revision &+= 1
    self.credential = credential
    return Lease(revision: revision)
  }

  public func clear() {
    revision &+= 1
    credential = nil
  }

  func clear(ifCurrent lease: Lease) {
    guard revision == lease.revision else {
      return
    }
    revision &+= 1
    credential = nil
  }

  public var containsCredential: Bool {
    credential != nil
  }

  fileprivate func currentCredential() -> ParticipantCredential? {
    credential
  }
}

enum APIOperationAuthorizationPolicy {
  static let publicOperationIDs: Set<String> = [
    "getHealth",
    "listLoginOptions",
  ]

  static let protectedOperationIDs: Set<String> = [
    "initiateMediaUpload",
    "completeMediaUpload",
    "discardMediaUpload",
    "issueMediaDownloadUrl",
    "getRelationshipScores",
    "listScoreChanges",
    "createScoreChange",
    "getScoreChange",
    "createScoreChangeComment",
    "listDiaryEntries",
    "createDiaryEntry",
    "getDiaryEntry",
    "updateDiaryEntry",
    "deleteDiaryEntry",
    "createDiaryEntryComment",
    "updateDiaryEntryComment",
    "deleteDiaryEntryComment",
    "registerNotificationFid",
    "unregisterNotificationFid",
  ]

  enum Requirement: Equatable {
    case publicOperation
    case credential
  }

  static func requirement(for operationID: String) throws -> Requirement {
    if publicOperationIDs.contains(operationID) {
      return .publicOperation
    }
    if protectedOperationIDs.contains(operationID) {
      return .credential
    }
    throw APIAuthorizationMiddlewareError.unknownOperation
  }
}

enum APIAuthorizationMiddlewareError: Error, Equatable {
  case credentialMissing
  case unknownOperation
  case untrustedOrigin
}

struct APIOrigin: Equatable, Sendable {
  let scheme: String
  let host: String
  let port: Int

  init?(url: URL) {
    guard url.scheme?.lowercased() == "https",
      let host = url.host?.lowercased(),
      !host.isEmpty,
      url.user == nil,
      url.password == nil,
      url.query == nil,
      url.fragment == nil
    else {
      return nil
    }

    scheme = "https"
    self.host = host
    port = url.port ?? 443
  }

  func contains(_ url: URL) -> Bool {
    guard let candidate = APIOrigin(url: url) else {
      return false
    }
    return candidate == self
  }
}

struct BasicAuthorizationMiddleware: ClientMiddleware {
  let apiOrigin: APIOrigin
  let credentialStore: InMemoryCredentialStore

  func intercept(
    _ request: HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String,
    next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
  ) async throws -> (HTTPResponse, HTTPBody?) {
    guard apiOrigin.contains(baseURL) else {
      throw APIAuthorizationMiddlewareError.untrustedOrigin
    }

    var request = request
    switch try APIOperationAuthorizationPolicy.requirement(for: operationID) {
    case .publicOperation:
      request.headerFields[.authorization] = nil
    case .credential:
      guard let credential = await credentialStore.currentCredential() else {
        throw APIAuthorizationMiddlewareError.credentialMissing
      }
      request.headerFields[.authorization] = credential.authorizationHeaderValue
    }

    return try await next(request, body, baseURL)
  }
}

final class SameOriginRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  let apiOrigin: APIOrigin

  init(apiOrigin: APIOrigin) {
    self.apiOrigin = apiOrigin
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(sanitizedRedirectRequest(request))
  }

  /// Redirects never inherit a credential-bearing header. A later generated-client operation can
  /// authorize its own request again, but URLSession may not forward Basic credentials implicitly.
  func sanitizedRedirectRequest(_ request: URLRequest) -> URLRequest? {
    guard let destination = request.url, apiOrigin.contains(destination) else {
      return nil
    }
    var request = request
    request.setValue(nil, forHTTPHeaderField: "Authorization")
    return request
  }
}

enum WoorisaiAPITransportFactory {
  static func makeSessionConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCache = nil
    configuration.urlCredentialStorage = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return configuration
  }

  static func make(apiOrigin: APIOrigin) -> URLSessionTransport {
    let configuration = makeSessionConfiguration()
    let session = URLSession(
      configuration: configuration,
      delegate: SameOriginRedirectDelegate(apiOrigin: apiOrigin),
      delegateQueue: nil
    )
    return URLSessionTransport(
      configuration: .init(session: session, httpBodyProcessingMode: .buffered)
    )
  }
}
