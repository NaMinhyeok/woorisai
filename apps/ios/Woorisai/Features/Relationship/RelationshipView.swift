import SwiftUI
import WoorisaiAPI

struct RelationshipSubmissionAccessibility: Equatable, Sendable {
  let label: String
  let value: String

  static func score(
    state: RelationshipModel.SubmissionState,
    targetScore: Int64,
    canSubmit: Bool,
    isReasonWithinLimit: Bool = true
  ) -> Self {
    switch state {
    case .submitting:
      return Self(label: "점수 저장 중", value: "진행 중")
    case .idle where !isReasonWithinLimit, .failed where !isReasonWithinLimit:
      return Self(label: "점수 기록하기", value: "이유를 200자 이하로 줄여 주세요")
    case .failed where canSubmit:
      return Self(
        label: "점수 기록하기",
        value: "선택한 점수 \(targetScore)점, 이전 저장 실패"
      )
    case .idle where canSubmit:
      return Self(label: "점수 기록하기", value: "선택한 점수 \(targetScore)점")
    case .idle, .failed:
      return Self(
        label: "점수 기록하기",
        value: "현재 점수와 다른 점수를 선택하세요"
      )
    }
  }

  static func comment(
    state: RelationshipModel.SubmissionState,
    hasContent: Bool,
    isBlockedByAnotherSubmission: Bool = false,
    isContentWithinLimit: Bool = true
  ) -> Self {
    switch state {
    case .submitting:
      return Self(label: "댓글 저장 중", value: "진행 중")
    case .idle where isBlockedByAnotherSubmission:
      return Self(
        label: "댓글 남기기",
        value: "다른 댓글 저장이 끝날 때까지 기다려 주세요"
      )
    case .failed where isBlockedByAnotherSubmission:
      return Self(
        label: "댓글 남기기",
        value: "다른 댓글 저장이 끝날 때까지 기다려 주세요"
      )
    case .idle where !isContentWithinLimit, .failed where !isContentWithinLimit:
      return Self(label: "댓글 남기기", value: "댓글을 500자 이하로 줄여 주세요")
    case .failed where hasContent:
      return Self(
        label: "댓글 남기기",
        value: "이전 저장 실패, 입력한 댓글 저장 가능"
      )
    case .idle where hasContent:
      return Self(label: "댓글 남기기", value: "입력한 댓글 저장 가능")
    case .idle, .failed:
      return Self(label: "댓글 남기기", value: "댓글을 입력하세요")
    }
  }
}

private enum RelationshipSheetDestination: String, Identifiable {
  case scoreComposer

  var id: String { rawValue }
}

/// Every pushed screen on the relationship tab must be a path element. Mixing
/// `navigationDestination(isPresented:)` with a bound path gives SwiftUI two competing owners
/// of the same stack depth, so a thread push from inside the archive lands unpredictably.
enum RelationshipDestination: Hashable, Sendable {
  case historyArchive
  case scoreThread(Int64)
}

struct RelationshipHomeUpdates: View {
  let calendar: CalendarModel
  let diary: DiaryModel
  let canNavigate: Bool
  let openCalendar: @MainActor (CalendarEvent?) -> Void
  let openDiary: @MainActor (Int64?) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: WoorisaiSpacing.small) {
      Text("둘의 소식")
        .font(.title3.bold())
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("relationship.hero")
      WarmSurface {
        VStack(spacing: 0) {
          upcomingRow
          Divider().accessibilityHidden(true)
          diaryRow
        }
        .padding(.horizontal, WoorisaiSpacing.regular)
      }
    }
  }

  @ViewBuilder private var upcomingRow: some View {
    switch calendar.upcoming {
    case .loading:
      summary("다음 약속", "일정을 확인하고 있어요", symbol: "calendar")
    case .empty:
      shortcut("다음 약속", "앞으로 30일간 일정이 없어요", symbol: "calendar") { openCalendar(nil) }
    case .failed:
      shortcut("다음 약속", "불러오지 못했어요 · 일정 보기", symbol: "calendar") { openCalendar(nil) }
    case .event(let event):
      let now = Date.now
      let day = max(event.startAt, now).formatted(.dateTime.month().day().weekday(.abbreviated))
      let time = event.allDay ? "종일" : event.startAt < now ? "진행 중" : event.startAt.formatted(date: .omitted, time: .shortened)
      shortcut("다음 약속 · \(day) \(time)", event.title, symbol: "calendar") { openCalendar(event) }
        .accessibilityIdentifier("relationship.upcomingEvent")
    }
  }

  @ViewBuilder private var diaryRow: some View {
    switch diary.listState {
    case .idle, .loading:
      summary("최근 일기", "일기를 확인하고 있어요", symbol: "book.closed")
    case .unavailable, .failed:
      shortcut("최근 일기", "불러오지 못했어요 · 일기 보기", symbol: "book.closed") { openDiary(nil) }
    case .loaded:
      if let entry = diary.entries.first {
        let preview = entry.content.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        shortcut("최근 일기 · \(entry.author.displayName)", preview.isEmpty ? "첨부가 있는 일기" : preview, symbol: "book.closed") {
          openDiary(entry.id)
        }
        .accessibilityIdentifier("relationship.latestDiary")
      } else {
        shortcut("최근 일기", "아직 함께 남긴 일기가 없어요", symbol: "book.closed") { openDiary(nil) }
      }
    }
  }

  private func shortcut(_ title: String, _ detail: String, symbol: String, action: @escaping @MainActor () -> Void) -> some View {
    Button(action: action) {
      summary(title, detail, symbol: symbol, showsChevron: true).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!canNavigate)
    .accessibilityLabel("\(title), \(detail)")
  }

  private func summary(_ title: String, _ detail: String, symbol: String, showsChevron: Bool = false) -> some View {
    HStack(spacing: WoorisaiSpacing.medium) {
      Image(systemName: symbol).foregroundStyle(WoorisaiColor.Fg.brand).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: WoorisaiSpacing.xSmall) {
        Text(title).font(.caption).foregroundStyle(WoorisaiColor.Fg.neutralMuted)
        Text(detail).font(.subheadline.weight(.semibold)).foregroundStyle(WoorisaiColor.Fg.neutral)
          .lineLimit(2)
      }
      Spacer(minLength: 0)
      if showsChevron {
        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
          .foregroundStyle(WoorisaiColor.Fg.brand).accessibilityHidden(true)
      }
    }
    .frame(minHeight: WoorisaiControlMetric.minimumTapTarget)
    .padding(.vertical, WoorisaiSpacing.small)
  }
}

struct RelationshipView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var model: RelationshipModel
  @State private var scoreMediaModel: MediaAttachmentComposerModel
  @State private var targetScore: Int64 = 50
  @State private var reason = ""
  @State private var presentedSheet: RelationshipSheetDestination?
  @Binding private var navigationPath: [RelationshipDestination]

  private let mediaService: any MediaServing
  private let mediaUploader: any PresignedMediaUploading
  private let mediaSessionCoordinator: TopLevelMediaSessionCoordinator

  private let updates: RelationshipHomeUpdates
  private let refreshUpdates: @MainActor () async -> Void
  let onAuthenticationRequired: @MainActor () -> Void

  @MainActor
  init(
    model: RelationshipModel,
    navigationPath: Binding<[RelationshipDestination]>,
    mediaService: any MediaServing,
    mediaUploader: any PresignedMediaUploading,
    mediaSessionCoordinator: TopLevelMediaSessionCoordinator,
    scoreMediaModel: MediaAttachmentComposerModel,
    updates: RelationshipHomeUpdates,
    refreshUpdates: @escaping @MainActor () async -> Void,
    onAuthenticationRequired: @escaping @MainActor () -> Void
  ) {
    _model = State(initialValue: model)
    _scoreMediaModel = State(initialValue: scoreMediaModel)
    _navigationPath = navigationPath
    self.mediaService = mediaService
    self.mediaUploader = mediaUploader
    self.mediaSessionCoordinator = mediaSessionCoordinator
    self.updates = updates
    self.refreshUpdates = refreshUpdates
    self.onAuthenticationRequired = onAuthenticationRequired
  }

  var body: some View {
    NavigationStack(path: $navigationPath) {
      stateContent
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: RelationshipDestination.self) { destination in
          switch destination {
          case .scoreThread(let scoreChangeID):
            ScoreChangeThreadView(
              model: model,
              scoreChangeID: scoreChangeID,
              mediaService: mediaService,
              mediaUploader: mediaUploader,
              mediaSessionCoordinator: mediaSessionCoordinator,
              onAuthenticationRequired: onAuthenticationRequired
            )
            .toolbar(.visible, for: .navigationBar)
          case .historyArchive:
            RelationshipHistoryArchiveView(
              model: model,
              mediaService: mediaService,
              onAuthenticationRequired: onAuthenticationRequired
            )
            .toolbar(.visible, for: .navigationBar)
          }
        }
    }
    .accessibilityIdentifier("relationship.screen")
    // One toast host for the whole stack: `model.toast` is model-level state, so per-screen
    // hosts replayed the same toast on the dashboard after popping the thread mid-dismissal.
    .woorisaiToast(
      model.toast,
      reduceMotion: reduceMotion,
      onDismiss: model.dismissToast
    )
    // Recording a score is the app's central act; confirm it in the hand, not only on screen.
    .sensoryFeedback(trigger: model.lastSuccessfulScoreChangeID) { _, scoreChangeID in
      scoreChangeID == nil ? nil : .success
    }
    .task {
      model.loadIfNeeded()
    }
    .onChange(of: model.authenticationRequired) { _, required in
      if required {
        scoreMediaModel.releaseSubmittedUploadOwnership()
        scoreMediaModel.clear()
        onAuthenticationRequired()
      }
    }
    .onChange(of: scoreMediaModel.hasAuthenticationFailure) { _, required in
      if required {
        scoreMediaModel.releaseSubmittedUploadOwnership()
        scoreMediaModel.clear()
        onAuthenticationRequired()
      }
    }
    .onChange(of: model.rejectedMediaMutation) { _, rejection in
      if rejection == .scoreChange {
        scoreMediaModel.releaseSubmittedUploadOwnership()
      }
    }
    .onChange(of: model.lastSuccessfulScoreChangeID) { _, scoreChangeID in
      guard scoreChangeID != nil else { return }
      scoreMediaModel.consumeReadyUploads()
      reason = ""
      presentedSheet = nil
    }
    .onDisappear {
      if model.scoreSubmissionState != .submitting,
        !model.scoreOutcomeRequiresConfirmation,
        !model.hasProtectedManualRetryDraft,
        !model.hasProtectedLocalScoreDraft
      {
        if model.rejectedMediaMutation == .scoreChange {
          scoreMediaModel.releaseSubmittedUploadOwnership()
        }
        scoreMediaModel.clear()
      }
    }
    .sheet(item: $presentedSheet) { destination in
      switch destination {
      case .scoreComposer:
        ScoreComposerSheet(
          model: model,
          mediaModel: scoreMediaModel,
          targetScore: $targetScore,
          reason: $reason
        )
      }
    }
    .alert(
      "최신 내용이 필요해요",
      isPresented: Binding(
        get: { model.conflict != nil && presentedSheet == nil },
        set: { if !$0 { model.dismissConflict() } }
      )
    ) {
      Button("최신 내용 불러오기") {
        model.reloadAfterConflict()
      }
    } message: {
      Text("다른 변경과 겹쳐 저장하지 못했습니다. 자동으로 다시 쓰지 않고 최신 내용을 불러옵니다.")
    }
  }

  @ViewBuilder
  private var stateContent: some View {
    switch model.loadState {
    case .idle, .loading:
      relationshipStateCard(identifier: "relationship.loading") {
        ProgressView()
          .controlSize(.large)
          .tint(WoorisaiColor.Fg.brandVivid)
          .accessibilityHidden(true)
        Text("점수와 기록을 불러오고 있어요.")
          .foregroundStyle(WoorisaiColor.Fg.neutralMuted)
      }
    case .unavailable:
      relationshipError(
        message: "관계 정보를 잠시 사용할 수 없어요.",
        identifier: "relationship.unavailable"
      )
    case .failed:
      relationshipError(
        message: "관계 정보를 불러오지 못했어요.",
        identifier: "relationship.failed"
      )
    case .loaded:
      relationshipDashboard
    }
  }

  private var relationshipDashboard: some View {
    WarmBackground {
      ScrollView {
        VStack(alignment: .leading, spacing: WoorisaiSpacing.regular) {
          updates

          if let scores = model.scores {
            scoreOverview(scores)
          }

          PrimaryHeartButton(
            "마음 남기기",
            isEnabled: model.scores != nil && model.scoreSubmissionState != .submitting,
            action: openScoreComposer
          )
          .accessibilityHint("내가 상대에게 보내는 점수와 선택적인 이유, 사진을 기록합니다.")
          .accessibilityIdentifier("relationship.editScore.open")

          if let notice = model.notice {
            noticeCard(notice, identifier: "relationship.notice")
          }

          historyTimeline
        }
        .frame(maxWidth: 680)
        .padding(.horizontal, WoorisaiSpacing.screenGutter)
        .padding(.top, WoorisaiSpacing.small)
        .padding(.bottom, WoorisaiSpacing.xLarge)
        .frame(maxWidth: .infinity)
      }
      .scrollDismissesKeyboard(.interactively)
      .refreshable {
        async let summaries: Void = refreshUpdates()
        await model.refresh()
        await summaries
      }
    }
    .accessibilityIdentifier("relationship.loaded")
  }

  private func scoreOverview(_ scores: RelationshipScores) -> some View {
    VStack(alignment: .leading, spacing: WoorisaiSpacing.small) {
      Text("서로 남긴 마음")
        .font(.title3.bold())
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("relationship.scores")
      WarmSurface {
        VStack(spacing: 0) {
          scoreRow(source: scores.currentParticipant.displayName, target: scores.partner.displayName,
                   score: scores.outgoingScore, identifier: "relationship.outgoingScore")
          Divider().accessibilityHidden(true)
          scoreRow(source: scores.partner.displayName, target: scores.currentParticipant.displayName,
                   score: scores.incomingScore, identifier: "relationship.incomingScore")
        }
        .padding(.horizontal, WoorisaiSpacing.regular)
      }
    }
  }

  private func scoreRow(source: String, target: String, score: Int64, identifier: String) -> some View {
    let direction = Text("\(source) → \(target)").font(.subheadline.weight(.semibold))
    let value = Text("\(score)점").font(.body.monospacedDigit().weight(.semibold))
    return ViewThatFits(in: .horizontal) {
      HStack(spacing: WoorisaiSpacing.small) {
        direction.fixedSize(horizontal: true, vertical: false)
        Spacer(minLength: 0)
        value.fixedSize(horizontal: true, vertical: false)
      }
      VStack(alignment: .leading, spacing: WoorisaiSpacing.xSmall) {
        direction
        value
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .foregroundStyle(WoorisaiColor.Fg.neutral)
    .frame(minHeight: WoorisaiControlMetric.minimumTapTarget)
    .padding(.vertical, WoorisaiSpacing.xSmall)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(source)님이 \(target)님에게 보내는 마음")
    .accessibilityValue("\(score)점")
    .accessibilityIdentifier(identifier)
  }

  private func openScoreComposer() {
    guard let currentScore = model.scores?.outgoingScore,
      model.scoreSubmissionState != .submitting
    else { return }
    #if DEBUG
      if !WoorisaiUITestService.usesSyntheticMedia(
        arguments: ProcessInfo.processInfo.arguments
      ) {
        scoreMediaModel.clear()
      }
    #else
      scoreMediaModel.clear()
    #endif
    targetScore = currentScore
    reason = ""
    presentedSheet = .scoreComposer
  }

  private var historyTimeline: some View {
    VStack(alignment: .leading, spacing: WoorisaiSpacing.medium) {
      WoorisaiSectionHeading(
        "우리의 마음 기록",
        detail: model.totalCount == 0 ? nil : "\(model.totalCount)개",
        symbol: "heart.text.square.fill"
      )

      if model.changes.isEmpty {
        BrandedStateCard {
          VStack(spacing: WoorisaiSpacing.small) {
            Image(systemName: "heart")
              .font(.title2)
              .foregroundStyle(WoorisaiColor.Fg.brandVivid)
              .accessibilityHidden(true)
            Text("아직 점수 기록이 없어요.")
              .font(.headline)
              .foregroundStyle(WoorisaiColor.Fg.neutral)
            Text("첫 마음을 남기면 여기에 차곡차곡 쌓여요.")
              .font(.subheadline)
              .foregroundStyle(WoorisaiColor.Fg.neutralMuted)
              .multilineTextAlignment(.center)
          }
        }
        .accessibilityIdentifier("relationship.history.empty")
      } else {
        LazyVStack(spacing: 0) {
          ForEach(Array(model.changes.prefix(3))) { change in
            HistoryTimelineRow(
              change: change,
              isLast: change.id == model.changes.prefix(3).last?.id,
              mediaService: mediaService,
              onAuthenticationRequired: onAuthenticationRequired
            )
          }
        }
        .accessibilityIdentifier("relationship.history.timeline")
      }

      if model.changes.count > 3 || model.hasNextPage {
        Button {
          navigationPath.append(.historyArchive)
        } label: {
          HStack(spacing: WoorisaiSpacing.small) {
            Text("마음 기록 전체 보기")
            Spacer(minLength: WoorisaiSpacing.small)
            Image(systemName: "chevron.right")
              .accessibilityHidden(true)
          }
          .frame(minHeight: WoorisaiControlMetric.minimumTapTarget)
          .contentShape(Rectangle())
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(WoorisaiColor.Fg.brand)
        .padding(.horizontal, WoorisaiSpacing.medium)
        .padding(.vertical, WoorisaiSpacing.xSmall)
        .background(WoorisaiColor.Bg.brandWeak, in: RoundedRectangle(cornerRadius: WoorisaiRadius.small))
        .accessibilityHint("모든 점수 기록을 별도 화면에서 시간순으로 살펴봅니다.")
        .accessibilityIdentifier("relationship.history.openArchive")
      }
    }
  }

  private func noticeCard(_ message: String, identifier: String) -> some View {
    WarmSurface(cornerRadius: WoorisaiRadius.medium) {
      Label(message, systemImage: "heart.text.square")
        .font(.callout.weight(.semibold))
        .foregroundStyle(WoorisaiColor.Fg.neutral)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WoorisaiSpacing.medium)
    }
    .accessibilityIdentifier(identifier)
  }

  private func relationshipStateCard<Content: View>(
    identifier: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    WarmBackground {
      BrandedStateCard {
        VStack(spacing: WoorisaiSpacing.regular) {
          content()
        }
      }
      .padding(WoorisaiSpacing.regular)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(identifier)
  }

  private func relationshipError(message: String, identifier: String) -> some View {
    relationshipStateCard(identifier: identifier) {
      Image(systemName: "wifi.exclamationmark")
        .font(.system(size: 34))
        .foregroundStyle(WoorisaiColor.Fg.brandVivid)
        .accessibilityHidden(true)
      Text("불러오지 못했어요")
        .font(.title3.weight(.bold))
        .foregroundStyle(WoorisaiColor.Fg.neutral)
      Text(message)
        .font(.subheadline)
        .foregroundStyle(WoorisaiColor.Fg.neutralMuted)
        .multilineTextAlignment(.center)
      Button("다시 시도") {
        model.reload()
      }
      .buttonStyle(.borderedProminent)
      .tint(WoorisaiColor.Bg.brandSolid)
      .foregroundStyle(WoorisaiColor.Fg.brandContrast)
      .accessibilityIdentifier("relationship.retry")
    }
  }

}
