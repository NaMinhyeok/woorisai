import Foundation
import OpenAPIRuntime

public struct DiaryParticipant: Equatable, Sendable {
  public let slot: ParticipantSlot
  public let displayName: String

  public init(slot: ParticipantSlot, displayName: String) {
    self.slot = slot
    self.displayName = displayName
  }
}

public enum DiaryMediaKind: Equatable, Sendable {
  case image
  case video
}

public struct DiaryAttachment: Equatable, Sendable, Identifiable {
  public let id: UUID
  public let kind: DiaryMediaKind
  public let fileName: String
  public let contentType: String
  public let byteSize: Int64

  public init(
    id: UUID,
    kind: DiaryMediaKind,
    fileName: String,
    contentType: String,
    byteSize: Int64
  ) {
    self.id = id
    self.kind = kind
    self.fileName = fileName
    self.contentType = contentType
    self.byteSize = byteSize
  }
}

public struct DiaryEntry: Equatable, Sendable, Identifiable {
  public let id: Int64
  public let author: DiaryParticipant
  public let content: String
  public let createdAt: Date
  public let updatedAt: Date?
  public let isMine: Bool
  public let attachments: [DiaryAttachment]
  public let commentCount: Int64

  public init(
    id: Int64,
    author: DiaryParticipant,
    content: String,
    createdAt: Date,
    updatedAt: Date?,
    isMine: Bool,
    attachments: [DiaryAttachment],
    commentCount: Int64
  ) {
    self.id = id
    self.author = author
    self.content = content
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.isMine = isMine
    self.attachments = attachments
    self.commentCount = commentCount
  }
}

public struct DiaryComment: Equatable, Sendable, Identifiable {
  public let id: Int64
  public let author: DiaryParticipant
  public let content: String
  public let createdAt: Date
  public let updatedAt: Date?
  public let isMine: Bool

  public init(
    id: Int64,
    author: DiaryParticipant,
    content: String,
    createdAt: Date,
    updatedAt: Date?,
    isMine: Bool
  ) {
    self.id = id
    self.author = author
    self.content = content
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.isMine = isMine
  }
}

public struct DiaryEntryDetail: Equatable, Sendable {
  public let entry: DiaryEntry
  public let comments: [DiaryComment]

  public init(entry: DiaryEntry, comments: [DiaryComment]) {
    self.entry = entry
    self.comments = comments
  }
}

public struct DiaryEntryPage: Equatable, Sendable {
  public let entries: [DiaryEntry]
  public let pageNumber: Int
  public let hasNext: Bool
  public let totalCount: Int64

  public init(entries: [DiaryEntry], pageNumber: Int, hasNext: Bool, totalCount: Int64) {
    self.entries = entries
    self.pageNumber = pageNumber
    self.hasNext = hasNext
    self.totalCount = totalCount
  }
}

public struct DiaryEntryCreateDraft: Equatable, Sendable {
  public static let maximumContentCharacterCount = 1_000

  public let content: String
  public let mediaUploadIDs: [UUID]

  public init(content: String, mediaUploadIDs: [UUID] = []) throws {
    let content = WoorisaiTextInput.normalized(content)
    guard !content.isEmpty,
      content.unicodeScalars.count <= Self.maximumContentCharacterCount,
      mediaUploadIDs.count <= 4,
      Set(mediaUploadIDs).count == mediaUploadIDs.count
    else {
      throw WoorisaiAPIError.invalidRequest
    }
    self.content = content
    self.mediaUploadIDs = mediaUploadIDs
  }
}

public enum DiaryAttachmentUpdate: Equatable, Sendable {
  case preserve
  case replace([UUID])
}

public struct DiaryEntryUpdateDraft: Equatable, Sendable {
  public static let maximumContentCharacterCount =
    DiaryEntryCreateDraft.maximumContentCharacterCount

  public let content: String?
  public let attachments: DiaryAttachmentUpdate

  public init(
    content: String? = nil,
    attachments: DiaryAttachmentUpdate = .preserve
  ) throws {
    let normalizedContent = content.map(WoorisaiTextInput.normalized)
    if let normalizedContent {
      guard !normalizedContent.isEmpty,
        normalizedContent.unicodeScalars.count <= Self.maximumContentCharacterCount
      else {
        throw WoorisaiAPIError.invalidRequest
      }
    }

    if case .replace(let mediaUploadIDs) = attachments {
      guard mediaUploadIDs.count <= 4,
        Set(mediaUploadIDs).count == mediaUploadIDs.count
      else {
        throw WoorisaiAPIError.invalidRequest
      }
    }

    guard normalizedContent != nil || attachments != .preserve else {
      throw WoorisaiAPIError.invalidRequest
    }
    self.content = normalizedContent
    self.attachments = attachments
  }
}

public struct DiaryCommentDraft: Equatable, Sendable {
  public static let maximumContentCharacterCount = 500

  public let content: String

  public init(content: String) throws {
    let content = WoorisaiTextInput.normalized(content)
    guard !content.isEmpty,
      content.unicodeScalars.count <= Self.maximumContentCharacterCount
    else {
      throw WoorisaiAPIError.invalidRequest
    }
    self.content = content
  }
}

public protocol DiaryServing: Sendable {
  func loadDiaryEntries(pageNumber: Int) async throws -> DiaryEntryPage
  func createDiaryEntry(_ draft: DiaryEntryCreateDraft) async throws -> DiaryEntry
  func loadDiaryEntry(id: Int64) async throws -> DiaryEntryDetail
  func updateDiaryEntry(id: Int64, draft: DiaryEntryUpdateDraft) async throws -> DiaryEntry
  func deleteDiaryEntry(id: Int64) async throws
  func createDiaryComment(entryID: Int64, draft: DiaryCommentDraft) async throws -> DiaryComment
  func updateDiaryComment(id: Int64, draft: DiaryCommentDraft) async throws -> DiaryComment
  func deleteDiaryComment(id: Int64) async throws
}

protocol DiaryAPIProtocol: Sendable {
  func listDiaryEntries(
    _ input: Operations.ListDiaryEntries.Input
  ) async throws -> Operations.ListDiaryEntries.Output
  func createDiaryEntry(
    _ input: Operations.CreateDiaryEntry.Input
  ) async throws -> Operations.CreateDiaryEntry.Output
  func getDiaryEntry(
    _ input: Operations.GetDiaryEntry.Input
  ) async throws -> Operations.GetDiaryEntry.Output
  func updateDiaryEntry(
    _ input: Operations.UpdateDiaryEntry.Input
  ) async throws -> Operations.UpdateDiaryEntry.Output
  func deleteDiaryEntry(
    _ input: Operations.DeleteDiaryEntry.Input
  ) async throws -> Operations.DeleteDiaryEntry.Output
  func createDiaryEntryComment(
    _ input: Operations.CreateDiaryEntryComment.Input
  ) async throws -> Operations.CreateDiaryEntryComment.Output
  func updateDiaryEntryComment(
    _ input: Operations.UpdateDiaryEntryComment.Input
  ) async throws -> Operations.UpdateDiaryEntryComment.Output
  func deleteDiaryEntryComment(
    _ input: Operations.DeleteDiaryEntryComment.Input
  ) async throws -> Operations.DeleteDiaryEntryComment.Output
}

extension Client: DiaryAPIProtocol {}

/// Diary-specific adapter used both by the composition root and narrow generated-client tests.
/// Generated OpenAPI types never cross this type's public boundary.
public struct WoorisaiDiaryAPI: DiaryServing, Sendable {
  private let diaryClient: any DiaryAPIProtocol

  public init(
    baseURL: URL,
    credentialStore: InMemoryCredentialStore = InMemoryCredentialStore()
  ) throws {
    guard let apiOrigin = APIOrigin(url: baseURL) else {
      throw WoorisaiAPIError.untrustedOrigin
    }
    diaryClient = Client(
      serverURL: baseURL,
      transport: WoorisaiAPITransportFactory.make(apiOrigin: apiOrigin),
      middlewares: [
        BasicAuthorizationMiddleware(
          apiOrigin: apiOrigin,
          credentialStore: credentialStore
        )
      ]
    )
  }

  init(diaryClient: any DiaryAPIProtocol) {
    self.diaryClient = diaryClient
  }

  public func loadDiaryEntries(pageNumber: Int) async throws -> DiaryEntryPage {
    guard pageNumber >= 1, pageNumber <= Int(Int32.max) else {
      throw WoorisaiAPIError.invalidRequest
    }
    return try await perform { client in
      let input = Operations.ListDiaryEntries.Input(
        query: .init(pageNumber: Int32(pageNumber))
      )
      switch try await client.listDiaryEntries(input) {
      case .ok(let response):
        return try Self.mapPage(response.body, expectedPageNumber: pageNumber)
      case .badRequest(let response): throw Self.mapProblem(response)
      case .unauthorized(let response): throw Self.mapProblem(response)
      case .forbidden(let response): throw Self.mapProblem(response)
      case .serviceUnavailable(let response): throw Self.mapProblem(response)
      case .undocumented(let statusCode, _):
        throw WoorisaiAPIError.undocumentedResponse(statusCode: statusCode)
      }
    }
  }

  public func createDiaryEntry(_ draft: DiaryEntryCreateDraft) async throws -> DiaryEntry {
    try await perform { client in
      let request = Components.Schemas.CreateDiaryEntryRequest(
        content: draft.content,
        mediaUploadIds: draft.mediaUploadIDs.map(\.uuidString)
      )
      switch try await client.createDiaryEntry(.init(body: .json(request))) {
      case .created(let response):
        return try Self.mapCreatedEntry(response.body)
      case .badRequest(let response): throw Self.mapProblem(response)
      case .unauthorized(let response): throw Self.mapProblem(response)
      case .forbidden(let response): throw Self.mapProblem(response)
      case .unsupportedMediaType(let response): throw Self.mapProblem(response)
      case .serviceUnavailable(let response): throw Self.mapProblem(response)
      case .undocumented(let statusCode, _):
        throw WoorisaiAPIError.undocumentedResponse(statusCode: statusCode)
      }
    }
  }

  public func loadDiaryEntry(id: Int64) async throws -> DiaryEntryDetail {
    try Self.validate(id: id)
    return try await perform { client in
      let input = Operations.GetDiaryEntry.Input(path: .init(entryId: id))
      switch try await client.getDiaryEntry(input) {
      case .ok(let response): return try Self.mapDetail(response.body)
      case .badRequest(let response): throw Self.mapProblem(response)
      case .unauthorized(let response): throw Self.mapProblem(response)
      case .forbidden(let response): throw Self.mapProblem(response)
      case .notFound(let response): throw Self.mapProblem(response)
      case .serviceUnavailable(let response): throw Self.mapProblem(response)
      case .undocumented(let statusCode, _):
        throw WoorisaiAPIError.undocumentedResponse(statusCode: statusCode)
      }
    }
  }

  public func updateDiaryEntry(
    id: Int64,
    draft: DiaryEntryUpdateDraft
  ) async throws -> DiaryEntry {
    try Self.validate(id: id)
    let mediaUploadIDs: [String]?
    switch draft.attachments {
    case .preserve: mediaUploadIDs = nil
    case .replace(let values): mediaUploadIDs = values.map(\.uuidString)
    }
    return try await perform { client in
      let request = Components.Schemas.UpdateDiaryEntryRequest(
        content: draft.content,
        mediaUploadIds: mediaUploadIDs
      )
      let input = Operations.UpdateDiaryEntry.Input(
        path: .init(entryId: id),
        body: .json(request)
      )
      switch try await client.updateDiaryEntry(input) {
      case .ok(let response): return try Self.mapUpdatedEntry(response.body)
      case .badRequest(let response): throw Self.mapProblem(response)
      case .unauthorized(let response): throw Self.mapProblem(response)
      case .forbidden(let response): throw Self.mapProblem(response)
      case .notFound(let response): throw Self.mapProblem(response)
      case .conflict(let response): throw Self.mapProblem(response)
      case .unsupportedMediaType(let response): throw Self.mapProblem(response)
      case .serviceUnavailable(let response): throw Self.mapProblem(response)
      case .undocumented(let statusCode, _):
        throw WoorisaiAPIError.undocumentedResponse(statusCode: statusCode)
      }
    }
  }

  public func deleteDiaryEntry(id: Int64) async throws {
    try Self.validate(id: id)
    try await perform { client in
      let input = Operations.DeleteDiaryEntry.Input(path: .init(entryId: id))
      switch try await client.deleteDiaryEntry(input) {
      case .noContent: return
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

  public func createDiaryComment(
    entryID: Int64,
    draft: DiaryCommentDraft
  ) async throws -> DiaryComment {
    try Self.validate(id: entryID)
    return try await perform { client in
      let request = Components.Schemas.CreateDiaryCommentRequest(content: draft.content)
      let input = Operations.CreateDiaryEntryComment.Input(
        path: .init(entryId: entryID),
        body: .json(request)
      )
      switch try await client.createDiaryEntryComment(input) {
      case .created(let response): return try Self.mapCreatedComment(response.body)
      case .badRequest(let response): throw Self.mapProblem(response)
      case .unauthorized(let response): throw Self.mapProblem(response)
      case .forbidden(let response): throw Self.mapProblem(response)
      case .notFound(let response): throw Self.mapProblem(response)
      case .conflict(let response): throw Self.mapProblem(response)
      case .unsupportedMediaType(let response): throw Self.mapProblem(response)
      case .serviceUnavailable(let response): throw Self.mapProblem(response)
      case .undocumented(let statusCode, _):
        throw WoorisaiAPIError.undocumentedResponse(statusCode: statusCode)
      }
    }
  }

  public func updateDiaryComment(
    id: Int64,
    draft: DiaryCommentDraft
  ) async throws -> DiaryComment {
    try Self.validate(id: id)
    return try await perform { client in
      let request = Components.Schemas.UpdateDiaryCommentRequest(content: draft.content)
      let input = Operations.UpdateDiaryEntryComment.Input(
        path: .init(commentId: id),
        body: .json(request)
      )
      switch try await client.updateDiaryEntryComment(input) {
      case .ok(let response): return try Self.mapUpdatedComment(response.body)
      case .badRequest(let response): throw Self.mapProblem(response)
      case .unauthorized(let response): throw Self.mapProblem(response)
      case .forbidden(let response): throw Self.mapProblem(response)
      case .notFound(let response): throw Self.mapProblem(response)
      case .conflict(let response): throw Self.mapProblem(response)
      case .unsupportedMediaType(let response): throw Self.mapProblem(response)
      case .serviceUnavailable(let response): throw Self.mapProblem(response)
      case .undocumented(let statusCode, _):
        throw WoorisaiAPIError.undocumentedResponse(statusCode: statusCode)
      }
    }
  }

  public func deleteDiaryComment(id: Int64) async throws {
    try Self.validate(id: id)
    try await perform { client in
      let input = Operations.DeleteDiaryEntryComment.Input(path: .init(commentId: id))
      switch try await client.deleteDiaryEntryComment(input) {
      case .noContent: return
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

  private func perform<T: Sendable>(
    _ operation: (any DiaryAPIProtocol) async throws -> T
  ) async throws -> T {
    do {
      return try await operation(diaryClient)
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
    } catch is DecodingError {
      throw WoorisaiAPIError.schemaDrift
    } catch {
      if Task.isCancelled { throw CancellationError() }
      throw WoorisaiAPIError.transport
    }
  }
}

extension WoorisaiAPIClient: DiaryServing {
  public func loadDiaryEntries(pageNumber: Int) async throws -> DiaryEntryPage {
    try await diaryAdapter().loadDiaryEntries(pageNumber: pageNumber)
  }

  public func createDiaryEntry(_ draft: DiaryEntryCreateDraft) async throws -> DiaryEntry {
    try await diaryAdapter().createDiaryEntry(draft)
  }

  public func loadDiaryEntry(id: Int64) async throws -> DiaryEntryDetail {
    try await diaryAdapter().loadDiaryEntry(id: id)
  }

  public func updateDiaryEntry(
    id: Int64,
    draft: DiaryEntryUpdateDraft
  ) async throws -> DiaryEntry {
    try await diaryAdapter().updateDiaryEntry(id: id, draft: draft)
  }

  public func deleteDiaryEntry(id: Int64) async throws {
    try await diaryAdapter().deleteDiaryEntry(id: id)
  }

  public func createDiaryComment(
    entryID: Int64,
    draft: DiaryCommentDraft
  ) async throws -> DiaryComment {
    try await diaryAdapter().createDiaryComment(entryID: entryID, draft: draft)
  }

  public func updateDiaryComment(
    id: Int64,
    draft: DiaryCommentDraft
  ) async throws -> DiaryComment {
    try await diaryAdapter().updateDiaryComment(id: id, draft: draft)
  }

  public func deleteDiaryComment(id: Int64) async throws {
    try await diaryAdapter().deleteDiaryComment(id: id)
  }

  private func diaryAdapter() throws -> WoorisaiDiaryAPI {
    guard let diaryClient = client as? any DiaryAPIProtocol else {
      throw WoorisaiAPIError.schemaDrift
    }
    return WoorisaiDiaryAPI(diaryClient: diaryClient)
  }
}

extension WoorisaiDiaryAPI {
  private static func validate(id: Int64) throws {
    guard id > 0 else { throw WoorisaiAPIError.invalidRequest }
  }

  private static func mapPage(
    _ body: Operations.ListDiaryEntries.Output.Ok.Body,
    expectedPageNumber: Int
  ) throws -> DiaryEntryPage {
    let response: Components.Schemas.DiaryEntryListResponse
    switch body {
    case .json(let value): response = value
    }
    let entries = try response.results.map { try mapEntry($0, requireMine: false) }
    guard Int(response.pageNumber) == expectedPageNumber,
      response.pageSize.rawValue == 20,
      response.totalCount >= Int64(entries.count),
      isNewestFirst(entries)
    else {
      throw WoorisaiAPIError.schemaDrift
    }
    return DiaryEntryPage(
      entries: entries,
      pageNumber: expectedPageNumber,
      hasNext: response.hasNext,
      totalCount: response.totalCount
    )
  }

  private static func mapCreatedEntry(
    _ body: Operations.CreateDiaryEntry.Output.Created.Body
  ) throws -> DiaryEntry {
    let response: Components.Schemas.DiaryEntryResponse
    switch body {
    case .json(let value): response = value
    }
    return try mapEntry(response, requireMine: true)
  }

  private static func mapUpdatedEntry(
    _ body: Operations.UpdateDiaryEntry.Output.Ok.Body
  ) throws -> DiaryEntry {
    let response: Components.Schemas.DiaryEntryUpdatedResponse
    switch body {
    case .json(let value): response = value
    }
    return try mapEntry(response)
  }

  private static func mapDetail(
    _ body: Operations.GetDiaryEntry.Output.Ok.Body
  ) throws -> DiaryEntryDetail {
    let response: Components.Schemas.DiaryEntryDetailResponse
    switch body {
    case .json(let value): response = value
    }
    let entry = try makeEntry(
      id: response.id,
      author: response.author,
      content: response.content,
      createdAt: response.createdAt,
      updatedAt: response.updatedAt,
      isMine: response.isMine,
      attachments: response.attachments,
      commentCount: response.commentCount,
      requireMine: false
    )
    let comments = try response.comments.map { try mapComment($0, requireMine: false) }
    guard Int64(comments.count) == entry.commentCount, isOldestFirst(comments) else {
      throw WoorisaiAPIError.schemaDrift
    }
    return DiaryEntryDetail(entry: entry, comments: comments)
  }

  private static func mapCreatedComment(
    _ body: Operations.CreateDiaryEntryComment.Output.Created.Body
  ) throws -> DiaryComment {
    let response: Components.Schemas.DiaryCommentResponse
    switch body {
    case .json(let value): response = value
    }
    return try mapComment(response, requireMine: true)
  }

  private static func mapUpdatedComment(
    _ body: Operations.UpdateDiaryEntryComment.Output.Ok.Body
  ) throws -> DiaryComment {
    let response: Components.Schemas.DiaryCommentUpdatedResponse
    switch body {
    case .json(let value): response = value
    }
    return try mapComment(response)
  }

  private static func mapEntry(
    _ response: Components.Schemas.DiaryEntryResponse,
    requireMine: Bool
  ) throws -> DiaryEntry {
    try makeEntry(
      id: response.id,
      author: response.author,
      content: response.content,
      createdAt: response.createdAt,
      updatedAt: response.updatedAt,
      isMine: response.isMine,
      attachments: response.attachments,
      commentCount: response.commentCount,
      requireMine: requireMine
    )
  }

  private static func mapEntry(
    _ response: Components.Schemas.DiaryEntryUpdatedResponse
  ) throws -> DiaryEntry {
    try makeEntry(
      id: response.id,
      author: response.author,
      content: response.content,
      createdAt: response.createdAt,
      updatedAt: response.updatedAt,
      isMine: response.isMine,
      attachments: response.attachments,
      commentCount: response.commentCount,
      requireMine: true
    )
  }

  private static func makeEntry(
    id: Int64,
    author: Components.Schemas.DiaryParticipant,
    content: String,
    createdAt: Date,
    updatedAt: Date?,
    isMine: Bool,
    attachments: Components.Schemas.FlexibleAttachmentGroup,
    commentCount: Int64,
    requireMine: Bool
  ) throws -> DiaryEntry {
    let author = try mapParticipant(author)
    let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
    let attachments = try mapAttachments(attachments)
    guard id > 0,
      !content.isEmpty,
      content.unicodeScalars.count <= DiaryEntryCreateDraft.maximumContentCharacterCount,
      commentCount >= 0,
      updatedAt.map({ $0 >= createdAt }) ?? true,
      !requireMine || isMine
    else {
      throw WoorisaiAPIError.schemaDrift
    }
    return DiaryEntry(
      id: id,
      author: author,
      content: content,
      createdAt: createdAt,
      updatedAt: updatedAt,
      isMine: isMine,
      attachments: attachments,
      commentCount: commentCount
    )
  }

  private static func mapComment(
    _ response: Components.Schemas.DiaryCommentResponse,
    requireMine: Bool
  ) throws -> DiaryComment {
    try makeComment(
      id: response.id,
      author: response.author,
      content: response.content,
      createdAt: response.createdAt,
      updatedAt: response.updatedAt,
      isMine: response.isMine,
      requireMine: requireMine
    )
  }

  private static func mapComment(
    _ response: Components.Schemas.DiaryCommentUpdatedResponse
  ) throws -> DiaryComment {
    try makeComment(
      id: response.id,
      author: response.author,
      content: response.content,
      createdAt: response.createdAt,
      updatedAt: response.updatedAt,
      isMine: response.isMine,
      requireMine: true
    )
  }

  private static func makeComment(
    id: Int64,
    author: Components.Schemas.DiaryParticipant,
    content: String,
    createdAt: Date,
    updatedAt: Date?,
    isMine: Bool,
    requireMine: Bool
  ) throws -> DiaryComment {
    let author = try mapParticipant(author)
    let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard id > 0,
      !content.isEmpty,
      content.unicodeScalars.count <= DiaryCommentDraft.maximumContentCharacterCount,
      updatedAt.map({ $0 >= createdAt }) ?? true,
      !requireMine || isMine
    else {
      throw WoorisaiAPIError.schemaDrift
    }
    return DiaryComment(
      id: id,
      author: author,
      content: content,
      createdAt: createdAt,
      updatedAt: updatedAt,
      isMine: isMine
    )
  }

  private static func mapParticipant(
    _ response: Components.Schemas.DiaryParticipant
  ) throws -> DiaryParticipant {
    let displayName = response.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let slot = ParticipantSlot(rawValue: response.slot.rawValue),
      !displayName.isEmpty,
      response.displayName.count <= 30
    else {
      throw WoorisaiAPIError.schemaDrift
    }
    return DiaryParticipant(slot: slot, displayName: response.displayName)
  }

  private static func mapAttachments(
    _ response: Components.Schemas.FlexibleAttachmentGroup
  ) throws -> [DiaryAttachment] {
    let attachments: [DiaryAttachment]
    switch response {
    case .case1(let values):
      attachments = try values.map { try mapAttachment($0.value1) }
      guard attachments.count <= 4,
        attachments.allSatisfy({ $0.kind == .image && $0.byteSize <= 10_485_760 })
      else {
        throw WoorisaiAPIError.schemaDrift
      }
    case .case2(let values):
      attachments = try values.map { try mapAttachment($0.value1) }
      guard attachments.count == 1,
        attachments.allSatisfy({ $0.kind == .video && $0.byteSize <= 104_857_600 })
      else {
        throw WoorisaiAPIError.schemaDrift
      }
    }
    guard Set(attachments.map(\.id)).count == attachments.count else {
      throw WoorisaiAPIError.schemaDrift
    }
    return attachments
  }

  private static func mapAttachment(
    _ response: Components.Schemas.AttachedMedia
  ) throws -> DiaryAttachment {
    guard let id = UUID(uuidString: response.id),
      !response.fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      response.fileName.count <= 255,
      (1...104_857_600).contains(response.byteSize)
    else {
      throw WoorisaiAPIError.schemaDrift
    }
    let kind: DiaryMediaKind
    switch response.kind {
    case .image:
      guard imageContentTypes.contains(response.contentType.rawValue) else {
        throw WoorisaiAPIError.schemaDrift
      }
      kind = .image
    case .video:
      guard videoContentTypes.contains(response.contentType.rawValue) else {
        throw WoorisaiAPIError.schemaDrift
      }
      kind = .video
    }
    return DiaryAttachment(
      id: id,
      kind: kind,
      fileName: response.fileName,
      contentType: response.contentType.rawValue,
      byteSize: response.byteSize
    )
  }

  private static func isNewestFirst(_ entries: [DiaryEntry]) -> Bool {
    zip(entries, entries.dropFirst()).allSatisfy { earlier, later in
      earlier.createdAt > later.createdAt
        || (earlier.createdAt == later.createdAt && earlier.id > later.id)
    }
  }

  private static func isOldestFirst(_ comments: [DiaryComment]) -> Bool {
    zip(comments, comments.dropFirst()).allSatisfy { earlier, later in
      earlier.createdAt < later.createdAt
        || (earlier.createdAt == later.createdAt && earlier.id < later.id)
    }
  }

  private static let imageContentTypes: Set<String> = [
    "image/jpeg", "image/png", "image/webp",
  ]
  private static let videoContentTypes: Set<String> = [
    "video/mp4", "video/webm", "video/quicktime",
  ]
}

extension WoorisaiDiaryAPI {
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
    _ response: Components.Responses.InvalidDiaryRequest
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
    _ response: Components.Responses.DiaryForbidden
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
    _ response: Components.Responses.DiaryNotFound
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
    _ response: Components.Responses.DiaryConflict
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
    _ response: Components.Responses.DiaryOrAuthenticationUnavailable
  ) -> WoorisaiAPIError {
    let problem: Components.Schemas.ApiProblem
    switch response.body {
    case .applicationProblemJson(let payload):
      switch payload {
      case .AuthenticationUnavailableProblem(let value): problem = value.value1
      case .DiaryUnavailableProblem(let value): problem = value.value1
      }
    }
    return .mapProblem(
      httpStatus: 503,
      problemStatus: problem.status,
      errorCode: problem.errorCode
    )
  }
}
