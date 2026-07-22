import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

protocol LoginOptionsAPIProtocol: Sendable {
  func listLoginOptions(
    _ input: Operations.ListLoginOptions.Input
  ) async throws -> Operations.ListLoginOptions.Output
}

extension Client: LoginOptionsAPIProtocol {}

public protocol LoginOptionsLoading: Sendable {
  func loadLoginOptions() async throws -> [LoginOption]
}

public struct LoginOption: Equatable, Sendable {
  public let slot: Int
  public let displayName: String

  public init(slot: Int, displayName: String) {
    self.slot = slot
    self.displayName = displayName
  }
}

public struct WoorisaiAPIClient: LoginOptionsLoading, Sendable {
  let client: (any APIProtocol)?
  let loginOptionsClient: (any LoginOptionsAPIProtocol)?
  let credentialValidationClient: (any CredentialValidationAPIProtocol)?
  let relationshipClient: (any RelationshipAPIProtocol)?
  public let credentialStore: InMemoryCredentialStore

  public init(
    baseURL: URL,
    credentialStore: InMemoryCredentialStore = InMemoryCredentialStore()
  ) throws {
    guard let apiOrigin = APIOrigin(url: baseURL) else {
      throw WoorisaiAPIError.untrustedOrigin
    }

    self.init(
      baseURL: baseURL,
      apiOrigin: apiOrigin,
      credentialStore: credentialStore,
      transport: WoorisaiAPITransportFactory.make(apiOrigin: apiOrigin)
    )
  }

  init(
    baseURL: URL,
    credentialStore: InMemoryCredentialStore = InMemoryCredentialStore(),
    transport: any ClientTransport
  ) throws {
    guard let apiOrigin = APIOrigin(url: baseURL) else {
      throw WoorisaiAPIError.untrustedOrigin
    }

    self.init(
      baseURL: baseURL,
      apiOrigin: apiOrigin,
      credentialStore: credentialStore,
      transport: transport
    )
  }

  private init(
    baseURL: URL,
    apiOrigin: APIOrigin,
    credentialStore: InMemoryCredentialStore,
    transport: any ClientTransport
  ) {
    self.credentialStore = credentialStore
    let client = Client(
      serverURL: baseURL,
      configuration: .init(dateTranscoder: FlexibleISO8601DateTranscoder()),
      transport: transport,
      middlewares: [
        BasicAuthorizationMiddleware(
          apiOrigin: apiOrigin,
          credentialStore: credentialStore
        )
      ]
    )
    self.client = client
    loginOptionsClient = client
    credentialValidationClient = client
    relationshipClient = client
  }

  init(loginOptionsClient: any LoginOptionsAPIProtocol) {
    client = nil
    self.loginOptionsClient = loginOptionsClient
    credentialValidationClient = nil
    relationshipClient = nil
    credentialStore = InMemoryCredentialStore()
  }

  public func loadLoginOptions() async throws -> [LoginOption] {
    do {
      guard let loginOptionsClient else {
        throw WoorisaiAPIError.schemaDrift
      }
      let output = try await loginOptionsClient.listLoginOptions(.init())

      switch output {
      case .ok(let response):
        return try Self.makeLoginOptions(from: response.body)
      case .serviceUnavailable(let response):
        let problem: Components.Schemas.LoginOptionsUnavailableProblem
        switch response.body {
        case .applicationProblemJson(let value):
          problem = value
        }
        throw WoorisaiAPIError.mapProblem(
          httpStatus: 503,
          problemStatus: problem.value1.status,
          errorCode: problem.value1.errorCode
        )
      case .undocumented(let statusCode, _):
        throw WoorisaiAPIError.undocumentedResponse(statusCode: statusCode)
      }
    } catch let error as CancellationError {
      throw error
    } catch let error as WoorisaiAPIError {
      throw error
    } catch let error as ClientError {
      if Task.isCancelled || error.underlyingError is CancellationError {
        throw CancellationError()
      }
      if error.underlyingError is URLError {
        throw WoorisaiAPIError.transport
      }
      if error.underlyingError is DecodingError {
        throw WoorisaiAPIError.schemaDrift
      }
      if let middlewareError = error.underlyingError as? APIAuthorizationMiddlewareError {
        switch middlewareError {
        case .credentialMissing:
          throw WoorisaiAPIError.credentialMissing
        case .unknownOperation:
          throw WoorisaiAPIError.schemaDrift
        case .untrustedOrigin:
          throw WoorisaiAPIError.untrustedOrigin
        }
      }
      if error.response != nil {
        throw WoorisaiAPIError.schemaDrift
      }
      throw WoorisaiAPIError.transport
    } catch is DecodingError {
      throw WoorisaiAPIError.schemaDrift
    } catch {
      if Task.isCancelled {
        throw CancellationError()
      }
      throw WoorisaiAPIError.transport
    }
  }

  private static func makeLoginOptions(
    from body: Operations.ListLoginOptions.Output.Ok.Body
  ) throws -> [LoginOption] {
    let response: Components.Schemas.LoginOptionsResponse
    switch body {
    case .json(let value):
      response = value
    }

    let options = response.participants.map { participant in
      LoginOption(
        slot: participant.participantSlot.rawValue,
        displayName: participant.displayName
      )
    }

    guard options.map(\.slot) == [1, 2],
      options.allSatisfy({ option in
        !option.displayName
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .isEmpty
      })
    else {
      throw WoorisaiAPIError.schemaDrift
    }

    return options
  }
}

/// Spring's RFC 3339 `Instant` output includes fractional seconds when the stored value has them,
/// but omits the fraction for whole-second values. The OpenAPI runtime's two built-in ISO 8601
/// transcoders each accept only one of those representations, so production responses need this
/// deliberately tolerant decoder.
struct FlexibleISO8601DateTranscoder: DateTranscoder {
  private let fractional = ISO8601DateTranscoder(
    options: [.withInternetDateTime, .withFractionalSeconds]
  )
  private let wholeSeconds = ISO8601DateTranscoder()

  func encode(_ date: Date) throws -> String {
    try fractional.encode(date)
  }

  func decode(_ dateString: String) throws -> Date {
    do {
      return try fractional.decode(dateString)
    } catch {
      return try wholeSeconds.decode(dateString)
    }
  }
}
