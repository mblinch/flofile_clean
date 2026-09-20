import AppKit
import FlutterMacOS

/// Bridges Flutter spell-check requests to macOS [NSSpellChecker].
public class MacSpellCheckPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "caption_writer/spell_check",
      binaryMessenger: registrar.messenger
    )
    let instance = MacSpellCheckPlugin()
    channel.setMethodCallHandler(instance.handle)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "check" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let args = call.arguments as? [String: Any],
          let text = args["text"] as? String else {
      result(FlutterError(code: "bad_args", message: "Expected text", details: nil))
      return
    }
    let localeTag = (args["locale"] as? String) ?? ""

    DispatchQueue.global(qos: .userInitiated).async {
      let spans = Self.checkSpelling(text: text, localeTag: localeTag)
      DispatchQueue.main.async {
        result(spans)
      }
    }
  }

  private static func checkSpelling(text: String, localeTag: String) -> [[String: Any]] {
    guard !text.isEmpty else { return [] }

    let checker = NSSpellChecker.shared
    let language = resolveLanguage(localeTag: localeTag, checker: checker)
    let nsText = text as NSString
    let length = nsText.length
    var starting = 0
    var out: [[String: Any]] = []

    while starting < length {
      let range = checker.checkSpelling(
        of: text,
        startingAt: starting,
        language: language,
        wrap: false,
        inSpellDocumentWithTag: 0,
        wordCount: nil
      )
      if range.location == NSNotFound {
        break
      }

      let guesses = checker.guesses(
        forWordRange: range,
        in: text,
        language: language,
        inSpellDocumentWithTag: 0
      ) ?? []

      out.append([
        "startIndex": range.location,
        "endIndex": range.location + range.length,
        "suggestions": Array(guesses.prefix(8)),
      ])
      starting = range.location + max(range.length, 1)
    }
    return out
  }

  private static func currentLanguage(checker: NSSpellChecker) -> String? {
    // Prefer the string property when available; fall back to the method form.
    let value = checker.value(forKey: "language")
    if let language = value as? String, !language.isEmpty {
      return language
    }
    return nil
  }

  private static func resolveLanguage(
    localeTag: String,
    checker: NSSpellChecker
  ) -> String? {
    let available = Set(checker.availableLanguages)
    var candidates: [String] = []
    let trimmed = localeTag.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
      candidates.append(trimmed)
      candidates.append(trimmed.replacingOccurrences(of: "-", with: "_"))
      if let dash = trimmed.split(separator: "-").first {
        candidates.append(String(dash))
      }
      if let under = trimmed.split(separator: "_").first {
        candidates.append(String(under))
      }
    }
    if let current = currentLanguage(checker: checker) {
      candidates.append(current)
    }
    candidates.append(contentsOf: ["en", "en_US", "en-US"])

    for candidate in candidates where available.contains(candidate) {
      return candidate
    }
    return currentLanguage(checker: checker)
  }
}
