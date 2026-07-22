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

struct RelationshipView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var model: RelationshipModel
  @State private var scoreMediaModel: MediaAttachmentComposerModel
  @State private var targetScore = 50
  @State private var reason = ""
  @FocusState private var isReasonFocused: Bool
  @Binding private var navigationPath: [Int64]

  private let mediaService: any MediaServing
  private let mediaUploader: any PresignedMediaUploading

  let participant: AuthenticatedParticipant
  let onSignOut: @MainActor () -> Void
  let onAuthenticationRequired: @MainActor () -> Void

  @MainActor
  init(
    model: RelationshipModel,
    navigationPath: Binding<[Int64]>,
    mediaService: any MediaServing,
    mediaUploader: any PresignedMediaUploading,
    scoreMediaModel: MediaAttachmentComposerModel,
    participant: AuthenticatedParticipant,
    onSignOut: @escaping @MainActor () -> Void,
    onAuthenticationRequired: @escaping @MainActor () -> Void
  ) {
    _model = State(initialValue: model)
    _scoreMediaModel = State(initialValue: scoreMediaModel)
    _navigationPath = navigationPath
    self.mediaService = mediaService
    self.mediaUploader = mediaUploader
    self.participant = participant
    self.onSignOut = onSignOut
    self.onAuthenticationRequired = onAuthenticationRequired
  }

  var body: some View {
    NavigationStack(path: $navigationPath) {
      stateContent
        .navigationTitle("우리 사이")
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button("나가기") {
              onSignOut()
            }
            .accessibilityIdentifier("relationship.signOut")
          }
          KeyboardDismissToolbar {
            isReasonFocused = false
          }
        }
        .navigationDestination(for: Int64.self) { scoreChangeID in
          ScoreChangeThreadView(
            model: model,
            scoreChangeID: scoreChangeID,
            mediaService: mediaService,
            mediaUploader: mediaUploader,
            onAuthenticationRequired: onAuthenticationRequired
          )
        }
    }
    .accessibilityIdentifier("relationship.screen")
    .task {
      model.loadIfNeeded()
    }
    .onChange(of: model.scores?.outgoingScore) { _, score in
      if let score { targetScore = score }
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
      isReasonFocused = false
    }
    .onDisappear {
      isReasonFocused = false
      if model.scoreSubmissionState != .submitting {
        if model.rejectedMediaMutation == .scoreChange {
          scoreMediaModel.releaseSubmittedUploadOwnership()
        }
        scoreMediaModel.clear()
      }
    }
    .alert(
      "최신 내용이 필요해요",
      isPresented: Binding(
        get: { model.conflict != nil },
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
        VStack(alignment: .leading, spacing: 18) {
          relationshipHero

          if let scores = model.scores {
            scoreOverview(scores)
          }

          scoreComposer

          if let notice = model.notice {
            noticeCard(notice, identifier: "relationship.notice")
          }

          historyTimeline
        }
        .frame(maxWidth: 720)
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity)
      }
      .scrollDismissesKeyboard(.interactively)
      .refreshable {
        model.reload()
      }
    }
    .accessibilityIdentifier("relationship.loaded")
  }

  private var relationshipHero: some View {
    VStack(alignment: .leading, spacing: 8) {
      Eyebrow("\(participant.displayName)님의 마음 공간")

      VStack(alignment: .leading, spacing: 0) {
        Text("오늘 우리 사이는")
        Text("몇 점일까요?")
          .foregroundStyle(WoorisaiPalette.coral)
      }
      .font(
        .system(
          dynamicTypeSize.isAccessibilitySize ? .title : .largeTitle,
          design: .rounded,
          weight: .bold
        )
      )
      .tracking(dynamicTypeSize.isAccessibilitySize ? -0.4 : -1.2)

      Text("점수도 이유도 서로에게 솔직하게 보여요.")
        .font(.subheadline)
        .foregroundStyle(WoorisaiPalette.muted)
    }
    .foregroundStyle(WoorisaiPalette.ink)
    .padding(.vertical, 10)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
    .accessibilityIdentifier("relationship.hero")
  }

  private func scoreOverview(_ scores: RelationshipScores) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("현재 점수")
        .font(.headline.weight(.bold))
        .foregroundStyle(WoorisaiPalette.ink)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("relationship.scores")

      Group {
        if dynamicTypeSize.isAccessibilitySize {
          VStack(spacing: 12) {
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
          HStack(alignment: .top, spacing: 12) {
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
      VStack(alignment: .leading, spacing: 12) {
        Group {
          if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 7) {
              Text(eyebrow)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WoorisaiPalette.muted)
              if isMine {
                scoreOwnershipBadge
              }
            }
          } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text(eyebrow)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WoorisaiPalette.muted)
              Spacer(minLength: 4)
              if isMine {
                scoreOwnershipBadge
              }
            }
          }
        }

        Text("\(sourceName)  →  \(targetName)")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(WoorisaiPalette.ink)
          .fixedSize(horizontal: false, vertical: true)

        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text("\(score)")
            .font(.system(size: 44, weight: .bold, design: .rounded))
            .foregroundStyle(WoorisaiPalette.ink)
            .minimumScaleFactor(0.7)
          Text("/ 100")
            .font(.caption.weight(.bold))
            .foregroundStyle(WoorisaiPalette.muted)
        }

        ProgressView(value: Double(score), total: 100)
          .tint(isMine ? WoorisaiPalette.coral : WoorisaiPalette.sage)
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
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

  private var scoreComposer: some View {
    let headerLayout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
      : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    let stepperLabelLayout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 5))
      : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
    let fieldHeaderLayout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
      : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))

    return WarmSurface {
      VStack(alignment: .leading, spacing: 18) {
        headerLayout {
          VStack(alignment: .leading, spacing: 5) {
            Eyebrow("MY FEELING")
            Text("\(model.scores?.partner.displayName ?? "상대방")님을 향한 마음")
              .font(.title3.weight(.bold))
              .foregroundStyle(WoorisaiPalette.ink)
              .fixedSize(horizontal: false, vertical: true)
          }
          if !dynamicTypeSize.isAccessibilitySize {
            Spacer(minLength: 8)
          }
          Image(systemName: "heart.fill")
            .font(.headline)
            .foregroundStyle(WoorisaiPalette.coral)
            .frame(width: 42, height: 42)
            .background(WoorisaiPalette.coralSoft, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("어떤 점수를 남길까요?")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(WoorisaiPalette.ink)

          Stepper(value: $targetScore, in: 0...100) {
            stepperLabelLayout {
              Text("목표 점수")
                .foregroundStyle(WoorisaiPalette.muted)
              if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 8)
              }
              Text("\(targetScore)점")
                .font(.title3.weight(.bold))
                .foregroundStyle(WoorisaiPalette.coralDark)
                .fixedSize(horizontal: true, vertical: true)
            }
          }
          .padding(14)
          .background(WoorisaiPalette.creamDeep, in: RoundedRectangle(cornerRadius: 14))
          .accessibilityIdentifier("relationship.targetScore")
        }

        scorePreview

        VStack(alignment: .leading, spacing: 8) {
          fieldHeaderLayout {
            Text("이유 (선택)")
              .font(.subheadline.weight(.bold))
              .foregroundStyle(WoorisaiPalette.ink)
            if !dynamicTypeSize.isAccessibilitySize {
              Spacer(minLength: 8)
            }
            Text(
              "\(reasonCodePointCount)/\(RelationshipScoreChangeDraft.maximumReasonCharacterCount)"
            )
              .font(.caption)
              .foregroundStyle(
                reasonCodePointCount > RelationshipScoreChangeDraft.maximumReasonCharacterCount
                  ? WoorisaiPalette.error : WoorisaiPalette.muted
              )
              .fixedSize(horizontal: true, vertical: true)
          }

          TextField("남기고 싶은 이유가 있다면 적어 주세요.", text: $reason, axis: .vertical)
            .lineLimit(2...4)
            .focused($isReasonFocused)
            .foregroundStyle(WoorisaiPalette.ink)
            .tint(WoorisaiPalette.coralDark)
            .padding(12)
            .background(WoorisaiPalette.field, in: RoundedRectangle(cornerRadius: 13))
            .overlay {
              RoundedRectangle(cornerRadius: 13)
                .stroke(WoorisaiPalette.line, lineWidth: 1)
            }
            .accessibilityIdentifier("relationship.reason")
        }

        MediaAttachmentComposer(model: scoreMediaModel)

        PrimaryHeartButton(
          "이 마음 기록하기",
          isEnabled: canSubmitScore,
          isLoading: model.scoreSubmissionState == .submitting,
          action: submitScoreChange
        )
        .accessibilityLabel(Text(scoreSubmissionAccessibility.label))
        .accessibilityValue(Text(scoreSubmissionAccessibility.value))
        .accessibilityIdentifier("relationship.createScoreChange")
      }
      .padding(18)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("relationship.composer")
  }

  private var scorePreview: some View {
    let currentScore = model.scores?.outgoingScore ?? targetScore
    let delta = targetScore - currentScore
    let previewLayout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
      : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    return previewLayout {
      HStack(spacing: 12) {
        previewScore(label: "현재", score: currentScore)

        Image(systemName: "arrow.right")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(WoorisaiPalette.coral)
          .accessibilityHidden(true)

        previewScore(label: "목표", score: targetScore)
      }
      if !dynamicTypeSize.isAccessibilitySize {
        Spacer(minLength: 0)
      }
      Text(deltaLabel(delta))
        .font(.caption.weight(.heavy))
        .foregroundStyle(delta < 0 ? WoorisaiPalette.sage : WoorisaiPalette.coralDark)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
          delta < 0 ? WoorisaiPalette.sageSoft : WoorisaiPalette.coralSoft,
          in: Capsule()
        )
        .fixedSize(horizontal: true, vertical: true)
    }
    .padding(14)
    .background(WoorisaiPalette.selectedSurface, in: RoundedRectangle(cornerRadius: 14))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("점수 미리보기")
    .accessibilityValue(
      "현재 \(currentScore)점, 목표 \(targetScore)점, \(deltaAccessibilityLabel(delta))"
    )
    .accessibilityIdentifier("relationship.scorePreview")
  }

  private func previewScore(label: String, score: Int) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(WoorisaiPalette.muted)
      Text("\(score)점")
        .font(.subheadline.weight(.bold))
        .foregroundStyle(WoorisaiPalette.ink)
    }
  }

  private var historyTimeline: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Eyebrow("OUR MEMORIES")
        Text("우리의 마음 기록")
          .font(.title2.weight(.bold))
          .foregroundStyle(WoorisaiPalette.ink)
          .accessibilityAddTraits(.isHeader)
      }

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
          ForEach(Array(model.changes.enumerated()), id: \.element.id) { index, change in
            HistoryTimelineRow(
              change: change,
              isLast: index == model.changes.count - 1,
              mediaService: mediaService,
              onAuthenticationRequired: onAuthenticationRequired
            )
          }
        }
        .accessibilityIdentifier("relationship.history.timeline")
      }

      if model.hasNextPage {
        Button("이전 기록 더 보기") {
          model.loadNextPage()
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(WoorisaiPalette.coralDark)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(WoorisaiPalette.coralSoft, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("relationship.history.nextPage")
      }
    }
  }

  private var scoreSubmissionAccessibility: RelationshipSubmissionAccessibility {
    .score(
      state: model.scoreSubmissionState,
      targetScore: targetScore,
      canSubmit: canSubmitScore,
      isReasonWithinLimit:
        reasonCodePointCount <= RelationshipScoreChangeDraft.maximumReasonCharacterCount
    )
  }

  private var reasonCodePointCount: Int {
    WoorisaiTextInput.normalizedCodePointCount(reason)
  }

  private var canSubmitScore: Bool {
    model.canCreateScoreChange(targetScore: targetScore)
      && scoreMediaModel.isReadyForSubmission
      && reasonCodePointCount <= RelationshipScoreChangeDraft.maximumReasonCharacterCount
  }

  private func submitScoreChange() {
    let uploadIDs = scoreMediaModel.readyUploadIDs
    let accepted = model.createScoreChange(
      targetScore: targetScore,
      reason: reason,
      mediaUploadIDs: uploadIDs
    )
    if accepted {
      isReasonFocused = false
      scoreMediaModel.markReadyUploadsSubmitted()
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

  private func deltaLabel(_ delta: Int) -> String {
    if delta == 0 { return "변화 없음" }
    return delta > 0 ? "+\(delta)점" : "\(delta)점"
  }

  private func deltaAccessibilityLabel(_ delta: Int) -> String {
    if delta == 0 { return "변화 없음" }
    return delta > 0 ? "\(delta)점 올라감" : "\(-delta)점 내려감"
  }
}

private struct HistoryTimelineRow: View {
  let change: RelationshipScoreChange
  let isLast: Bool
  let mediaService: any MediaServing
  let onAuthenticationRequired: @MainActor () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(spacing: 0) {
        Circle()
          .fill(WoorisaiPalette.coral)
          .frame(width: 12, height: 12)
          .overlay {
            Circle()
              .stroke(WoorisaiPalette.cream, lineWidth: 3)
          }
          .padding(.top, 22)

        if !isLast {
          Rectangle()
            .fill(WoorisaiPalette.line)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
        }
      }
      .frame(width: 16)

      ScoreChangeRow(
        change: change,
        mediaService: mediaService,
        onAuthenticationRequired: onAuthenticationRequired,
        reasonDisplay: .historySummary,
        navigationValue: change.id
      )
      .padding(.bottom, isLast ? 0 : 12)
    }
  }
}

private enum ScoreChangeReasonDisplay {
  case historySummary
  case threadDetail

  var lineLimit: Int? {
    switch self {
    case .historySummary: 4
    case .threadDetail: nil
    }
  }

  func accessibilityIdentifier(changeID: Int64) -> String {
    switch self {
    case .historySummary: "relationship.history.reason.\(changeID)"
    case .threadDetail: "relationship.thread.reason.\(changeID)"
    }
  }
}

private struct ScoreChangeRow: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let change: RelationshipScoreChange
  let mediaService: any MediaServing
  let onAuthenticationRequired: @MainActor () -> Void
  let reasonDisplay: ScoreChangeReasonDisplay
  var navigationValue: Int64? = nil

  var body: some View {
    let headerLayout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
      : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
    let footerLayout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
      : AnyLayout(HStackLayout(alignment: .center, spacing: 12))

    return WarmSurface {
      VStack(alignment: .leading, spacing: 14) {
        headerLayout {
          VStack(alignment: .leading, spacing: 4) {
            Text(
              "\(change.sourceParticipant.displayName)  →  \(change.targetParticipant.displayName)"
            )
            .font(.subheadline.weight(.heavy))
            .foregroundStyle(WoorisaiPalette.ink)
            Text(change.createdAt.formatted(date: .abbreviated, time: .shortened))
              .font(.caption2)
              .foregroundStyle(WoorisaiPalette.muted)
          }
          if !dynamicTypeSize.isAccessibilitySize {
            Spacer(minLength: 8)
          }
          Text(change.delta > 0 ? "+\(change.delta)점" : "\(change.delta)점")
            .font(.subheadline.weight(.heavy))
            .foregroundStyle(
              change.delta > 0 ? WoorisaiPalette.coralDark : WoorisaiPalette.sage
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
              change.delta > 0 ? WoorisaiPalette.coralSoft : WoorisaiPalette.sageSoft,
              in: RoundedRectangle(cornerRadius: 11)
            )
            .fixedSize(horizontal: true, vertical: true)
        }

        if let reason = change.reason {
          Text("“\(reason)”")
            .font(.body)
            .foregroundStyle(WoorisaiPalette.ink.opacity(0.88))
            .lineLimit(reasonDisplay.lineLimit)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(
              reasonDisplay.accessibilityIdentifier(changeID: change.id)
            )
        }

        if !change.attachments.isEmpty {
          RelationshipMediaGallery(
            attachments: change.attachments,
            mediaService: mediaService,
            onAuthenticationRequired: onAuthenticationRequired
          )
        }

        Divider()
          .overlay(WoorisaiPalette.line)

        footerLayout {
          Label("변경 후 \(change.resultingScore)점", systemImage: "heart.fill")
          if !dynamicTypeSize.isAccessibilitySize {
            Spacer(minLength: 4)
          }
          if !change.attachments.isEmpty {
            Label("첨부 \(change.attachments.count)", systemImage: "paperclip")
          }
          Label("댓글 \(change.commentCount)", systemImage: "bubble.left")
        }
        .font(.caption)
        .foregroundStyle(WoorisaiPalette.muted)

        if let navigationValue {
          NavigationLink(value: navigationValue) {
            HStack {
              Text("전체 내용과 대화 보기")
              Spacer()
              Image(systemName: "chevron.right")
                .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(WoorisaiPalette.coralDark)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .padding(.top, 2)
          }
          .accessibilityIdentifier("relationship.history.\(change.id)")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
    }
    .accessibilityElement(children: .contain)
  }
}

private struct ScoreChangeThreadView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var model: RelationshipModel
  @State private var commentMediaModel: MediaAttachmentComposerModel
  @State private var comment = ""
  @FocusState private var isCommentFocused: Bool

  let scoreChangeID: Int64
  let onAuthenticationRequired: @MainActor () -> Void
  private let mediaService: any MediaServing

  @MainActor
  init(
    model: RelationshipModel,
    scoreChangeID: Int64,
    mediaService: any MediaServing,
    mediaUploader: any PresignedMediaUploading,
    onAuthenticationRequired: @escaping @MainActor () -> Void
  ) {
    _model = State(initialValue: model)
    _commentMediaModel = State(
      initialValue: MediaAttachmentComposerModel(
        purpose: .comment,
        service: mediaService,
        uploader: mediaUploader
      )
    )
    self.scoreChangeID = scoreChangeID
    self.mediaService = mediaService
    self.onAuthenticationRequired = onAuthenticationRequired
  }

  var body: some View {
    Group {
      switch model.threadState {
      case .idle, .loading:
        threadStateCard(identifier: "relationship.thread.loading") {
          ProgressView()
            .controlSize(.large)
            .tint(WoorisaiPalette.coral)
            .accessibilityHidden(true)
          Text("대화를 불러오고 있어요.")
            .foregroundStyle(WoorisaiPalette.muted)
        }
      case .loaded:
        threadList
      case .notFound:
        threadError("이 점수 기록을 찾을 수 없어요.", "relationship.thread.notFound")
      case .unavailable:
        threadError("대화를 잠시 사용할 수 없어요.", "relationship.thread.unavailable")
      case .failed:
        threadError("대화를 불러오지 못했어요.", "relationship.thread.failed")
      }
    }
    .navigationTitle("점수 대화")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(currentCommentSubmissionState == .submitting)
    .toolbar {
      KeyboardDismissToolbar {
        isCommentFocused = false
      }
    }
    .task(id: scoreChangeID) {
      model.loadThread(scoreChangeID: scoreChangeID)
    }
    .onDisappear {
      isCommentFocused = false
      model.cancelThreadReadForScreenExit(scoreChangeID: scoreChangeID)
      if currentCommentSubmissionState != .submitting {
        if model.rejectedMediaMutation == .comment(scoreChangeID: scoreChangeID) {
          commentMediaModel.releaseSubmittedUploadOwnership()
        }
        commentMediaModel.clear()
      }
    }
    .onChange(of: commentMediaModel.hasAuthenticationFailure) { _, required in
      if required {
        commentMediaModel.releaseSubmittedUploadOwnership()
        commentMediaModel.clear()
        onAuthenticationRequired()
      }
    }
    .onChange(of: model.authenticationRequired) { _, required in
      if required {
        commentMediaModel.releaseSubmittedUploadOwnership()
        commentMediaModel.clear()
      }
    }
    .onChange(of: model.rejectedMediaMutation) { _, rejection in
      if rejection == .comment(scoreChangeID: scoreChangeID) {
        commentMediaModel.releaseSubmittedUploadOwnership()
      }
    }
    .onChange(of: model.lastSuccessfulCommentScoreChangeID) { _, successfulID in
      guard successfulID == scoreChangeID else { return }
      commentMediaModel.consumeReadyUploads()
      comment = ""
      isCommentFocused = false
    }
  }

  private var threadList: some View {
    let commentsHeaderLayout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
      : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
    let composerHeaderLayout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
      : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))

    return WarmBackground {
      ScrollView {
        if let thread = model.selectedThread {
          VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
              Eyebrow("SCORE TALK")
              Text("이 마음에 대한 대화")
                .font(.title2.weight(.bold))
                .foregroundStyle(WoorisaiPalette.ink)
              Text("점수에 담긴 마음을 천천히 이야기해 보세요.")
                .font(.subheadline)
                .foregroundStyle(WoorisaiPalette.muted)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("relationship.thread.hero")

            VStack(alignment: .leading, spacing: 10) {
              ScoreChangeRow(
                change: thread.change,
                mediaService: mediaService,
                onAuthenticationRequired: onAuthenticationRequired,
                reasonDisplay: .threadDetail
              )
            }

            WarmSurface {
              VStack(alignment: .leading, spacing: 16) {
                commentsHeaderLayout {
                  VStack(alignment: .leading, spacing: 4) {
                    Eyebrow("COMMENTS")
                    Text("댓글 \(thread.comments.count)")
                      .font(.title3.weight(.bold))
                      .foregroundStyle(WoorisaiPalette.ink)
                  }
                  if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 8)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                      .foregroundStyle(WoorisaiPalette.coral)
                      .accessibilityHidden(true)
                  }
                }
                .accessibilityIdentifier("relationship.thread.comments")

                Divider()
                  .overlay(WoorisaiPalette.line)

                if thread.comments.isEmpty {
                  Text("아직 댓글이 없어요. 먼저 이야기를 건네 보세요.")
                    .font(.subheadline)
                    .foregroundStyle(WoorisaiPalette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                } else {
                  LazyVStack(spacing: 12) {
                    ForEach(thread.comments) { scoreComment in
                      ScoreCommentBubble(
                        comment: scoreComment,
                        mediaService: mediaService,
                        onAuthenticationRequired: onAuthenticationRequired
                      )
                    }
                  }
                }

                Divider()
                  .overlay(WoorisaiPalette.line)

                VStack(alignment: .leading, spacing: 10) {
                  composerHeaderLayout {
                    Text("댓글 달기")
                      .font(.subheadline.weight(.bold))
                      .foregroundStyle(WoorisaiPalette.ink)
                    if !dynamicTypeSize.isAccessibilitySize {
                      Spacer(minLength: 8)
                    }
                    Text(
                      "\(commentCodePointCount)/\(RelationshipScoreCommentDraft.maximumContentCharacterCount)"
                    )
                      .font(.caption)
                      .foregroundStyle(
                        commentCodePointCount
                            > RelationshipScoreCommentDraft.maximumContentCharacterCount
                          ? WoorisaiPalette.error : WoorisaiPalette.muted
                      )
                      .fixedSize(horizontal: true, vertical: true)
                  }

                  TextField("답장을 쓰거나 사진·영상을 남겨 보세요.", text: $comment, axis: .vertical)
                    .lineLimit(2...5)
                    .focused($isCommentFocused)
                    .foregroundStyle(WoorisaiPalette.ink)
                    .tint(WoorisaiPalette.coralDark)
                    .padding(12)
                    .background(WoorisaiPalette.field, in: RoundedRectangle(cornerRadius: 13))
                    .overlay {
                      RoundedRectangle(cornerRadius: 13)
                        .stroke(WoorisaiPalette.line, lineWidth: 1)
                    }
                    .accessibilityIdentifier("relationship.thread.commentInput")

                  MediaAttachmentComposer(model: commentMediaModel)

                  PrimaryHeartButton(
                    "댓글 남기기",
                    isEnabled: canSubmitComment,
                    isLoading: currentCommentSubmissionState == .submitting,
                    action: submitComment
                  )
                  .accessibilityLabel(Text(commentSubmissionAccessibility.label))
                  .accessibilityValue(Text(commentSubmissionAccessibility.value))
                  .accessibilityIdentifier("relationship.thread.createComment")
                }
              }
              .padding(18)
            }

            if let notice = model.commentNotice(for: scoreChangeID) {
              WarmSurface(cornerRadius: 16) {
                Label(notice, systemImage: "bubble.left.fill")
                  .font(.callout.weight(.semibold))
                  .foregroundStyle(WoorisaiPalette.ink)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(14)
              }
              .accessibilityAddTraits(.updatesFrequently)
              .accessibilityIdentifier("relationship.thread.notice")
            }
          }
          .frame(maxWidth: 720)
          .padding(.horizontal, 18)
          .padding(.top, 12)
          .padding(.bottom, 36)
          .frame(maxWidth: .infinity)
        }
      }
      .scrollDismissesKeyboard(.interactively)
    }
    .accessibilityIdentifier("relationship.thread.loaded")
  }

  private var trimmedComment: String {
    WoorisaiTextInput.normalized(comment)
  }

  private var commentCodePointCount: Int {
    WoorisaiTextInput.normalizedCodePointCount(comment)
  }

  private var commentSubmissionAccessibility: RelationshipSubmissionAccessibility {
    .comment(
      state: currentCommentSubmissionState,
      hasContent: !trimmedComment.isEmpty || !commentMediaModel.readyUploadIDs.isEmpty,
      isBlockedByAnotherSubmission: isBlockedByAnotherCommentSubmission,
      isContentWithinLimit:
        commentCodePointCount <= RelationshipScoreCommentDraft.maximumContentCharacterCount
    )
  }

  private var currentCommentSubmissionState: RelationshipModel.SubmissionState {
    model.commentSubmissionState(for: scoreChangeID)
  }

  private var isBlockedByAnotherCommentSubmission: Bool {
    model.commentSubmissionState == .submitting
      && model.commentSubmissionScoreChangeID != scoreChangeID
  }

  private var canSubmitComment: Bool {
    (!trimmedComment.isEmpty || !commentMediaModel.readyUploadIDs.isEmpty)
      && commentCodePointCount <= RelationshipScoreCommentDraft.maximumContentCharacterCount
      && commentMediaModel.isReadyForSubmission
      && model.commentSubmissionState != .submitting
  }

  private func submitComment() {
    let uploadIDs = commentMediaModel.readyUploadIDs
    let accepted = model.createComment(
      scoreChangeID: scoreChangeID,
      content: comment,
      mediaUploadIDs: uploadIDs
    )
    if accepted {
      isCommentFocused = false
      commentMediaModel.markReadyUploadsSubmitted()
    }
  }

  private func threadStateCard<Content: View>(
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

  private func threadError(_ message: String, _ identifier: String) -> some View {
    threadStateCard(identifier: identifier) {
      Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
        .font(.system(size: 34))
        .foregroundStyle(WoorisaiPalette.coral)
        .accessibilityHidden(true)
      Text("대화를 열 수 없어요")
        .font(.title3.weight(.bold))
        .foregroundStyle(WoorisaiPalette.ink)
      Text(message)
        .font(.subheadline)
        .foregroundStyle(WoorisaiPalette.muted)
        .multilineTextAlignment(.center)
      Button("다시 시도") {
        model.loadThread(scoreChangeID: scoreChangeID)
      }
      .buttonStyle(.borderedProminent)
      .tint(WoorisaiPalette.primaryButtonStart)
      .foregroundStyle(WoorisaiPalette.primaryButtonLabel)
      .accessibilityIdentifier("relationship.thread.retry")
    }
  }
}

private struct ScoreCommentBubble: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let comment: RelationshipScoreComment
  let mediaService: any MediaServing
  let onAuthenticationRequired: @MainActor () -> Void

  private var isMine: Bool {
    comment.author.isCurrentParticipant
  }

  var body: some View {
    let metadataLayout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3))
      : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))

    return HStack(alignment: .top, spacing: 0) {
      if isMine && !dynamicTypeSize.isAccessibilitySize {
        Spacer(minLength: 44)
      }

      VStack(alignment: .leading, spacing: 7) {
        metadataLayout {
          Text(isMine ? "나" : comment.author.displayName)
            .font(.caption.weight(.heavy))
            .foregroundStyle(WoorisaiPalette.ink)
          if !dynamicTypeSize.isAccessibilitySize {
            Spacer(minLength: 8)
          }
          Text(comment.createdAt.formatted(date: .omitted, time: .shortened))
            .font(.caption2)
            .foregroundStyle(WoorisaiPalette.muted)
            .fixedSize(horizontal: true, vertical: true)
        }

        if let content = comment.content {
          Text(content)
            .font(.body)
            .foregroundStyle(WoorisaiPalette.ink)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if !comment.attachments.isEmpty {
          RelationshipMediaGallery(
            attachments: comment.attachments,
            mediaService: mediaService,
            onAuthenticationRequired: onAuthenticationRequired
          )
        }
      }
      .padding(13)
      .background(
        isMine ? WoorisaiPalette.coralSoft : WoorisaiPalette.field,
        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 17, style: .continuous)
          .stroke(
            isMine ? WoorisaiPalette.coral.opacity(0.22) : WoorisaiPalette.line,
            lineWidth: 1
          )
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if !isMine && !dynamicTypeSize.isAccessibilitySize {
        Spacer(minLength: 44)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("relationship.thread.comment.\(comment.id)")
  }
}

private struct RelationshipMediaGallery: View {
  let attachments: [RelationshipMedia]
  let mediaService: any MediaServing
  let onAuthenticationRequired: @MainActor () -> Void

  var body: some View {
    Group {
      if attachments.count == 1, let attachment = attachments.first {
        preview(attachment)
      } else {
        ScrollView(.horizontal) {
          LazyHStack(spacing: 10) {
            ForEach(attachments) { attachment in
              preview(attachment)
                .containerRelativeFrame(.horizontal, count: 1, span: 1, spacing: 22)
            }
          }
          .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .accessibilityLabel("첨부 미디어 \(attachments.count)개")
      }
    }
  }

  private func preview(_ attachment: RelationshipMedia) -> some View {
    MediaAttachmentPreview(
      attachmentID: attachment.id,
      fileName: attachment.fileName,
      contentType: attachment.contentType,
      byteSize: attachment.byteSize,
      onAuthenticationRequired: onAuthenticationRequired
    )
  }
}
