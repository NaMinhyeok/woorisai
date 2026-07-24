import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@testable import WoorisaiAPI

struct WoorisaiCredentialArchiveTests {
  @Test
  func archiveRoundTripReconstructsIdenticalAuthorizationHeader() async throws {
    let original = try ParticipantCredential(slot: .one, pin: "0123")
    let archive = original.archived()

    // Persisted bytes reload into an equal archive.
    let reloaded = try #require(ArchivedCredential(rawData: archive.rawData))
    #expect(reloaded == archive)

    // The reconstructed credential injects the exact header the original would have injected.
    let restored = try ParticipantCredential(archived: reloaded)
    #expect(try await authorizationHeader(for: restored) == "Basic MTowMTIz")
  }

  @Test(arguments: [ParticipantSlot.one, ParticipantSlot.two])
  func archiveReconstructsHeaderForEitherSlot(slot: ParticipantSlot) async throws {
    let restored = try ParticipantCredential(
      archived: ParticipantCredential(slot: slot, pin: "4821").archived()
    )
    let expected = "Basic " + Data("\(slot.rawValue):4821".utf8).base64EncodedString()
    #expect(try await authorizationHeader(for: restored) == expected)
  }

  @Test
  func rejectsEmptyTruncatedAndNonArchiveRawData() throws {
    #expect(ArchivedCredential(rawData: Data()) == nil)
    #expect(ArchivedCredential(rawData: Data("not-json".utf8)) == nil)

    let good = try ParticipantCredential(slot: .one, pin: "0123").archived().rawData
    #expect(!good.isEmpty)
    let truncated = Data(good.prefix(good.count / 2))
    #expect(ArchivedCredential(rawData: truncated) == nil)
  }

  // NOTE: these craft the module-private archive JSON directly (keys mirror the private `Payload`)
  // to prove reconstruction never trusts stored bytes and always re-validates the header.
  @Test
  func rejectsArchiveWhoseHeaderIsNotValidBase64() throws {
    let archive = try #require(
      ArchivedCredential(rawData: archiveJSON(slot: 1, authorization: "Basic bogus"))
    )
    #expect(throws: ParticipantCredentialError.invalidPIN) {
      _ = try ParticipantCredential(archived: archive)
    }
  }

  @Test
  func rejectsArchiveWhoseHeaderSlotDisagreesWithStoredSlot() throws {
    let header = "Basic " + Data("2:0123".utf8).base64EncodedString()
    let archive = try #require(
      ArchivedCredential(rawData: archiveJSON(slot: 1, authorization: header))
    )
    #expect(throws: ParticipantCredentialError.invalidPIN) {
      _ = try ParticipantCredential(archived: archive)
    }
  }

  @Test
  func rejectsArchiveWhoseHeaderDecodesToAnInvalidPIN() throws {
    let header = "Basic " + Data("1:99".utf8).base64EncodedString()
    let archive = try #require(
      ArchivedCredential(rawData: archiveJSON(slot: 1, authorization: header))
    )
    #expect(throws: ParticipantCredentialError.invalidPIN) {
      _ = try ParticipantCredential(archived: archive)
    }
  }

  @Test
  func descriptionDoesNotRevealSlotOrPIN() throws {
    let archive = try ParticipantCredential(slot: .two, pin: "0123").archived()
    #expect(archive.description == "ArchivedCredential(slot: [REDACTED])")
    #expect(!archive.description.contains("0123"))
    #expect(!archive.description.contains("2"))
  }
}

private func archiveJSON(slot: Int, authorization: String) -> Data {
  Data(#"{"version":1,"slot":\#(slot),"authorization":"\#(authorization)"}"#.utf8)
}

private func authorizationHeader(
  for credential: ParticipantCredential
) async throws -> String? {
  let store = InMemoryCredentialStore()
  await store.replace(with: credential)
  let baseURL = try #require(URL(string: "https://api.example.test"))
  let middleware = BasicAuthorizationMiddleware(
    apiOrigin: try #require(APIOrigin(url: baseURL)),
    credentialStore: store
  )
  let recorder = RequestRecorder()

  _ = try await middleware.intercept(
    HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/api/v2/relationship-scores"),
    body: nil,
    baseURL: baseURL,
    operationID: "getRelationshipScores"
  ) { request, _, _ in
    await recorder.record(request)
    return (HTTPResponse(status: .ok), nil)
  }

  return try #require(await recorder.request).headerFields[.authorization]
}

private actor RequestRecorder {
  private(set) var request: HTTPRequest?

  func record(_ request: HTTPRequest) {
    self.request = request
  }
}
