import Testing
import WoorisaiAPI

@testable import Woorisai

@MainActor
struct LoginOptionsModelTests {
  private let expectedOptions = [
    LoginOption(slot: 1, displayName: "첫 번째"),
    LoginOption(slot: 2, displayName: "두 번째"),
  ]

  @Test
  func loadConvergesToCanonicalOptions() async {
    let loader = ScriptedLoginOptionsLoader(steps: [.success(expectedOptions)])
    let model = LoginOptionsModel(loader: loader)

    model.load()

    await expectEventually {
      model.state == .loaded(self.expectedOptions)
    }
    #expect(await loader.loadCount == 1)
  }

  @Test
  func serviceUnavailableUsesDedicatedState() async {
    let loader = ScriptedLoginOptionsLoader(steps: [.unavailable])
    let model = LoginOptionsModel(loader: loader)

    model.load()

    await expectEventually {
      model.state == .unavailable
    }
  }

  @Test
  func loaderCancellationReturnsToIdle() async {
    let loader = ScriptedLoginOptionsLoader(steps: [.cancelled])
    let model = LoginOptionsModel(loader: loader)

    model.load()

    await expectEventually {
      model.state == .idle
    }
  }

  @Test
  func retryConvergesAfterUnavailableResponse() async {
    let loader = ScriptedLoginOptionsLoader(
      steps: [.unavailable, .success(expectedOptions)]
    )
    let model = LoginOptionsModel(loader: loader)

    model.load()
    await expectEventually {
      model.state == .unavailable
    }

    model.retry()

    await expectEventually {
      model.state == .loaded(self.expectedOptions)
    }
    #expect(await loader.loadCount == 2)
  }

  @Test
  func cancellationReturnsToIdleAndIgnoresLateCompletion() async {
    let loader = ControlledLoginOptionsLoader()
    let model = LoginOptionsModel(loader: loader)

    model.load()
    await expectEventually {
      await loader.requestCount == 1
    }

    model.cancel()
    #expect(model.state == .idle)

    await loader.succeed(request: 0, options: expectedOptions)
    await Task.yield()

    #expect(model.state == .idle)
  }

  @Test
  func staleCompletionCannotReplaceNewerRequest() async {
    let loader = ControlledLoginOptionsLoader()
    let model = LoginOptionsModel(loader: loader)
    let staleOptions = [
      LoginOption(slot: 1, displayName: "오래된 첫 번째"),
      LoginOption(slot: 2, displayName: "오래된 두 번째"),
    ]

    model.load()
    await expectEventually {
      await loader.requestCount == 1
    }

    model.retry()
    await expectEventually {
      await loader.requestCount == 2
    }

    await loader.succeed(request: 0, options: staleOptions)
    await Task.yield()
    #expect(model.state == .loading)

    await loader.succeed(request: 1, options: expectedOptions)
    await expectEventually {
      model.state == .loaded(self.expectedOptions)
    }
  }
}

@MainActor
struct ParticipantAvatarTests {
  @Test
  func labelUsesUpToTwoLeadingCharacters() {
    #expect(ParticipantAvatar.label(for: "가나다") == "가나")
    #expect(ParticipantAvatar.label(for: "라마") == "라마")
    #expect(ParticipantAvatar.label(for: "봄") == "봄")
    #expect(ParticipantAvatar.label(for: "가나다라마바사") == "가나")
  }
}

private actor ScriptedLoginOptionsLoader: LoginOptionsLoading {
  enum Step: Sendable {
    case cancelled
    case success([LoginOption])
    case unavailable
  }

  private var steps: [Step]
  private(set) var loadCount = 0

  init(steps: [Step]) {
    self.steps = steps
  }

  func loadLoginOptions() async throws -> [LoginOption] {
    loadCount += 1
    guard !steps.isEmpty else {
      throw TestFailure.unexpectedLoad
    }

    switch steps.removeFirst() {
    case .cancelled:
      throw CancellationError()
    case .success(let options):
      return options
    case .unavailable:
      throw WoorisaiAPIError.loginOptionsUnavailable
    }
  }
}

private actor ControlledLoginOptionsLoader: LoginOptionsLoading {
  private var continuations: [Int: CheckedContinuation<[LoginOption], any Error>] = [:]
  private(set) var requestCount = 0

  func loadLoginOptions() async throws -> [LoginOption] {
    let request = requestCount
    requestCount += 1

    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        continuations[request] = continuation
      }
    } onCancel: {
      // Intentionally ignore cancellation to prove generation checks reject stale work.
    }
  }

  func succeed(request: Int, options: [LoginOption]) {
    continuations.removeValue(forKey: request)?.resume(returning: options)
  }
}

private enum TestFailure: Error, Sendable {
  case unexpectedLoad
}

@MainActor
private func expectEventually(
  _ condition: @escaping @MainActor () async -> Bool,
  sourceLocation: SourceLocation = #_sourceLocation
) async {
  for _ in 0..<200 {
    if await condition() {
      return
    }
    try? await Task.sleep(for: .milliseconds(5))
  }

  Issue.record("조건이 제한 시간 안에 충족되지 않았습니다.", sourceLocation: sourceLocation)
}
