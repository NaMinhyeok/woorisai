import Foundation
import Testing

@testable import WoorisaiAPI

struct WoorisaiDiaryAPITests {
  @Test
  func mapsListAndDetailIntoAppOwnedModels() async throws {
    let stub = DiaryAPIStub(
      list: { input in
        #expect(input.query.pageNumber == 1)
        return DiaryWireFixtures.listOutput
      },
      detail: { input in
        #expect(input.path.entryId == 41)
        return DiaryWireFixtures.detailOutput
      }
    )
    let api = WoorisaiDiaryAPI(diaryClient: stub)

    let page = try await api.loadDiaryEntries(pageNumber: 1)
    let detail = try await api.loadDiaryEntry(id: 41)

    #expect(page.entries == [DiaryWireFixtures.appEntry])
    #expect(page.pageNumber == 1)
    #expect(page.totalCount == 1)
    #expect(detail.entry == DiaryWireFixtures.appEntry)
    #expect(detail.comments == [DiaryWireFixtures.appComment])
  }

  @Test
  func forwardsAllMutationsExactlyOnceAndPreservesPatchSemantics() async throws {
    let recorder = DiaryInputRecorder()
    let stub = DiaryAPIStub(
      createEntry: { input in
        await recorder.record(createEntry: input)
        return DiaryWireFixtures.createEntryOutput
      },
      updateEntry: { input in
        await recorder.record(updateEntry: input)
        return DiaryWireFixtures.updateEntryOutput
      },
      deleteEntry: { input in
        await recorder.record(deleteEntry: input)
        return DiaryWireFixtures.deleteEntryOutput
      },
      createComment: { input in
        await recorder.record(createComment: input)
        return DiaryWireFixtures.createCommentOutput
      },
      updateComment: { input in
        await recorder.record(updateComment: input)
        return DiaryWireFixtures.updateCommentOutput
      },
      deleteComment: { input in
        await recorder.record(deleteComment: input)
        return DiaryWireFixtures.deleteCommentOutput
      }
    )
    let api = WoorisaiDiaryAPI(diaryClient: stub)
    let uploadID = try #require(UUID(uuidString: "5e8216f2-dda4-4f01-8f26-4a6889c67abe"))

    let created = try await api.createDiaryEntry(
      try DiaryEntryCreateDraft(content: "  새 일기  ", mediaUploadIDs: [uploadID])
    )
    let updated = try await api.updateDiaryEntry(
      id: 41,
      draft: try DiaryEntryUpdateDraft(
        content: "  고친 일기  ",
        attachments: .replace([])
      )
    )
    try await api.deleteDiaryEntry(id: 41)
    let createdComment = try await api.createDiaryComment(
      entryID: 41,
      draft: try DiaryCommentDraft(content: "  새 댓글  ")
    )
    let updatedComment = try await api.updateDiaryComment(
      id: 51,
      draft: try DiaryCommentDraft(content: "  고친 댓글  ")
    )
    try await api.deleteDiaryComment(id: 51)

    let createEntryInput = try #require(await recorder.createEntryInput)
    guard case .json(let createEntryRequest) = createEntryInput.body else {
      Issue.record("Expected a JSON create-entry request")
      return
    }
    #expect(createEntryRequest.content == "새 일기")
    #expect(createEntryRequest.mediaUploadIds == [uploadID.uuidString])

    let updateEntryInput = try #require(await recorder.updateEntryInput)
    #expect(updateEntryInput.path.entryId == 41)
    guard case .json(let updateEntryRequest) = updateEntryInput.body else {
      Issue.record("Expected a JSON update-entry request")
      return
    }
    #expect(updateEntryRequest.content == "고친 일기")
    #expect(updateEntryRequest.mediaUploadIds == [])
    #expect(await recorder.deleteEntryInput?.path.entryId == 41)

    let createCommentInput = try #require(await recorder.createCommentInput)
    #expect(createCommentInput.path.entryId == 41)
    guard case .json(let createCommentRequest) = createCommentInput.body else {
      Issue.record("Expected a JSON create-comment request")
      return
    }
    #expect(createCommentRequest.content == "새 댓글")

    let updateCommentInput = try #require(await recorder.updateCommentInput)
    #expect(updateCommentInput.path.commentId == 51)
    guard case .json(let updateCommentRequest) = updateCommentInput.body else {
      Issue.record("Expected a JSON update-comment request")
      return
    }
    #expect(updateCommentRequest.content == "고친 댓글")
    #expect(await recorder.deleteCommentInput?.path.commentId == 51)

    #expect(created == DiaryWireFixtures.appEntry)
    #expect(updated.content == "고친 일기")
    #expect(createdComment.content == "새 댓글")
    #expect(updatedComment.content == "고친 댓글")
  }

  @Test
  func omittedAttachmentPatchRemainsOmitted() async throws {
    let recorder = DiaryInputRecorder()
    let api = WoorisaiDiaryAPI(
      diaryClient: DiaryAPIStub(updateEntry: { input in
        await recorder.record(updateEntry: input)
        return DiaryWireFixtures.updateEntryOutput
      })
    )

    _ = try await api.updateDiaryEntry(
      id: 41,
      draft: try DiaryEntryUpdateDraft(content: "내용만 변경", attachments: .preserve)
    )

    let input = try #require(await recorder.updateEntryInput)
    guard case .json(let request) = input.body else {
      Issue.record("Expected a JSON update-entry request")
      return
    }
    #expect(request.content == "내용만 변경")
    #expect(request.mediaUploadIds == nil)
  }

  @Test
  func mapsConflictWithoutRetryingMutation() async throws {
    let counter = DiaryInvocationCounter()
    let api = WoorisaiDiaryAPI(
      diaryClient: DiaryAPIStub(updateEntry: { _ in
        await counter.increment()
        return try DiaryWireFixtures.conflictOutput()
      })
    )

    await #expect(throws: WoorisaiAPIError.conflict) {
      _ = try await api.updateDiaryEntry(
        id: 41,
        draft: try DiaryEntryUpdateDraft(content: "경합한 변경")
      )
    }
    #expect(await counter.value == 1)
  }

  @Test
  func rejectsInvalidIdentifiersAndDraftsBeforeTransport() async {
    let counter = DiaryInvocationCounter()
    let api = WoorisaiDiaryAPI(
      diaryClient: DiaryAPIStub(
        list: { _ in
          await counter.increment()
          return DiaryWireFixtures.listOutput
        },
        detail: { _ in
          await counter.increment()
          return DiaryWireFixtures.detailOutput
        }
      )
    )

    await #expect(throws: WoorisaiAPIError.invalidRequest) {
      _ = try await api.loadDiaryEntries(pageNumber: 0)
    }
    await #expect(throws: WoorisaiAPIError.invalidRequest) {
      _ = try await api.loadDiaryEntry(id: 0)
    }
    #expect(throws: WoorisaiAPIError.invalidRequest) {
      _ = try DiaryEntryCreateDraft(content: "   ")
    }
    #expect(throws: WoorisaiAPIError.invalidRequest) {
      _ = try DiaryEntryUpdateDraft()
    }
    #expect(throws: WoorisaiAPIError.invalidRequest) {
      _ = try DiaryCommentDraft(content: String(repeating: "가", count: 501))
    }
    #expect(await counter.value == 0)
  }

  @Test
  func draftsValidateNormalizedUnicodeCodePointsLikeTheBackend() throws {
    let decomposedCharacter = "e\u{301}"
    let maximumEntry = String(repeating: decomposedCharacter, count: 500)
    let maximumComment = String(repeating: decomposedCharacter, count: 250)

    let createDraft = try DiaryEntryCreateDraft(content: " \(maximumEntry)\n")
    let updateDraft = try DiaryEntryUpdateDraft(content: "\t\(maximumEntry) ")
    let commentDraft = try DiaryCommentDraft(content: " \(maximumComment)\n")

    #expect(createDraft.content == maximumEntry)
    #expect(updateDraft.content == maximumEntry)
    #expect(commentDraft.content == maximumComment)
    #expect(createDraft.content.unicodeScalars.count == 1_000)
    #expect(commentDraft.content.unicodeScalars.count == 500)

    #expect(throws: WoorisaiAPIError.invalidRequest) {
      _ = try DiaryEntryCreateDraft(content: maximumEntry + decomposedCharacter)
    }
    #expect(throws: WoorisaiAPIError.invalidRequest) {
      _ = try DiaryEntryUpdateDraft(content: maximumEntry + decomposedCharacter)
    }
    #expect(throws: WoorisaiAPIError.invalidRequest) {
      _ = try DiaryCommentDraft(content: maximumComment + decomposedCharacter)
    }
  }

  @Test
  func rejectsWireOrderingCountAndOwnershipDrift() async {
    var invalidDetail = DiaryWireFixtures.detail
    invalidDetail.commentCount = 2
    let invalidCount = invalidDetail
    let countAPI = WoorisaiDiaryAPI(
      diaryClient: DiaryAPIStub(detail: { _ in
        DiaryWireFixtures.detailOutput(detail: invalidCount)
      })
    )
    await #expect(throws: WoorisaiAPIError.schemaDrift) {
      _ = try await countAPI.loadDiaryEntry(id: 41)
    }

    var nonMineCreated = DiaryWireFixtures.entry
    nonMineCreated.isMine = false
    let invalidCreated = nonMineCreated
    let createAPI = WoorisaiDiaryAPI(
      diaryClient: DiaryAPIStub(createEntry: { _ in
        DiaryWireFixtures.createEntryOutput(entry: invalidCreated)
      })
    )
    await #expect(throws: WoorisaiAPIError.schemaDrift) {
      _ = try await createAPI.createDiaryEntry(
        try DiaryEntryCreateDraft(content: "새 일기")
      )
    }
  }
}

private struct DiaryAPIStub: DiaryAPIProtocol {
  typealias ListHandler =
    @Sendable (Operations.ListDiaryEntries.Input) async throws ->
    Operations.ListDiaryEntries.Output
  typealias CreateEntryHandler =
    @Sendable (Operations.CreateDiaryEntry.Input) async throws ->
    Operations.CreateDiaryEntry.Output
  typealias DetailHandler =
    @Sendable (Operations.GetDiaryEntry.Input) async throws ->
    Operations.GetDiaryEntry.Output
  typealias UpdateEntryHandler =
    @Sendable (Operations.UpdateDiaryEntry.Input) async throws ->
    Operations.UpdateDiaryEntry.Output
  typealias DeleteEntryHandler =
    @Sendable (Operations.DeleteDiaryEntry.Input) async throws ->
    Operations.DeleteDiaryEntry.Output
  typealias CreateCommentHandler =
    @Sendable (
      Operations.CreateDiaryEntryComment.Input
    ) async throws -> Operations.CreateDiaryEntryComment.Output
  typealias UpdateCommentHandler =
    @Sendable (
      Operations.UpdateDiaryEntryComment.Input
    ) async throws -> Operations.UpdateDiaryEntryComment.Output
  typealias DeleteCommentHandler =
    @Sendable (
      Operations.DeleteDiaryEntryComment.Input
    ) async throws -> Operations.DeleteDiaryEntryComment.Output

  let list: ListHandler?
  let createEntry: CreateEntryHandler?
  let detail: DetailHandler?
  let updateEntry: UpdateEntryHandler?
  let deleteEntry: DeleteEntryHandler?
  let createComment: CreateCommentHandler?
  let updateComment: UpdateCommentHandler?
  let deleteComment: DeleteCommentHandler?

  init(
    list: ListHandler? = nil,
    createEntry: CreateEntryHandler? = nil,
    detail: DetailHandler? = nil,
    updateEntry: UpdateEntryHandler? = nil,
    deleteEntry: DeleteEntryHandler? = nil,
    createComment: CreateCommentHandler? = nil,
    updateComment: UpdateCommentHandler? = nil,
    deleteComment: DeleteCommentHandler? = nil
  ) {
    self.list = list
    self.createEntry = createEntry
    self.detail = detail
    self.updateEntry = updateEntry
    self.deleteEntry = deleteEntry
    self.createComment = createComment
    self.updateComment = updateComment
    self.deleteComment = deleteComment
  }

  func listDiaryEntries(
    _ input: Operations.ListDiaryEntries.Input
  ) async throws -> Operations.ListDiaryEntries.Output {
    guard let list else { throw DiaryAPITestFailure.unexpectedOperation }
    return try await list(input)
  }

  func createDiaryEntry(
    _ input: Operations.CreateDiaryEntry.Input
  ) async throws -> Operations.CreateDiaryEntry.Output {
    guard let createEntry else { throw DiaryAPITestFailure.unexpectedOperation }
    return try await createEntry(input)
  }

  func getDiaryEntry(
    _ input: Operations.GetDiaryEntry.Input
  ) async throws -> Operations.GetDiaryEntry.Output {
    guard let detail else { throw DiaryAPITestFailure.unexpectedOperation }
    return try await detail(input)
  }

  func updateDiaryEntry(
    _ input: Operations.UpdateDiaryEntry.Input
  ) async throws -> Operations.UpdateDiaryEntry.Output {
    guard let updateEntry else { throw DiaryAPITestFailure.unexpectedOperation }
    return try await updateEntry(input)
  }

  func deleteDiaryEntry(
    _ input: Operations.DeleteDiaryEntry.Input
  ) async throws -> Operations.DeleteDiaryEntry.Output {
    guard let deleteEntry else { throw DiaryAPITestFailure.unexpectedOperation }
    return try await deleteEntry(input)
  }

  func createDiaryEntryComment(
    _ input: Operations.CreateDiaryEntryComment.Input
  ) async throws -> Operations.CreateDiaryEntryComment.Output {
    guard let createComment else { throw DiaryAPITestFailure.unexpectedOperation }
    return try await createComment(input)
  }

  func updateDiaryEntryComment(
    _ input: Operations.UpdateDiaryEntryComment.Input
  ) async throws -> Operations.UpdateDiaryEntryComment.Output {
    guard let updateComment else { throw DiaryAPITestFailure.unexpectedOperation }
    return try await updateComment(input)
  }

  func deleteDiaryEntryComment(
    _ input: Operations.DeleteDiaryEntryComment.Input
  ) async throws -> Operations.DeleteDiaryEntryComment.Output {
    guard let deleteComment else { throw DiaryAPITestFailure.unexpectedOperation }
    return try await deleteComment(input)
  }
}

private actor DiaryInputRecorder {
  private(set) var createEntryInput: Operations.CreateDiaryEntry.Input?
  private(set) var updateEntryInput: Operations.UpdateDiaryEntry.Input?
  private(set) var deleteEntryInput: Operations.DeleteDiaryEntry.Input?
  private(set) var createCommentInput: Operations.CreateDiaryEntryComment.Input?
  private(set) var updateCommentInput: Operations.UpdateDiaryEntryComment.Input?
  private(set) var deleteCommentInput: Operations.DeleteDiaryEntryComment.Input?

  func record(createEntry input: Operations.CreateDiaryEntry.Input) { createEntryInput = input }
  func record(updateEntry input: Operations.UpdateDiaryEntry.Input) { updateEntryInput = input }
  func record(deleteEntry input: Operations.DeleteDiaryEntry.Input) { deleteEntryInput = input }
  func record(createComment input: Operations.CreateDiaryEntryComment.Input) {
    createCommentInput = input
  }
  func record(updateComment input: Operations.UpdateDiaryEntryComment.Input) {
    updateCommentInput = input
  }
  func record(deleteComment input: Operations.DeleteDiaryEntryComment.Input) {
    deleteCommentInput = input
  }
}

private actor DiaryInvocationCounter {
  private(set) var value = 0
  func increment() { value += 1 }
}

private enum DiaryAPITestFailure: Error, Sendable {
  case unexpectedOperation
}

private enum DiaryWireFixtures {
  static let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
  static let author = Components.Schemas.DiaryParticipant(slot: ._1, displayName: "봄")
  static let partner = Components.Schemas.DiaryParticipant(slot: ._2, displayName: "여름")
  static let entry = Components.Schemas.DiaryEntryResponse(
    id: 41,
    author: author,
    content: "첫 일기",
    createdAt: timestamp,
    updatedAt: nil,
    isMine: true,
    attachments: .case1([]),
    commentCount: 1
  )
  static let updatedEntry = Components.Schemas.DiaryEntryUpdatedResponse(
    id: 41,
    author: author,
    content: "고친 일기",
    createdAt: timestamp,
    updatedAt: timestamp.addingTimeInterval(30),
    isMine: true,
    attachments: .case1([]),
    commentCount: 1
  )
  static let comment = Components.Schemas.DiaryCommentResponse(
    id: 51,
    author: partner,
    content: "잘 읽었어",
    createdAt: timestamp.addingTimeInterval(10),
    updatedAt: nil,
    isMine: false
  )
  static let createdComment = Components.Schemas.DiaryCommentResponse(
    id: 52,
    author: author,
    content: "새 댓글",
    createdAt: timestamp.addingTimeInterval(20),
    updatedAt: nil,
    isMine: true
  )
  static let updatedComment = Components.Schemas.DiaryCommentUpdatedResponse(
    id: 51,
    author: author,
    content: "고친 댓글",
    createdAt: timestamp.addingTimeInterval(10),
    updatedAt: timestamp.addingTimeInterval(30),
    isMine: true
  )
  static let detail = Components.Schemas.DiaryEntryDetailResponse(
    id: entry.id,
    author: entry.author,
    content: entry.content,
    createdAt: entry.createdAt,
    updatedAt: entry.updatedAt,
    isMine: entry.isMine,
    attachments: entry.attachments,
    commentCount: entry.commentCount,
    comments: [comment]
  )

  static let appAuthor = DiaryParticipant(slot: .one, displayName: "봄")
  static let appPartner = DiaryParticipant(slot: .two, displayName: "여름")
  static let appEntry = DiaryEntry(
    id: 41,
    author: appAuthor,
    content: "첫 일기",
    createdAt: timestamp,
    updatedAt: nil,
    isMine: true,
    attachments: [],
    commentCount: 1
  )
  static let appComment = DiaryComment(
    id: 51,
    author: appPartner,
    content: "잘 읽었어",
    createdAt: timestamp.addingTimeInterval(10),
    updatedAt: nil,
    isMine: false
  )

  static let listOutput = Operations.ListDiaryEntries.Output.ok(
    .init(
      headers: .init(cacheControl: "no-store"),
      body: .json(
        .init(
          results: [entry],
          pageNumber: 1,
          pageSize: ._20,
          hasNext: false,
          totalCount: 1
        )
      )
    )
  )
  static let detailOutput = Operations.GetDiaryEntry.Output.ok(
    .init(headers: .init(cacheControl: "no-store"), body: .json(detail))
  )
  static let createEntryOutput = Operations.CreateDiaryEntry.Output.created(
    .init(headers: .init(cacheControl: "no-store"), body: .json(entry))
  )
  static let updateEntryOutput = Operations.UpdateDiaryEntry.Output.ok(
    .init(headers: .init(cacheControl: "no-store"), body: .json(updatedEntry))
  )
  static let deleteEntryOutput = Operations.DeleteDiaryEntry.Output.noContent(
    .init(headers: .init(cacheControl: "no-store"))
  )
  static let createCommentOutput = Operations.CreateDiaryEntryComment.Output.created(
    .init(headers: .init(cacheControl: "no-store"), body: .json(createdComment))
  )
  static let updateCommentOutput = Operations.UpdateDiaryEntryComment.Output.ok(
    .init(headers: .init(cacheControl: "no-store"), body: .json(updatedComment))
  )
  static let deleteCommentOutput = Operations.DeleteDiaryEntryComment.Output.noContent(
    .init(headers: .init(cacheControl: "no-store"))
  )

  static func detailOutput(
    detail: Components.Schemas.DiaryEntryDetailResponse
  ) -> Operations.GetDiaryEntry.Output {
    .ok(.init(headers: .init(cacheControl: "no-store"), body: .json(detail)))
  }

  static func createEntryOutput(
    entry: Components.Schemas.DiaryEntryResponse
  ) -> Operations.CreateDiaryEntry.Output {
    .created(.init(headers: .init(cacheControl: "no-store"), body: .json(entry)))
  }

  static func conflictOutput() throws -> Operations.UpdateDiaryEntry.Output {
    let problem = try JSONDecoder().decode(
      Components.Schemas.DiaryConflictProblem.self,
      from: Data(
        """
        {
          "title": "Diary conflict",
          "status": 409,
          "detail": "Reload the latest diary state.",
          "instance": "/api/v2/diary-entries/41",
          "errorCode": "DIARY_CONFLICT"
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
