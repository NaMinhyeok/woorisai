import Foundation
import Observation
import WoorisaiAPI

final class OwnedTemporaryMediaUploadFile: @unchecked Sendable {
  let url: URL
  let byteSize: Int64

  private let lock = NSLock()
  private var hasRemovedFile = false
  private var removalCountStorage = 0

  init(url: URL, byteSize: Int64) {
    self.url = url
    self.byteSize = byteSize
  }

  var isRemoved: Bool {
    lock.withLock { hasRemovedFile }
  }

  var removalCount: Int {
    lock.withLock { removalCountStorage }
  }

  func removeIfNeeded() {
    let shouldRemove = lock.withLock {
      guard !hasRemovedFile else { return false }
      hasRemovedFile = true
      removalCountStorage += 1
      return true
    }
    guard shouldRemove else { return }
    try? FileManager.default.removeItem(at: url)
  }

  deinit {
    removeIfNeeded()
  }
}

struct MediaUploadSelection: Sendable {
  enum Payload: Sendable {
    case data(Data)
    case file(OwnedTemporaryMediaUploadFile)
  }

  let draft: MediaUploadDraft
  let payload: Payload

  init(draft: MediaUploadDraft, data: Data) throws {
    guard !data.isEmpty, Int64(data.count) == draft.byteSize else {
      throw MediaValidationError.invalidByteSize
    }
    self.draft = draft
    payload = .data(data)
  }

  init(draft: MediaUploadDraft, file: OwnedTemporaryMediaUploadFile) throws {
    guard !file.isRemoved, file.byteSize == draft.byteSize else {
      throw MediaValidationError.invalidByteSize
    }
    self.draft = draft
    payload = .file(file)
  }

  func removeOwnedFileIfNeeded() {
    guard case .file(let file) = payload else { return }
    file.removeIfNeeded()
  }
}

@MainActor
@Observable
final class MediaUploadModel {
  enum State: Equatable, Sendable {
    case idle
    case initiating
    case uploading(progress: Double)
    case completing
    case ready(CompletedMediaUpload)
    case failed(Failure)
    case cancelled
  }

  enum Failure: Equatable, Sendable {
    case authenticationRequired
    case forbidden
    case unavailable
    case expiredGrant
    case uploadRejected
    case uploadFailed
    case completionFailed
  }

  private enum ResumePoint: Equatable, Sendable {
    case initiate
    case upload
    case complete
  }

  private(set) var state: State = .idle

  var readyUpload: CompletedMediaUpload? {
    guard case .ready(let upload) = state else { return nil }
    return upload
  }

  var canRetry: Bool {
    if case .failed = state { return selection != nil }
    return false
  }

  @ObservationIgnored
  private let service: any MediaServing

  @ObservationIgnored
  private let uploader: any PresignedMediaUploading

  @ObservationIgnored
  private let now: @Sendable () -> Date

  @ObservationIgnored
  private var task: Task<Void, Never>?

  @ObservationIgnored
  private var generation: UInt = 0

  @ObservationIgnored
  private var selection: MediaUploadSelection?

  @ObservationIgnored
  private var grant: MediaUploadGrant?

  @ObservationIgnored
  private var resumePoint: ResumePoint = .initiate

  init(
    service: any MediaServing,
    uploader: any PresignedMediaUploading,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.service = service
    self.uploader = uploader
    self.now = now
  }

  func start(_ selection: MediaUploadSelection) {
    invalidateCurrentUpload(discard: true)
    self.selection?.removeOwnedFileIfNeeded()
    self.selection = selection
    grant = nil
    resumePoint = .initiate
    begin()
  }

  func retry() {
    guard canRetry else { return }
    if resumePoint == .upload, let grant, grant.isExpired(at: now()) {
      discardBestEffort(grant.uploadID)
      self.grant = nil
      resumePoint = .initiate
    }
    begin()
  }

  func cancel() {
    guard state != .idle, state != .cancelled else { return }
    generation &+= 1
    task?.cancel()
    task = nil
    if let grant { discardBestEffort(grant.uploadID) }
    selection?.removeOwnedFileIfNeeded()
    selection = nil
    grant = nil
    resumePoint = .initiate
    state = .cancelled
  }

  /// Drops the current selection and discards a pending or unattached ready upload best effort.
  func clear() {
    _ = clearForCredentialRemoval()
  }

  /// Starts discard while an authenticated session still owns its in-memory credential.
  /// The returned task lets session teardown wait briefly before removing that credential.
  @discardableResult
  func clearForCredentialRemoval() -> Task<Void, Never>? {
    generation &+= 1
    task?.cancel()
    task = nil
    let uploadID = grant?.uploadID
    selection?.removeOwnedFileIfNeeded()
    selection = nil
    grant = nil
    resumePoint = .initiate
    state = .idle
    guard let uploadID else { return nil }
    let service = service
    return Task {
      try? await service.discardUpload(id: uploadID)
    }
  }

  /// Transfers an attached upload to its parent mutation without discarding the server resource.
  ///
  /// Call this only after the parent mutation has accepted `readyUpload.id`. Failed or cancelled
  /// parent mutations should continue to use `clear()` so the unattached upload is discarded.
  @discardableResult
  func consumeReadyUpload() -> CompletedMediaUpload? {
    guard case .ready(let completed) = state else { return nil }
    generation &+= 1
    task?.cancel()
    task = nil
    selection?.removeOwnedFileIfNeeded()
    selection = nil
    grant = nil
    resumePoint = .initiate
    state = .idle
    return completed
  }

  private func begin() {
    guard let selection else { return }
    generation &+= 1
    let generation = generation
    let resumePoint = resumePoint
    let service = service
    let uploader = uploader
    task?.cancel()

    task = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        var currentGrant = self.grant

        if resumePoint == .initiate {
          self.state = .initiating
          let initiatedGrant = try await service.initiateUpload(selection.draft)
          currentGrant = initiatedGrant
          guard !Task.isCancelled, self.generation == generation else {
            self.discardBestEffort(initiatedGrant.uploadID)
            return
          }
          guard initiatedGrant.requiredHeaders.contentType == selection.draft.contentType else {
            throw WoorisaiAPIError.schemaDrift
          }
          self.grant = initiatedGrant
          self.resumePoint = .upload
        }

        guard let currentGrant else { throw WoorisaiAPIError.schemaDrift }

        if resumePoint != .complete {
          guard !currentGrant.isExpired(at: self.now()) else {
            self.resumePoint = .initiate
            throw PresignedMediaUploadError.expiredGrant
          }
          self.state = .uploading(progress: 0)
          let reportProgress: @Sendable (Double) -> Void = { [weak self] progress in
            Task { @MainActor [weak self] in
              guard let self, self.generation == generation else { return }
              self.state = .uploading(progress: min(1, max(0, progress)))
            }
          }
          switch selection.payload {
          case .data(let data):
            try await uploader.put(data, using: currentGrant, progress: reportProgress)
          case .file(let file):
            guard !file.isRemoved else { throw PresignedMediaUploadError.invalidGrant }
            try await uploader.put(
              fileAt: file.url,
              byteSize: file.byteSize,
              using: currentGrant,
              progress: reportProgress
            )
          }
          try Task.checkCancellation()
          guard self.generation == generation else { return }
          self.resumePoint = .complete
        }

        self.state = .completing
        let completed = try await service.completeUpload(id: currentGrant.uploadID)
        try Task.checkCancellation()
        guard self.generation == generation else { return }
        guard completed.id == currentGrant.uploadID,
          completed.kind == selection.draft.kind,
          completed.fileName == selection.draft.fileName,
          completed.contentType == selection.draft.contentType,
          completed.byteSize == selection.draft.byteSize
        else {
          throw WoorisaiAPIError.schemaDrift
        }
        selection.removeOwnedFileIfNeeded()
        self.selection = nil
        self.task = nil
        self.state = .ready(completed)
      } catch is CancellationError {
        return
      } catch {
        guard self.generation == generation else { return }
        self.task = nil
        self.state = .failed(self.mapFailure(error))
      }
    }
  }

  private func mapFailure(_ error: any Error) -> Failure {
    if let uploadError = error as? PresignedMediaUploadError {
      switch uploadError {
      case .expiredGrant:
        if let grant { discardBestEffort(grant.uploadID) }
        grant = nil
        resumePoint = .initiate
        return .expiredGrant
      case .rejected:
        resumePoint = .upload
        return .uploadRejected
      case .invalidGrant, .transport:
        resumePoint = .upload
        return .uploadFailed
      }
    }

    guard let apiError = error as? WoorisaiAPIError else {
      return resumePoint == .complete ? .completionFailed : .uploadFailed
    }
    switch apiError {
    case .credentialMissing, .credentialRejected:
      return .authenticationRequired
    case .forbidden:
      return .forbidden
    case .serviceUnavailable:
      return .unavailable
    case .notFound,
      .conflict where resumePoint == .complete:
      if let grant { discardBestEffort(grant.uploadID) }
      grant = nil
      resumePoint = .initiate
      return .completionFailed
    default:
      return resumePoint == .complete ? .completionFailed : .uploadFailed
    }
  }

  private func invalidateCurrentUpload(discard: Bool) {
    generation &+= 1
    task?.cancel()
    task = nil
    if discard, let grant { discardBestEffort(grant.uploadID) }
  }

  private func discardBestEffort(_ uploadID: UUID) {
    let service = service
    Task {
      try? await service.discardUpload(id: uploadID)
    }
  }
}
