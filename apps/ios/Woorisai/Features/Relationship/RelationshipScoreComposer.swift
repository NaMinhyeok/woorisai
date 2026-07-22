import SwiftUI
import WoorisaiAPI

struct ScoreComposerSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var model: RelationshipModel
  @State private var mediaModel: MediaAttachmentComposerModel
  @State private var confirmsDiscard = false
  @FocusState private var isReasonFocused: Bool

  @Binding private var targetScore: Int
  @Binding private var reason: String

  @MainActor
  init(
    model: RelationshipModel,
    mediaModel: MediaAttachmentComposerModel,
    targetScore: Binding<Int>,
    reason: Binding<String>
  ) {
    _model = State(initialValue: model)
    _mediaModel = State(initialValue: mediaModel)
    _targetScore = targetScore
    _reason = reason
  }

  var body: some View {
    NavigationStack {
      WarmBackground {
        ScrollView {
          VStack(alignment: .leading, spacing: WoorisaiSpacing.large) {
            scoreControl
            scorePreview
            reasonField

            VStack(alignment: .leading, spacing: WoorisaiSpacing.small) {
              Text("사진 (선택)")
                .font(.headline)
                .foregroundStyle(WoorisaiPalette.ink)
              Text("점수 기록에는 사진 한 장을 함께 남길 수 있어요.")
                .font(.footnote)
                .foregroundStyle(WoorisaiPalette.muted)
              MediaAttachmentComposer(model: mediaModel)
            }
          }
          .disabled(isDraftEditingLocked)
          .frame(maxWidth: 620)
          .padding(.horizontal, WoorisaiSpacing.screenGutter)
          .padding(.top, WoorisaiSpacing.regular)
          .padding(.bottom, WoorisaiSpacing.large)
          .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        stickySubmit
      }
      .navigationTitle("내 점수 바꾸기")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("취소", action: requestDismissal)
            .disabled(
              model.scoreSubmissionState == .submitting
                || model.scoreOutcomeRequiresConfirmation
            )
        }
      }
      .interactiveDismissDisabled(
        isDirty || model.scoreSubmissionState == .submitting
          || model.scoreOutcomeRequiresConfirmation
      )
      .confirmationDialog(
        "작성 중인 마음을 지울까요?",
        isPresented: $confirmsDiscard,
        titleVisibility: .visible
      ) {
        Button("초안 지우기", role: .destructive, action: discardAndDismiss)
        Button("계속 작성하기", role: .cancel) {}
      } message: {
        Text("선택한 점수와 이유, 아직 기록하지 않은 사진이 사라집니다.")
      }
      .alert(
        "최신 내용이 필요해요",
        isPresented: Binding(
          get: { model.conflict == .scoreChange },
          set: {
            if !$0, model.conflict == .scoreChange {
              model.dismissConflict()
            }
          }
        )
      ) {
        Button("최신 내용 불러오기") {
          model.reloadAfterConflict()
        }
      } message: {
        Text("다른 변경과 겹쳐 저장하지 못했습니다. 입력은 유지하고 최신 점수를 불러옵니다.")
      }
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
    .accessibilityIdentifier("relationship.composer")
    .onAppear {
      syncScoreDraftProtection()
    }
    .onChange(of: isDirty, initial: true) { _, _ in
      syncScoreDraftProtection()
    }
    .onChange(of: mediaModel.uploads.map(\.id), initial: true) { _, _ in
      syncScoreDraftProtection()
    }
    .onChange(of: mediaModel.isImporting, initial: true) { _, _ in
      syncScoreDraftProtection()
    }
    .onDisappear {
      isReasonFocused = false
      guard model.scoreSubmissionState != .submitting else { return }
      if !isDirty {
        model.updateLocalScoreDraftProtection(isProtected: false)
      }
      if !model.scoreOutcomeRequiresConfirmation {
        model.releaseManualRetryDraftProtection(.scoreChange)
      }
      if model.rejectedMediaMutation == .scoreChange {
        mediaModel.releaseSubmittedUploadOwnership()
      }
      mediaModel.clear()
    }
  }

  private var scoreControl: some View {
    WarmSurface {
      VStack(alignment: .leading, spacing: WoorisaiSpacing.regular) {
        VStack(alignment: .leading, spacing: WoorisaiSpacing.xSmall) {
          Text("어떤 마음을 남길까요?")
            .font(.title3.weight(.bold))
            .foregroundStyle(WoorisaiPalette.ink)
          Text("0점부터 100점까지 빠르게 고르고, 양옆 버튼으로 한 점씩 다듬어 보세요.")
            .font(.footnote)
            .foregroundStyle(WoorisaiPalette.muted)
        }

        HStack(spacing: WoorisaiSpacing.medium) {
          scoreAdjustmentButton(
            symbol: "minus",
            label: "점수 1점 내리기",
            identifier: "relationship.targetScore.decrement",
            isEnabled: targetScore > 0
          ) {
            targetScore = max(0, targetScore - 1)
          }

          Text("\(targetScore)점")
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            .foregroundStyle(WoorisaiPalette.coralDark)
            .frame(maxWidth: .infinity)
            .contentTransition(.numericText())
            .accessibilityHidden(true)

          scoreAdjustmentButton(
            symbol: "plus",
            label: "점수 1점 올리기",
            identifier: "relationship.targetScore.increment",
            isEnabled: targetScore < 100
          ) {
            targetScore = min(100, targetScore + 1)
          }
        }

        Slider(value: scoreSliderValue, in: 0...100, step: 1)
          .tint(WoorisaiPalette.coral)
          .accessibilityLabel("목표 점수")
          .accessibilityValue("\(targetScore)점")
          .accessibilityIdentifier("relationship.targetScore")
      }
      .padding(WoorisaiSpacing.regular)
    }
  }

  private func scoreAdjustmentButton(
    symbol: String,
    label: String,
    identifier: String,
    isEnabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.headline.weight(.bold))
        .foregroundStyle(isEnabled ? WoorisaiPalette.coralDark : WoorisaiPalette.muted)
        .frame(
          width: WoorisaiControlMetric.minimumTapTarget,
          height: WoorisaiControlMetric.minimumTapTarget
        )
        .background(WoorisaiPalette.coralSoft, in: Circle())
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
    .accessibilityLabel(label)
    .accessibilityIdentifier(identifier)
  }

  private var scorePreview: some View {
    let currentScore = model.scores?.outgoingScore ?? targetScore
    let delta = targetScore - currentScore
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: WoorisaiSpacing.medium))
      : AnyLayout(HStackLayout(alignment: .center, spacing: WoorisaiSpacing.medium))

    return layout {
      HStack(spacing: WoorisaiSpacing.medium) {
        previewScore(label: "현재", score: currentScore)
        Image(systemName: "arrow.right")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(WoorisaiPalette.coral)
          .accessibilityHidden(true)
        previewScore(label: "새 마음", score: targetScore)
      }
      if !dynamicTypeSize.isAccessibilitySize {
        Spacer(minLength: 0)
      }
      Text(deltaLabel(delta))
        .font(.caption.weight(.heavy))
        .foregroundStyle(delta < 0 ? WoorisaiPalette.sage : WoorisaiPalette.coralDark)
        .padding(.horizontal, WoorisaiSpacing.small)
        .padding(.vertical, WoorisaiSpacing.xSmall)
        .background(delta < 0 ? WoorisaiPalette.sageSoft : WoorisaiPalette.coralSoft, in: Capsule())
    }
    .padding(WoorisaiSpacing.regular)
    .background(
      WoorisaiPalette.selectedSurface,
      in: RoundedRectangle(cornerRadius: WoorisaiRadius.medium, style: .continuous)
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("점수 미리보기")
    .accessibilityValue(
      "현재 \(currentScore)점, 목표 \(targetScore)점, \(deltaAccessibilityLabel(delta))"
    )
    .accessibilityIdentifier("relationship.scorePreview")
  }

  private func previewScore(label: String, score: Int) -> some View {
    VStack(alignment: .leading, spacing: WoorisaiSpacing.xSmall) {
      Text(label)
        .font(.caption.weight(.semibold))
        .foregroundStyle(WoorisaiPalette.muted)
      Text("\(score)점")
        .font(.headline.weight(.bold))
        .foregroundStyle(WoorisaiPalette.ink)
    }
  }

  private var reasonField: some View {
    VStack(alignment: .leading, spacing: WoorisaiSpacing.small) {
      HStack(alignment: .firstTextBaseline, spacing: WoorisaiSpacing.small) {
        Text("이유 (선택)")
          .font(.headline)
          .foregroundStyle(WoorisaiPalette.ink)
        Spacer(minLength: WoorisaiSpacing.small)
        Text("\(reasonCodePointCount)/\(RelationshipScoreChangeDraft.maximumReasonCharacterCount)")
          .font(.caption)
          .foregroundStyle(reasonIsWithinLimit ? WoorisaiPalette.muted : WoorisaiPalette.error)
      }

      HStack(alignment: .bottom, spacing: WoorisaiSpacing.small) {
        TextField("남기고 싶은 이유가 있다면 적어 주세요.", text: $reason, axis: .vertical)
          .lineLimit(2...5)
          .focused($isReasonFocused)
          .foregroundStyle(WoorisaiPalette.ink)
          .tint(WoorisaiPalette.coralDark)
          .padding(WoorisaiSpacing.medium)
          .background(
            WoorisaiPalette.field,
            in: RoundedRectangle(cornerRadius: WoorisaiRadius.small, style: .continuous)
          )
          .overlay {
            RoundedRectangle(cornerRadius: WoorisaiRadius.small, style: .continuous)
              .stroke(
                reasonIsWithinLimit ? WoorisaiPalette.line : WoorisaiPalette.error, lineWidth: 1)
          }
          .accessibilityIdentifier("relationship.reason")

        if isReasonFocused {
          KeyboardDismissButton {
            isReasonFocused = false
          }
        }
      }
    }
  }

  private var stickySubmit: some View {
    VStack(alignment: .leading, spacing: WoorisaiSpacing.small) {
      if model.scoreOutcomeRequiresConfirmation {
        RelationshipUnknownOutcomeRecovery(
          inspectionState: model.scoreOutcomeInspectionState,
          inspectionResult: model.scoreOutcomeInspectionResult,
          allowsResolveAsSaved: model.canResolveUnknownScoreOutcomeAsCommitted,
          allowsManualRetry: model.canRetryUnknownScoreOutcome,
          onReloadLatest: model.inspectUnknownScoreOutcome,
          onResolveAsSaved: resolveUnknownOutcomeAsSaved,
          onConfirmManualRetry: allowUnknownOutcomeRetry,
          onAbandonInconclusive: abandonInconclusiveUnknownOutcome
        )
      }
      if let validationMessage {
        Text(validationMessage)
          .font(.caption)
          .foregroundStyle(WoorisaiPalette.muted)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      PrimaryHeartButton(
        "이 마음 기록하기",
        isEnabled: canSubmitScore,
        isLoading: model.scoreSubmissionState == .submitting,
        action: submitScoreChange
      )
      .accessibilityLabel(Text(submissionAccessibility.label))
      .accessibilityValue(Text(submissionAccessibility.value))
      .accessibilityIdentifier("relationship.createScoreChange")
    }
    .padding(.horizontal, WoorisaiSpacing.screenGutter)
    .padding(.vertical, WoorisaiSpacing.medium)
    .background(.regularMaterial)
    .overlay(alignment: .top) {
      Divider().overlay(WoorisaiPalette.line)
    }
  }

  private var scoreSliderValue: Binding<Double> {
    Binding(
      get: { Double(targetScore) },
      set: { targetScore = min(100, max(0, Int($0.rounded()))) }
    )
  }

  private var currentScore: Int {
    model.scores?.outgoingScore ?? targetScore
  }

  private var reasonCodePointCount: Int {
    WoorisaiTextInput.normalizedCodePointCount(reason)
  }

  private var reasonIsWithinLimit: Bool {
    reasonCodePointCount <= RelationshipScoreChangeDraft.maximumReasonCharacterCount
  }

  private var canSubmitScore: Bool {
    model.canCreateScoreChange(targetScore: targetScore)
      && mediaModel.isReadyForSubmission
      && reasonIsWithinLimit
  }

  private var isDraftEditingLocked: Bool {
    SubmittedDraftEditingPolicy.isLocked(
      isSubmitting: model.scoreSubmissionState == .submitting,
      requiresOutcomeConfirmation: model.scoreOutcomeRequiresConfirmation
    )
  }

  private var isDirty: Bool {
    targetScore != currentScore
      || !WoorisaiTextInput.normalized(reason).isEmpty
      || !mediaModel.uploads.isEmpty
      || mediaModel.isImporting
  }

  private var validationMessage: String? {
    if model.scoreOutcomeRequiresConfirmation {
      return "이전 저장 결과를 먼저 확인해 주세요."
    }
    if !reasonIsWithinLimit {
      return "이유를 200자 이하로 줄여 주세요."
    }
    if mediaModel.isImporting || !mediaModel.isReadyForSubmission {
      return "사진 준비가 끝나면 기록할 수 있어요."
    }
    if targetScore == currentScore {
      return "현재 점수와 다른 점수를 골라 주세요."
    }
    return nil
  }

  private var submissionAccessibility: RelationshipSubmissionAccessibility {
    .score(
      state: model.scoreSubmissionState,
      targetScore: targetScore,
      canSubmit: canSubmitScore,
      isReasonWithinLimit: reasonIsWithinLimit
    )
  }

  private func submitScoreChange() {
    let accepted = model.createScoreChange(
      targetScore: targetScore,
      reason: reason,
      mediaUploadIDs: mediaModel.readyUploadIDs
    )
    if accepted {
      isReasonFocused = false
      mediaModel.markReadyUploadsSubmitted()
    }
  }

  private func requestDismissal() {
    isReasonFocused = false
    if isDirty {
      confirmsDiscard = true
    } else {
      dismiss()
    }
  }

  private func discardAndDismiss() {
    isReasonFocused = false
    model.updateLocalScoreDraftProtection(isProtected: false)
    model.releaseManualRetryDraftProtection(.scoreChange)
    if model.rejectedMediaMutation == .scoreChange {
      mediaModel.releaseSubmittedUploadOwnership()
    }
    mediaModel.clear()
    targetScore = currentScore
    reason = ""
    dismiss()
  }

  private func resolveUnknownOutcomeAsSaved() {
    guard model.resolveUnknownScoreOutcomeAsCommitted() else { return }
    mediaModel.consumeReadyUploads()
    targetScore = currentScore
    reason = ""
    dismiss()
  }

  private func allowUnknownOutcomeRetry() {
    guard model.confirmUnknownScoreOutcomeForRetry() else { return }
    mediaModel.releaseSubmittedUploadOwnership()
  }

  private func abandonInconclusiveUnknownOutcome() {
    guard model.abandonInconclusiveUnknownScoreOutcome() else { return }
    mediaModel.consumeReadyUploads()
    targetScore = currentScore
    reason = ""
    dismiss()
  }

  private func syncScoreDraftProtection() {
    model.updateLocalScoreDraftProtection(isProtected: isDirty)
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

private struct RelationshipUnknownOutcomeRecovery: View {
  let inspectionState: RelationshipModel.OutcomeInspectionState
  let inspectionResult: RelationshipModel.OutcomeInspectionResult
  let allowsResolveAsSaved: Bool
  let allowsManualRetry: Bool
  let onReloadLatest: () -> Void
  let onResolveAsSaved: () -> Void
  let onConfirmManualRetry: () -> Void
  let onAbandonInconclusive: () -> Void
  @State private var showsRecoveryActions = false

  var body: some View {
    VStack(alignment: .leading, spacing: WoorisaiSpacing.xSmall) {
      Text(message)
        .font(.caption)
        .foregroundStyle(WoorisaiPalette.error)
      Button {
        showsRecoveryActions = true
      } label: {
        Label(
          inspectionState == .loading ? "저장 결과 확인 중" : "저장 결과 확인하기",
          systemImage: "arrow.triangle.2.circlepath"
        )
        .frame(maxWidth: .infinity, minHeight: WoorisaiControlMetric.minimumTapTarget)
      }
      .buttonStyle(.borderedProminent)
      .tint(WoorisaiPalette.coralDark)
      .disabled(inspectionState == .loading)
      .accessibilityIdentifier("relationship.mutation.openRecovery")
    }
    .confirmationDialog(
      "점수 기록의 저장 결과를 어떻게 확인했나요?",
      isPresented: $showsRecoveryActions,
      titleVisibility: .visible
    ) {
      Button("최신 점수와 기록 불러오기", action: onReloadLatest)
        .disabled(inspectionState == .loading)
        .accessibilityIdentifier("relationship.mutation.reloadLatest")
      Button("이미 저장됨 · 초안 정리", action: onResolveAsSaved)
        .disabled(!allowsResolveAsSaved)
        .accessibilityIdentifier("relationship.mutation.resolveSaved")
      Button("저장 안 됨 · 다시 시도 허용", action: onConfirmManualRetry)
        .disabled(inspectionState != .loaded || !allowsManualRetry)
        .accessibilityIdentifier("relationship.mutation.confirmRetry")
      Button("판단 보류 · 재전송 없이 초안 정리", role: .destructive) {
        onAbandonInconclusive()
      }
      .disabled(inspectionState != .loaded || inspectionResult != .inconclusive)
      .accessibilityIdentifier("relationship.mutation.abandonInconclusive")
      Button("취소", role: .cancel) {}
    } message: {
      Text(message)
    }
  }

  private var message: String {
    switch inspectionState {
    case .idle:
      return "저장됐을 수도 있어요. 최신 점수와 기록을 먼저 확인해 주세요."
    case .loading:
      return "최신 점수와 기록을 확인하고 있어요. 초안은 그대로 유지됩니다."
    case .loaded:
      switch inspectionResult {
      case .committed:
        return "제출한 점수·이유·첨부가 같은 새 기록을 확인했어요. 초안을 정리해 주세요."
      case .notCommitted:
        return "제출 전 점수와 갱신 시각이 그대로예요. 이제 직접 다시 시도할 수 있어요."
      case .inconclusive:
        return "다른 점수 변경이 함께 보여 자동 판단할 수 없어요. 재전송하지 않고 초안을 정리할 수 있어요."
      }
    case .failed:
      return "최신 기록을 불러오지 못했어요. 초안을 유지한 채 다시 시도해 주세요."
    }
  }
}
