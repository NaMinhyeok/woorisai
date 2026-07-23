import Foundation
import Observation
import SwiftUI
import UIKit
import WoorisaiAPI

@MainActor
@Observable
final class MediaDownloadModel {
  enum State: Equatable, Sendable {
    case idle
    case loading
    case loaded(MediaDownloadGrant)
    case authenticationRequired
    case notFound
    case unavailable
    case failed
  }

  private(set) var state: State = .idle

  @ObservationIgnored
  private let service: any MediaServing

  @ObservationIgnored
  private var task: Task<Void, Never>?

  @ObservationIgnored
  private var generation: UInt = 0

  @ObservationIgnored
  private var attachmentID: UUID?

  init(service: any MediaServing) {
    self.service = service
  }

  func load(attachmentID: UUID) {
    generation &+= 1
    let generation = generation
    let service = service
    self.attachmentID = attachmentID
    task?.cancel()
    state = .loading
    task = Task { @MainActor [weak self] in
      do {
        let grant = try await service.issueDownloadGrant(attachmentID: attachmentID)
        try Task.checkCancellation()
        guard let self, self.generation == generation else { return }
        self.task = nil
        self.state = .loaded(grant)
      } catch is CancellationError {
        return
      } catch {
        guard let self, self.generation == generation else { return }
        self.task = nil
        switch error as? WoorisaiAPIError {
        case .credentialMissing, .credentialRejected:
          self.state = .authenticationRequired
        case .notFound:
          self.state = .notFound
        case .serviceUnavailable:
          self.state = .unavailable
        default:
          self.state = .failed
        }
      }
    }
  }

  func retry() {
    guard let attachmentID else { return }
    load(attachmentID: attachmentID)
  }

  func cancel() {
    generation &+= 1
    task?.cancel()
    task = nil
    state = .idle
  }

  func clear() {
    cancel()
    attachmentID = nil
  }
}

struct PrivateMediaPreviewDescriptor: Equatable, Sendable {
  let attachmentID: UUID
  let fileName: String
  let contentType: String
  let byteSize: Int64

  var isImage: Bool {
    contentType.lowercased().hasPrefix("image/")
  }
}

struct PrivateMediaPreviewDownloadedFile: Equatable, Sendable {
  let localURL: URL
  let byteSize: Int64
}

struct PrivateMediaPreviewLease: Equatable, Sendable {
  let token: UUID
  let attachmentID: UUID
  let localURL: URL
  let fileName: String
  let contentType: String
  let byteSize: Int64
}

protocol PrivateMediaPreviewLoading: Sendable {
  func load(_ descriptor: PrivateMediaPreviewDescriptor) async throws
    -> PrivateMediaPreviewLease
  func release(_ lease: PrivateMediaPreviewLease) async
  func discard(_ lease: PrivateMediaPreviewLease) async
  func clearSession() async
}

private struct UnavailablePrivateMediaPreviewLoader: PrivateMediaPreviewLoading {
  func load(_ descriptor: PrivateMediaPreviewDescriptor) async throws
    -> PrivateMediaPreviewLease
  {
    throw PrivateMediaPreviewError.transport
  }

  func release(_ lease: PrivateMediaPreviewLease) async {}
  func discard(_ lease: PrivateMediaPreviewLease) async {}
  func clearSession() async {}
}

private struct PrivateMediaPreviewLoaderKey: EnvironmentKey {
  static let defaultValue: any PrivateMediaPreviewLoading =
    UnavailablePrivateMediaPreviewLoader()
}

extension EnvironmentValues {
  var privateMediaPreviewLoader: any PrivateMediaPreviewLoading {
    get { self[PrivateMediaPreviewLoaderKey.self] }
    set { self[PrivateMediaPreviewLoaderKey.self] = newValue }
  }
}

private actor PrivateMediaPreviewConcurrencyGate {
  private let maximumConcurrentLoads: Int
  private var activeLoads = 0
  private var waitingOrder: [UUID] = []
  private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]

  init(maximumConcurrentLoads: Int) {
    self.maximumConcurrentLoads = max(1, maximumConcurrentLoads)
  }

  func acquire() async throws {
    let token = UUID()
    try Task.checkCancellation()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
        } else if activeLoads < maximumConcurrentLoads {
          activeLoads += 1
          continuation.resume()
        } else {
          waitingOrder.append(token)
          waiters[token] = continuation
        }
      }
    } onCancel: {
      Task { await self.cancelWaiter(token) }
    }
  }

  func release() {
    while let token = waitingOrder.first {
      waitingOrder.removeFirst()
      guard let continuation = waiters.removeValue(forKey: token) else { continue }
      continuation.resume()
      return
    }
    activeLoads = max(0, activeLoads - 1)
  }

  private func cancelWaiter(_ token: UUID) {
    guard let continuation = waiters.removeValue(forKey: token) else { return }
    continuation.resume(throwing: CancellationError())
  }
}

actor PrivateMediaPreviewStore: PrivateMediaPreviewLoading {
  private struct CacheEntry: Sendable {
    let descriptor: PrivateMediaPreviewDescriptor
    let file: PrivateMediaPreviewDownloadedFile
    var leaseTokens: Set<UUID>
    var lastAccess: UInt64
  }

  private struct Flight: Sendable {
    let id: UUID
    let descriptor: PrivateMediaPreviewDescriptor
    let task: Task<PrivateMediaPreviewDownloadedFile, any Error>
    var waiterTokens: Set<UUID>
  }

  private let service: any MediaServing
  private let downloader: any PrivateMediaPreviewDownloading
  private let concurrencyGate: PrivateMediaPreviewConcurrencyGate
  private let maximumCachedByteSize: Int64
  private let now: @Sendable () -> Date
  private var cache: [UUID: CacheEntry] = [:]
  private var flights: [UUID: Flight] = [:]
  private var retiredFlights: [UUID: Flight] = [:]
  private var accessCounter: UInt64 = 0
  private var isClearingSession = false

  init(
    service: any MediaServing,
    downloader: any PrivateMediaPreviewDownloading =
      EphemeralPrivateMediaPreviewDownloader(),
    maximumConcurrentLoads: Int = 3,
    maximumCachedByteSize: Int64 = 128 * 1_024 * 1_024,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.service = service
    self.downloader = downloader
    concurrencyGate = PrivateMediaPreviewConcurrencyGate(
      maximumConcurrentLoads: maximumConcurrentLoads
    )
    self.maximumCachedByteSize = max(0, maximumCachedByteSize)
    self.now = now
  }

  func load(_ descriptor: PrivateMediaPreviewDescriptor) async throws
    -> PrivateMediaPreviewLease
  {
    guard !isClearingSession else { throw CancellationError() }
    guard descriptor.byteSize > 0 else {
      throw PrivateMediaPreviewError.responseSizeMismatch
    }
    try Task.checkCancellation()

    if let lease = cachedLease(for: descriptor) {
      do {
        try Task.checkCancellation()
        return lease
      } catch {
        await release(lease)
        throw error
      }
    }

    let waiterToken = UUID()
    let flight = flight(for: descriptor, waiterToken: waiterToken)

    return try await withTaskCancellationHandler {
      do {
        let file = try await flight.task.value
        try Task.checkCancellation()
        let lease = try complete(
          descriptor: descriptor,
          file: file,
          flightID: flight.id,
          waiterToken: waiterToken
        )
        do {
          try Task.checkCancellation()
          return lease
        } catch {
          await release(lease)
          throw error
        }
      } catch {
        finishWaiter(
          attachmentID: descriptor.attachmentID,
          flightID: flight.id,
          waiterToken: waiterToken
        )
        if Task.isCancelled || EphemeralPrivateMediaPreviewDownloader.isCancellation(error) {
          throw CancellationError()
        }
        throw error
      }
    } onCancel: {
      Task {
        await self.cancelWaiter(
          attachmentID: descriptor.attachmentID,
          flightID: flight.id,
          waiterToken: waiterToken
        )
      }
    }
  }

  func release(_ lease: PrivateMediaPreviewLease) async {
    guard var entry = cache[lease.attachmentID],
      entry.file.localURL == lease.localURL
    else { return }
    entry.leaseTokens.remove(lease.token)
    cache[lease.attachmentID] = entry
    trimCacheIfNeeded()
  }

  func discard(_ lease: PrivateMediaPreviewLease) async {
    guard let entry = cache[lease.attachmentID],
      entry.file.localURL == lease.localURL
    else { return }
    cache.removeValue(forKey: lease.attachmentID)
    ProtectedTemporaryMediaPreview.remove(entry.file.localURL)
  }

  func clearSession() async {
    guard !isClearingSession else { return }
    isClearingSession = true
    defer { isClearingSession = false }
    let currentFlights = Array(flights.values) + Array(retiredFlights.values)
    flights.removeAll()
    retiredFlights.removeAll()
    for flight in currentFlights {
      flight.task.cancel()
    }
    let currentEntries = Array(cache.values)
    cache.removeAll()
    for entry in currentEntries {
      ProtectedTemporaryMediaPreview.remove(entry.file.localURL)
    }
    for flight in currentFlights {
      if let file = try? await flight.task.value {
        ProtectedTemporaryMediaPreview.remove(file.localURL)
      }
    }
    try? ProtectedTemporaryMediaPreview.purgeStaleFiles()
  }

  private func cachedLease(
    for descriptor: PrivateMediaPreviewDescriptor
  ) -> PrivateMediaPreviewLease? {
    guard var entry = cache[descriptor.attachmentID] else { return nil }
    guard entry.descriptor == descriptor,
      FileManager.default.fileExists(atPath: entry.file.localURL.path)
    else {
      cache.removeValue(forKey: descriptor.attachmentID)
      ProtectedTemporaryMediaPreview.remove(entry.file.localURL)
      return nil
    }
    accessCounter &+= 1
    let token = UUID()
    entry.lastAccess = accessCounter
    entry.leaseTokens.insert(token)
    cache[descriptor.attachmentID] = entry
    return lease(token: token, descriptor: descriptor, file: entry.file)
  }

  private func flight(
    for descriptor: PrivateMediaPreviewDescriptor,
    waiterToken: UUID
  ) -> Flight {
    if var existing = flights[descriptor.attachmentID],
      existing.descriptor == descriptor,
      !existing.waiterTokens.isEmpty
    {
      existing.waiterTokens.insert(waiterToken)
      flights[descriptor.attachmentID] = existing
      return existing
    }

    if let obsolete = flights.removeValue(forKey: descriptor.attachmentID) {
      retire(obsolete)
    }

    let id = UUID()
    let service = service
    let downloader = downloader
    let concurrencyGate = concurrencyGate
    let now = now
    let task = Task.detached(priority: .utility) {
      try await concurrencyGate.acquire()
      do {
        let file = try await Self.fetch(
          descriptor: descriptor,
          service: service,
          downloader: downloader,
          now: now
        )
        await concurrencyGate.release()
        return file
      } catch {
        await concurrencyGate.release()
        throw error
      }
    }
    let flight = Flight(
      id: id,
      descriptor: descriptor,
      task: task,
      waiterTokens: [waiterToken]
    )
    flights[descriptor.attachmentID] = flight
    return flight
  }

  private func complete(
    descriptor: PrivateMediaPreviewDescriptor,
    file: PrivateMediaPreviewDownloadedFile,
    flightID: UUID,
    waiterToken: UUID
  ) throws -> PrivateMediaPreviewLease {
    guard var flight = flights[descriptor.attachmentID], flight.id == flightID,
      flight.waiterTokens.remove(waiterToken) != nil
    else {
      removeIfUnowned(file, attachmentID: descriptor.attachmentID)
      throw CancellationError()
    }

    accessCounter &+= 1
    let leaseToken = UUID()
    if var entry = cache[descriptor.attachmentID],
      entry.file.localURL == file.localURL
    {
      entry.lastAccess = accessCounter
      entry.leaseTokens.insert(leaseToken)
      cache[descriptor.attachmentID] = entry
    } else {
      if let replaced = cache.removeValue(forKey: descriptor.attachmentID) {
        ProtectedTemporaryMediaPreview.remove(replaced.file.localURL)
      }
      cache[descriptor.attachmentID] = CacheEntry(
        descriptor: descriptor,
        file: file,
        leaseTokens: [leaseToken],
        lastAccess: accessCounter
      )
    }

    if flight.waiterTokens.isEmpty {
      flights.removeValue(forKey: descriptor.attachmentID)
    } else {
      flights[descriptor.attachmentID] = flight
    }
    trimCacheIfNeeded()
    return lease(token: leaseToken, descriptor: descriptor, file: file)
  }

  private func finishWaiter(
    attachmentID: UUID,
    flightID: UUID,
    waiterToken: UUID
  ) {
    guard var flight = flights[attachmentID], flight.id == flightID else { return }
    flight.waiterTokens.remove(waiterToken)
    if flight.waiterTokens.isEmpty {
      flights.removeValue(forKey: attachmentID)
      retire(flight)
    } else {
      flights[attachmentID] = flight
    }
  }

  private func cancelWaiter(
    attachmentID: UUID,
    flightID: UUID,
    waiterToken: UUID
  ) {
    guard var flight = flights[attachmentID], flight.id == flightID,
      flight.waiterTokens.remove(waiterToken) != nil
    else { return }
    if flight.waiterTokens.isEmpty {
      flights.removeValue(forKey: attachmentID)
      retire(flight)
    } else {
      flights[attachmentID] = flight
    }
  }

  private func retire(_ flight: Flight) {
    flight.task.cancel()
    retiredFlights[flight.id] = flight
    Task {
      if let file = try? await flight.task.value {
        self.finishRetiredFlight(flight, file: file)
      } else {
        self.finishRetiredFlight(flight, file: nil)
      }
    }
  }

  private func finishRetiredFlight(
    _ flight: Flight,
    file: PrivateMediaPreviewDownloadedFile?
  ) {
    retiredFlights.removeValue(forKey: flight.id)
    if let file {
      removeIfUnowned(file, attachmentID: flight.descriptor.attachmentID)
    }
  }

  private func removeIfUnowned(
    _ file: PrivateMediaPreviewDownloadedFile,
    attachmentID: UUID
  ) {
    guard cache[attachmentID]?.file.localURL != file.localURL else { return }
    ProtectedTemporaryMediaPreview.remove(file.localURL)
  }

  private func trimCacheIfNeeded() {
    var totalByteSize = cache.values.reduce(Int64(0)) { partial, entry in
      partial + entry.file.byteSize
    }
    while totalByteSize > maximumCachedByteSize {
      let releasableEntries = cache.values.filter {
        $0.leaseTokens.isEmpty && flights[$0.descriptor.attachmentID] == nil
      }
      guard let victim = releasableEntries.min(by: { $0.lastAccess < $1.lastAccess }) else {
        return
      }
      cache.removeValue(forKey: victim.descriptor.attachmentID)
      ProtectedTemporaryMediaPreview.remove(victim.file.localURL)
      totalByteSize -= victim.file.byteSize
    }
  }

  private func lease(
    token: UUID,
    descriptor: PrivateMediaPreviewDescriptor,
    file: PrivateMediaPreviewDownloadedFile
  ) -> PrivateMediaPreviewLease {
    PrivateMediaPreviewLease(
      token: token,
      attachmentID: descriptor.attachmentID,
      localURL: file.localURL,
      fileName: descriptor.fileName,
      contentType: descriptor.contentType,
      byteSize: file.byteSize
    )
  }

  private nonisolated static func fetch(
    descriptor: PrivateMediaPreviewDescriptor,
    service: any MediaServing,
    downloader: any PrivateMediaPreviewDownloading,
    now: @Sendable () -> Date
  ) async throws -> PrivateMediaPreviewDownloadedFile {
    var lastError: (any Error)?
    for attempt in 0..<2 {
      try Task.checkCancellation()
      do {
        let grant = try await service.issueDownloadGrant(
          attachmentID: descriptor.attachmentID
        )
        guard grant.expiresAt.timeIntervalSince(now()) > 30 else {
          throw PrivateMediaPreviewError.invalidGrant
        }
        return try await downloader.download(descriptor, using: grant)
      } catch {
        if Task.isCancelled || EphemeralPrivateMediaPreviewDownloader.isCancellation(error) {
          throw CancellationError()
        }
        lastError = error
        guard attempt == 0, isRetryable(error) else { throw error }
      }
    }
    throw lastError ?? PrivateMediaPreviewError.transport
  }

  private nonisolated static func isRetryable(_ error: any Error) -> Bool {
    switch error as? WoorisaiAPIError {
    case .serviceUnavailable, .transport:
      return true
    default:
      break
    }
    switch error as? PrivateMediaPreviewError {
    case .invalidGrant, .transport:
      return true
    case .rejected(let statusCode):
      return statusCode == 401 || statusCode == 403 || statusCode == 408
        || statusCode == 429 || statusCode >= 500
    default:
      return false
    }
  }
}

@MainActor
@Observable
final class PrivateMediaPreviewModel {
  enum State: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case authenticationRequired
    case notFound
    case unavailable
    case invalidContent
    case failed
  }

  let descriptor: PrivateMediaPreviewDescriptor
  private(set) var state: State = .idle
  private(set) var localURL: URL?
  private(set) var image: UIImage?

  @ObservationIgnored
  private var task: Task<Void, Never>?

  @ObservationIgnored
  private var lease: PrivateMediaPreviewLease?

  @ObservationIgnored
  private var loader: (any PrivateMediaPreviewLoading)?

  @ObservationIgnored
  private var generation: UInt = 0

  init(descriptor: PrivateMediaPreviewDescriptor) {
    self.descriptor = descriptor
  }

  func load(using loader: any PrivateMediaPreviewLoading) {
    startLoad(using: loader, discardingCurrentLease: false)
  }

  /// Removes a locally cached file that could not be decoded before acquiring it again.
  /// Discard must finish before the replacement load starts, otherwise the shared store can hand
  /// the same corrupt cached file straight back to this model.
  func reloadDiscardingCurrentLease(using loader: any PrivateMediaPreviewLoading) {
    startLoad(using: loader, discardingCurrentLease: true)
  }

  private func startLoad(
    using loader: any PrivateMediaPreviewLoading,
    discardingCurrentLease: Bool
  ) {
    generation &+= 1
    let generation = generation
    task?.cancel()
    let previousLease = lease
    let previousLoader = self.loader
    lease = nil
    self.loader = loader
    state = .loading
    localURL = nil
    image = nil

    let descriptor = descriptor
    task = Task { @MainActor [weak self] in
      var acquiredLease: PrivateMediaPreviewLease?
      do {
        if let previousLease, let previousLoader {
          if discardingCurrentLease {
            await previousLoader.discard(previousLease)
          } else {
            await previousLoader.release(previousLease)
          }
          try Task.checkCancellation()
        }

        let newLease = try await loader.load(descriptor)
        acquiredLease = newLease
        try Task.checkCancellation()

        let decodedImage: UIImage? =
          if descriptor.isImage {
            await Task.detached(priority: .userInitiated) {
              MediaImagePreview.thumbnail(fromFileAt: newLease.localURL)
            }.value
          } else {
            nil
          }
        try Task.checkCancellation()
        if descriptor.isImage, decodedImage == nil {
          await loader.discard(newLease)
          acquiredLease = nil
          throw PrivateMediaPreviewError.invalidImage
        }

        guard let self, self.generation == generation else {
          await loader.release(newLease)
          return
        }
        self.lease = newLease
        acquiredLease = nil
        self.localURL = newLease.localURL
        self.image = decodedImage
        self.task = nil
        self.state = .loaded
      } catch {
        if let acquiredLease {
          await loader.release(acquiredLease)
        }
        guard let self, self.generation == generation else { return }
        self.task = nil
        if Task.isCancelled || EphemeralPrivateMediaPreviewDownloader.isCancellation(error) {
          self.state = .idle
          return
        }
        self.state = Self.failureState(for: error)
      }
    }
  }

  func clear() {
    generation &+= 1
    task?.cancel()
    task = nil
    releaseCurrentLease()
    localURL = nil
    image = nil
    state = .idle
  }

  private func releaseCurrentLease() {
    guard let lease, let loader else {
      lease = nil
      return
    }
    self.lease = nil
    Task { await loader.release(lease) }
  }

  private static func failureState(for error: any Error) -> State {
    switch error as? WoorisaiAPIError {
    case .credentialMissing, .credentialRejected:
      return .authenticationRequired
    case .notFound:
      return .notFound
    case .serviceUnavailable, .transport:
      return .unavailable
    default:
      break
    }
    switch error as? PrivateMediaPreviewError {
    case .rejected(statusCode: 404):
      return .notFound
    case .invalidImage, .responseSizeMismatch, .responseTooLarge:
      return .invalidContent
    case .invalidGrant, .rejected, .transport, .temporaryFile:
      return .unavailable
    default:
      return .failed
    }
  }
}
