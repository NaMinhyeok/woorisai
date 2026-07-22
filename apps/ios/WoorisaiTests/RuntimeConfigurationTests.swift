import Testing

@testable import Woorisai

struct RuntimeConfigurationTests {
  @Test
  func createsHTTPSBaseURLFromPinnedHost() throws {
    let configuration = try RuntimeConfiguration(apiHost: "staging.invalid")

    #expect(configuration.apiBaseURL.absoluteString == "https://staging.invalid")
  }

  @Test(arguments: [
    "staging.invalid/path",
    "https://staging.invalid",
    "user@staging.invalid",
    "staging.invalid:443",
    " staging.invalid",
    "localhost",
    "-staging.invalid",
  ])
  func rejectsValuesThatAreNotPinnedDNSHosts(value: String) {
    do {
      _ = try RuntimeConfiguration(apiHost: value)
      Issue.record("Expected invalidAPIHost for \(value)")
    } catch let error as RuntimeConfigurationError {
      #expect(error == .invalidAPIHost)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }
}
