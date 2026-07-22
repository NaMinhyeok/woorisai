import Foundation
import Testing
import WoorisaiAPI

@testable import Woorisai

@MainActor
struct DiaryModelTests {
  @Test
  func loadsListAndDetailThenAppliesEntryAndCommentCRUDLocally() async {
    let service = DiaryServiceFake()
    let model = DiaryModel(service: service)

    model.loadIfNeeded()
    await diaryExpectEventually { model.listState == .loaded }
    model.loadDetail(entryID: DiaryFeatureFixtures.entry.id)
    await diaryExpectEventually { model.detailState == .loaded }

    model.updateEntry(entryID: 41, content: "고친 일기")
    await diaryExpectEventually {
      await service.updateEntryCount == 1 && model.mutationState == .idle
    }
    #expect(model.entries.first?.content == "고친 일기")
    #expect(model.selectedDetail?.entry.content == "고친 일기")

    model.createComment(entryID: 41, content: "새 댓글")
    await diaryExpectEventually {
      await service.createCommentCount == 1 && model.mutationState == .idle
    }
    #expect(model.selectedDetail?.comments.map(\.id) == [51, 52])
    #expect(model.entries.first?.commentCount == 2)

    model.updateComment(entryID: 41, commentID: 52, content: "고친 댓글")
    await diaryExpectEventually {
      await service.updateCommentCount == 1 && model.mutationState == .idle
    }
    #expect(model.selectedDetail?.comments.last?.content == "고친 댓글")

    model.deleteComment(entryID: 41, commentID: 52)
    await diaryExpectEventually {
      await service.deleteCommentCount == 1 && model.mutationState == .idle
    }
    #expect(model.selectedDetail?.comments.map(\.id) == [51])
    #expect(model.entries.first?.commentCount == 1)

    model.deleteEntry(entryID: 41)
    await diaryExpectEventually {
      await service.deleteEntryCount == 1 && model.mutationState == .idle
    }
    #expect(model.entries.isEmpty)
    #expect(model.selectedDetail == nil)

    #expect(await service.updateEntryCount == 1)
    #expect(await service.createCommentCount == 1)
    #expect(await service.updateCommentCount == 1)
    #expect(await service.deleteCommentCount == 1)
    #expect(await service.deleteEntryCount == 1)
  }

  @Test
  func createsEntryOnceAndAddsItToNewestFirstList() async {
    let service = DiaryServiceFake()
    let model = DiaryModel(service: service)
    model.loadIfNeeded()
    await diaryExpectEventually { model.listState == .loaded }

    model.createEntry(content: "새 일기")
    await diaryExpectEventually {
      await service.createEntryCount == 1 && model.mutationState == .idle
    }

    #expect(model.entries.map(\.id) == [42, 41])
    #expect(model.totalCount == 2)
    #expect(await service.createEntryCount == 1)
  }

  @Test
  func invalidMediaBearingEntryDraftIsRejectedBeforeSubmissionOwnershipTransfers() async {
    let service = DiaryServiceFake()
    let model = DiaryModel(service: service)
    let uploadID = UUID(uuidString: "00000000-0000-0000-0000-000000000092")!
    let oversizedContent = String(repeating: "가", count: 1_001)

    let createAccepted = model.createEntry(
      content: oversizedContent,
      mediaUploadIDs: [uploadID]
    )
    let updateAccepted = model.updateEntry(
      entryID: DiaryFeatureFixtures.entry.id,
      content: oversizedContent,
      attachments: .replace([uploadID])
    )

    #expect(!createAccepted)
    #expect(!updateAccepted)
    #expect(await service.createEntryCount == 0)
    #expect(await service.updateEntryCount == 0)
  }

  @Test
  func conflictNeverRetriesAndReloadsOnlyAfterExplicitAction() async {
    let service = DiaryServiceFake(updateEntryFailure: .conflict)
    let model = DiaryModel(service: service)
    model.loadDetail(entryID: 41)
    await diaryExpectEventually { model.detailState == .loaded }

    model.updateEntry(entryID: 41, content: "경합한 내용")
    await diaryExpectEventually { model.conflict == .entry(entryID: 41) }

    #expect(model.rejectedMediaMutation == .updateEntry(entryID: 41))
    #expect(await service.updateEntryCount == 1)
    #expect(await service.detailLoadCount == 1)

    model.reloadAfterConflict()
    await diaryExpectEventually {
      await service.detailLoadCount == 2 && model.detailState == .loaded
    }

    #expect(await service.updateEntryCount == 1)
    #expect(model.conflict == nil)
    #expect(model.lastConflictEditorInvalidation == .entry(entryID: 41))
    #expect(
      DiaryConflictEditorDisposition.resolve(
        conflict: model.lastConflictEditorInvalidation,
        visibleEntryID: 41
      ) == .closeEntryEditor
    )
    #expect(
      DiaryConflictEditorDisposition.resolve(
        conflict: .comment(entryID: 41),
        visibleEntryID: 41
      ) == .closeCommentEditor
    )
  }

  @Test
  func dismissingConflictInvalidatesEditorsAndReloadsTheKnownStaleDetail() async {
    let entryService = DiaryServiceFake(updateEntryFailure: .conflict)
    let entryModel = DiaryModel(service: entryService)
    entryModel.loadDetail(entryID: 41)
    await diaryExpectEventually { entryModel.detailState == .loaded }
    entryModel.updateEntry(entryID: 41, content: "경합한 일기")
    await diaryExpectEventually { entryModel.conflict == .entry(entryID: 41) }

    entryModel.dismissConflict()

    #expect(entryModel.conflict == nil)
    #expect(entryModel.lastConflictEditorInvalidation == .entry(entryID: 41))
    #expect(entryModel.selectedDetail == nil)
    await diaryExpectEventually {
      await entryService.detailLoadCount == 2 && entryModel.detailState == .loaded
    }
    #expect(
      DiaryConflictEditorDisposition.resolve(
        conflict: entryModel.lastConflictEditorInvalidation,
        visibleEntryID: 41
      ) == .closeEntryEditor
    )

    let commentService = DiaryServiceFake(updateCommentFailure: .conflict)
    let commentModel = DiaryModel(service: commentService)
    commentModel.loadDetail(entryID: 41)
    await diaryExpectEventually { commentModel.detailState == .loaded }
    commentModel.updateComment(entryID: 41, commentID: 51, content: "경합한 댓글")
    await diaryExpectEventually { commentModel.conflict == .comment(entryID: 41) }

    commentModel.dismissConflict()

    #expect(commentModel.conflict == nil)
    #expect(commentModel.lastConflictEditorInvalidation == .comment(entryID: 41))
    #expect(commentModel.selectedDetail == nil)
    await diaryExpectEventually {
      await commentService.detailLoadCount == 2 && commentModel.detailState == .loaded
    }
    #expect(
      DiaryConflictEditorDisposition.resolve(
        conflict: commentModel.lastConflictEditorInvalidation,
        visibleEntryID: 41
      ) == .closeCommentEditor
    )
  }

  @Test
  func detailMutationReplacesAnInflightListReloadInsteadOfLeavingAStaleSpinner() async {
    let service = DelayedDiaryListMutationService()
    let model = DiaryModel(service: service)

    model.reload()
    await diaryExpectEventually { await service.firstListReadIsPending }
    #expect(model.listState == .loading)

    model.loadDetail(entryID: 41)
    await diaryExpectEventually { model.detailState == .loaded }
    model.updateEntry(entryID: 41, content: "고친 일기")

    await diaryExpectEventually {
      await service.listRequestCount == 2 && model.listState == .loaded
    }
    #expect(model.entries == [DiaryFeatureFixtures.updatedEntry])

    await service.finishStaleFirstListRead()
    await Task.yield()

    #expect(model.listState == .loaded)
    #expect(model.entries == [DiaryFeatureFixtures.updatedEntry])
  }

  @Test
  func ambiguousCreateFailureIsIssuedOnceWithoutAutomaticRetry() async {
    let service = DiaryServiceFake(createEntryFailure: .transport)
    let model = DiaryModel(service: service)
    model.loadIfNeeded()
    await diaryExpectEventually { model.listState == .loaded }

    model.createEntry(content: "응답을 잃은 일기")
    await diaryExpectEventually { model.mutationState == .failed }
    try? await Task.sleep(for: .milliseconds(30))

    #expect(await service.createEntryCount == 1)
    #expect(model.mutationNotice?.contains("자동으로 다시 보내지 않았습니다") == true)
  }

  @Test
  func screenExitInvalidatesDetailReadAndIgnoresLateCompletion() async {
    let service = ControlledDiaryDetailService()
    let model = DiaryModel(service: service)

    model.loadDetail(entryID: 41)
    await diaryExpectEventually { await service.requestCount == 1 }
    #expect(model.detailState == .loading)

    model.cancelDetailReadForScreenExit(entryID: 41)
    #expect(model.detailState == .idle)
    #expect(model.selectedDetail == nil)

    await service.succeed()
    await diaryExpectEventually { await service.returnCount == 1 }
    try? await Task.sleep(for: .milliseconds(30))

    #expect(model.detailState == .idle)
    #expect(model.selectedDetail == nil)
  }

  @Test
  func exitingPreviousDetailDoesNotCancelReplacementRead() async {
    let service = ControlledDiaryDetailService()
    let model = DiaryModel(service: service)

    model.loadDetail(entryID: DiaryFeatureFixtures.entry.id)
    await diaryExpectEventually { await service.requestCount == 1 }

    model.loadDetail(entryID: DiaryFeatureFixtures.createdEntry.id)
    await diaryExpectEventually { await service.requestCount == 2 }

    model.cancelDetailReadForScreenExit(entryID: DiaryFeatureFixtures.entry.id)
    #expect(model.detailState == .loading)
    #expect(model.selectedEntryID == DiaryFeatureFixtures.createdEntry.id)

    await service.succeed(
      entryID: DiaryFeatureFixtures.createdEntry.id,
      with: DiaryFeatureFixtures.createdDetail
    )
    await diaryExpectEventually {
      model.detailState == .loaded
        && model.selectedDetail?.entry.id == DiaryFeatureFixtures.createdEntry.id
    }

    await service.succeed(
      entryID: DiaryFeatureFixtures.entry.id,
      with: DiaryFeatureFixtures.detail
    )
    await diaryExpectEventually { await service.returnCount == 2 }
    try? await Task.sleep(for: .milliseconds(30))

    #expect(model.detailState == .loaded)
    #expect(model.selectedDetail == DiaryFeatureFixtures.createdDetail)
  }

  @Test
  func reloadCancelsStalePageAndAllowsAReplacementPageRequest() async {
    let service = ControlledDiaryPaginationService()
    let model = DiaryModel(service: service)
    model.loadIfNeeded()
    await diaryExpectEventually { model.listState == .loaded }

    model.loadNextPage()
    await diaryExpectEventually { await service.pageTwoRequestCount == 1 }

    model.reload()
    await diaryExpectEventually {
      await service.firstPageRequestCount == 2 && model.listState == .loaded
    }
    model.loadNextPage()
    await diaryExpectEventually { await service.pageTwoRequestCount == 2 }

    await service.succeedPageTwo(request: 1)
    await diaryExpectEventually { model.currentPage == 2 }
    await service.succeedPageTwo(request: 0)
    try? await Task.sleep(for: .milliseconds(30))

    #expect(model.currentPage == 2)
    #expect(model.entries.map(\.id) == [41, 40])
  }

  @Test
  func authenticationFailureClearsPrivateCacheAndRequestsPIN() async {
    let service = DiaryServiceFake(readFailure: .credentialRejected)
    let model = DiaryModel(service: service)

    model.loadIfNeeded()
    await diaryExpectEventually { model.authenticationRequired }

    #expect(model.entries.isEmpty)
    #expect(model.selectedDetail == nil)
    #expect(model.listState == .idle)
  }
}

private func diaryExpectEventually(
  timeout: Duration = .seconds(1),
  _ condition: @escaping @MainActor () async -> Bool
) async {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)
  while clock.now < deadline {
    if await condition() { return }
    await Task.yield()
  }
  Issue.record("Timed out waiting for diary state")
}

private actor DiaryServiceFake: DiaryServing {
  enum Failure: Sendable {
    case none
    case conflict
    case transport
    case credentialRejected
  }

  private let readFailure: Failure
  private let createEntryFailure: Failure
  private let updateEntryFailure: Failure
  private let updateCommentFailure: Failure

  private(set) var listLoadCount = 0
  private(set) var detailLoadCount = 0
  private(set) var createEntryCount = 0
  private(set) var updateEntryCount = 0
  private(set) var deleteEntryCount = 0
  private(set) var createCommentCount = 0
  private(set) var updateCommentCount = 0
  private(set) var deleteCommentCount = 0

  init(
    readFailure: Failure = .none,
    createEntryFailure: Failure = .none,
    updateEntryFailure: Failure = .none,
    updateCommentFailure: Failure = .none
  ) {
    self.readFailure = readFailure
    self.createEntryFailure = createEntryFailure
    self.updateEntryFailure = updateEntryFailure
    self.updateCommentFailure = updateCommentFailure
  }

  func loadDiaryEntries(pageNumber: Int) throws -> DiaryEntryPage {
    listLoadCount += 1
    try throwIfNeeded(readFailure)
    return DiaryFeatureFixtures.page
  }

  func createDiaryEntry(_ draft: DiaryEntryCreateDraft) throws -> DiaryEntry {
    createEntryCount += 1
    try throwIfNeeded(createEntryFailure)
    return DiaryFeatureFixtures.createdEntry
  }

  func loadDiaryEntry(id: Int64) throws -> DiaryEntryDetail {
    detailLoadCount += 1
    try throwIfNeeded(readFailure)
    return DiaryFeatureFixtures.detail
  }

  func updateDiaryEntry(id: Int64, draft: DiaryEntryUpdateDraft) throws -> DiaryEntry {
    updateEntryCount += 1
    try throwIfNeeded(updateEntryFailure)
    return DiaryFeatureFixtures.updatedEntry
  }

  func deleteDiaryEntry(id: Int64) {
    deleteEntryCount += 1
  }

  func createDiaryComment(entryID: Int64, draft: DiaryCommentDraft) -> DiaryComment {
    createCommentCount += 1
    return DiaryFeatureFixtures.createdComment
  }

  func updateDiaryComment(id: Int64, draft: DiaryCommentDraft) throws -> DiaryComment {
    updateCommentCount += 1
    try throwIfNeeded(updateCommentFailure)
    return DiaryFeatureFixtures.updatedComment
  }

  func deleteDiaryComment(id: Int64) {
    deleteCommentCount += 1
  }

  private func throwIfNeeded(_ failure: Failure) throws {
    switch failure {
    case .none: return
    case .conflict: throw WoorisaiAPIError.conflict
    case .transport: throw WoorisaiAPIError.transport
    case .credentialRejected: throw WoorisaiAPIError.credentialRejected
    }
  }
}

private actor ControlledDiaryDetailService: DiaryServing {
  private var continuations: [Int64: CheckedContinuation<DiaryEntryDetail, Error>] = [:]
  private(set) var requestCount = 0
  private(set) var returnCount = 0

  func loadDiaryEntry(id: Int64) async throws -> DiaryEntryDetail {
    requestCount += 1
    let detail = try await withCheckedThrowingContinuation { continuation in
      continuations[id] = continuation
    }
    returnCount += 1
    return detail
  }

  func succeed(
    entryID: Int64 = DiaryFeatureFixtures.entry.id,
    with detail: DiaryEntryDetail = DiaryFeatureFixtures.detail
  ) {
    continuations.removeValue(forKey: entryID)?.resume(returning: detail)
  }

  func loadDiaryEntries(pageNumber: Int) throws -> DiaryEntryPage { throw UnexpectedDiaryCall() }
  func createDiaryEntry(_ draft: DiaryEntryCreateDraft) throws -> DiaryEntry {
    throw UnexpectedDiaryCall()
  }
  func updateDiaryEntry(id: Int64, draft: DiaryEntryUpdateDraft) throws -> DiaryEntry {
    throw UnexpectedDiaryCall()
  }
  func deleteDiaryEntry(id: Int64) throws { throw UnexpectedDiaryCall() }
  func createDiaryComment(entryID: Int64, draft: DiaryCommentDraft) throws -> DiaryComment {
    throw UnexpectedDiaryCall()
  }
  func updateDiaryComment(id: Int64, draft: DiaryCommentDraft) throws -> DiaryComment {
    throw UnexpectedDiaryCall()
  }
  func deleteDiaryComment(id: Int64) throws { throw UnexpectedDiaryCall() }
}

private actor DelayedDiaryListMutationService: DiaryServing {
  private var firstListContinuation: CheckedContinuation<DiaryEntryPage, Error>?
  private(set) var listRequestCount = 0

  var firstListReadIsPending: Bool {
    firstListContinuation != nil
  }

  func loadDiaryEntries(pageNumber: Int) async throws -> DiaryEntryPage {
    listRequestCount += 1
    if listRequestCount == 1 {
      return try await withCheckedThrowingContinuation { continuation in
        firstListContinuation = continuation
      }
    }
    return DiaryFeatureFixtures.updatedPage
  }

  func finishStaleFirstListRead() {
    firstListContinuation?.resume(returning: DiaryFeatureFixtures.page)
    firstListContinuation = nil
  }

  func loadDiaryEntry(id: Int64) -> DiaryEntryDetail {
    DiaryFeatureFixtures.detail
  }

  func updateDiaryEntry(id: Int64, draft: DiaryEntryUpdateDraft) -> DiaryEntry {
    DiaryFeatureFixtures.updatedEntry
  }

  func createDiaryEntry(_ draft: DiaryEntryCreateDraft) throws -> DiaryEntry {
    throw UnexpectedDiaryCall()
  }
  func deleteDiaryEntry(id: Int64) throws { throw UnexpectedDiaryCall() }
  func createDiaryComment(entryID: Int64, draft: DiaryCommentDraft) throws -> DiaryComment {
    throw UnexpectedDiaryCall()
  }
  func updateDiaryComment(id: Int64, draft: DiaryCommentDraft) throws -> DiaryComment {
    throw UnexpectedDiaryCall()
  }
  func deleteDiaryComment(id: Int64) throws { throw UnexpectedDiaryCall() }
}

private actor ControlledDiaryPaginationService: DiaryServing {
  private var pageTwoContinuations: [CheckedContinuation<DiaryEntryPage, Error>] = []
  private(set) var firstPageRequestCount = 0
  private(set) var pageTwoRequestCount = 0

  func loadDiaryEntries(pageNumber: Int) async throws -> DiaryEntryPage {
    if pageNumber == 1 {
      firstPageRequestCount += 1
      return DiaryFeatureFixtures.pageWithNext
    }
    pageTwoRequestCount += 1
    return try await withCheckedThrowingContinuation { continuation in
      pageTwoContinuations.append(continuation)
    }
  }

  func succeedPageTwo(request: Int) {
    guard pageTwoContinuations.indices.contains(request) else { return }
    pageTwoContinuations[request].resume(returning: DiaryFeatureFixtures.secondPage)
  }

  func createDiaryEntry(_ draft: DiaryEntryCreateDraft) throws -> DiaryEntry {
    throw UnexpectedDiaryCall()
  }
  func loadDiaryEntry(id: Int64) throws -> DiaryEntryDetail { throw UnexpectedDiaryCall() }
  func updateDiaryEntry(id: Int64, draft: DiaryEntryUpdateDraft) throws -> DiaryEntry {
    throw UnexpectedDiaryCall()
  }
  func deleteDiaryEntry(id: Int64) throws { throw UnexpectedDiaryCall() }
  func createDiaryComment(entryID: Int64, draft: DiaryCommentDraft) throws -> DiaryComment {
    throw UnexpectedDiaryCall()
  }
  func updateDiaryComment(id: Int64, draft: DiaryCommentDraft) throws -> DiaryComment {
    throw UnexpectedDiaryCall()
  }
  func deleteDiaryComment(id: Int64) throws { throw UnexpectedDiaryCall() }
}

private struct UnexpectedDiaryCall: Error, Sendable {}

private enum DiaryFeatureFixtures {
  static let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
  static let author = DiaryParticipant(slot: .one, displayName: "봄")
  static let partner = DiaryParticipant(slot: .two, displayName: "여름")
  static let entry = DiaryEntry(
    id: 41,
    author: author,
    content: "첫 일기",
    createdAt: timestamp,
    updatedAt: nil,
    isMine: true,
    attachments: [],
    commentCount: 1
  )
  static let olderEntry = DiaryEntry(
    id: 40,
    author: partner,
    content: "이전 일기",
    createdAt: timestamp.addingTimeInterval(-100),
    updatedAt: nil,
    isMine: false,
    attachments: [],
    commentCount: 0
  )
  static let createdEntry = DiaryEntry(
    id: 42,
    author: author,
    content: "새 일기",
    createdAt: timestamp.addingTimeInterval(100),
    updatedAt: nil,
    isMine: true,
    attachments: [],
    commentCount: 0
  )
  static let updatedEntry = DiaryEntry(
    id: 41,
    author: author,
    content: "고친 일기",
    createdAt: timestamp,
    updatedAt: timestamp.addingTimeInterval(20),
    isMine: true,
    attachments: [],
    commentCount: 1
  )
  static let comment = DiaryComment(
    id: 51,
    author: partner,
    content: "잘 읽었어",
    createdAt: timestamp.addingTimeInterval(10),
    updatedAt: nil,
    isMine: false
  )
  static let createdComment = DiaryComment(
    id: 52,
    author: author,
    content: "새 댓글",
    createdAt: timestamp.addingTimeInterval(20),
    updatedAt: nil,
    isMine: true
  )
  static let updatedComment = DiaryComment(
    id: 52,
    author: author,
    content: "고친 댓글",
    createdAt: timestamp.addingTimeInterval(20),
    updatedAt: timestamp.addingTimeInterval(30),
    isMine: true
  )
  static let detail = DiaryEntryDetail(entry: entry, comments: [comment])
  static let createdDetail = DiaryEntryDetail(entry: createdEntry, comments: [])
  static let page = DiaryEntryPage(
    entries: [entry], pageNumber: 1, hasNext: false, totalCount: 1
  )
  static let updatedPage = DiaryEntryPage(
    entries: [updatedEntry], pageNumber: 1, hasNext: false, totalCount: 1
  )
  static let pageWithNext = DiaryEntryPage(
    entries: [entry], pageNumber: 1, hasNext: true, totalCount: 2
  )
  static let secondPage = DiaryEntryPage(
    entries: [olderEntry], pageNumber: 2, hasNext: false, totalCount: 2
  )
}
