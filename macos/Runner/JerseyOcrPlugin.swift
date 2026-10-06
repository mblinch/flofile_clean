import AppKit
import FlutterMacOS
import ImageIO
import Vision

/// On-device jersey / name OCR via Apple Vision (not generative AI).
class JerseyOcrPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "caption_writer/jersey_ocr",
      binaryMessenger: registrar.messenger
    )
    let instance = JerseyOcrPlugin()
    channel.setMethodCallHandler(instance.handle)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "recognize" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let args = call.arguments as? [String: Any],
          let path = args["path"] as? String else {
      result(FlutterError(code: "bad_args", message: "Expected path", details: nil))
      return
    }
    let maxPx = (args["maxPixelDimension"] as? NSNumber)?.intValue ?? 2400
    let customWords = (args["customWords"] as? [String]) ?? []
    // Optional Vision ROI, normalized, origin bottom-left: {x,y,width,height}
    let roi = args["regionOfInterest"] as? [String: Any]

    DispatchQueue.global(qos: .userInitiated).async {
      let hits = Self.recognizeText(
        path: path,
        maxPixelDimension: maxPx,
        customWords: customWords,
        regionOfInterest: roi
      )
      DispatchQueue.main.async {
        result(hits)
      }
    }
  }

  /// Returns `[{ text, confidence, boundingBox: {x,y,width,height} }]`.
  private static func recognizeText(
    path: String,
    maxPixelDimension: Int,
    customWords: [String],
    regionOfInterest: [String: Any]?
  ) -> [[String: Any]] {
    let cap = CGFloat(max(256, min(maxPixelDimension, 4096)))
    guard let cgImage = loadOrientedImage(path: path, maxPixelDimension: cap) else {
      return []
    }

    var merged: [[String: Any]] = []

    if let roi = parseRoi(regionOfInterest) {
      // Focused loupe / subject crop — highest priority.
      merged.append(contentsOf: runPass(
        cgImage: cgImage,
        customWords: customWords,
        roi: roi,
        minTextHeight: 0.01,
        confidenceBoost: 0.08,
        minConfidence: 0.22
      ))
    } else {
      // Pass 1: center subject (cuts rink-board ads / crowd text).
      let center = CGRect(x: 0.18, y: 0.12, width: 0.64, height: 0.76)
      merged.append(contentsOf: runPass(
        cgImage: cgImage,
        customWords: customWords,
        roi: center,
        minTextHeight: 0.012,
        confidenceBoost: 0.06,
        minConfidence: 0.24
      ))

      // Pass 2: full frame (catch edge subjects).
      merged.append(contentsOf: runPass(
        cgImage: cgImage,
        customWords: customWords,
        roi: nil,
        minTextHeight: 0.02,
        confidenceBoost: 0,
        minConfidence: 0.30
      ))
    }

    // Dedupe by normalized text + roughly same box; keep best confidence.
    var bestByKey: [String: [String: Any]] = [:]
    for hit in merged {
      let text = (hit["text"] as? String ?? "").lowercased()
      guard !text.isEmpty else { continue }
      let box = hit["boundingBox"] as? [String: Double] ?? [:]
      let qx = Int(((box["x"] ?? 0) * 20).rounded())
      let qy = Int(((box["y"] ?? 0) * 20).rounded())
      let key = "\(text)|\(qx)|\(qy)"
      let conf = hit["confidence"] as? Double ?? 0
      let prev = bestByKey[key]?["confidence"] as? Double ?? -1
      if conf > prev {
        bestByKey[key] = hit
      }
    }

    var out = Array(bestByKey.values)
    out.sort {
      spatialScore($0) > spatialScore($1)
    }
    if out.count > 72 {
      return Array(out.prefix(72))
    }
    return out
  }

  /// Prefer large, central, high-confidence hits (jersey over board ads).
  private static func spatialScore(_ hit: [String: Any]) -> Double {
    let conf = hit["confidence"] as? Double ?? 0
    let box = hit["boundingBox"] as? [String: Double] ?? [:]
    let x = box["x"] ?? 0
    let y = box["y"] ?? 0
    let w = box["width"] ?? 0
    let h = box["height"] ?? 0
    let cx = x + w * 0.5
    let cy = y + h * 0.5
    let centerDist = hypot(cx - 0.5, cy - 0.5) // 0 = center
    let centerFactor = max(0, 1.0 - centerDist * 1.35)
    let area = min(w * h, 0.25) // cap so huge banners don't dominate
    let sizeFactor = min(1.0, area / 0.02)
    let text = hit["text"] as? String ?? ""
    let digitBonus = isJerseyDigits(text) ? 0.12 : 0
    return conf * 0.55 + centerFactor * 0.25 + sizeFactor * 0.20 + digitBonus
  }

  private static func runPass(
    cgImage: CGImage,
    customWords: [String],
    roi: CGRect?,
    minTextHeight: Float,
    confidenceBoost: Double,
    minConfidence: Double
  ) -> [[String: Any]] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.recognitionLanguages = ["en-US"]
    request.minimumTextHeight = minTextHeight
    if !customWords.isEmpty {
      request.customWords = Array(customWords.prefix(200))
    }
    if let roi {
      request.regionOfInterest = roi
    }

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
      try handler.perform([request])
    } catch {
      return []
    }

    guard let observations = request.results else { return [] }
    var out: [[String: Any]] = []

    for observation in observations {
      let candidates = observation.topCandidates(3)
      guard let best = candidates.first else { continue }

      var chosen = best
      if !isJerseyDigits(best.string) {
        if let digitAlt = candidates.dropFirst().first(where: {
          isJerseyDigits($0.string) && Double($0.confidence) >= minConfidence
        }) {
          chosen = digitAlt
        }
      }

      let text = normalizeOcrText(chosen.string)
      guard !text.isEmpty, text.count <= 40 else { continue }
      let confidence = min(1.0, Double(chosen.confidence) + confidenceBoost)
      guard confidence >= minConfidence else { continue }

      let hasLetterOrDigit = text.unicodeScalars.contains {
        CharacterSet.alphanumerics.contains($0)
      }
      guard hasLetterOrDigit else { continue }

      // Map observation box (relative to ROI) into full-image coords when ROI set.
      var box = observation.boundingBox
      if let roi {
        box = CGRect(
          x: roi.origin.x + box.origin.x * roi.size.width,
          y: roi.origin.y + box.origin.y * roi.size.height,
          width: box.size.width * roi.size.width,
          height: box.size.height * roi.size.height
        )
      }

      func appendHit(_ value: String, conf: Double) {
        out.append([
          "text": value,
          "confidence": conf,
          "boundingBox": [
            "x": Double(box.origin.x),
            "y": Double(box.origin.y),
            "width": Double(box.size.width),
            "height": Double(box.size.height),
          ] as [String: Double],
        ])
      }

      appendHit(text, conf: confidence)
      for token in splitTokens(text) where token != text {
        appendHit(token, conf: confidence * 0.95)
      }
    }
    return out
  }

  private static func parseRoi(_ raw: [String: Any]?) -> CGRect? {
    guard let raw else { return nil }
    let x = (raw["x"] as? NSNumber)?.doubleValue
      ?? (raw["x"] as? Double)
    let y = (raw["y"] as? NSNumber)?.doubleValue
      ?? (raw["y"] as? Double)
    let w = (raw["width"] as? NSNumber)?.doubleValue
      ?? (raw["width"] as? Double)
    let h = (raw["height"] as? NSNumber)?.doubleValue
      ?? (raw["height"] as? Double)
    guard let x, let y, let w, let h, w > 0.02, h > 0.02 else { return nil }
    let rect = CGRect(x: x, y: y, width: w, height: h)
      .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    guard rect.width > 0.02, rect.height > 0.02 else { return nil }
    return rect
  }

  private static func normalizeOcrText(_ raw: String) -> String {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    while text.hasPrefix("#") {
      text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
    return text
  }

  private static func isJerseyDigits(_ raw: String) -> Bool {
    let text = normalizeOcrText(raw)
    guard let regex = try? NSRegularExpression(pattern: "^\\d{1,2}$") else {
      return false
    }
    let range = NSRange(location: 0, length: (text as NSString).length)
    return regex.firstMatch(in: text, options: [], range: range) != nil
  }

  private static func splitTokens(_ text: String) -> [String] {
    text
      .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "/" })
      .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
      .filter { !$0.isEmpty && $0.count <= 40 }
  }

  private static func loadOrientedImage(
    path: String,
    maxPixelDimension: CGFloat
  ) -> CGImage? {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let src = CGImageSourceCreateWithURL(url, nil) else { return nil }

    let thumbOpts: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
    ]
    return CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary)
  }
}
