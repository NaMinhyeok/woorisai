import Foundation
import ImageIO
import Observation
import PhotosUI
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WoorisaiAPI

private actor MediaSessionCleanupDeadlineGate {
  private var continuation: CheckedContinuation<Void, Never>?

  init(_ continuation: CheckedContinuation<Void, Never>) {
    self.continuation = continuation
  }

  func resolve() {
    guard let continuation else { return }
    self.continuation = nil
    continuation.resume()
  }
}

enum MediaAttachmentRuleViolation: Error, Equatable, Sendable {
  case videoNotAllowed
  case tooManyImages(maximum: Int)
  case onlyOneVideoAllowed
  case mixedMediaNotAllowed
}

struct MediaAttachmentPolicy: Equatable, Sendable {
  let purpose: MediaPurpose

  var allowsVideo: Bool {
    purpose != .scoreChange
  }

  var pickerSelectionLimit: Int {
    purpose == .scoreChange ? 1 : 4
  }

  func remainingSelectionCapacity(for existingKinds: [MediaKind]) -> Int {
    switch purpose {
    case .scoreChange:
      return max(0, 1 - existingKinds.count)
    case .comment, .diaryEntry:
      if existingKinds.contains(.video) { return 0 }
      return max(0, 4 - existingKinds.count)
    }
  }

  func validate(existingKinds: [MediaKind], adding kind: MediaKind) throws {
    switch purpose {
    case .scoreChange:
      guard kind == .image else {
        throw MediaAttachmentRuleViolation.videoNotAllowed
      }
      guard existingKinds.isEmpty else {
        throw MediaAttachmentRuleViolation.tooManyImages(maximum: 1)
      }
    case .comment, .diaryEntry:
      if existingKinds.contains(.video) {
        if kind == .video {
          throw MediaAttachmentRuleViolation.onlyOneVideoAllowed
        }
        throw MediaAttachmentRuleViolation.mixedMediaNotAllowed
      }

      if kind == .video {
        guard existingKinds.isEmpty else {
          throw MediaAttachmentRuleViolation.mixedMediaNotAllowed
        }
        return
      }

      guard existingKinds.count < 4 else {
        throw MediaAttachmentRuleViolation.tooManyImages(maximum: 4)
      }
    }
  }
}

@MainActor
@Observable
final class MediaAttachmentComposerModel {
  struct UploadItem: Identifiable {
    let id: UUID
    let kind: MediaKind
    let fileName: String
    let byteSize: Int64
    let previewImage: UIImage?
    let upload: MediaUploadModel
  }

  enum ImportFailure: Equatable, Sendable {
    case unreadableSelection
    case unsupportedType
    case imageConversionFailed
    case invalidFile
    case fileTooLarge(kind: MediaKind)
    case rule(MediaAttachmentRuleViolation)
  }

  let policy: MediaAttachmentPolicy
  private(set) var existingKinds: [MediaKind]
  private(set) var uploads: [UploadItem] = []
  private(set) var submittedReadyUploadIDs: Set<UUID> = []
  private(set) var isImporting = false
  private(set) var importFailure: ImportFailure?

  var readyUploadIDs: [UUID] {
    uploads.compactMap(\.upload.readyUpload?.id)
  }

  /// Empty attachment lists are valid. Non-empty lists are valid only after every upload is READY.
  var isReadyForSubmission: Bool {
    !isImporting && uploads.allSatisfy { $0.upload.readyUpload != nil }
  }

  var hasAuthenticationFailure: Bool {
    uploads.contains { $0.upload.state == .failed(.authenticationRequired) }
  }

  var canSelectMore: Bool {
    !isImporting && policy.remainingSelectionCapacity(for: allKinds) > 0
  }

  var pickerSelectionLimit: Int {
    max(1, policy.remainingSelectionCapacity(for: allKinds))
  }

  @ObservationIgnored
  private let service: any MediaServing

  @ObservationIgnored
  private let uploader: any PresignedMediaUploading

  @ObservationIgnored
  private var importTask: Task<Void, Never>?

  @ObservationIgnored
  private var importGeneration: UInt = 0

  init(
    purpose: MediaPurpose,
    service: any MediaServing,
    uploader: any PresignedMediaUploading = URLSessionPresignedMediaUploader(),
    existingKinds: [MediaKind] = []
  ) {
    policy = MediaAttachmentPolicy(purpose: purpose)
    self.existingKinds = existingKinds
    self.service = service
    self.uploader = uploader
  }

  func setExistingKinds(_ kinds: [MediaKind]) {
    existingKinds = kinds
    importFailure = nil
  }

  func importPickerItems(_ pickerItems: [PhotosPickerItem]) {
    guard !pickerItems.isEmpty else { return }
    importGeneration &+= 1
    let generation = importGeneration
    importTask?.cancel()
    importFailure = nil
    isImporting = true

    importTask = Task { @MainActor [weak self] in
      guard let self else { return }
      for pickerItem in pickerItems {
        guard !Task.isCancelled, self.importGeneration == generation else { return }
        do {
          let prepared = try await Self.preparePickerItem(pickerItem)
          guard !Task.isCancelled, self.importGeneration == generation else { return }
          try self.addPreparedAttachment(
            kind: prepared.kind,
            fileName: prepared.fileName,
            contentType: prepared.contentType,
            data: prepared.data,
            previewImage: prepared.previewCGImage.map(UIImage.init(cgImage:))
          )
        } catch is CancellationError {
          return
        } catch {
          self.importFailure = Self.mapImportFailure(error)
        }
      }

      guard self.importGeneration == generation else { return }
      self.importTask = nil
      self.isImporting = false
    }
  }

  /// Adds already-loaded bytes and starts the initiate/PUT/complete flow.
  ///
  /// This is also the non-PhotosPicker seam for deterministic tests. Production callers should
  /// normally use ``importPickerItems(_:)`` so the app never requests broad Photos access.
  func addPreparedAttachment(
    kind: MediaKind,
    fileName: String,
    contentType: String,
    data: Data
  ) throws {
    try addPreparedAttachment(
      kind: kind,
      fileName: fileName,
      contentType: contentType,
      data: data,
      previewImage: kind == .image ? MediaImagePreview.thumbnail(from: data) : nil
    )
  }

  private func addPreparedAttachment(
    kind: MediaKind,
    fileName: String,
    contentType: String,
    data: Data,
    previewImage: UIImage?
  ) throws {
    do {
      try policy.validate(existingKinds: allKinds, adding: kind)
    } catch let violation as MediaAttachmentRuleViolation {
      importFailure = .rule(violation)
      throw violation
    }

    do {
      let draft = try MediaUploadDraft(
        purpose: policy.purpose,
        kind: kind,
        fileName: fileName,
        contentType: contentType,
        byteSize: Int64(data.count)
      )
      let selection = try MediaUploadSelection(draft: draft, data: data)
      let upload = MediaUploadModel(service: service, uploader: uploader)
      uploads.append(
        UploadItem(
          id: UUID(),
          kind: kind,
          fileName: draft.fileName,
          byteSize: draft.byteSize,
          previewImage: previewImage,
          upload: upload
        )
      )
      importFailure = nil
      upload.start(selection)
    } catch {
      importFailure = Self.mapImportFailure(error, kind: kind)
      throw error
    }
  }

  func retry(_ itemID: UUID) {
    uploads.first(where: { $0.id == itemID })?.upload.retry()
  }

  func cancel(_ itemID: UUID) {
    uploads.first(where: { $0.id == itemID })?.upload.cancel()
  }

  func remove(_ itemID: UUID) {
    guard let index = uploads.firstIndex(where: { $0.id == itemID }) else { return }
    clearUploadRespectingSubmissionOwnership(uploads[index].upload)
    uploads.remove(at: index)
    importFailure = nil
  }

  func dismissImportFailure() {
    importFailure = nil
  }

  /// Marks every READY upload as owned by an issued parent mutation and returns its ordered IDs.
  ///
  /// Once marked, view cleanup must not race the parent transaction by discarding these uploads.
  /// A successful parent mutation finishes the transfer with ``consumeReadyUploads()``.
  @discardableResult
  func markReadyUploadsSubmitted() -> [UUID] {
    guard isReadyForSubmission else { return [] }
    let uploadIDs = readyUploadIDs
    submittedReadyUploadIDs.formUnion(uploadIDs)
    return uploadIDs
  }

  /// Releases submission ownership after a definitive server rejection (for example 401/403/409).
  /// The READY upload remains selectable for an explicit retry, but later remove/clear may discard
  /// it because the parent transaction is known not to have committed.
  func releaseSubmittedUploadOwnership() {
    submittedReadyUploadIDs.removeAll()
  }

  /// Transfers READY uploads after the parent mutation has committed them.
  /// No discard request is sent for consumed uploads.
  @discardableResult
  func consumeReadyUploads() -> [CompletedMediaUpload] {
    guard isReadyForSubmission else { return [] }
    let completed = uploads.compactMap { $0.upload.consumeReadyUpload() }
    uploads.removeAll()
    submittedReadyUploadIDs.removeAll()
    importFailure = nil
    return completed
  }

  /// Cancels selection work and discards every pending or unattached READY upload best effort.
  func clear() {
    importGeneration &+= 1
    importTask?.cancel()
    importTask = nil
    isImporting = false
    for item in uploads {
      clearUploadRespectingSubmissionOwnership(item.upload)
    }
    uploads.removeAll()
    importFailure = nil
  }

  /// Starts all known discards before the shared Basic credential is removed and returns their
  /// tasks so composition-root teardown can wait with an app-level deadline.
  func clearForCredentialRemoval() -> [Task<Void, Never>] {
    importGeneration &+= 1
    importTask?.cancel()
    importTask = nil
    isImporting = false
    var discardTasks: [Task<Void, Never>] = []
    for item in uploads {
      if let uploadID = item.upload.readyUpload?.id,
        submittedReadyUploadIDs.contains(uploadID)
      {
        _ = item.upload.consumeReadyUpload()
      } else if let task = item.upload.clearForCredentialRemoval() {
        discardTasks.append(task)
      }
    }
    uploads.removeAll()
    submittedReadyUploadIDs.removeAll()
    importFailure = nil
    return discardTasks
  }

  private func clearUploadRespectingSubmissionOwnership(_ upload: MediaUploadModel) {
    if let uploadID = upload.readyUpload?.id, submittedReadyUploadIDs.contains(uploadID) {
      _ = upload.consumeReadyUpload()
    } else {
      upload.clear()
    }
  }

  private struct PreparedPickerItem: Sendable {
    let kind: MediaKind
    let fileName: String
    let contentType: String
    let data: Data
    let previewCGImage: CGImage?
  }

  private var allKinds: [MediaKind] {
    existingKinds + uploads.map(\.kind)
  }

  private enum PickerPreparationError: Error {
    case unreadableSelection
    case unsupportedType
    case imageConversionFailed
  }

  private static func preparePickerItem(_ item: PhotosPickerItem) async throws
    -> PreparedPickerItem
  {
    let supportedTypes = item.supportedContentTypes

    if let type = supportedTypes.first(where: {
      guard let contentType = $0.preferredMIMEType?.lowercased() else { return false }
      return allowedImageMIMETypes.contains(contentType)
    }) {
      let data = try await loadData(from: item)
      let contentType = type.preferredMIMEType!.lowercased()
      return PreparedPickerItem(
        kind: .image,
        fileName: generatedFileName(kind: .image, type: type, contentType: contentType),
        contentType: contentType,
        data: data,
        previewCGImage: MediaImagePreview.thumbnailCGImage(from: data)
      )
    }

    if supportedTypes.contains(where: isHEIFType) {
      let sourceData = try await loadData(from: item)
      guard let image = UIImage(data: sourceData),
        let jpegData = image.jpegData(compressionQuality: 0.9),
        !jpegData.isEmpty
      else {
        throw PickerPreparationError.imageConversionFailed
      }
      return PreparedPickerItem(
        kind: .image,
        fileName: generatedFileName(kind: .image, type: .jpeg, contentType: "image/jpeg"),
        contentType: "image/jpeg",
        data: jpegData,
        previewCGImage: MediaImagePreview.thumbnailCGImage(from: jpegData)
      )
    }

    if let type = supportedTypes.first(where: {
      guard let contentType = $0.preferredMIMEType?.lowercased() else { return false }
      return allowedVideoMIMETypes.contains(contentType)
    }) {
      let data = try await loadData(from: item)
      let contentType = type.preferredMIMEType!.lowercased()
      return PreparedPickerItem(
        kind: .video,
        fileName: generatedFileName(kind: .video, type: type, contentType: contentType),
        contentType: contentType,
        data: data,
        previewCGImage: nil
      )
    }

    throw PickerPreparationError.unsupportedType
  }

  private static func loadData(from item: PhotosPickerItem) async throws -> Data {
    do {
      guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else {
        throw PickerPreparationError.unreadableSelection
      }
      return data
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as PickerPreparationError {
      throw error
    } catch {
      throw PickerPreparationError.unreadableSelection
    }
  }

  private static let allowedImageMIMETypes: Set<String> = [
    "image/jpeg", "image/png", "image/webp",
  ]

  private static let allowedVideoMIMETypes: Set<String> = [
    "video/mp4", "video/quicktime", "video/webm",
  ]

  private static let heifTypeIdentifiers: Set<String> = [
    "public.heic", "public.heics", "public.heif", "public.heifs",
  ]

  private static func isHEIFType(_ type: UTType) -> Bool {
    heifTypeIdentifiers.contains(type.identifier)
      || type.preferredMIMEType?.lowercased() == "image/heic"
      || type.preferredMIMEType?.lowercased() == "image/heif"
  }

  private static func generatedFileName(
    kind: MediaKind,
    type: UTType,
    contentType: String
  ) -> String {
    let fallbackExtension: String
    switch contentType {
    case "image/jpeg": fallbackExtension = "jpg"
    case "image/png": fallbackExtension = "png"
    case "image/webp": fallbackExtension = "webp"
    case "video/mp4": fallbackExtension = "mp4"
    case "video/quicktime": fallbackExtension = "mov"
    case "video/webm": fallbackExtension = "webm"
    default: fallbackExtension = kind == .image ? "jpg" : "mp4"
    }
    let fileExtension = type.preferredFilenameExtension ?? fallbackExtension
    let prefix = kind == .image ? "photo" : "video"
    return "\(prefix)-\(UUID().uuidString.lowercased()).\(fileExtension.lowercased())"
  }

  private static func mapImportFailure(
    _ error: any Error,
    kind: MediaKind? = nil
  ) -> ImportFailure {
    if let preparationError = error as? PickerPreparationError {
      switch preparationError {
      case .unreadableSelection: return .unreadableSelection
      case .unsupportedType: return .unsupportedType
      case .imageConversionFailed: return .imageConversionFailed
      }
    }
    if let violation = error as? MediaAttachmentRuleViolation {
      return .rule(violation)
    }
    if let validationError = error as? MediaValidationError {
      switch validationError {
      case .invalidByteSize: return .fileTooLarge(kind: kind ?? .image)
      case .unsupportedContentType: return .unsupportedType
      case .invalidFileName, .videoNotAllowed, .invalidUploadGrant, .expiredUploadGrant,
        .invalidCompletedUpload, .invalidDownloadGrant:
        return .invalidFile
      }
    }
    return .invalidFile
  }
}

/// Owns composers that outlive navigation destinations so session teardown can start their
/// cleanup while the Basic credential is still available.
@MainActor
final class TopLevelMediaSessionCoordinator {
  let relationshipScoreComposer: MediaAttachmentComposerModel
  let diaryEntryComposer: MediaAttachmentComposerModel

  init(
    service: any MediaServing,
    uploader: any PresignedMediaUploading
  ) {
    relationshipScoreComposer = MediaAttachmentComposerModel(
      purpose: .scoreChange,
      service: service,
      uploader: uploader
    )
    diaryEntryComposer = MediaAttachmentComposerModel(
      purpose: .diaryEntry,
      service: service,
      uploader: uploader
    )
  }

  func prepareForCredentialRemoval(
    releaseRejectedScoreSubmission: Bool,
    releaseRejectedDiarySubmission: Bool,
    timeout: Duration = .seconds(1)
  ) async {
    if releaseRejectedScoreSubmission {
      relationshipScoreComposer.releaseSubmittedUploadOwnership()
    }
    if releaseRejectedDiarySubmission {
      diaryEntryComposer.releaseSubmittedUploadOwnership()
    }
    let discardTasks =
      relationshipScoreComposer.clearForCredentialRemoval()
      + diaryEntryComposer.clearForCredentialRemoval()
    await waitForDiscardTasks(discardTasks, timeout: timeout)
  }

  private func waitForDiscardTasks(
    _ tasks: [Task<Void, Never>],
    timeout: Duration
  ) async {
    guard !tasks.isEmpty, timeout > .zero else { return }
    await withCheckedContinuation { continuation in
      let gate = MediaSessionCleanupDeadlineGate(continuation)
      Task {
        for task in tasks { await task.value }
        await gate.resolve()
      }
      Task {
        try? await Task.sleep(for: timeout)
        guard !Task.isCancelled else { return }
        await gate.resolve()
      }
    }
  }
}

struct MediaAttachmentComposer: View {
  @State private var model: MediaAttachmentComposerModel
  @State private var pickerItems: [PhotosPickerItem] = []

  @MainActor
  init(model: MediaAttachmentComposerModel) {
    _model = State(initialValue: model)
  }

  var body: some View {
    let pickerLabel = model.policy.allowsVideo ? "사진 또는 동영상 첨부" : "사진 첨부"
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        PhotosPicker(
          selection: $pickerItems,
          maxSelectionCount: model.pickerSelectionLimit,
          selectionBehavior: .ordered,
          matching: model.policy.allowsVideo ? .any(of: [.images, .videos]) : .images,
          preferredItemEncoding: .current
        ) {
          Label(pickerLabel, systemImage: "paperclip")
        }
        .disabled(!model.canSelectMore)
        .accessibilityLabel(pickerLabel)
        .accessibilityHint(pickerAccessibilityHint)

        Spacer()

        if !model.uploads.isEmpty {
          Text(attachmentCountLabel)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(attachmentCountLabel)
        }
      }

      if model.isImporting {
        ProgressView("선택한 파일을 준비하고 있어요.")
          .accessibilityIdentifier("media.importing")
      }

      if let failure = model.importFailure {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Label(importFailureMessage(failure), systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(WoorisaiPalette.error)
          Spacer()
          Button("닫기") {
            model.dismissImportFailure()
          }
          .font(.footnote)
          .accessibilityLabel("첨부 오류 닫기")
        }
        .accessibilityIdentifier("media.importError")
      }

      ForEach(model.uploads) { item in
        uploadRow(item)
      }
    }
    .onChange(of: pickerItems) { _, selectedItems in
      guard !selectedItems.isEmpty else { return }
      model.importPickerItems(selectedItems)
      pickerItems = []
    }
    .accessibilityElement(children: .contain)
  }

  private var pickerAccessibilityHint: String {
    switch model.policy.purpose {
    case .scoreChange:
      return "10메가바이트 이하 사진 한 장을 선택합니다."
    case .comment, .diaryEntry:
      return "사진은 최대 네 장, 동영상은 한 개만 선택할 수 있습니다."
    }
  }

  private var attachmentCountLabel: String {
    "첨부 \(model.uploads.count)개"
  }

  @ViewBuilder
  private func uploadRow(_ item: MediaAttachmentComposerModel.UploadItem) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if let previewImage = item.previewImage {
        MediaAspectFitImageSurface(image: previewImage)
          .frame(maxWidth: .infinity)
          .frame(height: 132)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .accessibilityLabel("선택한 사진 미리보기")
      } else if item.kind == .video {
        ZStack {
          WoorisaiPalette.sageSoft
          Image(systemName: "play.circle.fill")
            .font(.system(size: 38))
            .foregroundStyle(WoorisaiPalette.sage)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel("선택한 동영상")
      }

      HStack(alignment: .firstTextBaseline) {
        Label(item.fileName, systemImage: item.kind == .image ? "photo" : "video")
          .font(.subheadline)
          .lineLimit(1)
        Spacer()
        Text(item.byteSize.formatted(.byteCount(style: .file)))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      uploadStatus(item)

      HStack {
        if item.upload.canRetry {
          Button("재시도") {
            model.retry(item.id)
          }
          .accessibilityLabel("\(item.fileName) 업로드 재시도")
        } else if item.upload.state.isActiveUpload {
          Button("취소", role: .cancel) {
            model.cancel(item.id)
          }
          .accessibilityLabel("\(item.fileName) 업로드 취소")
        }

        Spacer()

        Button("제거", role: .destructive) {
          model.remove(item.id)
        }
        .accessibilityLabel("\(item.fileName) 첨부 제거")
      }
      .font(.footnote)
    }
    .padding(10)
    .background(
      WoorisaiPalette.creamDeep.opacity(0.72),
      in: RoundedRectangle(cornerRadius: 14, style: .continuous)
    )
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("media.upload.\(item.id.uuidString)")
  }

  @ViewBuilder
  private func uploadStatus(_ item: MediaAttachmentComposerModel.UploadItem) -> some View {
    switch item.upload.state {
    case .idle:
      Text("업로드 대기 중")
        .font(.caption)
        .foregroundStyle(.secondary)
    case .initiating:
      ProgressView("업로드 준비 중")
    case .uploading(let progress):
      ProgressView(value: progress, total: 1) {
        Text("업로드 중")
      } currentValueLabel: {
        Text(progress.formatted(.percent.precision(.fractionLength(0))))
      }
      .accessibilityLabel("\(item.fileName) 업로드 중")
      .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
    case .completing:
      ProgressView("업로드 확인 중")
    case .ready:
      Label("첨부 준비 완료", systemImage: "checkmark.circle.fill")
        .font(.caption)
        .foregroundStyle(WoorisaiPalette.success)
    case .failed(let failure):
      Label(uploadFailureMessage(failure), systemImage: "exclamationmark.circle")
        .font(.caption)
        .foregroundStyle(WoorisaiPalette.error)
        .accessibilityLabel("\(item.fileName) 업로드 실패. \(uploadFailureMessage(failure))")
    case .cancelled:
      Label("업로드를 취소했어요.", systemImage: "xmark.circle")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private func uploadFailureMessage(_ failure: MediaUploadModel.Failure) -> String {
    switch failure {
    case .authenticationRequired: return "다시 로그인한 뒤 첨부해 주세요."
    case .forbidden: return "이 파일을 첨부할 권한이 없어요."
    case .unavailable: return "미디어 서버를 잠시 사용할 수 없어요."
    case .expiredGrant: return "업로드 시간이 만료됐어요. 재시도해 주세요."
    case .uploadRejected: return "파일 전송이 거부됐어요."
    case .uploadFailed: return "파일을 전송하지 못했어요."
    case .completionFailed: return "업로드 확인을 마치지 못했어요."
    }
  }

  private func importFailureMessage(
    _ failure: MediaAttachmentComposerModel.ImportFailure
  ) -> String {
    switch failure {
    case .unreadableSelection:
      return "선택한 파일을 읽지 못했어요."
    case .unsupportedType:
      return "JPEG, PNG, WebP, MP4, QuickTime 또는 WebM 파일만 첨부할 수 있어요."
    case .imageConversionFailed:
      return "선택한 HEIC/HEIF 사진을 JPEG로 변환하지 못했어요."
    case .invalidFile:
      return "선택한 파일이 올바르지 않아요."
    case .fileTooLarge(let kind):
      return kind == .image
        ? "사진은 10메가바이트 이하여야 해요."
        : "동영상은 100메가바이트 이하여야 해요."
    case .rule(.videoNotAllowed):
      return "점수 기록에는 사진 한 장만 첨부할 수 있어요."
    case .rule(.tooManyImages(let maximum)):
      return "사진은 최대 \(maximum)장까지 첨부할 수 있어요."
    case .rule(.onlyOneVideoAllowed):
      return "동영상은 한 개만 첨부할 수 있어요."
    case .rule(.mixedMediaNotAllowed):
      return "사진과 동영상을 함께 첨부할 수 없어요."
    }
  }
}

extension MediaUploadModel.State {
  fileprivate var isActiveUpload: Bool {
    switch self {
    case .initiating, .uploading, .completing:
      return true
    case .idle, .ready, .failed, .cancelled:
      return false
    }
  }
}

/// Keeps the complete image visible inside a fixed preview frame, including unusually tall or
/// wide photos. The surrounding neutral surface makes any letterboxing intentional rather than
/// stretching or cropping private media.
struct MediaAspectFitImageSurface: View {
  let image: UIImage

  var body: some View {
    GeometryReader { proxy in
      let imageSize = Self.fittedSize(
        imageSize: image.size,
        containerSize: proxy.size
      )

      ZStack {
        WoorisaiPalette.creamDeep.opacity(0.58)

        Image(uiImage: image)
          .resizable()
          .frame(width: imageSize.width, height: imageSize.height)
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
  }

  static func fittedSize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
    guard imageSize.width.isFinite, imageSize.height.isFinite,
      containerSize.width.isFinite, containerSize.height.isFinite,
      imageSize.width > 0, imageSize.height > 0,
      containerSize.width > 0, containerSize.height > 0
    else {
      return .zero
    }

    let scale = min(
      containerSize.width / imageSize.width,
      containerSize.height / imageSize.height
    )
    return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
  }
}

enum PrivateMediaPreviewError: Error, Equatable, Sendable {
  case invalidGrant
  case invalidImage
  case rejected(statusCode: Int)
  case responseTooLarge
  case responseSizeMismatch
  case transport
  case temporaryFile
}

enum MediaImagePreview {
  /// Bounds retained decoded image memory even when a small compressed upload contains very large
  /// pixel dimensions. 1,200 px is comfortably above the app's inline/Quick Look preview size.
  static let maximumPixelSize = 1_200

  static func thumbnail(
    from data: Data,
    maximumPixelSize: Int = maximumPixelSize
  ) -> UIImage? {
    thumbnailCGImage(from: data, maximumPixelSize: maximumPixelSize).map(UIImage.init(cgImage:))
  }

  static func thumbnailCGImage(
    from data: Data,
    maximumPixelSize: Int = maximumPixelSize
  ) -> CGImage? {
    guard !data.isEmpty, maximumPixelSize > 0 else { return nil }
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
      return nil
    }
    let thumbnailOptions =
      [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        kCGImageSourceShouldCacheImmediately: true,
      ] as CFDictionary
    return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
  }

  static func thumbnail(
    fromFileAt url: URL,
    maximumPixelSize: Int = maximumPixelSize
  ) -> UIImage? {
    guard url.isFileURL, maximumPixelSize > 0 else { return nil }
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
      return nil
    }
    let thumbnailOptions =
      [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        kCGImageSourceShouldCacheImmediately: true,
      ] as CFDictionary
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
      return nil
    }
    return UIImage(cgImage: image)
  }
}

protocol PrivateMediaPreviewDownloading: Sendable {
  func download(
    _ descriptor: PrivateMediaPreviewDescriptor,
    using grant: MediaDownloadGrant
  ) async throws -> PrivateMediaPreviewDownloadedFile
}

final class EphemeralPrivateMediaPreviewDownloader: PrivateMediaPreviewDownloading,
  @unchecked Sendable
{
  static let maximumResponseByteSize = Int64(MediaUploadDraft.maximumVideoByteSize)

  private let delegate: PrivateMediaRedirectRejectingDelegate
  private let session: URLSession
  private let temporaryDirectory: URL

  init(temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
    let delegate = PrivateMediaRedirectRejectingDelegate()
    self.delegate = delegate
    session = URLSession(
      configuration: Self.makeConfiguration(),
      delegate: delegate,
      delegateQueue: nil
    )
    self.temporaryDirectory = temporaryDirectory
  }

  deinit {
    session.invalidateAndCancel()
  }

  func download(
    _ descriptor: PrivateMediaPreviewDescriptor,
    using grant: MediaDownloadGrant
  ) async throws -> PrivateMediaPreviewDownloadedFile {
    guard grant.expiresAt > Date() else { throw PrivateMediaPreviewError.invalidGrant }
    let request = try Self.makeRequest(grant: grant)
    var downloadedURL: URL?

    do {
      let (temporaryURL, response) = try await session.download(for: request)
      downloadedURL = temporaryURL
      try Task.checkCancellation()
      guard let response = response as? HTTPURLResponse,
        (200...299).contains(response.statusCode)
      else {
        throw PrivateMediaPreviewError.rejected(
          statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0
        )
      }
      if response.expectedContentLength > Self.maximumResponseByteSize {
        throw PrivateMediaPreviewError.responseTooLarge
      }
      let byteSize =
        try temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
        .map(Int64.init) ?? 0
      guard byteSize > 0 else { throw PrivateMediaPreviewError.transport }
      guard byteSize <= Self.maximumResponseByteSize else {
        throw PrivateMediaPreviewError.responseTooLarge
      }
      guard byteSize == descriptor.byteSize else {
        throw PrivateMediaPreviewError.responseSizeMismatch
      }
      let localURL = try ProtectedTemporaryMediaPreview.adoptDownloadedFile(
        temporaryURL,
        fileName: descriptor.fileName,
        temporaryDirectory: temporaryDirectory
      )
      downloadedURL = nil
      do {
        try Task.checkCancellation()
      } catch {
        ProtectedTemporaryMediaPreview.remove(localURL)
        throw error
      }
      return PrivateMediaPreviewDownloadedFile(localURL: localURL, byteSize: byteSize)
    } catch {
      ProtectedTemporaryMediaPreview.remove(downloadedURL)
      if Task.isCancelled || Self.isCancellation(error) {
        throw CancellationError()
      }
      if let error = error as? PrivateMediaPreviewError {
        throw error
      }
      throw PrivateMediaPreviewError.transport
    }
  }

  static func isCancellation(_ error: any Error) -> Bool {
    if error is CancellationError { return true }
    let error = error as NSError
    return error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
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

  static func makeRequest(grant: MediaDownloadGrant) throws -> URLRequest {
    guard grant.expiresAt > Date(), grant.downloadURL.scheme?.lowercased() == "https",
      grant.downloadURL.host?.isEmpty == false,
      grant.downloadURL.user == nil,
      grant.downloadURL.password == nil,
      grant.downloadURL.fragment == nil
    else {
      throw PrivateMediaPreviewError.invalidGrant
    }
    var request = URLRequest(url: grant.downloadURL)
    request.httpMethod = "GET"
    request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    request.httpShouldHandleCookies = false
    request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
    request.setValue(nil, forHTTPHeaderField: "Authorization")
    request.setValue(nil, forHTTPHeaderField: "Cookie")
    return request
  }
}

private final class PrivateMediaRedirectRejectingDelegate: NSObject, URLSessionTaskDelegate,
  @unchecked Sendable
{
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    // A signed media URL is a single-origin credential and must never cross a redirect.
    completionHandler(nil)
  }
}

enum ProtectedTemporaryMediaPreview {
  private static let directoryName = "woorisai-private-preview"

  static func directoryURL(in temporaryDirectory: URL) -> URL {
    temporaryDirectory.appendingPathComponent(directoryName, isDirectory: true)
  }

  /// Removes preview bytes left by a previous process termination. The fixed child directory keeps
  /// launch cleanup scoped away from unrelated temporary files.
  static func purgeStaleFiles(
    fileManager: FileManager = .default,
    temporaryDirectory: URL? = nil
  ) throws {
    let root = temporaryDirectory ?? fileManager.temporaryDirectory
    let directory = directoryURL(in: root)
    guard fileManager.fileExists(atPath: directory.path) else { return }
    try fileManager.removeItem(at: directory)
  }

  static func write(_ data: Data, fileName: String) throws -> URL {
    guard !data.isEmpty else { throw PrivateMediaPreviewError.temporaryFile }
    let fileExtension = safeFileExtension(from: fileName)
    let directory = directoryURL(in: FileManager.default.temporaryDirectory)
    do {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [
          .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ]
      )
      var directoryValues = URLResourceValues()
      directoryValues.isExcludedFromBackup = true
      var mutableDirectory = directory
      try mutableDirectory.setResourceValues(directoryValues)

      let url =
        directory
        .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: false)
        .appendingPathExtension(fileExtension)
      try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      var mutableURL = url
      try mutableURL.setResourceValues(values)
      return url
    } catch {
      throw PrivateMediaPreviewError.temporaryFile
    }
  }

  static func adoptDownloadedFile(
    _ sourceURL: URL,
    fileName: String,
    fileManager: FileManager = .default,
    temporaryDirectory: URL? = nil
  ) throws -> URL {
    guard sourceURL.isFileURL, fileManager.fileExists(atPath: sourceURL.path) else {
      throw PrivateMediaPreviewError.temporaryFile
    }
    let root = temporaryDirectory ?? fileManager.temporaryDirectory
    let directory = directoryURL(in: root)
    let destination =
      directory
      .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: false)
      .appendingPathExtension(safeFileExtension(from: fileName))
    do {
      try fileManager.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [
          .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ]
      )
      var directoryValues = URLResourceValues()
      directoryValues.isExcludedFromBackup = true
      var mutableDirectory = directory
      try mutableDirectory.setResourceValues(directoryValues)

      try fileManager.moveItem(at: sourceURL, to: destination)
      try fileManager.setAttributes(
        [.protectionKey: FileProtectionType.completeUnlessOpen],
        ofItemAtPath: destination.path
      )
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      var mutableDestination = destination
      try mutableDestination.setResourceValues(values)
      return destination
    } catch {
      try? fileManager.removeItem(at: destination)
      throw PrivateMediaPreviewError.temporaryFile
    }
  }

  static func remove(_ url: URL?) {
    guard let url, url.isFileURL else { return }
    try? FileManager.default.removeItem(at: url)
  }

  static func safeFileExtension(from fileName: String) -> String {
    let candidate = URL(fileURLWithPath: fileName).pathExtension.lowercased()
    let allowed = CharacterSet.alphanumerics
    guard !candidate.isEmpty,
      candidate.unicodeScalars.count <= 10,
      candidate.unicodeScalars.allSatisfy(allowed.contains)
    else {
      return "bin"
    }
    return candidate
  }
}

/// Uses the authenticated scene's shared private-media store. Images load only when this view is
/// mounted; videos remain tap-to-load so feed traversal never fetches large files speculatively.
struct MediaAttachmentPreview: View {
  @Environment(\.privateMediaPreviewLoader) private var previewLoader
  @State private var model: PrivateMediaPreviewModel
  @State private var quickLookURL: URL?

  let attachmentID: UUID
  let fileName: String
  let contentType: String
  let byteSize: Int64
  let onAuthenticationRequired: @MainActor () -> Void

  @MainActor
  init(
    attachmentID: UUID,
    fileName: String,
    contentType: String,
    byteSize: Int64,
    onAuthenticationRequired: @escaping @MainActor () -> Void
  ) {
    self.attachmentID = attachmentID
    self.fileName = fileName
    self.contentType = contentType
    self.byteSize = byteSize
    _model = State(
      initialValue: PrivateMediaPreviewModel(
        descriptor: PrivateMediaPreviewDescriptor(
          attachmentID: attachmentID,
          fileName: fileName,
          contentType: contentType,
          byteSize: byteSize
        )
      )
    )
    self.onAuthenticationRequired = onAuthenticationRequired
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button(action: openOrLoad) {
        ZStack {
          previewBackground

          if model.state == .loading {
            ProgressView(isImage ? "사진을 불러오는 중" : "동영상을 준비하는 중")
              .tint(WoorisaiPalette.coralDark)
              .foregroundStyle(WoorisaiPalette.ink)
              .padding()
          }
        }
        .frame(maxWidth: .infinity)
        .frame(height: isImage ? 190 : 132)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(WoorisaiPalette.line, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      }
      .buttonStyle(.plain)
      .disabled(model.state == .loading)
      .accessibilityLabel(previewAccessibilityLabel)
      .accessibilityHint("비공개 파일을 앱 안에서 안전하게 미리 봅니다.")

      if let failureMessage {
        Text(failureMessage)
          .font(.caption)
          .foregroundStyle(WoorisaiPalette.muted)
      }
    }
    .task(id: attachmentID) {
      if isImage, model.localURL == nil, model.state == .idle {
        model.load(using: previewLoader)
      }
    }
    .onChange(of: model.state) { _, state in
      switch state {
      case .loaded:
        if !isImage {
          quickLookURL = model.localURL
        }
      case .authenticationRequired:
        onAuthenticationRequired()
      case .idle, .loading, .notFound, .unavailable, .invalidContent, .failed:
        break
      }
    }
    .quickLookPreview($quickLookURL)
    .onDisappear {
      quickLookURL = nil
      model.clear()
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("media.inline.\(attachmentID.uuidString)")
  }

  @ViewBuilder
  private var previewBackground: some View {
    if let image = model.image {
      MediaAspectFitImageSurface(image: image)
        .overlay(alignment: .bottomTrailing) {
          Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(9)
            .background(.black.opacity(0.46), in: Circle())
            .padding(10)
            .accessibilityHidden(true)
        }
    } else {
      ZStack {
        isImage ? WoorisaiPalette.coralSoft.opacity(0.5) : WoorisaiPalette.sageSoft

        VStack(spacing: 8) {
          Image(systemName: isImage ? "photo.fill" : "play.circle.fill")
            .font(.system(size: isImage ? 34 : 42))
            .foregroundStyle(isImage ? WoorisaiPalette.coral : WoorisaiPalette.sage)
          Text(fileName)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(WoorisaiPalette.muted)
            .lineLimit(1)
            .padding(.horizontal, 14)
        }
      }
    }
  }

  private var isImage: Bool {
    contentType.lowercased().hasPrefix("image/")
  }

  private var previewAccessibilityLabel: String {
    guard model.localURL != nil else { return "첨부 파일 \(fileName) 불러오기" }
    return isImage ? "첨부 사진 \(fileName) 크게 보기" : "첨부 동영상 \(fileName) 열기"
  }

  private var failureMessage: String? {
    switch model.state {
    case .authenticationRequired: return "다시 로그인이 필요해요."
    case .notFound: return "첨부 파일을 찾을 수 없어요."
    case .unavailable: return "첨부 파일을 잠시 열 수 없어요. 눌러서 다시 시도해 주세요."
    case .invalidContent: return "첨부 파일이 손상되었거나 정보가 일치하지 않아요."
    case .failed: return "첨부 파일을 열지 못했어요. 눌러서 다시 시도해 주세요."
    case .idle, .loading, .loaded: return nil
    }
  }

  private func openOrLoad() {
    if let localURL = model.localURL {
      quickLookURL = localURL
    } else {
      model.load(using: previewLoader)
    }
  }
}
