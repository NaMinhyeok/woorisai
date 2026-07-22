import Foundation
import Testing
import WoorisaiAPI

@testable import Woorisai

@MainActor
struct MediaModelTests {
  @Test
  func mediaDraftNormalizesSupportedTypesAndRejectsPolicyViolations() throws {
    let image = try MediaUploadDraft(
      purpose: .scoreChange,
      kind: .image,
      fileName: "  folder\\photo.WEBP  ",
      contentType: "IMAGE/WEBP; charset=binary",
      byteSize: MediaUploadDraft.maximumImageByteSize
    )

    #expect(image.fileName == "photo.WEBP")
    #expect(image.contentType == "image/webp")
    #expect(
      throws: MediaValidationError.videoNotAllowed,
      performing: {
        _ = try MediaUploadDraft(
          purpose: .scoreChange,
          kind: .video,
          fileName: "clip.mp4",
          contentType: "video/mp4",
          byteSize: 1
        )
      }
    )
    #expect(
      throws: MediaValidationError.invalidByteSize,
      performing: {
        _ = try MediaUploadDraft(
          purpose: .diaryEntry,
          kind: .image,
          fileName: "photo.png",
          contentType: "image/png",
          byteSize: MediaUploadDraft.maximumImageByteSize + 1
        )
      }
    )
    #expect(
      throws: MediaValidationError.unsupportedContentType,
      performing: {
        _ = try MediaUploadDraft(
          purpose: .comment,
          kind: .video,
          fileName: "clip.mov",
          contentType: "application/octet-stream",
          byteSize: 1
        )
      }
    )
    #expect(
      throws: MediaValidationError.invalidFileName,
      performing: {
        _ = try MediaUploadDraft(
          purpose: .comment,
          kind: .image,
          fileName: String(repeating: "e\u{301}", count: 128),
          contentType: "image/jpeg",
          byteSize: 1
        )
      }
    )
  }

  @Test
  func uploadRunsInitiatePutCompleteAndPublishesProgress() async throws {
    let service = MediaServiceFake()
    let uploader = RecordingMediaUploader()
    let model = MediaUploadModel(
      service: service,
      uploader: uploader,
      now: { MediaModelFixtures.now }
    )

    model.start(try MediaModelFixtures.selection())
    await mediaExpectEventually {
      if case .ready = model.state { return true }
      return false
    }

    #expect(await service.initiateCount == 1)
    #expect(await uploader.putCount == 1)
    #expect(await service.completeCount == 1)
    #expect(model.readyUpload?.id == MediaModelFixtures.firstUploadID)
    #expect(await uploader.observedProgress == [0.25, 0.75, 1])
  }

  @Test
  func retryAfterPutFailureReusesGrantWithoutDuplicateInitiate() async throws {
    let service = MediaServiceFake()
    let uploader = RecordingMediaUploader(failFirstPut: true)
    let model = MediaUploadModel(
      service: service,
      uploader: uploader,
      now: { MediaModelFixtures.now }
    )

    model.start(try MediaModelFixtures.selection())
    await mediaExpectEventually { model.state == .failed(.uploadFailed) }

    #expect(model.canRetry)
    #expect(await service.initiateCount == 1)
    #expect(await uploader.putCount == 1)
    #expect(await service.completeCount == 0)

    model.retry()
    await mediaExpectEventually {
      if case .ready = model.state { return true }
      return false
    }

    #expect(await service.initiateCount == 1)
    #expect(await uploader.putCount == 2)
    #expect(await service.completeCount == 1)
  }

  @Test
  func retryAfterCompletionUnavailableDoesNotRepeatPut() async throws {
    let service = MediaServiceFake(failFirstComplete: true)
    let uploader = RecordingMediaUploader()
    let model = MediaUploadModel(
      service: service,
      uploader: uploader,
      now: { MediaModelFixtures.now }
    )

    model.start(try MediaModelFixtures.selection())
    await mediaExpectEventually { model.state == .failed(.unavailable) }

    model.retry()
    await mediaExpectEventually {
      if case .ready = model.state { return true }
      return false
    }

    #expect(await service.initiateCount == 1)
    #expect(await uploader.putCount == 1)
    #expect(await service.completeCount == 2)
  }

  @Test
  func retryAfterCompletionConflictStartsAReplacementUpload() async throws {
    let service = MediaServiceFake(conflictFirstComplete: true)
    let uploader = RecordingMediaUploader()
    let model = MediaUploadModel(
      service: service,
      uploader: uploader,
      now: { MediaModelFixtures.now }
    )

    model.start(try MediaModelFixtures.selection())
    await mediaExpectEventually { model.state == .failed(.completionFailed) }
    await mediaExpectEventually { await service.discardedIDs.count == 1 }

    model.retry()
    await mediaExpectEventually {
      if case .ready = model.state { return true }
      return false
    }

    #expect(await service.initiateCount == 2)
    #expect(await uploader.putCount == 2)
    #expect(await service.completeCount == 2)
    #expect(await service.discardedIDs == [MediaModelFixtures.firstUploadID])
    #expect(model.readyUpload?.id == MediaModelFixtures.secondUploadID)
  }

  @Test
  func consumeReadyUploadTransfersOwnershipWithoutDiscard() async throws {
    let service = MediaServiceFake()
    let model = MediaUploadModel(
      service: service,
      uploader: RecordingMediaUploader(),
      now: { MediaModelFixtures.now }
    )

    model.start(try MediaModelFixtures.selection())
    await mediaExpectEventually {
      if case .ready = model.state { return true }
      return false
    }

    let consumed = model.consumeReadyUpload()
    model.clear()
    await Task.yield()

    #expect(consumed?.id == MediaModelFixtures.firstUploadID)
    #expect(model.state == .idle)
    #expect(model.readyUpload == nil)
    #expect(model.consumeReadyUpload() == nil)
    #expect(await service.discardedIDs.isEmpty)
  }

  @Test
  func cancelDuringInitiateDiscardsGrantReturnedAfterCancellation() async throws {
    let service = MediaServiceFake(returnInitiateGrantAfterCancellation: true)
    let model = MediaUploadModel(
      service: service,
      uploader: RecordingMediaUploader(),
      now: { MediaModelFixtures.now }
    )

    model.start(try MediaModelFixtures.selection())
    await mediaExpectEventually { await service.initiateCount == 1 }
    model.cancel()
    await mediaExpectEventually { await service.discardedIDs.count == 1 }

    #expect(model.state == .cancelled)
    #expect(await service.discardedIDs == [MediaModelFixtures.firstUploadID])
    #expect(await service.completeCount == 0)
  }

  @Test
  func cancelStopsActivePutAndDiscardsUploadBestEffort() async throws {
    let service = MediaServiceFake()
    let uploader = SuspendedMediaUploader()
    let model = MediaUploadModel(
      service: service,
      uploader: uploader,
      now: { MediaModelFixtures.now }
    )

    model.start(try MediaModelFixtures.selection())
    await mediaExpectEventually { await uploader.hasStarted }
    #expect(model.state == .uploading(progress: 0))

    model.cancel()
    await mediaExpectEventually { await service.discardedIDs.count == 1 }

    #expect(model.state == .cancelled)
    #expect(await service.discardedIDs == [MediaModelFixtures.firstUploadID])
    #expect(await service.completeCount == 0)
  }

  @Test
  func downloadRetryReplacesFailureWithFreshPrivateGrant() async {
    let service = MediaServiceFake(failFirstDownload: true)
    let model = MediaDownloadModel(service: service)

    model.load(attachmentID: MediaModelFixtures.firstUploadID)
    await mediaExpectEventually { model.state == .unavailable }

    model.retry()
    await mediaExpectEventually {
      if case .loaded = model.state { return true }
      return false
    }

    #expect(await service.downloadCount == 2)
  }
}

private actor MediaServiceFake: MediaServing {
  private(set) var initiateCount = 0
  private(set) var completeCount = 0
  private(set) var downloadCount = 0
  private(set) var discardedIDs: [UUID] = []
  private var failFirstComplete: Bool
  private var conflictFirstComplete: Bool
  private var failFirstDownload: Bool
  private var returnInitiateGrantAfterCancellation: Bool

  init(
    failFirstComplete: Bool = false,
    conflictFirstComplete: Bool = false,
    failFirstDownload: Bool = false,
    returnInitiateGrantAfterCancellation: Bool = false
  ) {
    self.failFirstComplete = failFirstComplete
    self.conflictFirstComplete = conflictFirstComplete
    self.failFirstDownload = failFirstDownload
    self.returnInitiateGrantAfterCancellation = returnInitiateGrantAfterCancellation
  }

  func initiateUpload(_ draft: MediaUploadDraft) async throws -> MediaUploadGrant {
    initiateCount += 1
    if returnInitiateGrantAfterCancellation {
      returnInitiateGrantAfterCancellation = false
      do {
        try await Task.sleep(for: .seconds(60))
      } catch is CancellationError {
        // Model cleanup is also required when a provider ignores cancellation after creating a row.
      }
    }
    let uploadID =
      initiateCount == 1
      ? MediaModelFixtures.firstUploadID
      : MediaModelFixtures.secondUploadID
    return try MediaModelFixtures.grant(id: uploadID)
  }

  func completeUpload(id: UUID) async throws -> CompletedMediaUpload {
    completeCount += 1
    if failFirstComplete {
      failFirstComplete = false
      throw WoorisaiAPIError.serviceUnavailable
    }
    if conflictFirstComplete {
      conflictFirstComplete = false
      throw WoorisaiAPIError.conflict
    }
    return try MediaModelFixtures.completed(id: id)
  }

  func discardUpload(id: UUID) async throws {
    discardedIDs.append(id)
  }

  func issueDownloadGrant(attachmentID: UUID) async throws -> MediaDownloadGrant {
    downloadCount += 1
    if failFirstDownload {
      failFirstDownload = false
      throw WoorisaiAPIError.serviceUnavailable
    }
    return try MediaDownloadGrant(
      downloadURL: URL(string: "https://media.example.test/download?signature=private")!,
      expiresAt: MediaModelFixtures.now.addingTimeInterval(300),
      now: MediaModelFixtures.now
    )
  }
}

private actor RecordingMediaUploader: PresignedMediaUploading {
  private(set) var putCount = 0
  private(set) var observedProgress: [Double] = []
  private var failFirstPut: Bool

  init(failFirstPut: Bool = false) {
    self.failFirstPut = failFirstPut
  }

  func put(
    _ data: Data,
    using grant: MediaUploadGrant,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws {
    putCount += 1
    if failFirstPut {
      failFirstPut = false
      throw PresignedMediaUploadError.transport
    }
    for value in [0.25, 0.75, 1.0] {
      observedProgress.append(value)
      progress(value)
      await Task.yield()
    }
  }
}

private actor SuspendedMediaUploader: PresignedMediaUploading {
  private(set) var hasStarted = false

  func put(
    _ data: Data,
    using grant: MediaUploadGrant,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws {
    hasStarted = true
    try await Task.sleep(for: .seconds(60))
  }
}

private enum MediaModelFixtures {
  static let now = Date(timeIntervalSince1970: 1_700_000_000)
  static let firstUploadID = UUID(uuidString: "123E4567-E89B-12D3-A456-426614174000")!
  static let secondUploadID = UUID(uuidString: "223E4567-E89B-12D3-A456-426614174000")!

  static func selection() throws -> MediaUploadSelection {
    let data = Data([0x89, 0x50, 0x4E])
    return try MediaUploadSelection(
      draft: MediaUploadDraft(
        purpose: .diaryEntry,
        kind: .image,
        fileName: "summer.png",
        contentType: "image/png",
        byteSize: Int64(data.count)
      ),
      data: data
    )
  }

  static func grant(id: UUID) throws -> MediaUploadGrant {
    try MediaUploadGrant(
      uploadID: id,
      uploadURL: URL(string: "https://media.example.test/upload?signature=private")!,
      requiredHeaders: MediaUploadRequiredHeaders(
        contentType: "image/png",
        cacheControl: "private, no-store, max-age=0"
      ),
      expiresAt: now.addingTimeInterval(600),
      now: now
    )
  }

  static func completed(id: UUID) throws -> CompletedMediaUpload {
    try CompletedMediaUpload(
      id: id,
      kind: .image,
      fileName: "summer.png",
      contentType: "image/png",
      byteSize: 3
    )
  }
}

@MainActor
private func mediaExpectEventually(
  _ predicate: @escaping @MainActor @Sendable () async -> Bool,
  iterations: Int = 500
) async {
  for _ in 0..<iterations {
    if await predicate() { return }
    await Task.yield()
  }
  Issue.record("Timed out waiting for media state")
}
