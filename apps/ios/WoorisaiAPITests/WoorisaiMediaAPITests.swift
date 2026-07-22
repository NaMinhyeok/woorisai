import Foundation
import OpenAPIRuntime
import Testing

@testable import WoorisaiAPI

struct WoorisaiMediaAPITests {
  @Test
  func initiateNormalizesPolicyAndMapsPrivateGrant() async throws {
    let recorder = MediaInputRecorder()
    let stub = MediaAPIStub(initiate: { input in
      await recorder.record(initiate: input)
      return MediaWireFixtures.initiatedOutput
    })
    let api = WoorisaiMediaAPI(mediaClient: stub, now: { MediaWireFixtures.now })
    let draft = try MediaUploadDraft(
      purpose: .diaryEntry,
      kind: .image,
      fileName: "  album\\summer.png  ",
      contentType: "IMAGE/PNG; charset=binary",
      byteSize: 3
    )

    let grant = try await api.initiateUpload(draft)

    let input = try #require(await recorder.initiateInput)
    guard case .json(let request) = input.body,
      let object = request.value1.value as? [String: (any Sendable)?]
    else {
      Issue.record("Expected an app-owned media request encoded at the generated boundary")
      return
    }
    #expect(object["purpose"] as? String == "diaryEntry")
    #expect(object["kind"] as? String == "image")
    #expect(object["fileName"] as? String == "summer.png")
    #expect(object["contentType"] as? String == "image/png")
    #expect(object["byteSize"] as? Int == 3)
    #expect(grant.uploadID == MediaWireFixtures.uploadID)
    #expect(grant.requiredHeaders.contentType == "image/png")
    #expect(grant.requiredHeaders.cacheControl == "private, no-store, max-age=0")
  }

  @Test
  func completeDiscardAndDownloadUseCanonicalIdentifiersAndMapResults() async throws {
    let recorder = MediaInputRecorder()
    let stub = MediaAPIStub(
      complete: { input in
        await recorder.record(complete: input)
        return try MediaWireFixtures.completedOutput()
      },
      discard: { input in
        await recorder.record(discard: input)
        return MediaWireFixtures.discardedOutput
      },
      download: { input in
        await recorder.record(download: input)
        return MediaWireFixtures.downloadOutput
      }
    )
    let api = WoorisaiMediaAPI(mediaClient: stub, now: { MediaWireFixtures.now })

    let completed = try await api.completeUpload(id: MediaWireFixtures.uploadID)
    try await api.discardUpload(id: MediaWireFixtures.uploadID)
    let download = try await api.issueDownloadGrant(attachmentID: MediaWireFixtures.uploadID)

    #expect((await recorder.completeInput)?.path.uploadId == MediaWireFixtures.uploadID.uuidString)
    #expect((await recorder.discardInput)?.path.uploadId == MediaWireFixtures.uploadID.uuidString)
    #expect(
      (await recorder.downloadInput)?.path.attachmentId == MediaWireFixtures.uploadID.uuidString
    )
    #expect(completed.id == MediaWireFixtures.uploadID)
    #expect(completed.kind == .image)
    #expect(completed.fileName == "summer.png")
    #expect(download.downloadURL.host == "media.example.test")
  }

  @Test
  func rejectsProviderGrantWithWrongOriginExpiryOrRequiredContentType() async throws {
    let insecure = WoorisaiMediaAPI(
      mediaClient: MediaAPIStub(initiate: { _ in
        MediaWireFixtures.initiatedOutput(uploadURL: "http://media.example.test/upload")
      }),
      now: { MediaWireFixtures.now }
    )
    let expired = WoorisaiMediaAPI(
      mediaClient: MediaAPIStub(initiate: { _ in
        MediaWireFixtures.initiatedOutput(expiresAt: MediaWireFixtures.now)
      }),
      now: { MediaWireFixtures.now }
    )
    let wrongHeader = WoorisaiMediaAPI(
      mediaClient: MediaAPIStub(initiate: { _ in
        MediaWireFixtures.initiatedOutput(contentType: .imageJpeg)
      }),
      now: { MediaWireFixtures.now }
    )
    let draft = try MediaWireFixtures.imageDraft()

    await #expect(throws: WoorisaiAPIError.schemaDrift) {
      _ = try await insecure.initiateUpload(draft)
    }
    await #expect(throws: WoorisaiAPIError.schemaDrift) {
      _ = try await expired.initiateUpload(draft)
    }
    await #expect(throws: WoorisaiAPIError.schemaDrift) {
      _ = try await wrongHeader.initiateUpload(draft)
    }
  }

  @Test
  func mapsConflictOnceWithoutAutomaticCompleteRetry() async throws {
    let counter = MediaInvocationCounter()
    let api = WoorisaiMediaAPI(
      mediaClient: MediaAPIStub(complete: { _ in
        await counter.increment()
        return try MediaWireFixtures.conflictOutput()
      })
    )

    await #expect(throws: WoorisaiAPIError.conflict) {
      _ = try await api.completeUpload(id: MediaWireFixtures.uploadID)
    }
    #expect(await counter.value == 1)
  }

  @Test
  func presignedPutRequestContainsOnlyGrantHeadersAndNeverBasicCredential() throws {
    let grant = try MediaUploadGrant(
      uploadID: MediaWireFixtures.uploadID,
      uploadURL: try #require(URL(string: "https://media.example.test/upload?signature=private")),
      requiredHeaders: try .init(
        contentType: "image/png",
        cacheControl: "private, no-store, max-age=0"
      ),
      expiresAt: Date().addingTimeInterval(600)
    )

    let request = try URLSessionPresignedMediaUploader.makeRequest(using: grant)

    #expect(request.httpMethod == "PUT")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "image/png")
    #expect(
      request.value(forHTTPHeaderField: "Cache-Control")
        == "private, no-store, max-age=0"
    )
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    #expect(request.httpShouldHandleCookies == false)
  }
}

private struct MediaAPIStub: MediaAPIProtocol {
  typealias InitiateHandler =
    @Sendable (Operations.InitiateMediaUpload.Input) async throws ->
    Operations.InitiateMediaUpload.Output
  typealias CompleteHandler =
    @Sendable (Operations.CompleteMediaUpload.Input) async throws ->
    Operations.CompleteMediaUpload.Output
  typealias DiscardHandler =
    @Sendable (Operations.DiscardMediaUpload.Input) async throws ->
    Operations.DiscardMediaUpload.Output
  typealias DownloadHandler =
    @Sendable (Operations.IssueMediaDownloadUrl.Input) async throws ->
    Operations.IssueMediaDownloadUrl.Output

  let initiate: InitiateHandler?
  let complete: CompleteHandler?
  let discard: DiscardHandler?
  let download: DownloadHandler?

  init(
    initiate: InitiateHandler? = nil,
    complete: CompleteHandler? = nil,
    discard: DiscardHandler? = nil,
    download: DownloadHandler? = nil
  ) {
    self.initiate = initiate
    self.complete = complete
    self.discard = discard
    self.download = download
  }

  func initiateMediaUpload(
    _ input: Operations.InitiateMediaUpload.Input
  ) async throws -> Operations.InitiateMediaUpload.Output {
    guard let initiate else { throw MediaAPITestFailure.unexpectedOperation }
    return try await initiate(input)
  }

  func completeMediaUpload(
    _ input: Operations.CompleteMediaUpload.Input
  ) async throws -> Operations.CompleteMediaUpload.Output {
    guard let complete else { throw MediaAPITestFailure.unexpectedOperation }
    return try await complete(input)
  }

  func discardMediaUpload(
    _ input: Operations.DiscardMediaUpload.Input
  ) async throws -> Operations.DiscardMediaUpload.Output {
    guard let discard else { throw MediaAPITestFailure.unexpectedOperation }
    return try await discard(input)
  }

  func issueMediaDownloadUrl(
    _ input: Operations.IssueMediaDownloadUrl.Input
  ) async throws -> Operations.IssueMediaDownloadUrl.Output {
    guard let download else { throw MediaAPITestFailure.unexpectedOperation }
    return try await download(input)
  }
}

private actor MediaInputRecorder {
  private(set) var initiateInput: Operations.InitiateMediaUpload.Input?
  private(set) var completeInput: Operations.CompleteMediaUpload.Input?
  private(set) var discardInput: Operations.DiscardMediaUpload.Input?
  private(set) var downloadInput: Operations.IssueMediaDownloadUrl.Input?

  func record(initiate: Operations.InitiateMediaUpload.Input) { initiateInput = initiate }
  func record(complete: Operations.CompleteMediaUpload.Input) { completeInput = complete }
  func record(discard: Operations.DiscardMediaUpload.Input) { discardInput = discard }
  func record(download: Operations.IssueMediaDownloadUrl.Input) { downloadInput = download }
}

private actor MediaInvocationCounter {
  private(set) var value = 0
  func increment() { value += 1 }
}

private enum MediaAPITestFailure: Error, Sendable {
  case unexpectedOperation
}

private enum MediaWireFixtures {
  static let now = Date(timeIntervalSince1970: 1_700_000_000)
  static let uploadID = UUID(uuidString: "123E4567-E89B-12D3-A456-426614174000")!

  static func imageDraft() throws -> MediaUploadDraft {
    try MediaUploadDraft(
      purpose: .diaryEntry,
      kind: .image,
      fileName: "summer.png",
      contentType: "image/png",
      byteSize: 3
    )
  }

  static var initiatedOutput: Operations.InitiateMediaUpload.Output {
    initiatedOutput()
  }

  static func initiatedOutput(
    uploadURL: String = "https://media.example.test/upload?signature=private",
    expiresAt: Date = now.addingTimeInterval(600),
    contentType: Components.Schemas.MediaUploadRequiredHeaders.ContentTypePayload = .imagePng
  ) -> Operations.InitiateMediaUpload.Output {
    .created(
      .init(
        headers: .init(cacheControl: "no-store"),
        body: .json(
          .init(
            uploadId: uploadID.uuidString,
            uploadUrl: uploadURL,
            requiredHeaders: .init(
              contentType: contentType,
              cacheControl: .private_comma_NoStore_comma_MaxAge_equals_0
            ),
            expiresAt: expiresAt
          )
        )
      )
    )
  }

  static func completedOutput() throws -> Operations.CompleteMediaUpload.Output {
    let object: [String: (any Sendable)?] = [
      "uploadId": uploadID.uuidString,
      "kind": "image",
      "fileName": "summer.png",
      "contentType": "image/png",
      "byteSize": 3,
    ]
    return .ok(
      .init(
        headers: .init(cacheControl: "no-store"),
        body: .json(
          .init(
            value1: try .init(unvalidatedValue: object),
            value2: try .init(unvalidatedValue: object)
          )
        )
      )
    )
  }

  static var discardedOutput: Operations.DiscardMediaUpload.Output {
    .noContent(.init(headers: .init(cacheControl: "no-store")))
  }

  static var downloadOutput: Operations.IssueMediaDownloadUrl.Output {
    .ok(
      .init(
        headers: .init(cacheControl: "no-store"),
        body: .json(
          .init(
            downloadUrl: "https://media.example.test/download?signature=private",
            expiresAt: now.addingTimeInterval(300)
          )
        )
      )
    )
  }

  static func conflictOutput() throws -> Operations.CompleteMediaUpload.Output {
    let problem = try JSONDecoder().decode(
      Components.Schemas.MediaUploadConflictProblem.self,
      from: Data(
        """
        {
          "title": "Media upload conflict",
          "status": 409,
          "detail": "The upload cannot be completed.",
          "instance": "/api/v2/media-uploads/123E4567-E89B-12D3-A456-426614174000/complete",
          "errorCode": "MEDIA_UPLOAD_CONFLICT"
        }
        """.utf8
      )
    )
    return .conflict(
      .init(
        headers: .init(cacheControl: "no-store"),
        body: .applicationProblemJson(problem)
      )
    )
  }
}
