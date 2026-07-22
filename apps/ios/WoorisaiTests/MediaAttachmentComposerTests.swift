import Foundation
import ImageIO
import SwiftUI
import Testing
import UIKit
import UniformTypeIdentifiers
import WoorisaiAPI

@testable import Woorisai

@MainActor
struct MediaAttachmentComposerTests {
  @Test
  func scoreChangeAcceptsOneImageAndRejectsVideoOrSecondImage() throws {
    let policy = MediaAttachmentPolicy(purpose: .scoreChange)

    try policy.validate(existingKinds: [], adding: .image)
    #expect(policy.remainingSelectionCapacity(for: []) == 1)
    #expect(policy.remainingSelectionCapacity(for: [.image]) == 0)
    #expect(
      throws: MediaAttachmentRuleViolation.videoNotAllowed,
      performing: { try policy.validate(existingKinds: [], adding: .video) }
    )
    #expect(
      throws: MediaAttachmentRuleViolation.tooManyImages(maximum: 1),
      performing: { try policy.validate(existingKinds: [.image], adding: .image) }
    )
  }

  @Test
  func diaryAndCommentAcceptFourImagesOrExactlyOneVideoWithoutMixing() throws {
    for purpose in [MediaPurpose.diaryEntry, .comment] {
      let policy = MediaAttachmentPolicy(purpose: purpose)

      try policy.validate(existingKinds: [], adding: .video)
      #expect(policy.remainingSelectionCapacity(for: [.video]) == 0)
      #expect(
        throws: MediaAttachmentRuleViolation.onlyOneVideoAllowed,
        performing: { try policy.validate(existingKinds: [.video], adding: .video) }
      )
      #expect(
        throws: MediaAttachmentRuleViolation.mixedMediaNotAllowed,
        performing: { try policy.validate(existingKinds: [.video], adding: .image) }
      )
      #expect(
        throws: MediaAttachmentRuleViolation.mixedMediaNotAllowed,
        performing: { try policy.validate(existingKinds: [.image], adding: .video) }
      )

      try policy.validate(existingKinds: [.image, .image, .image], adding: .image)
      #expect(policy.remainingSelectionCapacity(for: [.image, .image, .image]) == 1)
      #expect(
        throws: MediaAttachmentRuleViolation.tooManyImages(maximum: 4),
        performing: {
          try policy.validate(
            existingKinds: [.image, .image, .image, .image],
            adding: .image
          )
        }
      )
    }
  }

  @Test
  func emptyComposerIsReadyAndAnActiveUploadBlocksSubmissionUntilComplete() async throws {
    let service = ComposerMediaServiceFake()
    let uploader = ComposerSuspendedUploader()
    let model = MediaAttachmentComposerModel(
      purpose: .diaryEntry,
      service: service,
      uploader: uploader
    )

    #expect(model.isReadyForSubmission)
    #expect(model.readyUploadIDs.isEmpty)
    #expect(!model.hasAuthenticationFailure)

    try model.addPreparedAttachment(
      kind: .image,
      fileName: "memory.png",
      contentType: "image/png",
      data: Data([0x89, 0x50, 0x4E, 0x47])
    )
    await composerExpectEventually { await uploader.hasStarted }

    #expect(!model.isReadyForSubmission)
    #expect(model.readyUploadIDs.isEmpty)
    model.clear()
  }

  @Test
  func preparedImageKeepsAnInMemoryThumbnailForTheComposer() throws {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
      UIColor.systemPink.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    }
    let data = try #require(image.pngData())
    let model = MediaAttachmentComposerModel(
      purpose: .scoreChange,
      service: ComposerMediaServiceFake(),
      uploader: ComposerSuspendedUploader()
    )

    try model.addPreparedAttachment(
      kind: .image,
      fileName: "preview.png",
      contentType: "image/png",
      data: data
    )

    #expect(model.uploads.first?.previewImage != nil)
    model.clear()
  }

  @Test
  func preparedImageThumbnailHasBoundedDecodedPixelDimensions() throws {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 1_600, height: 900)).image { context in
      UIColor.systemPink.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 1_600, height: 900))
    }
    let data = try #require(image.jpegData(compressionQuality: 0.9))

    let thumbnail = try #require(MediaImagePreview.thumbnail(from: data))
    let cgImage = try #require(thumbnail.cgImage)

    #expect(cgImage.width <= MediaImagePreview.maximumPixelSize)
    #expect(cgImage.height <= MediaImagePreview.maximumPixelSize)
    #expect(cgImage.width == MediaImagePreview.maximumPixelSize)
  }

  @Test
  func aspectFitSurfaceKeepsPortraitInsideFixedFrame() {
    let image = syntheticImage(size: CGSize(width: 800, height: 1_200))

    let fittedSize = MediaAspectFitImageSurface.fittedSize(
      imageSize: image.size,
      containerSize: CGSize(width: 320, height: 180)
    )

    #expect(fittedSize == CGSize(width: 120, height: 180))
  }

  @Test
  func aspectFitSurfaceKeepsLandscapeInsideFixedFrame() {
    let image = syntheticImage(size: CGSize(width: 1_200, height: 800))

    let fittedSize = MediaAspectFitImageSurface.fittedSize(
      imageSize: image.size,
      containerSize: CGSize(width: 320, height: 180)
    )

    #expect(fittedSize == CGSize(width: 270, height: 180))
  }

  @Test
  func aspectFitSurfaceKeepsPanoramaInsideFixedFrame() {
    let image = syntheticImage(size: CGSize(width: 2_400, height: 600))

    let fittedSize = MediaAspectFitImageSurface.fittedSize(
      imageSize: image.size,
      containerSize: CGSize(width: 320, height: 180)
    )

    #expect(fittedSize == CGSize(width: 320, height: 80))
  }

  @Test
  func orientedThumbnailUsesDisplayedPixelOrientationBeforeAspectFit() throws {
    let sourceImage = syntheticImage(size: CGSize(width: 80, height: 40))
    let sourceCGImage = try #require(sourceImage.cgImage)
    let encodedData = NSMutableData()
    let destination = try #require(
      CGImageDestinationCreateWithData(
        encodedData,
        UTType.jpeg.identifier as CFString,
        1,
        nil
      )
    )
    CGImageDestinationAddImage(
      destination,
      sourceCGImage,
      [kCGImagePropertyOrientation: 6] as CFDictionary
    )
    #expect(CGImageDestinationFinalize(destination))

    let thumbnail = try #require(MediaImagePreview.thumbnail(from: encodedData as Data))
    let thumbnailCGImage = try #require(thumbnail.cgImage)
    let fittedSize = MediaAspectFitImageSurface.fittedSize(
      imageSize: thumbnail.size,
      containerSize: CGSize(width: 320, height: 180)
    )

    #expect(thumbnailCGImage.width == 40)
    #expect(thumbnailCGImage.height == 80)
    #expect(fittedSize == CGSize(width: 90, height: 180))
  }

  @Test
  func retainedDiaryAttachmentsReducePickerCapacityAndEnforceKindMix() throws {
    let model = MediaAttachmentComposerModel(
      purpose: .diaryEntry,
      service: ComposerMediaServiceFake(),
      existingKinds: [.image, .image, .image]
    )

    #expect(model.canSelectMore)
    #expect(model.pickerSelectionLimit == 1)
    #expect(
      throws: MediaAttachmentRuleViolation.mixedMediaNotAllowed,
      performing: {
        try model.addPreparedAttachment(
          kind: .video,
          fileName: "clip.mov",
          contentType: "video/quicktime",
          data: Data([0x00])
        )
      }
    )

    model.setExistingKinds([.image, .image, .image, .image])
    #expect(!model.canSelectMore)
  }

  @Test
  func consumeTransfersReadyUploadsInSelectionOrderWithoutDiscarding() async throws {
    let service = ComposerMediaServiceFake()
    let model = MediaAttachmentComposerModel(
      purpose: .diaryEntry,
      service: service,
      uploader: ComposerImmediateUploader()
    )

    try model.addPreparedAttachment(
      kind: .image,
      fileName: "first.png",
      contentType: "image/png",
      data: Data([0x89, 0x50, 0x4E])
    )
    try model.addPreparedAttachment(
      kind: .image,
      fileName: "second.webp",
      contentType: "image/webp",
      data: Data([0x52, 0x49, 0x46, 0x46])
    )
    await composerExpectEventually { model.isReadyForSubmission }

    let ids = model.readyUploadIDs
    let consumed = model.consumeReadyUploads()
    await Task.yield()

    #expect(ids == Array(ComposerMediaFixtures.uploadIDs.prefix(2)))
    #expect(consumed.map(\.id) == Array(ComposerMediaFixtures.uploadIDs.prefix(2)))
    #expect(model.isReadyForSubmission)
    #expect(model.readyUploadIDs.isEmpty)
    #expect(await service.discardedIDs.isEmpty)
  }

  @Test
  func clearDiscardsAnUnattachedReadyUpload() async throws {
    let service = ComposerMediaServiceFake()
    let model = MediaAttachmentComposerModel(
      purpose: .comment,
      service: service,
      uploader: ComposerImmediateUploader()
    )

    try model.addPreparedAttachment(
      kind: .video,
      fileName: "clip.mov",
      contentType: "video/quicktime",
      data: Data([0x00, 0x00, 0x00, 0x14])
    )
    await composerExpectEventually { model.isReadyForSubmission }
    model.clear()
    await composerExpectEventually { await service.discardedIDs.count == 1 }

    #expect(await service.discardedIDs == [ComposerMediaFixtures.uploadIDs[0]])
    #expect(model.isReadyForSubmission)
  }

  @Test
  func submittedReadyUploadIsNotDiscardedByClearBeforeParentMutationFinishes() async throws {
    let service = ComposerMediaServiceFake()
    let model = MediaAttachmentComposerModel(
      purpose: .comment,
      service: service,
      uploader: ComposerImmediateUploader()
    )

    try model.addPreparedAttachment(
      kind: .image,
      fileName: "submitted.png",
      contentType: "image/png",
      data: Data([0x89, 0x50, 0x4E, 0x47])
    )
    await composerExpectEventually { model.isReadyForSubmission }

    let submittedIDs = model.markReadyUploadsSubmitted()
    model.clear()
    await Task.yield()

    #expect(submittedIDs == [ComposerMediaFixtures.uploadIDs[0]])
    #expect(model.submittedReadyUploadIDs == Set(submittedIDs))
    #expect(model.uploads.isEmpty)
    #expect(await service.discardedIDs.isEmpty)

    _ = model.consumeReadyUploads()
    #expect(model.submittedReadyUploadIDs.isEmpty)
  }

  @Test
  func submittedReadyUploadIsNotDiscardedWhenRemovedBeforeParentMutationFinishes() async throws {
    let service = ComposerMediaServiceFake()
    let model = MediaAttachmentComposerModel(
      purpose: .scoreChange,
      service: service,
      uploader: ComposerImmediateUploader()
    )

    try model.addPreparedAttachment(
      kind: .image,
      fileName: "submitted.jpg",
      contentType: "image/jpeg",
      data: Data([0xFF, 0xD8, 0xFF])
    )
    await composerExpectEventually { model.isReadyForSubmission }
    let itemID = try #require(model.uploads.first?.id)

    let submittedIDs = model.markReadyUploadsSubmitted()
    model.remove(itemID)
    await Task.yield()

    #expect(submittedIDs == [ComposerMediaFixtures.uploadIDs[0]])
    #expect(model.submittedReadyUploadIDs == Set(submittedIDs))
    #expect(model.uploads.isEmpty)
    #expect(await service.discardedIDs.isEmpty)

    _ = model.consumeReadyUploads()
    #expect(model.submittedReadyUploadIDs.isEmpty)
  }

  @Test
  func definitiveParentRejectionReleasesOwnershipSoCancelDiscardsReadyUpload() async throws {
    let service = ComposerMediaServiceFake()
    let model = MediaAttachmentComposerModel(
      purpose: .diaryEntry,
      service: service,
      uploader: ComposerImmediateUploader()
    )

    try model.addPreparedAttachment(
      kind: .image,
      fileName: "rejected.jpg",
      contentType: "image/jpeg",
      data: Data([0xFF, 0xD8, 0xFF])
    )
    await composerExpectEventually { model.isReadyForSubmission }
    model.markReadyUploadsSubmitted()

    model.releaseSubmittedUploadOwnership()
    model.clear()
    await composerExpectEventually { await service.discardedIDs.count == 1 }

    #expect(await service.discardedIDs == [ComposerMediaFixtures.uploadIDs[0]])
    #expect(model.submittedReadyUploadIDs.isEmpty)
  }

  @Test
  func sessionCoordinatorCleansTopLevelComposersBeforeCredentialRemoval() async throws {
    let service = ComposerMediaServiceFake(suspendsDiscard: true)
    let coordinator = TopLevelMediaSessionCoordinator(
      service: service,
      uploader: ComposerImmediateUploader()
    )

    try coordinator.relationshipScoreComposer.addPreparedAttachment(
      kind: .image,
      fileName: "rejected-score.jpg",
      contentType: "image/jpeg",
      data: Data([0xFF, 0xD8, 0xFF])
    )
    try coordinator.diaryEntryComposer.addPreparedAttachment(
      kind: .image,
      fileName: "ambiguous-diary.jpg",
      contentType: "image/jpeg",
      data: Data([0xFF, 0xD8, 0xFF, 0x00])
    )
    await composerExpectEventually {
      coordinator.relationshipScoreComposer.isReadyForSubmission
        && coordinator.diaryEntryComposer.isReadyForSubmission
    }
    coordinator.relationshipScoreComposer.markReadyUploadsSubmitted()
    coordinator.diaryEntryComposer.markReadyUploadsSubmitted()

    var cleanupFinished = false
    let cleanupTask = Task { @MainActor in
      await coordinator.prepareForCredentialRemoval(
        releaseRejectedScoreSubmission: true,
        releaseRejectedDiarySubmission: false
      )
      cleanupFinished = true
    }

    await composerExpectEventually { await service.hasSuspendedDiscard }
    #expect(!cleanupFinished)
    await service.resumeDiscards()
    await cleanupTask.value

    #expect(cleanupFinished)
    #expect(await service.discardedIDs == [ComposerMediaFixtures.uploadIDs[0]])
    #expect(coordinator.relationshipScoreComposer.uploads.isEmpty)
    #expect(coordinator.diaryEntryComposer.uploads.isEmpty)
    #expect(coordinator.relationshipScoreComposer.submittedReadyUploadIDs.isEmpty)
    #expect(coordinator.diaryEntryComposer.submittedReadyUploadIDs.isEmpty)
  }

  @Test
  func authenticationFailureIsExposedToCompositionRoot() async throws {
    let service = ComposerMediaServiceFake(rejectAuthentication: true)
    let model = MediaAttachmentComposerModel(
      purpose: .scoreChange,
      service: service,
      uploader: ComposerImmediateUploader()
    )

    try model.addPreparedAttachment(
      kind: .image,
      fileName: "photo.jpg",
      contentType: "image/jpeg",
      data: Data([0xFF, 0xD8, 0xFF])
    )
    await composerExpectEventually { model.hasAuthenticationFailure }

    #expect(!model.isReadyForSubmission)
    #expect(model.readyUploadIDs.isEmpty)
  }

  @Test
  func privatePreviewRequestAndSessionDoNotCarryAPIAuthenticationOrBrowserState() throws {
    let grant = try MediaDownloadGrant(
      downloadURL: URL(string: "https://media.example.test/object?signature=private")!,
      expiresAt: Date().addingTimeInterval(300)
    )

    let request = try EphemeralPrivateMediaPreviewDownloader.makeRequest(grant: grant)
    let configuration = EphemeralPrivateMediaPreviewDownloader.makeConfiguration()

    #expect(request.httpMethod == "GET")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-store")
    #expect(!request.httpShouldHandleCookies)
    #expect(request.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
    #expect(configuration.identifier == nil)
    #expect(configuration.urlCache == nil)
    #expect(configuration.httpCookieStorage == nil)
    #expect(configuration.urlCredentialStorage == nil)
    #expect(!configuration.httpShouldSetCookies)
    #expect(configuration.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
  }

  @Test
  func urlSessionCancelledErrorIsNormalizedAsCancellation() {
    let cancelled = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
    let timedOut = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)

    #expect(EphemeralPrivateMediaPreviewDownloader.isCancellation(cancelled))
    #expect(EphemeralPrivateMediaPreviewDownloader.isCancellation(CancellationError()))
    #expect(!EphemeralPrivateMediaPreviewDownloader.isCancellation(timedOut))
  }

  @Test
  func sharedPreviewStoreCoalescesGrantAndDownloadForTheSameAttachment() async throws {
    let service = PrivatePreviewServiceFake()
    let downloader = PrivatePreviewDownloaderFake(suspendsDownloads: true)
    let store = PrivateMediaPreviewStore(service: service, downloader: downloader)
    let descriptor = PrivatePreviewTestFixtures.descriptor()

    let first = Task { try await store.load(descriptor) }
    let second = Task { try await store.load(descriptor) }
    await composerExpectEventually { await downloader.suspendedDownloadCount == 1 }
    await downloader.resumeAll()

    let firstLease = try await first.value
    let secondLease = try await second.value
    #expect(await service.downloadGrantCount == 1)
    #expect(await downloader.downloadCount == 1)
    #expect(firstLease.localURL == secondLease.localURL)
    #expect(firstLease.token != secondLease.token)

    await store.release(firstLease)
    await store.release(secondLease)
    await store.clearSession()
  }

  @Test
  func rejectedSignedURLIsRetriedOnceWithAFreshGrant() async throws {
    let service = PrivatePreviewServiceFake()
    let downloader = PrivatePreviewDownloaderFake(firstRejectedStatusCode: 403)
    let store = PrivateMediaPreviewStore(service: service, downloader: downloader)

    let lease = try await store.load(PrivatePreviewTestFixtures.descriptor())

    #expect(await service.downloadGrantCount == 2)
    #expect(await downloader.downloadCount == 2)
    await store.release(lease)
    await store.clearSession()
  }

  @Test
  func cancellingOnePreviewWaiterDoesNotCancelTheSharedDownload() async throws {
    let service = PrivatePreviewServiceFake()
    let downloader = PrivatePreviewDownloaderFake(suspendsDownloads: true)
    let store = PrivateMediaPreviewStore(service: service, downloader: downloader)
    let descriptor = PrivatePreviewTestFixtures.descriptor()

    let cancelledWaiter = Task { try await store.load(descriptor) }
    let survivingWaiter = Task { try await store.load(descriptor) }
    await composerExpectEventually { await downloader.suspendedDownloadCount == 1 }
    cancelledWaiter.cancel()
    await Task.yield()
    await downloader.resumeAll()

    do {
      _ = try await cancelledWaiter.value
      Issue.record("A cancelled preview waiter unexpectedly received a lease")
    } catch {
      #expect(error is CancellationError)
    }
    let lease = try await survivingWaiter.value
    #expect(await downloader.cancelledDownloadCount == 0)
    #expect(await downloader.downloadCount == 1)

    await store.release(lease)
    await store.clearSession()
  }

  @Test
  func lastWaiterCancellationRemovesAProviderResultThatArrivesLate() async {
    let service = PrivatePreviewServiceFake()
    let downloader = PrivatePreviewDownloaderFake(
      suspendsDownloads: true,
      ignoresCancellation: true
    )
    let store = PrivateMediaPreviewStore(service: service, downloader: downloader)
    let load = Task {
      try await store.load(PrivatePreviewTestFixtures.descriptor())
    }
    await composerExpectEventually { await downloader.suspendedDownloadCount == 1 }

    load.cancel()
    await composerExpectEventually { await downloader.cancellationRequestCount == 1 }
    await downloader.resumeAll()
    await composerExpectEventually { await downloader.producedURLs.count == 1 }
    let producedURL = await downloader.producedURLs[0]
    await composerExpectEventually {
      !FileManager.default.fileExists(atPath: producedURL.path)
    }

    do {
      _ = try await load.value
      Issue.record("The cancelled final waiter unexpectedly received a lease")
    } catch {
      #expect(error is CancellationError)
    }
    #expect(!FileManager.default.fileExists(atPath: producedURL.path))
    await store.clearSession()
  }

  @Test
  func previewStoreBoundsConcurrentGrantAndObjectLoads() async throws {
    let service = PrivatePreviewServiceFake()
    let downloader = PrivatePreviewDownloaderFake(suspendsDownloads: true)
    let store = PrivateMediaPreviewStore(
      service: service,
      downloader: downloader,
      maximumConcurrentLoads: 3
    )
    let descriptors = (0..<5).map { PrivatePreviewTestFixtures.descriptor(index: $0) }
    let tasks = descriptors.map { descriptor in
      Task { try await store.load(descriptor) }
    }

    await composerExpectEventually { await downloader.suspendedDownloadCount == 3 }
    #expect(await downloader.maximumActiveDownloadCount == 3)
    await downloader.resumeAll()
    await composerExpectEventually { await downloader.suspendedDownloadCount == 2 }
    #expect(await downloader.maximumActiveDownloadCount == 3)
    await downloader.resumeAll()

    for task in tasks {
      let lease = try await task.value
      await store.release(lease)
    }
    #expect(await service.downloadGrantCount == 5)
    await store.clearSession()
  }

  @Test
  func previewCacheIsReusedAndClearedAtTheAuthenticationBoundary() async throws {
    let service = PrivatePreviewServiceFake()
    let downloader = PrivatePreviewDownloaderFake()
    let store = PrivateMediaPreviewStore(service: service, downloader: downloader)
    let descriptor = PrivatePreviewTestFixtures.descriptor()

    let firstLease = try await store.load(descriptor)
    let cachedURL = firstLease.localURL
    await store.release(firstLease)
    let cachedLease = try await store.load(descriptor)

    #expect(cachedLease.localURL == cachedURL)
    #expect(await downloader.downloadCount == 1)
    await store.release(cachedLease)
    await store.clearSession()
    #expect(!FileManager.default.fileExists(atPath: cachedURL.path))

    let postClearLease = try await store.load(descriptor)
    #expect(await downloader.downloadCount == 2)
    #expect(postClearLease.localURL != cachedURL)
    await store.release(postClearLease)
    await store.clearSession()
  }

  @Test
  func sessionClearRejectsLoadsUntilCancelledWorkersAreFullyRemoved() async {
    let service = PrivatePreviewServiceFake()
    let downloader = PrivatePreviewDownloaderFake(suspendsDownloads: true)
    let store = PrivateMediaPreviewStore(service: service, downloader: downloader)
    let activeLoad = Task {
      try await store.load(PrivatePreviewTestFixtures.descriptor())
    }
    await composerExpectEventually { await downloader.suspendedDownloadCount == 1 }

    let clearTask = Task { await store.clearSession() }
    await composerExpectEventually { await downloader.cancellationRequestCount == 1 }
    do {
      _ = try await store.load(PrivatePreviewTestFixtures.descriptor(index: 1))
      Issue.record("A new preview load started while the session was being cleared")
    } catch {
      #expect(error is CancellationError)
    }

    await downloader.resumeAll()
    await clearTask.value
    do {
      _ = try await activeLoad.value
      Issue.record("The session's active preview unexpectedly survived clearSession")
    } catch {
      #expect(error is CancellationError)
    }
  }

  @Test
  func previewModelClearIgnoresAndReleasesALateSuccessfulLoad() async {
    let descriptor = PrivatePreviewTestFixtures.descriptor()
    let loader = LatePrivatePreviewLoader(descriptor: descriptor)
    let model = PrivateMediaPreviewModel(descriptor: descriptor)

    model.load(using: loader)
    await composerExpectEventually { await loader.hasStarted }
    model.clear()
    await loader.resume()
    await composerExpectEventually { await loader.releaseCount == 1 }

    #expect(model.state == .idle)
    #expect(model.localURL == nil)
    #expect(model.image == nil)
    await loader.clearSession()
  }

  @Test
  func protectedPreviewUsesSanitizedTemporaryFileAndDeletesIt() throws {
    #expect(ProtectedTemporaryMediaPreview.safeFileExtension(from: "clip.MOV") == "mov")
    #expect(
      ProtectedTemporaryMediaPreview.safeFileExtension(from: "unsafe.very-long-extension")
        == "bin"
    )

    let contents = Data([0xFF, 0xD8, 0xFF])
    let url = try ProtectedTemporaryMediaPreview.write(contents, fileName: "photo.JPG")
    defer { ProtectedTemporaryMediaPreview.remove(url) }

    #expect(url.isFileURL)
    #expect(url.pathExtension == "jpg")
    #expect(FileManager.default.fileExists(atPath: url.path))
    #expect(try Data(contentsOf: url) == contents)
    #expect(
      try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
    )

    ProtectedTemporaryMediaPreview.remove(url)
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  @Test
  func downloadedPreviewFileIsMovedIntoTheProtectedOwnedDirectory() throws {
    let fileManager = FileManager.default
    let temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(
      "private-preview-adoption-test-\(UUID().uuidString)",
      isDirectory: true
    )
    let sourceURL = temporaryRoot.appendingPathComponent("provider-download.tmp")
    defer { try? fileManager.removeItem(at: temporaryRoot) }
    try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    try Data([0x01, 0x02]).write(to: sourceURL)

    let adoptedURL = try ProtectedTemporaryMediaPreview.adoptDownloadedFile(
      sourceURL,
      fileName: "memory.MP4",
      fileManager: fileManager,
      temporaryDirectory: temporaryRoot
    )

    #expect(!fileManager.fileExists(atPath: sourceURL.path))
    #expect(fileManager.fileExists(atPath: adoptedURL.path))
    #expect(adoptedURL.pathExtension == "mp4")
    #expect(
      adoptedURL.deletingLastPathComponent()
        == ProtectedTemporaryMediaPreview.directoryURL(in: temporaryRoot)
    )
    #expect(
      try adoptedURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        == true
    )
  }

  @Test
  func launchCleanupPurgesOnlyTheDedicatedPrivatePreviewDirectory() throws {
    let fileManager = FileManager.default
    let temporaryRoot = fileManager.temporaryDirectory
      .appendingPathComponent("private-preview-test-\(UUID().uuidString)", isDirectory: true)
    let previewDirectory = ProtectedTemporaryMediaPreview.directoryURL(in: temporaryRoot)
    let unrelatedFile = temporaryRoot.appendingPathComponent("unrelated.tmp")
    defer { try? fileManager.removeItem(at: temporaryRoot) }

    try fileManager.createDirectory(
      at: previewDirectory,
      withIntermediateDirectories: true
    )
    try Data([0x01]).write(to: previewDirectory.appendingPathComponent("stale.jpg"))
    try Data([0x02]).write(to: unrelatedFile)

    try ProtectedTemporaryMediaPreview.purgeStaleFiles(
      fileManager: fileManager,
      temporaryDirectory: temporaryRoot
    )

    #expect(!fileManager.fileExists(atPath: previewDirectory.path))
    #expect(fileManager.fileExists(atPath: unrelatedFile.path))
  }

  @Test
  func privacyCoverPolicyProtectsEveryNonactiveScenePhase() {
    #expect(!AppPrivacyCoverPolicy.shouldCover(.active))
    #expect(AppPrivacyCoverPolicy.shouldCover(.inactive))
    #expect(AppPrivacyCoverPolicy.shouldCover(.background))
  }

  @Test
  func snapshotPrivacyShieldStaysTopmostWithoutDuplicatingAndIsRemovedOnActivation() {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    let sensitiveContent = UILabel(frame: window.bounds)
    sensitiveContent.text = "private preview"
    window.addSubview(sensitiveContent)
    let shield = AppSnapshotPrivacyShield()

    shield.show(in: [window])

    #expect(shield.isCovering(window))
    #expect(
      window.subviews.last?.accessibilityIdentifier
        == AppSnapshotPrivacyShield.accessibilityIdentifier)
    #expect(
      window.subviews.filter {
        $0.accessibilityIdentifier == AppSnapshotPrivacyShield.accessibilityIdentifier
      }.count == 1
    )

    shield.show(in: [window])

    #expect(
      window.subviews.filter {
        $0.accessibilityIdentifier == AppSnapshotPrivacyShield.accessibilityIdentifier
      }.count == 1
    )
    #expect(
      window.subviews.last?.accessibilityIdentifier
        == AppSnapshotPrivacyShield.accessibilityIdentifier)

    shield.hide()

    #expect(!shield.isCovering(window))
    #expect(
      !window.subviews.contains {
        $0.accessibilityIdentifier == AppSnapshotPrivacyShield.accessibilityIdentifier
      }
    )
  }
}

private actor PrivatePreviewServiceFake: MediaServing {
  private(set) var downloadGrantCount = 0

  func initiateUpload(_ draft: MediaUploadDraft) async throws -> MediaUploadGrant {
    throw WoorisaiAPIError.invalidRequest
  }

  func completeUpload(id: UUID) async throws -> CompletedMediaUpload {
    throw WoorisaiAPIError.invalidRequest
  }

  func discardUpload(id: UUID) async throws {
    throw WoorisaiAPIError.invalidRequest
  }

  func issueDownloadGrant(attachmentID: UUID) async throws -> MediaDownloadGrant {
    downloadGrantCount += 1
    return try MediaDownloadGrant(
      downloadURL: URL(string: "https://media.example.test/object")!,
      expiresAt: Date().addingTimeInterval(300)
    )
  }
}

private actor PrivatePreviewDownloaderFake: PrivateMediaPreviewDownloading {
  private let suspendsDownloads: Bool
  private let ignoresCancellation: Bool
  private let root: URL
  private var firstRejectedStatusCode: Int?
  private var activeDownloadCount = 0
  private var continuations: [UUID: CheckedContinuation<Void, Never>] = [:]
  private(set) var downloadCount = 0
  private(set) var cancelledDownloadCount = 0
  private(set) var cancellationRequestCount = 0
  private(set) var maximumActiveDownloadCount = 0
  private(set) var producedURLs: [URL] = []

  var suspendedDownloadCount: Int {
    continuations.count
  }

  init(
    suspendsDownloads: Bool = false,
    ignoresCancellation: Bool = false,
    firstRejectedStatusCode: Int? = nil
  ) {
    self.suspendsDownloads = suspendsDownloads
    self.ignoresCancellation = ignoresCancellation
    self.firstRejectedStatusCode = firstRejectedStatusCode
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "private-preview-downloader-fake-\(UUID().uuidString)",
      isDirectory: true
    )
  }

  func download(
    _ descriptor: PrivateMediaPreviewDescriptor,
    using grant: MediaDownloadGrant
  ) async throws -> PrivateMediaPreviewDownloadedFile {
    downloadCount += 1
    activeDownloadCount += 1
    maximumActiveDownloadCount = max(maximumActiveDownloadCount, activeDownloadCount)
    defer { activeDownloadCount -= 1 }

    if let statusCode = firstRejectedStatusCode {
      firstRejectedStatusCode = nil
      throw PrivateMediaPreviewError.rejected(statusCode: statusCode)
    }

    if suspendsDownloads {
      let token = UUID()
      await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
          continuations[token] = continuation
        }
      } onCancel: {
        Task { await self.recordCancellationRequest() }
      }
    }
    if !ignoresCancellation {
      do {
        try Task.checkCancellation()
      } catch {
        cancelledDownloadCount += 1
        throw error
      }
    }

    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    let url = root.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
    try Data(repeating: 0x01, count: Int(descriptor.byteSize)).write(to: url)
    producedURLs.append(url)
    return PrivateMediaPreviewDownloadedFile(
      localURL: url,
      byteSize: descriptor.byteSize
    )
  }

  func resumeAll() {
    let resumptions = Array(continuations.values)
    continuations.removeAll()
    for continuation in resumptions {
      continuation.resume()
    }
  }

  private func recordCancellationRequest() {
    cancellationRequestCount += 1
  }
}

private actor LatePrivatePreviewLoader: PrivateMediaPreviewLoading {
  private let descriptor: PrivateMediaPreviewDescriptor
  private let url: URL
  private var continuation: CheckedContinuation<Void, Never>?
  private(set) var hasStarted = false
  private(set) var releaseCount = 0

  init(descriptor: PrivateMediaPreviewDescriptor) {
    self.descriptor = descriptor
    url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "late-private-preview-\(UUID().uuidString).mp4"
    )
  }

  func load(_ descriptor: PrivateMediaPreviewDescriptor) async throws
    -> PrivateMediaPreviewLease
  {
    hasStarted = true
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
    try Data(repeating: 0x01, count: Int(descriptor.byteSize)).write(to: url)
    return PrivateMediaPreviewLease(
      token: UUID(),
      attachmentID: descriptor.attachmentID,
      localURL: url,
      fileName: descriptor.fileName,
      contentType: descriptor.contentType,
      byteSize: descriptor.byteSize
    )
  }

  func release(_ lease: PrivateMediaPreviewLease) async {
    releaseCount += 1
    try? FileManager.default.removeItem(at: lease.localURL)
  }

  func discard(_ lease: PrivateMediaPreviewLease) async {
    await release(lease)
  }

  func clearSession() async {
    try? FileManager.default.removeItem(at: url)
  }

  func resume() {
    continuation?.resume()
    continuation = nil
  }
}

private enum PrivatePreviewTestFixtures {
  static func descriptor(index: Int = 0) -> PrivateMediaPreviewDescriptor {
    PrivateMediaPreviewDescriptor(
      attachmentID: UUID(
        uuidString: String(format: "123E4567-E89B-12D3-A456-%012d", index + 500)
      )!,
      fileName: "clip-\(index).mp4",
      contentType: "video/mp4",
      byteSize: 4
    )
  }
}

private func syntheticImage(size: CGSize) -> UIImage {
  let format = UIGraphicsImageRendererFormat()
  format.scale = 1
  return UIGraphicsImageRenderer(size: size, format: format).image { context in
    UIColor.systemPink.setFill()
    context.fill(CGRect(origin: .zero, size: size))
  }
}

private actor ComposerMediaServiceFake: MediaServing {
  private var nextIndex = 0
  private var drafts: [UUID: MediaUploadDraft] = [:]
  private let rejectAuthentication: Bool
  private let suspendsDiscard: Bool
  private var discardContinuations: [UUID: CheckedContinuation<Void, Never>] = [:]
  private(set) var discardedIDs: [UUID] = []

  init(rejectAuthentication: Bool = false, suspendsDiscard: Bool = false) {
    self.rejectAuthentication = rejectAuthentication
    self.suspendsDiscard = suspendsDiscard
  }

  var hasSuspendedDiscard: Bool {
    !discardContinuations.isEmpty
  }

  func initiateUpload(_ draft: MediaUploadDraft) async throws -> MediaUploadGrant {
    if rejectAuthentication {
      throw WoorisaiAPIError.credentialRejected
    }
    let id = ComposerMediaFixtures.uploadIDs[nextIndex]
    nextIndex += 1
    drafts[id] = draft
    return try MediaUploadGrant(
      uploadID: id,
      uploadURL: URL(string: "https://media.example.test/upload")!,
      requiredHeaders: MediaUploadRequiredHeaders(
        contentType: draft.contentType,
        cacheControl: MediaUploadRequiredHeaders.privateNoStore
      ),
      expiresAt: Date().addingTimeInterval(600)
    )
  }

  func completeUpload(id: UUID) async throws -> CompletedMediaUpload {
    guard let draft = drafts[id] else { throw WoorisaiAPIError.schemaDrift }
    return try CompletedMediaUpload(
      id: id,
      kind: draft.kind,
      fileName: draft.fileName,
      contentType: draft.contentType,
      byteSize: draft.byteSize
    )
  }

  func discardUpload(id: UUID) async throws {
    discardedIDs.append(id)
    if suspendsDiscard {
      await withCheckedContinuation { continuation in
        discardContinuations[id] = continuation
      }
    }
  }

  func resumeDiscards() {
    let continuations = Array(discardContinuations.values)
    discardContinuations.removeAll()
    for continuation in continuations { continuation.resume() }
  }

  func issueDownloadGrant(attachmentID: UUID) async throws -> MediaDownloadGrant {
    try MediaDownloadGrant(
      downloadURL: URL(string: "https://media.example.test/download")!,
      expiresAt: Date().addingTimeInterval(300)
    )
  }
}

private actor ComposerImmediateUploader: PresignedMediaUploading {
  func put(
    _ data: Data,
    using grant: MediaUploadGrant,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws {
    progress(0.5)
    await Task.yield()
    progress(1)
  }
}

private actor ComposerSuspendedUploader: PresignedMediaUploading {
  private(set) var hasStarted = false

  func put(
    _ data: Data,
    using grant: MediaUploadGrant,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws {
    hasStarted = true
    try await Task.sleep(for: .seconds(60))
  }
}

private enum ComposerMediaFixtures {
  static let uploadIDs = [
    UUID(uuidString: "123E4567-E89B-12D3-A456-426614174001")!,
    UUID(uuidString: "123E4567-E89B-12D3-A456-426614174002")!,
    UUID(uuidString: "123E4567-E89B-12D3-A456-426614174003")!,
    UUID(uuidString: "123E4567-E89B-12D3-A456-426614174004")!,
  ]
}

@MainActor
private func composerExpectEventually(
  _ predicate: @escaping @MainActor @Sendable () async -> Bool,
  timeout: Duration = .seconds(5)
) async {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)
  while clock.now < deadline {
    if await predicate() { return }
    try? await Task.sleep(for: .milliseconds(5))
  }
  Issue.record("Timed out waiting for media composer state")
}
