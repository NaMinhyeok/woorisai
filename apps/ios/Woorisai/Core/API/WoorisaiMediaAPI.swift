import Foundation
import OpenAPIRuntime

public enum MediaPurpose: String, CaseIterable, Sendable {
  case scoreChange
  case comment
  case diaryEntry
}

public enum MediaKind: String, CaseIterable, Sendable {
  case image
  case video
}

public enum MediaValidationError: Error, Equatable, Sendable {
  case invalidFileName
  case unsupportedContentType
  case invalidByteSize
  case videoNotAllowed
  case invalidUploadGrant
  case expiredUploadGrant
  case invalidCompletedUpload
  case invalidDownloadGrant
}

public struct MediaUploadDraft: Equatable, Sendable {
  public static let maximumImageByteSize: Int64 = 10 * 1_024 * 1_024
  public static let maximumVideoByteSize: Int64 = 100 * 1_024 * 1_024

  public let purpose: MediaPurpose
  public let kind: MediaKind
  public let fileName: String
  public let contentType: String
  public let byteSize: Int64

  public init(
    purpose: MediaPurpose,
    kind: MediaKind,
    fileName: String,
    contentType: String,
    byteSize: Int64
  ) throws {
    let normalizedName = try Self.normalizeFileName(fileName)
    let normalizedContentType = try Self.normalizeContentType(contentType)
    try Self.validate(
      purpose: purpose,
      kind: kind,
      contentType: normalizedContentType,
      byteSize: byteSize
    )

    self.purpose = purpose
    self.kind = kind
    self.fileName = normalizedName
    self.contentType = normalizedContentType
    self.byteSize = byteSize
  }

  private static func normalizeFileName(_ value: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\\", with: "/")
    let basename: String
    if let separator = trimmed.lastIndex(of: "/") {
      basename = String(trimmed[trimmed.index(after: separator)...])
    } else {
      basename = trimmed
    }

    guard !basename.isEmpty,
      basename.unicodeScalars.count <= 255,
      basename.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
    else {
      throw MediaValidationError.invalidFileName
    }
    return basename
  }

  private static func normalizeContentType(_ value: String) throws -> String {
    let mediaType =
      value.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
      .first
      .map(String.init)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased() ?? ""
    guard !mediaType.isEmpty, mediaType.count <= 100 else {
      throw MediaValidationError.unsupportedContentType
    }
    return mediaType
  }

  private static func validate(
    purpose: MediaPurpose,
    kind: MediaKind,
    contentType: String,
    byteSize: Int64
  ) throws {
    guard byteSize > 0 else {
      throw MediaValidationError.invalidByteSize
    }

    switch kind {
    case .image:
      guard imageContentTypes.contains(contentType) else {
        throw MediaValidationError.unsupportedContentType
      }
      guard byteSize <= maximumImageByteSize else {
        throw MediaValidationError.invalidByteSize
      }
    case .video:
      guard purpose != .scoreChange else {
        throw MediaValidationError.videoNotAllowed
      }
      guard videoContentTypes.contains(contentType) else {
        throw MediaValidationError.unsupportedContentType
      }
      guard byteSize <= maximumVideoByteSize else {
        throw MediaValidationError.invalidByteSize
      }
    }
  }

  fileprivate static let imageContentTypes: Set<String> = [
    "image/jpeg", "image/png", "image/webp",
  ]

  fileprivate static let videoContentTypes: Set<String> = [
    "video/mp4", "video/webm", "video/quicktime",
  ]
}

public struct MediaUploadRequiredHeaders: Equatable, Sendable {
  public static let privateNoStore = "private, no-store, max-age=0"

  public let contentType: String
  public let cacheControl: String

  public init(contentType: String, cacheControl: String) throws {
    guard
      MediaUploadDraft.imageContentTypes.contains(contentType)
        || MediaUploadDraft.videoContentTypes.contains(contentType),
      cacheControl == Self.privateNoStore
    else {
      throw MediaValidationError.invalidUploadGrant
    }
    self.contentType = contentType
    self.cacheControl = cacheControl
  }
}

public struct MediaUploadGrant: Equatable, Sendable {
  public let uploadID: UUID
  public let uploadURL: URL
  public let requiredHeaders: MediaUploadRequiredHeaders
  public let expiresAt: Date

  public init(
    uploadID: UUID,
    uploadURL: URL,
    requiredHeaders: MediaUploadRequiredHeaders,
    expiresAt: Date,
    now: Date = Date()
  ) throws {
    guard Self.isPrivateHTTPSURL(uploadURL), requiredHeaders.contentType.count <= 100 else {
      throw MediaValidationError.invalidUploadGrant
    }
    guard expiresAt > now else {
      throw MediaValidationError.expiredUploadGrant
    }
    self.uploadID = uploadID
    self.uploadURL = uploadURL
    self.requiredHeaders = requiredHeaders
    self.expiresAt = expiresAt
  }

  public func isExpired(at date: Date = Date()) -> Bool {
    expiresAt <= date
  }

  fileprivate static func isPrivateHTTPSURL(_ url: URL) -> Bool {
    url.scheme?.lowercased() == "https"
      && url.host?.isEmpty == false
      && url.user == nil
      && url.password == nil
      && url.fragment == nil
  }
}

public struct CompletedMediaUpload: Equatable, Sendable, Identifiable {
  public let id: UUID
  public let kind: MediaKind
  public let fileName: String
  public let contentType: String
  public let byteSize: Int64

  public init(
    id: UUID,
    kind: MediaKind,
    fileName: String,
    contentType: String,
    byteSize: Int64
  ) throws {
    let validationPurpose: MediaPurpose = kind == .video ? .comment : .diaryEntry
    let validated = try MediaUploadDraft(
      purpose: validationPurpose,
      kind: kind,
      fileName: fileName,
      contentType: contentType,
      byteSize: byteSize
    )
    guard validated.fileName == fileName, validated.contentType == contentType else {
      throw MediaValidationError.invalidCompletedUpload
    }
    self.id = id
    self.kind = kind
    self.fileName = fileName
    self.contentType = contentType
    self.byteSize = byteSize
  }
}

public struct MediaDownloadGrant: Equatable, Sendable {
  public let downloadURL: URL
  public let expiresAt: Date

  public init(downloadURL: URL, expiresAt: Date, now: Date = Date()) throws {
    guard MediaUploadGrant.isPrivateHTTPSURL(downloadURL), expiresAt > now else {
      throw MediaValidationError.invalidDownloadGrant
    }
    self.downloadURL = downloadURL
    self.expiresAt = expiresAt
  }
}

public protocol MediaServing: Sendable {
  func initiateUpload(_ draft: MediaUploadDraft) async throws -> MediaUploadGrant
  func completeUpload(id: UUID) async throws -> CompletedMediaUpload
  func discardUpload(id: UUID) async throws
  func issueDownloadGrant(attachmentID: UUID) async throws -> MediaDownloadGrant
}

protocol MediaAPIProtocol: Sendable {
  func initiateMediaUpload(
    _ input: Operations.InitiateMediaUpload.Input
  ) async throws -> Operations.InitiateMediaUpload.Output
  func completeMediaUpload(
    _ input: Operations.CompleteMediaUpload.Input
  ) async throws -> Operations.CompleteMediaUpload.Output
  func discardMediaUpload(
    _ input: Operations.DiscardMediaUpload.Input
  ) async throws -> Operations.DiscardMediaUpload.Output
  func issueMediaDownloadUrl(
    _ input: Operations.IssueMediaDownloadUrl.Input
  ) async throws -> Operations.IssueMediaDownloadUrl.Output
}

extension Client: MediaAPIProtocol {}

public struct WoorisaiMediaAPI: MediaServing, Sendable {
  private let mediaClient: any MediaAPIProtocol
  private let now: @Sendable () -> Date

  public init(apiClient: WoorisaiAPIClient) throws {
    guard let mediaClient = apiClient.client as? any MediaAPIProtocol else {
      throw WoorisaiAPIError.schemaDrift
    }
    self.mediaClient = mediaClient
    now = Date.init
  }

  init(
    mediaClient: any MediaAPIProtocol,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.mediaClient = mediaClient
    self.now = now
  }

  public func initiateUpload(_ draft: MediaUploadDraft) async throws -> MediaUploadGrant {
    try await performRequest {
      let object: [String: (any Sendable)?] = [
        "purpose": draft.purpose.rawValue,
        "kind": draft.kind.rawValue,
        "fileName": draft.fileName,
        "contentType": draft.contentType,
        "byteSize": Int(draft.byteSize),
      ]
      let request = Components.Schemas.InitiateMediaUploadRequest(
        value1: try .init(unvalidatedValue: object),
        value2: try .init(unvalidatedValue: [String: (any Sendable)?]()),
        value3: try .init(unvalidatedValue: [String: (any Sendable)?]())
      )

      switch try await mediaClient.initiateMediaUpload(.init(body: .json(request))) {
      case .created(let response):
        return try mapInitiated(response.body, draft: draft)
      case .badRequest(let response): throw Self.mapProblem(response)
      case .unauthorized(let response): throw Self.mapProblem(response)
      case .unsupportedMediaType(let response): throw Self.mapProblem(response)
      case .serviceUnavailable(let response): throw Self.mapProblem(response)
      case .undocumented(let statusCode, _):
        throw WoorisaiAPIError.undocumentedResponse(statusCode: statusCode)
      }
    }
  }

  public func completeUpload(id: UUID) async throws -> CompletedMediaUpload {
    try await performRequest {
      let input = Operations.CompleteMediaUpload.Input(
        path: .init(uploadId: id.uuidString)
      )
      switch try await mediaClient.completeMediaUpload(input) {
      case .ok(let response): return try Self.mapCompleted(response.body, expectedID: id)
      case .badRequest(let response): throw Self.mapProblem(response)
      case .unauthorized(let response): throw Self.mapProblem(response)
      case .forbidden(let response): throw Self.mapProblem(response)
      case .notFound(let response): throw Self.mapProblem(response)
      case .conflict(let response): throw Self.mapProblem(response)
      case .serviceUnavailable(let response): throw Self.mapProblem(response)
      case .undocumented(let statusCode, _):
        throw WoorisaiAPIError.undocumentedResponse(statusCode: statusCode)
      }
    }
  }

  public func discardUpload(id: UUID) async throws {
    try await performRequest {
      let input = Operations.DiscardMediaUpload.Input(path: .init(uploadId: id.uuidString))
      switch try await mediaClient.discardMediaUpload(input) {
      case .noContent: return
      case .badRequest(let response): throw Self.mapProblem(response)
      case .unauthorized(let response): throw Self.mapProblem(response)
      case .forbidden(let response): throw Self.mapProblem(response)
      case .conflict(let response): throw Self.mapProblem(response)
      case .serviceUnavailable(let response): throw Self.mapProblem(response)
      case .undocumented(let statusCode, _):
        throw WoorisaiAPIError.undocumentedResponse(statusCode: statusCode)
      }
    }
  }

  public func issueDownloadGrant(attachmentID: UUID) async throws -> MediaDownloadGrant {
    try await performRequest {
      let input = Operations.IssueMediaDownloadUrl.Input(
        path: .init(attachmentId: attachmentID.uuidString)
      )
      switch try await mediaClient.issueMediaDownloadUrl(input) {
      case .ok(let response): return try mapDownload(response.body)
      case .badRequest(let response): throw Self.mapProblem(response)
      case .unauthorized(let response): throw Self.mapProblem(response)
      case .notFound(let response): throw Self.mapProblem(response)
      case .serviceUnavailable(let response): throw Self.mapProblem(response)
      case .undocumented(let statusCode, _):
        throw WoorisaiAPIError.undocumentedResponse(statusCode: statusCode)
      }
    }
  }

  private func performRequest<T: Sendable>(
    _ operation: () async throws -> T
  ) async throws -> T {
    do {
      return try await operation()
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as WoorisaiAPIError {
      throw error
    } catch let error as ClientError {
      if Task.isCancelled || error.underlyingError is CancellationError {
        throw CancellationError()
      }
      if error.underlyingError is URLError {
        throw WoorisaiAPIError.transport
      }
      if let middlewareError = error.underlyingError as? APIAuthorizationMiddlewareError {
        switch middlewareError {
        case .credentialMissing: throw WoorisaiAPIError.credentialMissing
        case .unknownOperation: throw WoorisaiAPIError.schemaDrift
        case .untrustedOrigin: throw WoorisaiAPIError.untrustedOrigin
        }
      }
      if error.underlyingError is DecodingError || error.response != nil {
        throw WoorisaiAPIError.schemaDrift
      }
      throw WoorisaiAPIError.transport
    } catch is DecodingError, is MediaValidationError {
      throw WoorisaiAPIError.schemaDrift
    } catch {
      if Task.isCancelled { throw CancellationError() }
      throw WoorisaiAPIError.transport
    }
  }

  private func mapInitiated(
    _ body: Operations.InitiateMediaUpload.Output.Created.Body,
    draft: MediaUploadDraft
  ) throws -> MediaUploadGrant {
    let response: Components.Schemas.InitiatedMediaUploadResponse
    switch body {
    case .json(let value): response = value
    }
    guard let uploadID = UUID(uuidString: response.uploadId),
      let uploadURL = URL(string: response.uploadUrl),
      response.requiredHeaders.contentType.rawValue == draft.contentType,
      response.requiredHeaders.cacheControl.rawValue == MediaUploadRequiredHeaders.privateNoStore
    else {
      throw WoorisaiAPIError.schemaDrift
    }
    let headers = try MediaUploadRequiredHeaders(
      contentType: response.requiredHeaders.contentType.rawValue,
      cacheControl: response.requiredHeaders.cacheControl.rawValue
    )
    return try MediaUploadGrant(
      uploadID: uploadID,
      uploadURL: uploadURL,
      requiredHeaders: headers,
      expiresAt: response.expiresAt,
      now: now()
    )
  }

  private static func mapCompleted(
    _ body: Operations.CompleteMediaUpload.Output.Ok.Body,
    expectedID: UUID
  ) throws -> CompletedMediaUpload {
    let response: Components.Schemas.CompletedMediaUploadResponse
    switch body {
    case .json(let value): response = value
    }
    guard let object = response.value1.value as? [String: (any Sendable)?],
      let uploadIDString = object["uploadId"] as? String,
      let uploadID = UUID(uuidString: uploadIDString),
      uploadID == expectedID,
      let kindValue = object["kind"] as? String,
      let kind = MediaKind(rawValue: kindValue),
      let fileName = object["fileName"] as? String,
      let contentType = object["contentType"] as? String,
      let byteSize = object["byteSize"] as? Int
    else {
      throw WoorisaiAPIError.schemaDrift
    }
    return try CompletedMediaUpload(
      id: uploadID,
      kind: kind,
      fileName: fileName,
      contentType: contentType,
      byteSize: Int64(byteSize)
    )
  }

  private func mapDownload(
    _ body: Operations.IssueMediaDownloadUrl.Output.Ok.Body
  ) throws -> MediaDownloadGrant {
    let response: Components.Schemas.MediaDownloadUrlResponse
    switch body {
    case .json(let value): response = value
    }
    guard let url = URL(string: response.downloadUrl) else {
      throw WoorisaiAPIError.schemaDrift
    }
    return try MediaDownloadGrant(downloadURL: url, expiresAt: response.expiresAt, now: now())
  }
}

public enum PresignedMediaUploadError: Error, Equatable, Sendable {
  case invalidGrant
  case expiredGrant
  case rejected(statusCode: Int)
  case transport
}

public protocol PresignedMediaUploading: Sendable {
  func put(
    _ data: Data,
    using grant: MediaUploadGrant,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws

  func put(
    fileAt fileURL: URL,
    byteSize: Int64,
    using grant: MediaUploadGrant,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws
}

public struct URLSessionPresignedMediaUploader: PresignedMediaUploading, Sendable {
  public init() {}

  public func put(
    _ data: Data,
    using grant: MediaUploadGrant,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws {
    guard !data.isEmpty else { throw PresignedMediaUploadError.invalidGrant }
    guard !grant.isExpired() else { throw PresignedMediaUploadError.expiredGrant }
    let request = try Self.makeRequest(using: grant)
    let delegate = PresignedUploadTaskDelegate(progress: progress)
    let session = URLSession(configuration: Self.makeConfiguration())

    do {
      progress(0)
      let (_, response) = try await session.upload(for: request, from: data, delegate: delegate)
      try Self.validate(response: response)
      session.finishTasksAndInvalidate()
      progress(1)
    } catch is CancellationError {
      session.invalidateAndCancel()
      throw CancellationError()
    } catch let error as PresignedMediaUploadError {
      session.invalidateAndCancel()
      throw error
    } catch {
      session.invalidateAndCancel()
      throw PresignedMediaUploadError.transport
    }
  }

  public func put(
    fileAt fileURL: URL,
    byteSize: Int64,
    using grant: MediaUploadGrant,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws {
    try Self.validateUploadFile(at: fileURL, expectedByteSize: byteSize)
    guard !grant.isExpired() else { throw PresignedMediaUploadError.expiredGrant }
    let request = try Self.makeRequest(using: grant)
    let delegate = PresignedUploadTaskDelegate(progress: progress)
    let session = URLSession(configuration: Self.makeConfiguration())

    do {
      progress(0)
      let (_, response) = try await session.upload(
        for: request,
        fromFile: fileURL,
        delegate: delegate
      )
      try Self.validate(response: response)
      session.finishTasksAndInvalidate()
      progress(1)
    } catch is CancellationError {
      session.invalidateAndCancel()
      throw CancellationError()
    } catch let error as PresignedMediaUploadError {
      session.invalidateAndCancel()
      throw error
    } catch {
      session.invalidateAndCancel()
      throw PresignedMediaUploadError.transport
    }
  }

  static func makeConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCache = nil
    configuration.urlCredentialStorage = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    return configuration
  }

  private static func validateUploadFile(at fileURL: URL, expectedByteSize: Int64) throws {
    guard fileURL.isFileURL, expectedByteSize > 0 else {
      throw PresignedMediaUploadError.invalidGrant
    }
    let values: URLResourceValues
    do {
      values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    } catch {
      throw PresignedMediaUploadError.invalidGrant
    }
    guard values.isRegularFile == true,
      let fileSize = values.fileSize,
      Int64(fileSize) == expectedByteSize
    else {
      throw PresignedMediaUploadError.invalidGrant
    }
  }

  private static func validate(response: URLResponse) throws {
    try Task.checkCancellation()
    guard let response = response as? HTTPURLResponse else {
      throw PresignedMediaUploadError.transport
    }
    guard (200...299).contains(response.statusCode) else {
      throw PresignedMediaUploadError.rejected(statusCode: response.statusCode)
    }
  }

  static func makeRequest(using grant: MediaUploadGrant) throws -> URLRequest {
    guard !grant.isExpired(), MediaUploadGrant.isPrivateHTTPSURL(grant.uploadURL) else {
      throw PresignedMediaUploadError.expiredGrant
    }
    var request = URLRequest(url: grant.uploadURL)
    request.httpMethod = "PUT"
    request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    request.httpShouldHandleCookies = false
    request.setValue(grant.requiredHeaders.contentType, forHTTPHeaderField: "Content-Type")
    request.setValue(grant.requiredHeaders.cacheControl, forHTTPHeaderField: "Cache-Control")
    request.setValue(nil, forHTTPHeaderField: "Authorization")
    request.setValue(nil, forHTTPHeaderField: "Cookie")
    return request
  }
}

private final class PresignedUploadTaskDelegate: NSObject, URLSessionTaskDelegate,
  @unchecked Sendable
{
  private let progress: @Sendable (Double) -> Void

  init(progress: @escaping @Sendable (Double) -> Void) {
    self.progress = progress
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didSendBodyData bytesSent: Int64,
    totalBytesSent: Int64,
    totalBytesExpectedToSend: Int64
  ) {
    guard totalBytesExpectedToSend > 0 else { return }
    progress(min(1, max(0, Double(totalBytesSent) / Double(totalBytesExpectedToSend))))
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    // Presigned grants are single-origin credentials. A redirect is never followed.
    completionHandler(nil)
  }
}

extension WoorisaiMediaAPI {
  private static func mapProblem(
    _ response: Components.Responses.AuthenticationRequired
  ) -> WoorisaiAPIError {
    switch response.body {
    case .applicationProblemJson(let value):
      return .mapProblem(
        httpStatus: 401,
        problemStatus: value.value1.status,
        errorCode: value.value1.errorCode
      )
    }
  }

  private static func mapProblem(
    _ response: Components.Responses.InvalidMediaUploadRequest
  ) -> WoorisaiAPIError {
    switch response.body {
    case .applicationProblemJson(let value):
      return .mapProblem(
        httpStatus: 400,
        problemStatus: value.value1.status,
        errorCode: value.value1.errorCode
      )
    }
  }

  private static func mapProblem(
    _ response: Components.Responses.InvalidMediaDownloadRequest
  ) -> WoorisaiAPIError {
    switch response.body {
    case .applicationProblemJson(let value):
      return .mapProblem(
        httpStatus: 400,
        problemStatus: value.value1.status,
        errorCode: value.value1.errorCode
      )
    }
  }

  private static func mapProblem(
    _ response: Components.Responses.MediaUploadForbidden
  ) -> WoorisaiAPIError {
    switch response.body {
    case .applicationProblemJson(let value):
      return .mapProblem(
        httpStatus: 403,
        problemStatus: value.value1.status,
        errorCode: value.value1.errorCode
      )
    }
  }

  private static func mapProblem(
    _ response: Components.Responses.MediaUploadNotFound
  ) -> WoorisaiAPIError {
    switch response.body {
    case .applicationProblemJson(let value):
      return .mapProblem(
        httpStatus: 404,
        problemStatus: value.value1.status,
        errorCode: value.value1.errorCode
      )
    }
  }

  private static func mapProblem(
    _ response: Components.Responses.MediaAttachmentNotFound
  ) -> WoorisaiAPIError {
    switch response.body {
    case .applicationProblemJson(let value):
      return .mapProblem(
        httpStatus: 404,
        problemStatus: value.value1.status,
        errorCode: value.value1.errorCode
      )
    }
  }

  private static func mapProblem(
    _ response: Components.Responses.MediaUploadConflict
  ) -> WoorisaiAPIError {
    switch response.body {
    case .applicationProblemJson(let value):
      return .mapProblem(
        httpStatus: 409,
        problemStatus: value.value1.status,
        errorCode: value.value1.errorCode
      )
    }
  }

  private static func mapProblem(
    _ response: Components.Responses.UnsupportedMediaType
  ) -> WoorisaiAPIError {
    switch response.body {
    case .applicationProblemJson(let value):
      return .mapProblem(
        httpStatus: 415,
        problemStatus: value.value1.status,
        errorCode: value.value1.errorCode
      )
    }
  }

  private static func mapProblem(
    _ response: Components.Responses.MediaUploadsOrAuthenticationUnavailable
  ) -> WoorisaiAPIError {
    let problem: Components.Schemas.ApiProblem
    switch response.body {
    case .applicationProblemJson(let payload):
      switch payload {
      case .AuthenticationUnavailableProblem(let value): problem = value.value1
      case .MediaUploadsUnavailableProblem(let value): problem = value.value1
      }
    }
    return .mapProblem(
      httpStatus: 503,
      problemStatus: problem.status,
      errorCode: problem.errorCode
    )
  }

  private static func mapProblem(
    _ response: Components.Responses.MediaDownloadOrAuthenticationUnavailable
  ) -> WoorisaiAPIError {
    let problem: Components.Schemas.ApiProblem
    switch response.body {
    case .applicationProblemJson(let payload):
      switch payload {
      case .AuthenticationUnavailableProblem(let value): problem = value.value1
      case .MediaDownloadUnavailableProblem(let value): problem = value.value1
      }
    }
    return .mapProblem(
      httpStatus: 503,
      problemStatus: problem.status,
      errorCode: problem.errorCode
    )
  }
}
