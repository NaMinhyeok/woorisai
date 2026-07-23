import AVFoundation
import Combine
import CoreTransferable
import Foundation
import ImageIO
import Observation
import PhotosUI
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

enum PickerFileTransferError: Error, Equatable, Sendable {
  case unreadableSelection
  case fileTooLarge(kind: MediaKind)
}

enum PickerPreparationError: Error, Equatable, Sendable {
  case unreadableSelection
  case unsupportedType
  case imageConversionFailed
}

private enum BoundedPickerFileMetadata {
  static func byteSize(
    at url: URL,
    maximumByteSize: Int64,
    kind: MediaKind
  ) throws -> Int {
    guard url.isFileURL else {
      throw PickerFileTransferError.unreadableSelection
    }
    let values: URLResourceValues
    do {
      values = try url.resourceValues(
        forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
      )
    } catch {
      throw PickerFileTransferError.unreadableSelection
    }

    guard values.isRegularFile == true,
      values.isSymbolicLink != true,
      let fileSize = values.fileSize,
      fileSize > 0
    else {
      throw PickerFileTransferError.unreadableSelection
    }
    guard Int64(fileSize) <= maximumByteSize else {
      throw PickerFileTransferError.fileTooLarge(kind: kind)
    }
    return fileSize
  }
}

struct BoundedPickerImageTransfer: Transferable, Sendable {
  let data: Data
  let typeIdentifier: String?

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(
      importedContentType: .image,
      shouldAttemptToOpenInPlace: true
    ) { receivedFile in
      try importingFile(at: receivedFile.file)
    }
  }

  static func importingFile(at url: URL) throws -> Self {
    let fileSize = try BoundedPickerFileMetadata.byteSize(
      at: url,
      maximumByteSize: MediaUploadDraft.maximumImageByteSize,
      kind: .image
    )

    do {
      let handle = try FileHandle(forReadingFrom: url)
      defer { try? handle.close() }
      let maximumReadCount = Int(MediaUploadDraft.maximumImageByteSize) + 1
      var data = Data()
      while data.count < maximumReadCount {
        let nextReadCount = min(64 * 1_024, maximumReadCount - data.count)
        guard let chunk = try handle.read(upToCount: nextReadCount), !chunk.isEmpty else {
          break
        }
        data.append(chunk)
      }
      guard Int64(data.count) <= MediaUploadDraft.maximumImageByteSize else {
        throw PickerFileTransferError.fileTooLarge(kind: .image)
      }
      guard !data.isEmpty, data.count == fileSize else {
        throw PickerFileTransferError.unreadableSelection
      }
      let trailingData = try handle.read(upToCount: 1)
      guard trailingData?.isEmpty != false else {
        throw PickerFileTransferError.fileTooLarge(kind: .image)
      }
      let typeIdentifier = try? url.resourceValues(forKeys: [.contentTypeKey])
        .contentType?.identifier
      return Self(data: data, typeIdentifier: typeIdentifier)
    } catch let error as PickerFileTransferError {
      throw error
    } catch {
      throw PickerFileTransferError.unreadableSelection
    }
  }
}

enum ProtectedTemporaryMediaUpload {
  private static let directoryName = "woorisai-private-uploads"

  static func directoryURL(in temporaryDirectory: URL) -> URL {
    temporaryDirectory.appendingPathComponent(directoryName, isDirectory: true)
  }

  static func purgeStaleFiles(
    fileManager: FileManager = .default,
    temporaryDirectory: URL? = nil
  ) throws {
    let root = temporaryDirectory ?? fileManager.temporaryDirectory
    let directory = directoryURL(in: root)
    guard fileManager.fileExists(atPath: directory.path) else { return }
    try fileManager.removeItem(at: directory)
  }
}

struct BoundedPickerVideoTransfer: Transferable, Sendable {
  let file: OwnedTemporaryMediaUploadFile
  let typeIdentifier: String?

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(
      importedContentType: .movie,
      shouldAttemptToOpenInPlace: true
    ) { receivedFile in
      try importingFile(at: receivedFile.file)
    }
  }

  static func importingFile(at url: URL) throws -> Self {
    try importingFile(
      at: url,
      fileManager: .default,
      temporaryDirectory: FileManager.default.temporaryDirectory
    )
  }

  static func importingFile(
    at url: URL,
    fileManager: FileManager,
    temporaryDirectory: URL
  ) throws -> Self {
    guard temporaryDirectory.isFileURL else {
      throw PickerFileTransferError.unreadableSelection
    }
    let fileSize = try BoundedPickerFileMetadata.byteSize(
      at: url,
      maximumByteSize: MediaUploadDraft.maximumVideoByteSize,
      kind: .video
    )
    let typeIdentifier = try? url.resourceValues(forKeys: [.contentTypeKey])
      .contentType?.identifier

    let ownedDirectory = ProtectedTemporaryMediaUpload.directoryURL(in: temporaryDirectory)
    let ownedURL =
      ownedDirectory
      .appendingPathComponent(UUID().uuidString.lowercased())
      .appendingPathExtension("upload")
    do {
      try fileManager.createDirectory(
        at: ownedDirectory,
        withIntermediateDirectories: true,
        attributes: [
          .protectionKey: FileProtectionType.complete,
          .posixPermissions: 0o700,
        ]
      )
      try fileManager.setAttributes(
        [
          .protectionKey: FileProtectionType.complete,
          .posixPermissions: 0o700,
        ],
        ofItemAtPath: ownedDirectory.path
      )
      var directoryValues = URLResourceValues()
      directoryValues.isExcludedFromBackup = true
      var mutableOwnedDirectory = ownedDirectory
      try mutableOwnedDirectory.setResourceValues(directoryValues)
      try fileManager.copyItem(at: url, to: ownedURL)
      try fileManager.setAttributes(
        [
          .protectionKey: FileProtectionType.complete,
          .posixPermissions: 0o600,
        ],
        ofItemAtPath: ownedURL.path
      )
      var ownedValues = URLResourceValues()
      ownedValues.isExcludedFromBackup = true
      var mutableOwnedURL = ownedURL
      try mutableOwnedURL.setResourceValues(ownedValues)

      let copiedValues = try ownedURL.resourceValues(
        forKeys: [.fileSizeKey, .isRegularFileKey]
      )
      guard copiedValues.isRegularFile == true,
        copiedValues.fileSize == fileSize
      else {
        try? fileManager.removeItem(at: ownedURL)
        throw PickerFileTransferError.unreadableSelection
      }

      return Self(
        file: OwnedTemporaryMediaUploadFile(url: ownedURL, byteSize: Int64(fileSize)),
        typeIdentifier: typeIdentifier
      )
    } catch let error as PickerFileTransferError {
      throw error
    } catch {
      try? fileManager.removeItem(at: ownedURL)
      throw PickerFileTransferError.unreadableSelection
    }
  }
}

enum BoundedPickerHEIFConverter {
  static let maximumDecodedPixelSize = 4_096

  static func convertToJPEG(
    _ sourceData: Data,
    maximumPixelSize: Int = maximumDecodedPixelSize,
    maximumByteSize: Int64 = MediaUploadDraft.maximumImageByteSize
  ) -> Data? {
    guard !sourceData.isEmpty,
      Int64(sourceData.count) <= MediaUploadDraft.maximumImageByteSize,
      maximumPixelSize > 0,
      maximumByteSize > 0
    else {
      return nil
    }
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(sourceData as CFData, sourceOptions) else {
      return nil
    }

    let minimumPixelSize = min(1_200, maximumPixelSize)
    var candidatePixelSize = maximumPixelSize
    while candidatePixelSize >= minimumPixelSize {
      let thumbnailOptions =
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: candidatePixelSize,
          kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary
      guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
        return nil
      }

      for quality in [0.9, 0.75, 0.6, 0.45] as [CGFloat] {
        let encoded = NSMutableData()
        guard
          let destination = CGImageDestinationCreateWithData(
            encoded,
            UTType.jpeg.identifier as CFString,
            1,
            nil
          )
        else {
          return nil
        }
        CGImageDestinationAddImage(
          destination,
          image,
          [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        let data = encoded as Data
        if !data.isEmpty, Int64(data.count) <= maximumByteSize {
          return data
        }
      }

      guard candidatePixelSize > minimumPixelSize else { break }
      candidatePixelSize = max(minimumPixelSize, candidatePixelSize * 3 / 4)
    }
    return nil
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
        var preparedKind: MediaKind?
        do {
          let prepared = try await Self.preparePickerItem(pickerItem)
          preparedKind = prepared.kind
          guard !Task.isCancelled, self.importGeneration == generation else { return }
          switch prepared.payload {
          case .data(let data):
            try self.addPreparedAttachment(
              kind: prepared.kind,
              fileName: prepared.fileName,
              contentType: prepared.contentType,
              data: data,
              previewImage: prepared.previewCGImage.map(UIImage.init(cgImage:))
            )
          case .file(let file):
            try self.addPreparedAttachment(
              kind: prepared.kind,
              fileName: prepared.fileName,
              contentType: prepared.contentType,
              file: file
            )
          }
        } catch is CancellationError {
          return
        } catch {
          self.importFailure = Self.mapImportFailure(error, kind: preparedKind)
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
      upload.start(selection)
    } catch {
      importFailure = Self.mapImportFailure(error, kind: kind)
      throw error
    }
  }

  private func addPreparedAttachment(
    kind: MediaKind,
    fileName: String,
    contentType: String,
    file: OwnedTemporaryMediaUploadFile
  ) throws {
    do {
      try policy.validate(existingKinds: allKinds, adding: kind)
    } catch let violation as MediaAttachmentRuleViolation {
      importFailure = .rule(violation)
      file.removeIfNeeded()
      throw violation
    }

    do {
      let draft = try MediaUploadDraft(
        purpose: policy.purpose,
        kind: kind,
        fileName: fileName,
        contentType: contentType,
        byteSize: file.byteSize
      )
      let selection = try MediaUploadSelection(draft: draft, file: file)
      let upload = MediaUploadModel(service: service, uploader: uploader)
      uploads.append(
        UploadItem(
          id: UUID(),
          kind: kind,
          fileName: draft.fileName,
          byteSize: draft.byteSize,
          previewImage: nil,
          upload: upload
        )
      )
      upload.start(selection)
    } catch {
      file.removeIfNeeded()
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
    guard !submittedReadyUploadIDs.isEmpty else { return [] }
    var completed: [CompletedMediaUpload] = []
    uploads.removeAll { item in
      guard let uploadID = item.upload.readyUpload?.id,
        submittedReadyUploadIDs.contains(uploadID)
      else { return false }
      if let upload = item.upload.consumeReadyUpload() {
        completed.append(upload)
      }
      return true
    }
    submittedReadyUploadIDs.removeAll()
    if uploads.isEmpty { importFailure = nil }
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
    enum Payload: Sendable {
      case data(Data)
      case file(OwnedTemporaryMediaUploadFile)
    }

    let kind: MediaKind
    let fileName: String
    let contentType: String
    let payload: Payload
    let previewCGImage: CGImage?
  }

  private var allKinds: [MediaKind] {
    existingKinds + uploads.map(\.kind)
  }

  private static func preparePickerItem(_ item: PhotosPickerItem) async throws
    -> PreparedPickerItem
  {
    let supportedTypes = item.supportedContentTypes

    if let advertisedType = supportedTypes.first(where: isSupportedPickerImageType) {
      let transfer = try await loadBoundedImage(from: item)
      let type = try resolvedPickerType(
        actualIdentifier: transfer.typeIdentifier,
        advertisedType: advertisedType,
        isAllowed: isSupportedPickerImageType
      )

      if isHEIFType(type) {
        guard let converted = await convertHEIFToJPEG(transfer.data) else {
          throw PickerPreparationError.imageConversionFailed
        }
        return PreparedPickerItem(
          kind: .image,
          fileName: generatedFileName(kind: .image, type: .jpeg, contentType: "image/jpeg"),
          contentType: "image/jpeg",
          payload: .data(converted.data),
          previewCGImage: converted.previewCGImage
        )
      }

      guard let contentType = type.preferredMIMEType?.lowercased(),
        allowedImageMIMETypes.contains(contentType)
      else {
        throw PickerPreparationError.unsupportedType
      }
      return PreparedPickerItem(
        kind: .image,
        fileName: generatedFileName(kind: .image, type: type, contentType: contentType),
        contentType: contentType,
        payload: .data(transfer.data),
        previewCGImage: await thumbnailCGImage(from: transfer.data)
      )
    }

    if let advertisedType = supportedTypes.first(where: {
      guard let contentType = $0.preferredMIMEType?.lowercased() else { return false }
      return allowedVideoMIMETypes.contains(contentType)
    }) {
      let transfer = try await loadBoundedVideo(from: item)
      let type = try resolvedPickerType(
        actualIdentifier: transfer.typeIdentifier,
        advertisedType: advertisedType,
        isAllowed: isSupportedPickerVideoType
      )
      guard let contentType = type.preferredMIMEType?.lowercased() else {
        throw PickerPreparationError.unsupportedType
      }
      return PreparedPickerItem(
        kind: .video,
        fileName: generatedFileName(kind: .video, type: type, contentType: contentType),
        contentType: contentType,
        payload: .file(transfer.file),
        previewCGImage: nil
      )
    }

    throw PickerPreparationError.unsupportedType
  }

  private static func thumbnailCGImage(from data: Data) async -> CGImage? {
    await Task.detached(priority: .userInitiated) {
      MediaImagePreview.thumbnailCGImage(from: data)
    }.value
  }

  private static func convertHEIFToJPEG(_ sourceData: Data) async
    -> (data: Data, previewCGImage: CGImage?)?
  {
    await Task.detached(priority: .userInitiated) {
      guard let jpegData = BoundedPickerHEIFConverter.convertToJPEG(sourceData) else { return nil }
      return (
        data: jpegData,
        previewCGImage: MediaImagePreview.thumbnailCGImage(from: jpegData)
      )
    }.value
  }

  private static func loadBoundedImage(from item: PhotosPickerItem) async throws
    -> BoundedPickerImageTransfer
  {
    do {
      guard let transfer = try await item.loadTransferable(type: BoundedPickerImageTransfer.self)
      else {
        throw PickerFileTransferError.unreadableSelection
      }
      return transfer
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as PickerFileTransferError {
      throw error
    } catch {
      throw PickerFileTransferError.unreadableSelection
    }
  }

  private static func loadBoundedVideo(from item: PhotosPickerItem) async throws
    -> BoundedPickerVideoTransfer
  {
    do {
      guard let transfer = try await item.loadTransferable(type: BoundedPickerVideoTransfer.self)
      else {
        throw PickerFileTransferError.unreadableSelection
      }
      return transfer
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as PickerFileTransferError {
      throw error
    } catch {
      throw PickerFileTransferError.unreadableSelection
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

  private static func isSupportedPickerImageType(_ type: UTType) -> Bool {
    if isHEIFType(type) { return true }
    guard let contentType = type.preferredMIMEType?.lowercased() else { return false }
    return allowedImageMIMETypes.contains(contentType)
  }

  private static func isSupportedPickerVideoType(_ type: UTType) -> Bool {
    guard let contentType = type.preferredMIMEType?.lowercased() else { return false }
    return allowedVideoMIMETypes.contains(contentType)
  }

  static func resolvedPickerType(
    actualIdentifier: String?,
    advertisedType: UTType,
    isAllowed: (UTType) -> Bool
  ) throws -> UTType {
    guard let actualIdentifier else { return advertisedType }
    guard let actualType = UTType(actualIdentifier), isAllowed(actualType) else {
      throw PickerPreparationError.unsupportedType
    }
    return actualType
  }

  static func generatedFileName(
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

  static func mapImportFailure(
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
    if let transferError = error as? PickerFileTransferError {
      switch transferError {
      case .unreadableSelection: return .unreadableSelection
      case .fileTooLarge(let kind): return .fileTooLarge(kind: kind)
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
  private var transientComposers: [ObjectIdentifier: MediaAttachmentComposerModel] = [:]

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

  func registerTransient(_ composer: MediaAttachmentComposerModel) {
    transientComposers[ObjectIdentifier(composer)] = composer
  }

  func unregisterTransient(_ composer: MediaAttachmentComposerModel) {
    transientComposers.removeValue(forKey: ObjectIdentifier(composer))
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
    let sessionComposers =
      [relationshipScoreComposer, diaryEntryComposer] + Array(transientComposers.values)
    let discardTasks = sessionComposers.flatMap { $0.clearForCredentialRemoval() }
    transientComposers.removeAll()
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
            .frame(minHeight: WoorisaiControlMetric.minimumTapTarget)
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
          .frame(
            minWidth: WoorisaiControlMetric.minimumTapTarget,
            minHeight: WoorisaiControlMetric.minimumTapTarget
          )
          .accessibilityLabel("첨부 오류 닫기")
        }
        .accessibilityIdentifier("media.importError")
      }

      if !model.uploads.isEmpty {
        MediaAttachmentGallery(items: model.uploads, kind: \.kind) { item, _ in
          uploadTile(item)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("media.group")

        ForEach(model.uploads) { item in
          uploadDetails(item)
        }
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

  private func uploadTile(_ item: MediaAttachmentComposerModel.UploadItem) -> some View {
    MediaTileSurface {
      ZStack {
        if let previewImage = item.previewImage {
          MediaFillImageSurface(image: previewImage)
        } else {
          WoorisaiPalette.sageSoft
          VStack(spacing: WoorisaiSpacing.small) {
            Image(systemName: item.kind == .video ? "play.circle.fill" : "photo.fill")
              .font(.system(size: 36))
              .foregroundStyle(item.kind == .video ? WoorisaiPalette.sage : WoorisaiPalette.coral)
            Text(item.kind == .video ? "동영상" : "사진")
              .font(.caption.weight(.semibold))
              .foregroundStyle(WoorisaiPalette.muted)
          }
        }

        uploadTileStatus(item)
      }
      .overlay(alignment: .topTrailing) {
        Button {
          model.remove(item.id)
        } label: {
          Image(systemName: "xmark")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(
              width: WoorisaiControlMetric.minimumTapTarget,
              height: WoorisaiControlMetric.minimumTapTarget
            )
            .background(.black.opacity(0.54), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(WoorisaiSpacing.xSmall)
        .accessibilityLabel("\(item.fileName) 첨부 제거")
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(
      item.kind == .image ? "선택한 사진 \(item.fileName)" : "선택한 동영상 \(item.fileName)"
    )
    .accessibilityIdentifier("media.tile.\(item.id.uuidString)")
  }

  private func uploadDetails(_ item: MediaAttachmentComposerModel.UploadItem) -> some View {
    VStack(alignment: .leading, spacing: WoorisaiSpacing.small) {
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
          .frame(
            minWidth: WoorisaiControlMetric.minimumTapTarget,
            minHeight: WoorisaiControlMetric.minimumTapTarget
          )
          .accessibilityLabel("\(item.fileName) 업로드 재시도")
        } else if item.upload.state.isActiveUpload {
          Button("취소", role: .cancel) {
            model.cancel(item.id)
          }
          .frame(
            minWidth: WoorisaiControlMetric.minimumTapTarget,
            minHeight: WoorisaiControlMetric.minimumTapTarget
          )
          .accessibilityLabel("\(item.fileName) 업로드 취소")
        }

        Spacer(minLength: 0)
      }
      .font(.footnote)
    }
    .padding(WoorisaiSpacing.medium)
    .background(
      WoorisaiPalette.creamDeep.opacity(0.72),
      in: RoundedRectangle(cornerRadius: WoorisaiRadius.small, style: .continuous)
    )
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("media.upload.\(item.id.uuidString)")
  }

  @ViewBuilder
  private func uploadTileStatus(_ item: MediaAttachmentComposerModel.UploadItem) -> some View {
    switch item.upload.state {
    case .idle, .initiating, .uploading, .completing:
      ProgressView()
        .tint(.white)
        .padding(WoorisaiSpacing.medium)
        .background(.black.opacity(0.44), in: Circle())
        .accessibilityHidden(true)
    case .ready:
      Image(systemName: "checkmark.circle.fill")
        .font(.title2)
        .foregroundStyle(.white, WoorisaiPalette.success)
        .padding(WoorisaiSpacing.small)
        .background(.black.opacity(0.36), in: Circle())
        .accessibilityHidden(true)
    case .failed:
      Image(systemName: "exclamationmark.circle.fill")
        .font(.title2)
        .foregroundStyle(.white, WoorisaiPalette.error)
        .padding(WoorisaiSpacing.small)
        .background(.black.opacity(0.36), in: Circle())
        .accessibilityHidden(true)
    case .cancelled:
      Image(systemName: "xmark.circle.fill")
        .font(.title2)
        .foregroundStyle(.white)
        .padding(WoorisaiSpacing.small)
        .background(.black.opacity(0.44), in: Circle())
        .accessibilityHidden(true)
    }
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

/// Keeps the complete image visible in the full-screen viewer. Inline tiles intentionally crop to
/// their shared geometry; this surface is the place where portrait and panorama originals remain
/// fully visible.
struct MediaAspectFitImageSurface: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let image: UIImage
  let accessibilityName: String
  @State private var scale: CGFloat = 1
  @State private var committedScale: CGFloat = 1
  @State private var offset: CGSize = .zero
  @State private var committedOffset: CGSize = .zero
  @State private var fittedImageSize: CGSize = .zero
  @State private var viewerSize: CGSize = .zero

  init(image: UIImage, accessibilityName: String = "전체 사진") {
    self.image = image
    self.accessibilityName = accessibilityName
  }

  var body: some View {
    GeometryReader { proxy in
      let imageSize = Self.fittedSize(
        imageSize: image.size,
        containerSize: proxy.size
      )
      let viewerFrame = proxy.frame(in: .global)
      let accessibilityFrame = Self.accessibilityFrame(
        fittedImageSize: imageSize,
        containerFrame: viewerFrame,
        scale: scale,
        offset: offset
      )

      ZStack {
        WoorisaiPalette.creamDeep.opacity(0.58)

        Image(uiImage: image)
          .resizable()
          .frame(width: imageSize.width, height: imageSize.height)
          .scaleEffect(scale)
          .offset(offset)
          .accessibilityHidden(true)

        Rectangle()
          .fill(.clear)
          .frame(width: accessibilityFrame.width, height: accessibilityFrame.height)
          .position(
            x: accessibilityFrame.midX - viewerFrame.minX,
            y: accessibilityFrame.midY - viewerFrame.minY
          )
          .allowsHitTesting(false)
          .accessibilityElement()
          .accessibilityLabel(accessibilityName)
          .accessibilityValue("확대 \(Int((scale * 100).rounded()))퍼센트")
          .accessibilityHint("두 번 탭하거나 위아래로 조절해 확대할 수 있어요.")
          .accessibilityAdjustableAction { direction in
            adjustZoom(direction)
          }
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
      .clipped()
      .contentShape(Rectangle())
      .onAppear {
        fittedImageSize = imageSize
        viewerSize = proxy.size
      }
      .onChange(of: proxy.size) { _, size in
        let fittedSize = Self.fittedSize(imageSize: image.size, containerSize: size)
        fittedImageSize = fittedSize
        viewerSize = size
        offset = Self.clampedOffset(
          offset,
          imageSize: fittedSize,
          containerSize: size,
          scale: scale
        )
        committedOffset = offset
      }
      .gesture(magnifyGesture(imageSize: imageSize, containerSize: proxy.size))
      .simultaneousGesture(dragGesture(imageSize: imageSize, containerSize: proxy.size))
      .onTapGesture(count: 2) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
          if scale > 1 {
            resetZoom()
          } else {
            scale = 2.5
            committedScale = 2.5
          }
        }
      }
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

  static func accessibilityFrame(
    fittedImageSize: CGSize,
    containerFrame: CGRect,
    scale: CGFloat,
    offset: CGSize
  ) -> CGRect {
    guard fittedImageSize.width.isFinite, fittedImageSize.height.isFinite,
      containerFrame.origin.x.isFinite, containerFrame.origin.y.isFinite,
      containerFrame.width.isFinite, containerFrame.height.isFinite,
      scale.isFinite, offset.width.isFinite, offset.height.isFinite,
      fittedImageSize.width > 0, fittedImageSize.height > 0,
      containerFrame.width > 0, containerFrame.height > 0,
      scale > 0
    else {
      return .zero
    }

    let scaledSize = CGSize(
      width: fittedImageSize.width * scale,
      height: fittedImageSize.height * scale
    )
    let transformedFrame = CGRect(
      x: containerFrame.midX - scaledSize.width / 2 + offset.width,
      y: containerFrame.midY - scaledSize.height / 2 + offset.height,
      width: scaledSize.width,
      height: scaledSize.height
    )
    return transformedFrame.intersection(containerFrame)
  }

  private func magnifyGesture(
    imageSize: CGSize,
    containerSize: CGSize
  ) -> some Gesture {
    MagnifyGesture()
      .onChanged { value in
        scale = min(5, max(1, committedScale * value.magnification))
        offset = Self.clampedOffset(
          offset,
          imageSize: imageSize,
          containerSize: containerSize,
          scale: scale
        )
      }
      .onEnded { _ in
        committedScale = scale
        if scale == 1 {
          offset = .zero
        }
        committedOffset = offset
      }
  }

  private func dragGesture(
    imageSize: CGSize,
    containerSize: CGSize
  ) -> some Gesture {
    DragGesture(minimumDistance: 4)
      .onChanged { value in
        guard scale > 1 else { return }
        let candidate = CGSize(
          width: committedOffset.width + value.translation.width,
          height: committedOffset.height + value.translation.height
        )
        offset = Self.clampedOffset(
          candidate,
          imageSize: imageSize,
          containerSize: containerSize,
          scale: scale
        )
      }
      .onEnded { _ in
        committedOffset = offset
      }
  }

  private func resetZoom() {
    scale = 1
    committedScale = 1
    offset = .zero
    committedOffset = .zero
  }

  private func adjustZoom(_ direction: AccessibilityAdjustmentDirection) {
    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
      switch direction {
      case .increment:
        scale = min(5, scale + 0.5)
      case .decrement:
        scale = max(1, scale - 0.5)
      @unknown default:
        return
      }
      committedScale = scale
      offset = Self.clampedOffset(
        offset,
        imageSize: fittedImageSize,
        containerSize: viewerSize,
        scale: scale
      )
      if scale == 1 {
        offset = .zero
      }
      committedOffset = offset
    }
  }

  static func clampedOffset(
    _ offset: CGSize,
    imageSize: CGSize,
    containerSize: CGSize,
    scale: CGFloat
  ) -> CGSize {
    let maximumX = max(0, (imageSize.width * scale - containerSize.width) / 2)
    let maximumY = max(0, (imageSize.height * scale - containerSize.height) / 2)
    return CGSize(
      width: min(maximumX, max(-maximumX, offset.width)),
      height: min(maximumY, max(-maximumY, offset.height))
    )
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
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var model: PrivateMediaPreviewModel
  @State private var isImageViewerPresented = false
  @State private var isVideoViewerPresented = false
  @State private var opensImageViewerAfterLoading = false
  @State private var shouldReloadVideoAfterDismiss = false
  @State private var isMounted = false

  let attachmentID: UUID
  let fileName: String
  let contentType: String
  let byteSize: Int64
  let tileFormat: MediaInlineTileFormat
  let onAuthenticationRequired: @MainActor () -> Void

  @MainActor
  init(
    attachmentID: UUID,
    fileName: String,
    contentType: String,
    byteSize: Int64,
    tileFormat: MediaInlineTileFormat? = nil,
    onAuthenticationRequired: @escaping @MainActor () -> Void
  ) {
    self.attachmentID = attachmentID
    self.fileName = fileName
    self.contentType = contentType
    self.byteSize = byteSize
    self.tileFormat =
      tileFormat
      ?? (contentType.lowercased().hasPrefix("image/") ? .singleImage : .video)
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
    Button(action: openOrLoad) {
      MediaTileSurface {
        ZStack {
          previewBackground

          if model.state == .loading {
            ProgressView()
              .tint(WoorisaiPalette.coralDark)
              .padding(WoorisaiSpacing.small)
              .background(.ultraThinMaterial, in: Circle())
              .accessibilityHidden(true)
          }

          if failureMessage != nil {
            VStack {
              Spacer(minLength: 0)
              HStack(spacing: WoorisaiSpacing.xSmall) {
                Image(systemName: "exclamationmark.triangle.fill")
                if !dynamicTypeSize.isAccessibilitySize {
                  Text("다시 시도")
                }
              }
              .font(.caption.weight(.semibold))
              .foregroundStyle(WoorisaiPalette.ink)
              .frame(maxWidth: .infinity, alignment: .center)
              .padding(WoorisaiSpacing.small)
              .background(.regularMaterial)
              .lineLimit(1)
              .accessibilityHidden(true)
            }
          }
        }
      }
      .aspectRatio(tileFormat.aspectRatio, contentMode: .fit)
      .accessibilityIdentifier("media.tile.\(attachmentID.uuidString).surface")
    }
    .buttonStyle(.plain)
    .disabled(model.state == .loading && !isImage)
    .accessibilityLabel(previewAccessibilityLabel)
    .accessibilityValue(previewAccessibilityValue)
    .accessibilityHint("비공개 파일을 앱 안에서 안전하게 미리 봅니다.")
    .accessibilityIdentifier("media.inline.\(attachmentID.uuidString)")
    .task(id: attachmentID) {
      if isImage, model.localURL == nil, model.state == .idle {
        model.load(using: previewLoader)
      }
    }
    .onChange(of: model.state) { _, state in
      switch state {
      case .loaded:
        if isImage, opensImageViewerAfterLoading, model.localURL != nil {
          opensImageViewerAfterLoading = false
          isImageViewerPresented = true
        } else if !isImage {
          isVideoViewerPresented = model.localURL != nil
        }
      case .authenticationRequired:
        opensImageViewerAfterLoading = false
        onAuthenticationRequired()
      case .idle, .notFound, .unavailable, .invalidContent, .failed:
        opensImageViewerAfterLoading = false
      case .loading:
        break
      }
    }
    .fullScreenCover(isPresented: $isImageViewerPresented) {
      ZStack {
        Color.black.ignoresSafeArea()

        if let image = model.image {
          MediaAspectFitImageSurface(
            image: image,
            accessibilityName: "첨부 사진 \(fileName) 전체 보기"
          )
          .padding(.vertical, WoorisaiSpacing.xLarge)
          .accessibilityIdentifier("media.viewer")
        }
      }
      .overlay(alignment: .topTrailing) {
        Button {
          isImageViewerPresented = false
        } label: {
          Image(systemName: "xmark")
            .font(.body.weight(.bold))
            .foregroundStyle(.white)
            .frame(
              width: WoorisaiControlMetric.minimumTapTarget,
              height: WoorisaiControlMetric.minimumTapTarget
            )
            .background(.black.opacity(0.62), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(WoorisaiSpacing.regular)
        .accessibilityLabel("사진 전체 보기 닫기")
        .accessibilityIdentifier("media.viewer.close")
      }
    }
    .fullScreenCover(
      isPresented: $isVideoViewerPresented,
      onDismiss: {
        guard shouldReloadVideoAfterDismiss, isMounted else {
          shouldReloadVideoAfterDismiss = false
          return
        }
        shouldReloadVideoAfterDismiss = false
        model.reloadDiscardingCurrentLease(using: previewLoader)
      }
    ) {
      if let localURL = model.localURL {
        PrivateVideoViewer(
          url: localURL,
          fileName: fileName,
          onRetry: {
            shouldReloadVideoAfterDismiss = true
            isVideoViewerPresented = false
          },
          onClose: {
            isVideoViewerPresented = false
          }
        )
      }
    }
    .onAppear {
      isMounted = true
    }
    .onDisappear {
      isMounted = false
      opensImageViewerAfterLoading = false
      shouldReloadVideoAfterDismiss = false
      isImageViewerPresented = false
      isVideoViewerPresented = false
      model.clear()
    }
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private var previewBackground: some View {
    if let image = model.image {
      MediaFillImageSurface(image: image)
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

  private var previewAccessibilityValue: String {
    if model.state == .loading {
      return isImage ? "사진을 불러오는 중" : "동영상을 준비하는 중"
    }
    return failureMessage ?? ""
  }

  private func openOrLoad() {
    if model.localURL != nil {
      if isImage {
        isImageViewerPresented = true
      } else {
        isVideoViewerPresented = true
      }
    } else if isImage {
      opensImageViewerAfterLoading = true
      if model.state != .loading {
        model.load(using: previewLoader)
      }
    } else {
      model.load(using: previewLoader)
    }
  }
}

@MainActor
private struct PrivateVideoViewer: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var player: AVPlayer
  @State private var currentSeconds = 0.0
  @State private var durationSeconds = 0.0
  @State private var isPlaying = false
  @State private var hasReachedEnd = false
  @State private var playbackFailureMessage: String?

  let fileName: String
  let onRetry: () -> Void
  let onClose: () -> Void

  init(
    url: URL,
    fileName: String,
    onRetry: @escaping () -> Void,
    onClose: @escaping () -> Void
  ) {
    _player = State(initialValue: AVPlayer(url: url))
    self.fileName = fileName
    self.onRetry = onRetry
    self.onClose = onClose
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      PrivateVideoSurface(player: player)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("첨부 동영상 \(fileName) 전체 보기")
        .accessibilityIdentifier("media.videoViewer.player")
    }
    .overlay(alignment: .bottom) {
      Group {
        if let playbackFailureMessage {
          VStack(alignment: .leading, spacing: WoorisaiSpacing.small) {
            Label("동영상을 재생할 수 없어요", systemImage: "exclamationmark.triangle.fill")
              .font(.headline)
              .foregroundStyle(.white)

            Text(playbackFailureMessage)
              .font(.subheadline)
              .foregroundStyle(.white.opacity(0.88))

            Button(action: onRetry) {
              Label("파일 다시 받기", systemImage: "arrow.clockwise")
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: WoorisaiControlMetric.minimumTapTarget)
            }
            .buttonStyle(.borderedProminent)
            .tint(WoorisaiPalette.coralDark)
            .foregroundStyle(.white)
            .accessibilityIdentifier("media.videoViewer.retry")
          }
          .accessibilityElement(children: .contain)
          .accessibilityIdentifier("media.videoViewer.failure")
        } else {
          VStack(spacing: WoorisaiSpacing.small) {
            ProgressView(value: progressFraction)
              .tint(WoorisaiPalette.coral)
              .accessibilityLabel("동영상 재생 진행")
              .accessibilityValue(progressAccessibilityValue)
              .accessibilityIdentifier("media.videoViewer.progress")

            HStack(spacing: WoorisaiSpacing.regular) {
              Text("\(timeLabel(currentSeconds)) / \(timeLabel(durationSeconds))")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
                .accessibilityHidden(true)

              Spacer(minLength: 0)

              Button(action: togglePlayback) {
                Label(
                  isPlaying ? "일시 정지" : "재생",
                  systemImage: isPlaying ? "pause.fill" : "play.fill"
                )
                .font(.subheadline.weight(.bold))
                .frame(minHeight: WoorisaiControlMetric.minimumTapTarget)
              }
              .buttonStyle(.borderedProminent)
              .tint(WoorisaiPalette.coralDark)
              .foregroundStyle(.white)
              .accessibilityLabel(isPlaying ? "동영상 일시 정지" : "동영상 재생")
              .accessibilityIdentifier("media.videoViewer.playPause")
            }
          }
        }
      }
      .padding(WoorisaiSpacing.regular)
      .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 20))
      .padding(WoorisaiSpacing.regular)
    }
    .overlay(alignment: .topTrailing) {
      Button(action: onClose) {
        Image(systemName: "xmark")
          .font(.body.weight(.bold))
          .foregroundStyle(.white)
          .frame(
            width: WoorisaiControlMetric.minimumTapTarget,
            height: WoorisaiControlMetric.minimumTapTarget
          )
          .background(.black.opacity(0.62), in: Circle())
      }
      .buttonStyle(.plain)
      .padding(WoorisaiSpacing.regular)
      .accessibilityLabel("동영상 전체 보기 닫기")
      .accessibilityIdentifier("media.videoViewer.close")
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("media.videoViewer")
    .task {
      await loadDuration()
    }
    .task(id: isPlaying) {
      guard isPlaying else { return }
      while !Task.isCancelled, isPlaying {
        do {
          try await Task.sleep(for: .milliseconds(100))
        } catch {
          return
        }
        guard !Task.isCancelled else { return }
        refreshPlaybackState()
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: .AVPlayerItemDidPlayToEndTime,
        object: player.currentItem
      )
      .receive(on: DispatchQueue.main)
    ) { _ in
      hasReachedEnd = true
      isPlaying = false
      if durationSeconds > 0 {
        currentSeconds = durationSeconds
      }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase != .active {
        pausePlayback()
      }
    }
    .onDisappear {
      player.pause()
      player.replaceCurrentItem(with: nil)
    }
  }

  private func togglePlayback() {
    if isPlaying {
      pausePlayback()
      return
    }

    if hasReachedEnd {
      player.seek(to: .zero)
      currentSeconds = 0
      hasReachedEnd = false
    }
    player.play()
    isPlaying = true
  }

  private func pausePlayback() {
    player.pause()
    refreshPlaybackState()
    if isPlaying {
      isPlaying = false
    }
  }

  private func refreshPlaybackState() {
    guard let item = player.currentItem else {
      isPlaying = false
      return
    }
    if item.status == .failed {
      markPlaybackFailure()
      return
    }

    let current = player.currentTime().seconds
    if current.isFinite, abs(currentSeconds - current) > 0.001 {
      currentSeconds = max(0, current)
    }

    let duration = item.duration.seconds
    if duration.isFinite, duration > 0, abs(durationSeconds - duration) > 0.001 {
      durationSeconds = duration
    }

  }

  private func loadDuration() async {
    guard let item = player.currentItem else { return }
    do {
      let duration = try await item.asset.load(.duration).seconds
      guard !Task.isCancelled, player.currentItem === item else { return }
      if duration.isFinite, duration > 0, abs(durationSeconds - duration) > 0.001 {
        durationSeconds = duration
      }
      refreshPlaybackState()
    } catch {
      guard !Task.isCancelled, player.currentItem === item else { return }
      refreshPlaybackState()
    }
  }

  private func markPlaybackFailure() {
    player.pause()
    if isPlaying {
      isPlaying = false
    }
    playbackFailureMessage = "파일을 다시 받아 보거나 전체 보기를 닫아 주세요."
  }

  private var progressFraction: Double {
    guard durationSeconds > 0 else { return 0 }
    return min(1, max(0, currentSeconds / durationSeconds))
  }

  private var progressAccessibilityValue: String {
    let current = spokenTimeLabel(currentSeconds)
    guard durationSeconds > 0 else {
      return "현재 \(current), 전체 길이 확인 중"
    }
    return "현재 \(current), 전체 \(spokenTimeLabel(durationSeconds))"
  }

  private func timeLabel(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    if seconds < 1 {
      return String(format: "%.1f초", seconds)
    }
    let rounded = Int(seconds.rounded(.down))
    return String(format: "%d:%02d", rounded / 60, rounded % 60)
  }

  private func spokenTimeLabel(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0초" }
    if seconds < 1 {
      return String(format: "%.1f초", seconds)
    }
    let rounded = Int(seconds.rounded(.down))
    guard rounded >= 60 else { return "\(rounded)초" }
    return "\(rounded / 60)분 \(rounded % 60)초"
  }
}

@MainActor
private final class PrivateVideoSurfaceView: UIView {
  override class var layerClass: AnyClass {
    AVPlayerLayer.self
  }

  var playerLayer: AVPlayerLayer {
    layer as! AVPlayerLayer
  }
}

@MainActor
private struct PrivateVideoSurface: UIViewRepresentable {
  let player: AVPlayer

  func makeUIView(context: Context) -> PrivateVideoSurfaceView {
    let view = PrivateVideoSurfaceView()
    view.backgroundColor = .black
    view.playerLayer.videoGravity = .resizeAspect
    view.playerLayer.player = player
    return view
  }

  func updateUIView(_ view: PrivateVideoSurfaceView, context: Context) {
    if view.playerLayer.player !== player {
      view.playerLayer.player = player
    }
  }

  static func dismantleUIView(_ view: PrivateVideoSurfaceView, coordinator: Void) {
    view.playerLayer.player = nil
  }
}
