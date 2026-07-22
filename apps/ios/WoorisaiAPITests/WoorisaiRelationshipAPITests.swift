import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@testable import WoorisaiAPI

struct WoorisaiRelationshipAPITests {
  @Test
  func mapsGeneratedScoresHistoryAndThreadIntoAppOwnedModels() async throws {
    let stub = RelationshipAPIStub(
      scores: { _ in RelationshipWireFixtures.scoresOutput },
      history: { input in
        #expect(input.query.pageNumber == 1)
        return RelationshipWireFixtures.historyOutput
      },
      thread: { input in
        #expect(input.path.scoreChangeId == 101)
        return RelationshipWireFixtures.threadOutput
      }
    )
    let client = WoorisaiAPIClient(relationshipClient: stub)

    let scores = try await client.loadRelationshipScores()
    let history = try await client.loadScoreChanges(pageNumber: 1)
    let thread = try await client.loadScoreChange(id: 101)

    #expect(scores.currentParticipant.displayName == "봄")
    #expect(scores.partner.displayName == "여름")
    #expect(scores.outgoingScore == 70)
    #expect(scores.incomingScore == 82)
    #expect(history.pageNumber == 1)
    #expect(history.totalCount == 1)
    #expect(history.changes.first?.delta == 5)
    #expect(history.changes.first?.reason == "고마운 하루")
    #expect(thread.change.id == 101)
    #expect(thread.comments.first?.id == 301)
    #expect(thread.comments.first?.author.displayName == "여름")
    #expect(thread.comments.first?.content == "나도 고마워")
  }

  @Test
  func createScoreChangeSendsSingleMutationAndExplicitEmptyMediaList() async throws {
    let recorder = RelationshipInputRecorder()
    let stub = RelationshipAPIStub(createScore: { input in
      await recorder.record(scoreInput: input)
      return RelationshipWireFixtures.createdScoreOutput
    })
    let client = WoorisaiAPIClient(relationshipClient: stub)
    let draft = try RelationshipScoreChangeDraft(
      mutation: .target(75),
      reason: "  새 점수  ",
      mediaUploadIDs: []
    )

    let created = try await client.createScoreChange(draft)

    let input = try #require(await recorder.scoreInput)
    guard case .json(let request) = input.body else {
      Issue.record("Expected JSON score request")
      return
    }
    #expect(request.delta == nil)
    #expect(request.targetScore == 75)
    #expect(request.reason == "새 점수")
    #expect(request.mediaUploadIds == [])
    #expect(created.change.delta == 5)
    #expect(created.outgoingScore == 75)
  }

  @Test
  func createCommentSendsExplicitEmptyMediaListAndMapsCommonFields() async throws {
    let recorder = RelationshipInputRecorder()
    let stub = RelationshipAPIStub(createComment: { input in
      await recorder.record(commentInput: input)
      return RelationshipWireFixtures.createdCommentOutput
    })
    let client = WoorisaiAPIClient(relationshipClient: stub)
    let draft = try RelationshipScoreCommentDraft(content: "  새 댓글  ", mediaUploadIDs: [])

    let comment = try await client.createScoreChangeComment(scoreChangeID: 101, draft: draft)

    let input = try #require(await recorder.commentInput)
    #expect(input.path.scoreChangeId == 101)
    guard case .json(let request) = input.body else {
      Issue.record("Expected JSON comment request")
      return
    }
    #expect(request.content == "새 댓글")
    #expect(request.mediaUploadIds == [])
    #expect(comment.id == 302)
    #expect(comment.author.slot == .one)
    #expect(comment.content == "새 댓글")
    #expect(comment.attachments.isEmpty)
  }

  @Test
  func draftsValidateNormalizedUnicodeCodePointsLikeTheBackend() throws {
    let decomposedCharacter = "e\u{301}"
    let maximumReason = String(repeating: decomposedCharacter, count: 100)
    let maximumComment = String(repeating: decomposedCharacter, count: 250)

    let scoreDraft = try RelationshipScoreChangeDraft(
      mutation: .delta(1),
      reason: " \(maximumReason)\n"
    )
    let commentDraft = try RelationshipScoreCommentDraft(content: "\t\(maximumComment) ")

    #expect(scoreDraft.reason == maximumReason)
    #expect(commentDraft.content == maximumComment)
    #expect(scoreDraft.reason?.unicodeScalars.count == 200)
    #expect(commentDraft.content?.unicodeScalars.count == 500)

    #expect(throws: WoorisaiAPIError.invalidRequest) {
      _ = try RelationshipScoreChangeDraft(
        mutation: .delta(1),
        reason: maximumReason + decomposedCharacter
      )
    }
    #expect(throws: WoorisaiAPIError.invalidRequest) {
      _ = try RelationshipScoreCommentDraft(content: maximumComment + decomposedCharacter)
    }
  }

  @Test
  func mapsRelationshipConflictWithoutRetryingInsideAdapter() async throws {
    let counter = InvocationCounter()
    let stub = RelationshipAPIStub(createScore: { _ in
      await counter.increment()
      return try RelationshipWireFixtures.conflictOutput()
    })
    let client = WoorisaiAPIClient(relationshipClient: stub)
    let draft = try RelationshipScoreChangeDraft(mutation: .delta(5))

    await #expect(throws: WoorisaiAPIError.conflict) {
      _ = try await client.createScoreChange(draft)
    }
    #expect(await counter.value == 1)
  }

  @Test
  func rejectsInvalidIdentifiersAndPageNumbersBeforeTransport() async {
    let counter = InvocationCounter()
    let stub = RelationshipAPIStub(
      history: { _ in
        await counter.increment()
        return RelationshipWireFixtures.historyOutput
      },
      thread: { _ in
        await counter.increment()
        return RelationshipWireFixtures.threadOutput
      }
    )
    let client = WoorisaiAPIClient(relationshipClient: stub)

    await #expect(throws: WoorisaiAPIError.invalidRequest) {
      _ = try await client.loadScoreChanges(pageNumber: 0)
    }
    await #expect(throws: WoorisaiAPIError.invalidRequest) {
      _ = try await client.loadScoreChange(id: 0)
    }
    #expect(await counter.value == 0)
  }

  @Test
  func rejectsGeneratedHistoryThatViolatesContractBoundsOrOwnership() async {
    var overlongReason = RelationshipWireFixtures.change
    overlongReason.reason = String(repeating: "가", count: 201)
    let invalidReasonChange = overlongReason
    let reasonClient = WoorisaiAPIClient(
      relationshipClient: RelationshipAPIStub(history: { _ in
        RelationshipWireFixtures.historyOutput(change: invalidReasonChange)
      })
    )
    await #expect(throws: WoorisaiAPIError.schemaDrift) {
      _ = try await reasonClient.loadScoreChanges(pageNumber: 1)
    }

    var invalidTarget = RelationshipWireFixtures.partner
    invalidTarget.mine = true
    var invalidOwnership = RelationshipWireFixtures.change
    invalidOwnership.targetParticipant = invalidTarget
    let invalidOwnershipChange = invalidOwnership
    let ownershipClient = WoorisaiAPIClient(
      relationshipClient: RelationshipAPIStub(history: { _ in
        RelationshipWireFixtures.historyOutput(change: invalidOwnershipChange)
      })
    )
    await #expect(throws: WoorisaiAPIError.schemaDrift) {
      _ = try await ownershipClient.loadScoreChanges(pageNumber: 1)
    }
  }

  @Test
  func rejectsInvalidFlexibleAttachmentBranchAndNonCurrentCreatedAuthor() async throws {
    var invalidGroupComment = RelationshipWireFixtures.comment
    invalidGroupComment.attachments = .case2([])
    let invalidAttachmentComment = invalidGroupComment
    let threadClient = WoorisaiAPIClient(
      relationshipClient: RelationshipAPIStub(thread: { _ in
        RelationshipWireFixtures.threadOutput(comment: invalidAttachmentComment)
      })
    )
    await #expect(throws: WoorisaiAPIError.schemaDrift) {
      _ = try await threadClient.loadScoreChange(id: 101)
    }

    var nonCurrentComment = RelationshipWireFixtures.createdComment
    nonCurrentComment.author = RelationshipWireFixtures.partner
    let invalidCreatedComment = nonCurrentComment
    let commentClient = WoorisaiAPIClient(
      relationshipClient: RelationshipAPIStub(createComment: { _ in
        RelationshipWireFixtures.createdCommentOutput(comment: invalidCreatedComment)
      })
    )
    let draft = try RelationshipScoreCommentDraft(content: "새 댓글")
    await #expect(throws: WoorisaiAPIError.schemaDrift) {
      _ = try await commentClient.createScoreChangeComment(scoreChangeID: 101, draft: draft)
    }
  }

  @Test
  func mapsResponseBodyNetworkLossToAmbiguousTransportFailure() async throws {
    let stub = RelationshipAPIStub(createScore: { input in
      throw ClientError(
        operationID: "createScoreChange",
        operationInput: input,
        response: HTTPResponse(status: .created),
        causeDescription: "Synthetic response body stream failure",
        underlyingError: URLError(.networkConnectionLost)
      )
    })
    let client = WoorisaiAPIClient(relationshipClient: stub)
    let draft = try RelationshipScoreChangeDraft(mutation: .delta(5))

    await #expect(throws: WoorisaiAPIError.transport) {
      _ = try await client.createScoreChange(draft)
    }
  }
}

private struct RelationshipAPIStub: RelationshipAPIProtocol {
  typealias ScoresHandler = @Sendable (Operations.GetRelationshipScores.Input) async throws ->
    Operations.GetRelationshipScores.Output
  typealias HistoryHandler = @Sendable (Operations.ListScoreChanges.Input) async throws ->
    Operations.ListScoreChanges.Output
  typealias CreateScoreHandler = @Sendable (Operations.CreateScoreChange.Input) async throws ->
    Operations.CreateScoreChange.Output
  typealias ThreadHandler = @Sendable (Operations.GetScoreChange.Input) async throws ->
    Operations.GetScoreChange.Output
  typealias CreateCommentHandler = @Sendable (
    Operations.CreateScoreChangeComment.Input
  ) async throws -> Operations.CreateScoreChangeComment.Output

  private let scores: ScoresHandler?
  private let history: HistoryHandler?
  private let createScore: CreateScoreHandler?
  private let thread: ThreadHandler?
  private let createComment: CreateCommentHandler?

  init(
    scores: ScoresHandler? = nil,
    history: HistoryHandler? = nil,
    createScore: CreateScoreHandler? = nil,
    thread: ThreadHandler? = nil,
    createComment: CreateCommentHandler? = nil
  ) {
    self.scores = scores
    self.history = history
    self.createScore = createScore
    self.thread = thread
    self.createComment = createComment
  }

  func getRelationshipScores(
    _ input: Operations.GetRelationshipScores.Input
  ) async throws -> Operations.GetRelationshipScores.Output {
    guard let scores else { throw RelationshipAPITestFailure.unexpectedOperation }
    return try await scores(input)
  }

  func listScoreChanges(
    _ input: Operations.ListScoreChanges.Input
  ) async throws -> Operations.ListScoreChanges.Output {
    guard let history else { throw RelationshipAPITestFailure.unexpectedOperation }
    return try await history(input)
  }

  func createScoreChange(
    _ input: Operations.CreateScoreChange.Input
  ) async throws -> Operations.CreateScoreChange.Output {
    guard let createScore else { throw RelationshipAPITestFailure.unexpectedOperation }
    return try await createScore(input)
  }

  func getScoreChange(
    _ input: Operations.GetScoreChange.Input
  ) async throws -> Operations.GetScoreChange.Output {
    guard let thread else { throw RelationshipAPITestFailure.unexpectedOperation }
    return try await thread(input)
  }

  func createScoreChangeComment(
    _ input: Operations.CreateScoreChangeComment.Input
  ) async throws -> Operations.CreateScoreChangeComment.Output {
    guard let createComment else { throw RelationshipAPITestFailure.unexpectedOperation }
    return try await createComment(input)
  }
}

private actor RelationshipInputRecorder {
  private(set) var scoreInput: Operations.CreateScoreChange.Input?
  private(set) var commentInput: Operations.CreateScoreChangeComment.Input?

  func record(scoreInput: Operations.CreateScoreChange.Input) {
    self.scoreInput = scoreInput
  }

  func record(commentInput: Operations.CreateScoreChangeComment.Input) {
    self.commentInput = commentInput
  }
}

private actor InvocationCounter {
  private(set) var value = 0

  func increment() {
    value += 1
  }
}

private enum RelationshipAPITestFailure: Error, Sendable {
  case unexpectedOperation
}

private enum RelationshipWireFixtures {
  static let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
  static let current = Components.Schemas.RelationshipParticipant(
    slot: ._1,
    displayName: "봄",
    mine: true
  )
  static let partner = Components.Schemas.RelationshipParticipant(
    slot: ._2,
    displayName: "여름",
    mine: false
  )
  static let outgoing = Components.Schemas.RelationshipScore(
    sourceParticipant: current,
    targetParticipant: partner,
    currentScore: 70,
    updatedAt: timestamp
  )
  static let incoming = Components.Schemas.RelationshipScore(
    sourceParticipant: partner,
    targetParticipant: current,
    currentScore: 82,
    updatedAt: timestamp.addingTimeInterval(1)
  )
  static let change = Components.Schemas.ScoreChange(
    id: 101,
    sourceParticipant: current,
    targetParticipant: partner,
    changedBy: current,
    delta: 5,
    resultingScore: 70,
    reason: "고마운 하루",
    createdAt: timestamp,
    commentCount: 1,
    attachments: []
  )
  static let comment = Components.Schemas.ScoreChangeComment(
    id: 301,
    author: partner,
    content: "나도 고마워",
    createdAt: timestamp.addingTimeInterval(1),
    attachments: .case1([])
  )
  static let createdChange = Components.Schemas.ScoreChange(
    id: 102,
    sourceParticipant: current,
    targetParticipant: partner,
    changedBy: current,
    delta: 5,
    resultingScore: 75,
    reason: "새 점수",
    createdAt: timestamp.addingTimeInterval(2),
    commentCount: 0,
    attachments: []
  )
  static let createdOutgoing = Components.Schemas.RelationshipScore(
    sourceParticipant: current,
    targetParticipant: partner,
    currentScore: 75,
    updatedAt: timestamp.addingTimeInterval(2)
  )
  static let createdComment = Components.Schemas.ScoreChangeComment(
    id: 302,
    author: current,
    content: "새 댓글",
    createdAt: timestamp.addingTimeInterval(3),
    attachments: .case1([])
  )

  static let scoresOutput = Operations.GetRelationshipScores.Output.ok(
    .init(
      headers: .init(cacheControl: "no-store"),
      body: .json(
        .init(_self: current, partner: partner, outgoing: outgoing, incoming: incoming)
      )
    )
  )

  static let historyOutput = Operations.ListScoreChanges.Output.ok(
    .init(
      headers: .init(cacheControl: "no-store"),
      body: .json(
        .init(
          results: [change],
          paging: .init(pageNumber: 1, pageSize: ._20, hasNext: false, totalCount: 1)
        )
      )
    )
  )

  static func historyOutput(
    change: Components.Schemas.ScoreChange
  ) -> Operations.ListScoreChanges.Output {
    .ok(
      .init(
        headers: .init(cacheControl: "no-store"),
        body: .json(
          .init(
            results: [change],
            paging: .init(pageNumber: 1, pageSize: ._20, hasNext: false, totalCount: 1)
          )
        )
      )
    )
  }

  static let threadOutput = Operations.GetScoreChange.Output.ok(
    .init(
      headers: .init(cacheControl: "no-store"),
      body: .json(.init(change: change, comments: [comment]))
    )
  )

  static func threadOutput(
    comment: Components.Schemas.ScoreChangeComment
  ) -> Operations.GetScoreChange.Output {
    .ok(
      .init(
        headers: .init(cacheControl: "no-store"),
        body: .json(.init(change: change, comments: [comment]))
      )
    )
  }

  static let createdScoreOutput = Operations.CreateScoreChange.Output.created(
    .init(
      headers: .init(cacheControl: "no-store"),
      body: .json(.init(change: createdChange, outgoing: createdOutgoing))
    )
  )

  static let createdCommentOutput = Operations.CreateScoreChangeComment.Output.created(
    .init(
      headers: .init(cacheControl: "no-store"),
      body: .json(.init(comment: createdComment))
    )
  )

  static func createdCommentOutput(
    comment: Components.Schemas.ScoreChangeComment
  ) -> Operations.CreateScoreChangeComment.Output {
    .created(
      .init(
        headers: .init(cacheControl: "no-store"),
        body: .json(.init(comment: comment))
      )
    )
  }

  static func conflictOutput() throws -> Operations.CreateScoreChange.Output {
    let problem = try JSONDecoder().decode(
      Components.Schemas.RelationshipConflictProblem.self,
      from: Data(
        """
        {
          "title": "Relationship conflict",
          "status": 409,
          "detail": "Reload the latest relationship state.",
          "instance": "/api/v2/score-changes",
          "errorCode": "RELATIONSHIP_CONFLICT"
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
