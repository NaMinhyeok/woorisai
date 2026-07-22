import Foundation
import OpenAPIRuntime

public struct RelationshipParticipant: Equatable, Sendable {
  public let slot: ParticipantSlot
  public let displayName: String
  public let isCurrentParticipant: Bool

  public init(slot: ParticipantSlot, displayName: String, isCurrentParticipant: Bool) {
    self.slot = slot
    self.displayName = displayName
    self.isCurrentParticipant = isCurrentParticipant
  }
}

public struct RelationshipScores: Equatable, Sendable {
  public let currentParticipant: RelationshipParticipant
  public let partner: RelationshipParticipant
  public let outgoingScore: Int
  public let incomingScore: Int
  public let outgoingUpdatedAt: Date
  public let incomingUpdatedAt: Date

  public init(
    currentParticipant: RelationshipParticipant,
    partner: RelationshipParticipant,
    outgoingScore: Int,
    incomingScore: Int,
    outgoingUpdatedAt: Date,
    incomingUpdatedAt: Date
  ) {
    self.currentParticipant = currentParticipant
    self.partner = partner
    self.outgoingScore = outgoingScore
    self.incomingScore = incomingScore
    self.outgoingUpdatedAt = outgoingUpdatedAt
    self.incomingUpdatedAt = incomingUpdatedAt
  }
}

public enum RelationshipMediaKind: Equatable, Sendable {
  case image
  case video
}

/// An app-owned attachment reference. A later media slice can resolve this ID through the
/// download-URL operation without exposing generated OpenAPI types to feature code.
public struct RelationshipMedia: Equatable, Sendable, Identifiable {
  public let id: UUID
  public let kind: RelationshipMediaKind
  public let fileName: String
  public let contentType: String
  public let byteSize: Int64

  public init(
    id: UUID,
    kind: RelationshipMediaKind,
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

public struct RelationshipScoreChange: Equatable, Sendable, Identifiable {
  public let id: Int64
  public let sourceParticipant: RelationshipParticipant
  public let targetParticipant: RelationshipParticipant
  public let changedBy: RelationshipParticipant
  public let delta: Int
  public let resultingScore: Int
  public let reason: String?
  public let createdAt: Date
  public let commentCount: Int64
  public let attachments: [RelationshipMedia]

  public init(
    id: Int64,
    sourceParticipant: RelationshipParticipant,
    targetParticipant: RelationshipParticipant,
    changedBy: RelationshipParticipant,
    delta: Int,
    resultingScore: Int,
    reason: String?,
    createdAt: Date,
    commentCount: Int64,
    attachments: [RelationshipMedia]
  ) {
    self.id = id
    self.sourceParticipant = sourceParticipant
    self.targetParticipant = targetParticipant
    self.changedBy = changedBy
    self.delta = delta
    self.resultingScore = resultingScore
    self.reason = reason
    self.createdAt = createdAt
    self.commentCount = commentCount
    self.attachments = attachments
  }
}

public struct RelationshipScoreChangePage: Equatable, Sendable {
  public let changes: [RelationshipScoreChange]
  public let pageNumber: Int
  public let hasNext: Bool
  public let totalCount: Int64

  public init(
    changes: [RelationshipScoreChange],
    pageNumber: Int,
    hasNext: Bool,
    totalCount: Int64
  ) {
    self.changes = changes
    self.pageNumber = pageNumber
    self.hasNext = hasNext
    self.totalCount = totalCount
  }
}

public struct RelationshipScoreComment: Equatable, Sendable, Identifiable {
  public let id: Int64
  public let author: RelationshipParticipant
  public let content: String?
  public let createdAt: Date
  public let attachments: [RelationshipMedia]

  public init(
    id: Int64,
    author: RelationshipParticipant,
    content: String?,
    createdAt: Date,
    attachments: [RelationshipMedia]
  ) {
    self.id = id
    self.author = author
    self.content = content
    self.createdAt = createdAt
    self.attachments = attachments
  }
}

public struct RelationshipScoreThread: Equatable, Sendable {
  public let change: RelationshipScoreChange
  public let comments: [RelationshipScoreComment]

  public init(change: RelationshipScoreChange, comments: [RelationshipScoreComment]) {
    self.change = change
    self.comments = comments
  }
}

public enum RelationshipScoreMutation: Equatable, Sendable {
  case delta(Int)
  case target(Int)
}

public struct RelationshipScoreChangeDraft: Equatable, Sendable {
  public static let maximumReasonCharacterCount = 200

  public let mutation: RelationshipScoreMutation
  public let reason: String?
  public let mediaUploadIDs: [UUID]

  public init(
    mutation: RelationshipScoreMutation,
    reason: String? = nil,
    mediaUploadIDs: [UUID] = []
  ) throws {
    switch mutation {
    case .delta(let value):
      guard (-100...100).contains(value), value != 0 else {
        throw WoorisaiAPIError.invalidRequest
      }
    case .target(let value):
      guard (0...100).contains(value) else {
        throw WoorisaiAPIError.invalidRequest
      }
    }

    let normalizedReason = reason.map(WoorisaiTextInput.normalized)
    guard normalizedReason?.unicodeScalars.count ?? 0 <= Self.maximumReasonCharacterCount,
      mediaUploadIDs.count <= 1,
      Set(mediaUploadIDs).count == mediaUploadIDs.count
    else {
      throw WoorisaiAPIError.invalidRequest
    }

    self.mutation = mutation
    self.reason = normalizedReason?.isEmpty == true ? nil : normalizedReason
    self.mediaUploadIDs = mediaUploadIDs
  }
}

public struct RelationshipScoreCommentDraft: Equatable, Sendable {
  public static let maximumContentCharacterCount = 500

  public let content: String?
  public let mediaUploadIDs: [UUID]

  public init(content: String? = nil, mediaUploadIDs: [UUID] = []) throws {
    let normalizedContent = content.map(WoorisaiTextInput.normalized)
    let storedContent = normalizedContent?.isEmpty == true ? nil : normalizedContent
    guard storedContent?.unicodeScalars.count ?? 0 <= Self.maximumContentCharacterCount,
      !((storedContent == nil) && mediaUploadIDs.isEmpty),
      mediaUploadIDs.count <= 4,
      Set(mediaUploadIDs).count == mediaUploadIDs.count
    else {
      throw WoorisaiAPIError.invalidRequest
    }

    self.content = storedContent
    self.mediaUploadIDs = mediaUploadIDs
  }
}

public struct RelationshipScoreChangeCreated: Equatable, Sendable {
  public let change: RelationshipScoreChange
  public let outgoingScore: Int
  public let outgoingUpdatedAt: Date

  public init(
    change: RelationshipScoreChange,
    outgoingScore: Int,
    outgoingUpdatedAt: Date
  ) {
    self.change = change
    self.outgoingScore = outgoingScore
    self.outgoingUpdatedAt = outgoingUpdatedAt
  }
}

public protocol RelationshipServing: Sendable {
  func loadRelationshipScores() async throws -> RelationshipScores
  func loadScoreChanges(pageNumber: Int) async throws -> RelationshipScoreChangePage
  func createScoreChange(
    _ draft: RelationshipScoreChangeDraft
  ) async throws -> RelationshipScoreChangeCreated
  func loadScoreChange(id: Int64) async throws -> RelationshipScoreThread
  func createScoreChangeComment(
    scoreChangeID: Int64,
    draft: RelationshipScoreCommentDraft
  ) async throws -> RelationshipScoreComment
}

protocol RelationshipAPIProtocol: Sendable {
  func getRelationshipScores(
    _ input: Operations.GetRelationshipScores.Input
  ) async throws -> Operations.GetRelationshipScores.Output
  func listScoreChanges(
    _ input: Operations.ListScoreChanges.Input
  ) async throws -> Operations.ListScoreChanges.Output
  func createScoreChange(
    _ input: Operations.CreateScoreChange.Input
  ) async throws -> Operations.CreateScoreChange.Output
  func getScoreChange(
    _ input: Operations.GetScoreChange.Input
  ) async throws -> Operations.GetScoreChange.Output
  func createScoreChangeComment(
    _ input: Operations.CreateScoreChangeComment.Input
  ) async throws -> Operations.CreateScoreChangeComment.Output
}

extension Client: RelationshipAPIProtocol {}

extension WoorisaiAPIClient: RelationshipServing {
  init(
    relationshipClient: any RelationshipAPIProtocol,
    credentialStore: InMemoryCredentialStore = InMemoryCredentialStore()
  ) {
    client = nil
    loginOptionsClient = nil
    credentialValidationClient = nil
    self.relationshipClient = relationshipClient
    self.credentialStore = credentialStore
  }

  public func loadRelationshipScores() async throws -> RelationshipScores {
    try await performRelationshipRequest { client in
      switch try await client.getRelationshipScores(.init()) {
      case .ok(let response):
        return try Self.mapScores(response.body)
      case .unauthorized(let response):
        throw Self.mapProblem(response)
      case .forbidden(let response):
        throw Self.mapProblem(response)
      case .serviceUnavailable(let response):
        throw Self.mapProblem(response)
      case .undocumented(let statusCode, _):
        throw WoorisaiAPIError.undocumentedResponse(statusCode: statusCode)
      }
    }
  }

  public func loadScoreChanges(pageNumber: Int) async throws -> RelationshipScoreChangePage {
    guard pageNumber >= 1, pageNumber <= Int(Int32.max) else {
      throw WoorisaiAPIError.invalidRequest
    }

    return try await performRelationshipRequest { client in
      let input = Operations.ListScoreChanges.Input(
        query: .init(pageNumber: Int32(pageNumber))
      )
      switch try await client.listScoreChanges(input) {
      case .ok(let response):
        return try Self.mapScoreChangePage(response.body, expectedPageNumber: pageNumber)
      case .badRequest(let response):
        throw Self.mapProblem(response)
      case .unauthorized(let response):
        throw Self.mapProblem(response)
      case .forbidden(let response):
        throw Self.mapProblem(response)
      case .notFound(let response):
        throw Self.mapProblem(response)
      case .serviceUnavailable(let response):
        throw Self.mapProblem(response)
      case .undocumented(let statusCode, _):
        throw WoorisaiAPIError.undocumentedResponse(statusCode: statusCode)
      }
    }
  }

  public func createScoreChange(
    _ draft: RelationshipScoreChangeDraft
  ) async throws -> RelationshipScoreChangeCreated {
    let delta: Int32?
    let targetScore: Int32?
    switch draft.mutation {
    case .delta(let value):
      delta = Int32(value)
      targetScore = nil
    case .target(let value):
      delta = nil
      targetScore = Int32(value)
    }

    return try await performRelationshipRequest { client in
      let request = Components.Schemas.ChangeScoreRequest(
        delta: delta,
        targetScore: targetScore,
        reason: draft.reason,
        mediaUploadIds: draft.mediaUploadIDs.map(\.uuidString)
      )
      switch try await client.createScoreChange(.init(body: .json(request))) {
      case .created(let response):
        return try Self.mapCreatedScoreChange(response.body)
      case .badRequest(let response):
        throw Self.mapProblem(response)
      case .unauthorized(let response):
        throw Self.mapProblem(response)
      case .forbidden(let response):
        throw Self.mapProblem(response)
      case .notFound(let response):
        throw Self.mapProblem(response)
      case .conflict(let response):
        throw Self.mapProblem(response)
      case .unsupportedMediaType(let response):
        throw Self.mapProblem(response)
      case .serviceUnavailable(let response):
        throw Self.mapProblem(response)
      case .undocumented(let statusCode, _):
        throw WoorisaiAPIError.undocumentedResponse(statusCode: statusCode)
      }
    }
  }

  public func loadScoreChange(id: Int64) async throws -> RelationshipScoreThread {
    guard id > 0 else {
      throw WoorisaiAPIError.invalidRequest
    }

    return try await performRelationshipRequest { client in
      switch try await client.getScoreChange(.init(path: .init(scoreChangeId: id))) {
      case .ok(let response):
        return try Self.mapScoreThread(response.body)
      case .badRequest(let response):
        throw Self.mapProblem(response)
      case .unauthorized(let response):
        throw Self.mapProblem(response)
      case .forbidden(let response):
        throw Self.mapProblem(response)
      case .notFound(let response):
        throw Self.mapProblem(response)
      case .serviceUnavailable(let response):
        throw Self.mapProblem(response)
      case .undocumented(let statusCode, _):
        throw WoorisaiAPIError.undocumentedResponse(statusCode: statusCode)
      }
    }
  }

  public func createScoreChangeComment(
    scoreChangeID: Int64,
    draft: RelationshipScoreCommentDraft
  ) async throws -> RelationshipScoreComment {
    guard scoreChangeID > 0 else {
      throw WoorisaiAPIError.invalidRequest
    }

    return try await performRelationshipRequest { client in
      let request = Components.Schemas.CreateScoreChangeCommentRequest(
        content: draft.content,
        mediaUploadIds: draft.mediaUploadIDs.map(\.uuidString)
      )
      let input = Operations.CreateScoreChangeComment.Input(
        path: .init(scoreChangeId: scoreChangeID),
        body: .json(request)
      )
      switch try await client.createScoreChangeComment(input) {
      case .created(let response):
        return try Self.mapCreatedComment(response.body)
      case .badRequest(let response):
        throw Self.mapProblem(response)
      case .unauthorized(let response):
        throw Self.mapProblem(response)
      case .forbidden(let response):
        throw Self.mapProblem(response)
      case .notFound(let response):
        throw Self.mapProblem(response)
      case .conflict(let response):
        throw Self.mapProblem(response)
      case .unsupportedMediaType(let response):
        throw Self.mapProblem(response)
      case .serviceUnavailable(let response):
        throw Self.mapProblem(response)
      case .undocumented(let statusCode, _):
        throw WoorisaiAPIError.undocumentedResponse(statusCode: statusCode)
      }
    }
  }

  private func performRelationshipRequest<T: Sendable>(
    _ operation: (any RelationshipAPIProtocol) async throws -> T
  ) async throws -> T {
    guard let relationshipClient else {
      throw WoorisaiAPIError.schemaDrift
    }

    do {
      return try await operation(relationshipClient)
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
        case .credentialMissing:
          throw WoorisaiAPIError.credentialMissing
        case .unknownOperation:
          throw WoorisaiAPIError.schemaDrift
        case .untrustedOrigin:
          throw WoorisaiAPIError.untrustedOrigin
        }
      }
      if error.underlyingError is DecodingError || error.response != nil {
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
}

extension WoorisaiAPIClient {
  private static func mapScores(
    _ body: Operations.GetRelationshipScores.Output.Ok.Body
  ) throws -> RelationshipScores {
    let response: Components.Schemas.RelationshipScoresResponse
    switch body {
    case .json(let value): response = value
    }

    let current = try mapParticipant(response._self)
    let partner = try mapParticipant(response.partner)
    let outgoingSource = try mapParticipant(response.outgoing.sourceParticipant)
    let outgoingTarget = try mapParticipant(response.outgoing.targetParticipant)
    let incomingSource = try mapParticipant(response.incoming.sourceParticipant)
    let incomingTarget = try mapParticipant(response.incoming.targetParticipant)

    guard current.isCurrentParticipant,
      !partner.isCurrentParticipant,
      current.slot != partner.slot,
      outgoingSource == current,
      outgoingTarget == partner,
      incomingSource == partner,
      incomingTarget == current,
      (0...100).contains(Int(response.outgoing.currentScore)),
      (0...100).contains(Int(response.incoming.currentScore))
    else {
      throw WoorisaiAPIError.schemaDrift
    }

    return RelationshipScores(
      currentParticipant: current,
      partner: partner,
      outgoingScore: Int(response.outgoing.currentScore),
      incomingScore: Int(response.incoming.currentScore),
      outgoingUpdatedAt: response.outgoing.updatedAt,
      incomingUpdatedAt: response.incoming.updatedAt
    )
  }

  private static func mapScoreChangePage(
    _ body: Operations.ListScoreChanges.Output.Ok.Body,
    expectedPageNumber: Int
  ) throws -> RelationshipScoreChangePage {
    let response: Components.Schemas.ScoreChangeHistoryResponse
    switch body {
    case .json(let value): response = value
    }
    let changes = try response.results.map(mapScoreChange)
    guard Int(response.paging.pageNumber) == expectedPageNumber,
      response.paging.pageSize.rawValue == 20,
      response.paging.totalCount >= Int64(changes.count),
      isNewestFirst(changes)
    else {
      throw WoorisaiAPIError.schemaDrift
    }
    return RelationshipScoreChangePage(
      changes: changes,
      pageNumber: expectedPageNumber,
      hasNext: response.paging.hasNext,
      totalCount: response.paging.totalCount
    )
  }

  private static func mapCreatedScoreChange(
    _ body: Operations.CreateScoreChange.Output.Created.Body
  ) throws -> RelationshipScoreChangeCreated {
    let response: Components.Schemas.ScoreChangeCreatedResponse
    switch body {
    case .json(let value): response = value
    }
    let change = try mapScoreChange(response.change)
    let outgoingSource = try mapParticipant(response.outgoing.sourceParticipant)
    let outgoingTarget = try mapParticipant(response.outgoing.targetParticipant)
    guard (0...100).contains(Int(response.outgoing.currentScore)),
      change.sourceParticipant.isCurrentParticipant,
      !change.targetParticipant.isCurrentParticipant,
      outgoingSource == change.sourceParticipant,
      outgoingTarget == change.targetParticipant,
      Int(response.outgoing.currentScore) == change.resultingScore
    else {
      throw WoorisaiAPIError.schemaDrift
    }
    return RelationshipScoreChangeCreated(
      change: change,
      outgoingScore: Int(response.outgoing.currentScore),
      outgoingUpdatedAt: response.outgoing.updatedAt
    )
  }

  private static func mapScoreThread(
    _ body: Operations.GetScoreChange.Output.Ok.Body
  ) throws -> RelationshipScoreThread {
    let response: Components.Schemas.ScoreChangeThreadResponse
    switch body {
    case .json(let value): response = value
    }
    let change = try mapScoreChange(response.change)
    let comments = try response.comments.map(mapComment)
    guard isOldestFirst(comments), Int64(comments.count) == change.commentCount else {
      throw WoorisaiAPIError.schemaDrift
    }
    return RelationshipScoreThread(change: change, comments: comments)
  }

  private static func mapCreatedComment(
    _ body: Operations.CreateScoreChangeComment.Output.Created.Body
  ) throws -> RelationshipScoreComment {
    let response: Components.Schemas.ScoreChangeCommentCreatedResponse
    switch body {
    case .json(let value): response = value
    }
    let comment = try mapComment(response.comment)
    guard comment.author.isCurrentParticipant else {
      throw WoorisaiAPIError.schemaDrift
    }
    return comment
  }

  private static func mapScoreChange(
    _ response: Components.Schemas.ScoreChange
  ) throws -> RelationshipScoreChange {
    let source = try mapParticipant(response.sourceParticipant)
    let target = try mapParticipant(response.targetParticipant)
    let changedBy = try mapParticipant(response.changedBy)
    let attachments = try response.attachments.map { try mapMedia($0.value1) }
    let normalizedReason = response.reason?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard response.id > 0,
      source.slot != target.slot,
      source.isCurrentParticipant != target.isCurrentParticipant,
      changedBy == source,
      response.delta != 0,
      (-100...100).contains(Int(response.delta)),
      (0...100).contains(Int(response.resultingScore)),
      response.commentCount >= 0,
      normalizedReason?.isEmpty != true,
      normalizedReason?.unicodeScalars.count ?? 0
        <= RelationshipScoreChangeDraft.maximumReasonCharacterCount,
      attachments.count <= 1,
      attachments.allSatisfy({ $0.kind == .image && $0.byteSize <= 10_485_760 })
    else {
      throw WoorisaiAPIError.schemaDrift
    }
    return RelationshipScoreChange(
      id: response.id,
      sourceParticipant: source,
      targetParticipant: target,
      changedBy: changedBy,
      delta: Int(response.delta),
      resultingScore: Int(response.resultingScore),
      reason: normalizedReason,
      createdAt: response.createdAt,
      commentCount: response.commentCount,
      attachments: attachments
    )
  }

  private static func mapComment(
    _ response: Components.Schemas.ScoreChangeComment
  ) throws -> RelationshipScoreComment {
    let author = try mapParticipant(response.author)
    let content = response.content?.trimmingCharacters(in: .whitespacesAndNewlines)
    let rawAttachments: [Components.Schemas.AttachedMedia]
    let attachmentGroupIsValid: ([RelationshipMedia]) -> Bool
    switch response.attachments {
    case .case1(let values):
      rawAttachments = values.map(\.value1)
      attachmentGroupIsValid = { attachments in
        attachments.count <= 4
          && attachments.allSatisfy { $0.kind == .image && $0.byteSize <= 10_485_760 }
      }
    case .case2(let values):
      rawAttachments = values.map(\.value1)
      attachmentGroupIsValid = { attachments in
        attachments.count == 1 && attachments.allSatisfy { $0.kind == .video }
      }
    }
    let attachments = try rawAttachments.map(mapMedia)
    guard response.id > 0,
      content?.isEmpty != true,
      content?.unicodeScalars.count ?? 0
        <= RelationshipScoreCommentDraft.maximumContentCharacterCount,
      !(content == nil && attachments.isEmpty),
      attachmentGroupIsValid(attachments),
      Set(attachments.map(\.id)).count == attachments.count
    else {
      throw WoorisaiAPIError.schemaDrift
    }
    return RelationshipScoreComment(
      id: response.id,
      author: author,
      content: content,
      createdAt: response.createdAt,
      attachments: attachments
    )
  }

  private static func mapParticipant(
    _ response: Components.Schemas.RelationshipParticipant
  ) throws -> RelationshipParticipant {
    let normalizedDisplayName = response.displayName.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard let slot = ParticipantSlot(rawValue: response.slot.rawValue),
      !normalizedDisplayName.isEmpty,
      response.displayName.count <= 30
    else {
      throw WoorisaiAPIError.schemaDrift
    }
    return RelationshipParticipant(
      slot: slot,
      displayName: response.displayName,
      isCurrentParticipant: response.mine
    )
  }

  private static func mapMedia(
    _ response: Components.Schemas.AttachedMedia
  ) throws -> RelationshipMedia {
    let normalizedFileName = response.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
    let contentType = response.contentType.rawValue
    guard let id = UUID(uuidString: response.id),
      !normalizedFileName.isEmpty,
      response.fileName.count <= 255,
      (1...104_857_600).contains(response.byteSize)
    else {
      throw WoorisaiAPIError.schemaDrift
    }
    let kind: RelationshipMediaKind
    switch response.kind {
    case .image:
      guard imageContentTypes.contains(contentType) else {
        throw WoorisaiAPIError.schemaDrift
      }
      kind = .image
    case .video:
      guard videoContentTypes.contains(contentType) else {
        throw WoorisaiAPIError.schemaDrift
      }
      kind = .video
    }
    return RelationshipMedia(
      id: id,
      kind: kind,
      fileName: response.fileName,
      contentType: contentType,
      byteSize: response.byteSize
    )
  }

  private static func isNewestFirst(_ changes: [RelationshipScoreChange]) -> Bool {
    zip(changes, changes.dropFirst()).allSatisfy { earlier, later in
      earlier.createdAt > later.createdAt
        || (earlier.createdAt == later.createdAt && earlier.id > later.id)
    }
  }

  private static func isOldestFirst(_ comments: [RelationshipScoreComment]) -> Bool {
    zip(comments, comments.dropFirst()).allSatisfy { earlier, later in
      earlier.createdAt < later.createdAt
        || (earlier.createdAt == later.createdAt && earlier.id < later.id)
    }
  }

  private static let imageContentTypes: Set<String> = [
    "image/jpeg",
    "image/png",
    "image/webp",
  ]

  private static let videoContentTypes: Set<String> = [
    "video/mp4",
    "video/webm",
    "video/quicktime",
  ]
}

extension WoorisaiAPIClient {
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
    _ response: Components.Responses.InvalidRelationshipRequest
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
    _ response: Components.Responses.RelationshipForbidden
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
    _ response: Components.Responses.RelationshipNotFound
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
    _ response: Components.Responses.RelationshipConflict
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
    _ response: Components.Responses.RelationshipOrAuthenticationUnavailable
  ) -> WoorisaiAPIError {
    let problem: Components.Schemas.ApiProblem
    switch response.body {
    case .applicationProblemJson(let payload):
      switch payload {
      case .AuthenticationUnavailableProblem(let value): problem = value.value1
      case .RelationshipUnavailableProblem(let value): problem = value.value1
      }
    }
    return .mapProblem(
      httpStatus: 503,
      problemStatus: problem.status,
      errorCode: problem.errorCode
    )
  }
}
