import Foundation

public enum WoorisaiTextInput {
  public static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public static func normalizedCodePointCount(_ value: String) -> Int {
    normalized(value).unicodeScalars.count
  }
}
