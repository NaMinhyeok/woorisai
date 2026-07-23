import SwiftUI
import WoorisaiAPI

struct RelationshipSubmissionAccessibility: Equatable, Sendable {
  let label: String
  let value: String

  static func score(
    state: RelationshipModel.SubmissionState,
    targetScore: Int,
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

struct RelationshipView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var model: RelationshipModel
  @State private var scoreMediaModel: MediaAttachmentComposerModel
  @State private var targetScore = 50
  @State private var reason = ""
  @State private var presentedSheet: RelationshipSheetDestination?
  @State private var showsHistoryArchive = false
  @Binding private var navigationPath: [Int64]

  private let mediaService: any MediaServing
  private let mediaUploader: any PresignedMediaUploading
  private let mediaSessionCoordinator: TopLevelMediaSessionCoordinator

  let participant: AuthenticatedParticipant
  let onAuthenticationRequired: @MainActor () -> Void

  @MainActor
  init(
    model: RelationshipModel,
    navigationPath: Binding<[Int64]>,
    mediaService: any MediaServing,
    mediaUploader: any PresignedMediaUploading,
    mediaSessionCoordinator: TopLevelMediaSessionCoordinator,
    scoreMediaModel: MediaAttachmentComposerModel,
    participant: AuthenticatedParticipant,
    onAuthenticationRequired: @escaping @MainActor () -> Void
  ) {
    _model = State(initialValue: model)
    _scoreMediaModel = State(initialValue: scoreMediaModel)
    _navigationPath = navigationPath
    self.mediaService = mediaService
    self.mediaUploader = mediaUploader
    self.mediaSessionCoordinator = mediaSessionCoordinator
    self.participant = participant
    self.onAuthenticationRequired = onAuthenticationRequired
  }

  var body: some View {
    NavigationStack(path: $navigationPath) {
      stateContent
        .navigationTitle("우리 사이")
        .navigationDestination(for: Int64.self) { scoreChangeID in
          ScoreChangeThreadView(
            model: model,
            scoreChangeID: scoreChangeID,
            mediaService: mediaService,
            mediaUploader: mediaUploader,
            mediaSessionCoordinator: mediaSessionCoordinator,
            onAuthenticationRequired: onAuthenticationRequired
          )
        }
        .navigationDestination(isPresented: $showsHistoryArchive) {
          RelationshipHistoryArchiveView(
            model: model,
            mediaService: mediaService,
            onAuthenticationRequired: onAuthenticationRequired
          )
        }
    }
    .accessibilityIdentifier("relationship.screen")
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
          .tint(WoorisaiPalette.coral)
          .accessibilityHidden(true)
        Text("점수와 기록을 불러오고 있어요.")
          .foregroundStyle(WoorisaiPalette.muted)
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
          relationshipHero

          if let scores = model.scores {
            scoreOverview(scores)
          }

          PrimaryHeartButton(
            "내 점수 바꾸기",
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
        await model.refresh()
      }
    }
    .accessibilityIdentifier("relationship.loaded")
  }

  private var relationshipHero: some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: WoorisaiSpacing.medium))
      : AnyLayout(HStackLayout(alignment: .center, spacing: WoorisaiSpacing.medium))

    return layout {
      VStack(alignment: .leading, spacing: WoorisaiSpacing.xSmall) {
        Text("\(participant.displayName)님의 마음 공간")
          .font(.caption.weight(.bold))
          .foregroundStyle(WoorisaiPalette.coralDark)
        Text("오늘의 우리 사이")
          .font(.system(.title2, design: .rounded, weight: .bold))
          .foregroundStyle(WoorisaiPalette.ink)
        Text("서로 다른 두 마음을 나란히 살펴봐요.")
          .font(.subheadline)
          .foregroundStyle(WoorisaiPalette.muted)
      }
      if !dynamicTypeSize.isAccessibilitySize {
        Spacer(minLength: WoorisaiSpacing.small)
      }
      Image(systemName: "heart.circle.fill")
        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
        .foregroundStyle(WoorisaiPalette.coral, WoorisaiPalette.coralSoft)
        .accessibilityHidden(true)
    }
    .padding(.vertical, WoorisaiSpacing.small)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
    .accessibilityIdentifier("relationship.hero")
  }

  private func scoreOverview(_ scores: RelationshipScores) -> some View {
    VStack(alignment: .leading, spacing: WoorisaiSpacing.medium) {
      WoorisaiSectionHeading(
        "서로의 마음",
        detail: "각자 느끼는 방향이 달라요",
        symbol: "heart.text.square.fill"
      )
      .accessibilityIdentifier("relationship.scores")

      Group {
        if dynamicTypeSize.isAccessibilitySize {
          VStack(spacing: WoorisaiSpacing.medium) {
            scoreCard(
              eyebrow: "내가 느끼는 마음",
              sourceName: scores.currentParticipant.displayName,
              targetName: scores.partner.displayName,
              score: scores.outgoingScore,
              isMine: true,
              identifier: "relationship.outgoingScore"
            )
            scoreCard(
              eyebrow: "상대가 느끼는 마음",
              sourceName: scores.partner.displayName,
              targetName: scores.currentParticipant.displayName,
              score: scores.incomingScore,
              isMine: false,
              identifier: "relationship.incomingScore"
            )
          }
        } else {
          HStack(alignment: .top, spacing: WoorisaiSpacing.medium) {
            scoreCard(
              eyebrow: "내가 느끼는 마음",
              sourceName: scores.currentParticipant.displayName,
              targetName: scores.partner.displayName,
              score: scores.outgoingScore,
              isMine: true,
              identifier: "relationship.outgoingScore"
            )
            scoreCard(
              eyebrow: "상대가 느끼는 마음",
              sourceName: scores.partner.displayName,
              targetName: scores.currentParticipant.displayName,
              score: scores.incomingScore,
              isMine: false,
              identifier: "relationship.incomingScore"
            )
          }
        }
      }
    }
  }

  private func scoreCard(
    eyebrow: String,
    sourceName: String,
    targetName: String,
    score: Int,
    isMine: Bool,
    identifier: String
  ) -> some View {
    WarmSurface {
      VStack(alignment: .leading, spacing: WoorisaiSpacing.small) {
        HStack(alignment: .firstTextBaseline, spacing: WoorisaiSpacing.small) {
          Text(eyebrow)
            .font(.caption.weight(.semibold))
            .foregroundStyle(WoorisaiPalette.muted)
          Spacer(minLength: WoorisaiSpacing.xSmall)
          if isMine {
            scoreOwnershipBadge
          }
        }

        HStack(alignment: .firstTextBaseline, spacing: WoorisaiSpacing.xSmall) {
          Text("\(score)")
            .font(.system(.title, design: .rounded, weight: .bold))
            .foregroundStyle(WoorisaiPalette.ink)
          Text("점")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(WoorisaiPalette.muted)
        }

        Text("\(sourceName) → \(targetName)")
          .font(.caption.weight(.semibold))
          .foregroundStyle(WoorisaiPalette.muted)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)

        ProgressView(value: Double(score), total: 100)
          .tint(isMine ? WoorisaiPalette.coral : WoorisaiPalette.sage)
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(WoorisaiSpacing.regular)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(sourceName)님이 \(targetName)님에게 보내는 마음")
    .accessibilityValue("\(score)점")
    .accessibilityIdentifier(identifier)
  }

  private var scoreOwnershipBadge: some View {
    Text("내 점수")
      .font(.caption2.weight(.heavy))
      .foregroundStyle(WoorisaiPalette.coralDark)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(WoorisaiPalette.coralSoft, in: Capsule())
      .fixedSize(horizontal: true, vertical: true)
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
          VStack(spacing: 10) {
            Image(systemName: "heart")
              .font(.title2)
              .foregroundStyle(WoorisaiPalette.coral)
              .accessibilityHidden(true)
            Text("아직 점수 기록이 없어요.")
              .font(.headline)
              .foregroundStyle(WoorisaiPalette.ink)
            Text("첫 마음을 남기면 여기에 차곡차곡 쌓여요.")
              .font(.subheadline)
              .foregroundStyle(WoorisaiPalette.muted)
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
          showsHistoryArchive = true
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
        .foregroundStyle(WoorisaiPalette.coralDark)
        .padding(.horizontal, WoorisaiSpacing.medium)
        .padding(.vertical, WoorisaiSpacing.xSmall)
        .background(WoorisaiPalette.coralSoft, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityHint("모든 점수 기록을 별도 화면에서 시간순으로 살펴봅니다.")
        .accessibilityIdentifier("relationship.history.openArchive")
      }
    }
  }

  private func noticeCard(_ message: String, identifier: String) -> some View {
    WarmSurface(cornerRadius: 16) {
      Label(message, systemImage: "heart.text.square")
        .font(.callout.weight(.semibold))
        .foregroundStyle(WoorisaiPalette.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }
    .accessibilityIdentifier(identifier)
  }

  private func relationshipStateCard<Content: View>(
    identifier: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    WarmBackground {
      BrandedStateCard {
        VStack(spacing: 16) {
          content()
        }
      }
      .padding(20)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(identifier)
  }

  private func relationshipError(message: String, identifier: String) -> some View {
    relationshipStateCard(identifier: identifier) {
      Image(systemName: "wifi.exclamationmark")
        .font(.system(size: 34))
        .foregroundStyle(WoorisaiPalette.coral)
        .accessibilityHidden(true)
      Text("불러오지 못했어요")
        .font(.title3.weight(.bold))
        .foregroundStyle(WoorisaiPalette.ink)
      Text(message)
        .font(.subheadline)
        .foregroundStyle(WoorisaiPalette.muted)
        .multilineTextAlignment(.center)
      Button("다시 시도") {
        model.reload()
      }
      .buttonStyle(.borderedProminent)
      .tint(WoorisaiPalette.primaryButtonStart)
      .foregroundStyle(WoorisaiPalette.primaryButtonLabel)
      .accessibilityIdentifier("relationship.retry")
    }
  }

}
