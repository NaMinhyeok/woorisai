import Observation
import WoorisaiAPI

@MainActor
@Observable
final class LoginOptionsModel {
  enum State: Equatable, Sendable {
    case idle
    case loading
    case loaded([LoginOption])
    case unavailable
    case failed
  }

  private(set) var state: State = .idle

  @ObservationIgnored
  private let loader: any LoginOptionsLoading

  @ObservationIgnored
  private var loadTask: Task<Void, Never>?

  @ObservationIgnored
  private var requestGeneration: UInt = 0

  init(loader: any LoginOptionsLoading) {
    self.loader = loader
  }

  func load() {
    startLoad()
  }

  func loadIfNeeded() {
    guard state == .idle else {
      return
    }
    startLoad()
  }

  func retry() {
    startLoad()
  }

  func cancel() {
    requestGeneration &+= 1
    loadTask?.cancel()
    loadTask = nil
    state = .idle
  }

  func reset() {
    cancel()
  }

  private func startLoad() {
    requestGeneration &+= 1
    let generation = requestGeneration
    let loader = loader

    loadTask?.cancel()
    state = .loading

    loadTask = Task { @MainActor [weak self] in
      do {
        let options = try await loader.loadLoginOptions()
        try Task.checkCancellation()
        guard let self, self.requestGeneration == generation else {
          return
        }

        self.state = .loaded(options)
        self.loadTask = nil
      } catch is CancellationError {
        guard let self, self.requestGeneration == generation else {
          return
        }

        self.state = .idle
        self.loadTask = nil
      } catch WoorisaiAPIError.loginOptionsUnavailable {
        guard let self, self.requestGeneration == generation else {
          return
        }

        self.state = .unavailable
        self.loadTask = nil
      } catch {
        guard let self,
          self.requestGeneration == generation,
          !Task.isCancelled
        else {
          return
        }

        self.state = .failed
        self.loadTask = nil
      }
    }
  }
}
