import AppKit
import CoreImage
import FlutterMacOS
import ImageIO
import Vision

/// On-device jersey / name OCR via Apple Vision (not generative AI).
class JerseyOcrPlugin: NSObject, FlutterPlugin {
  private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

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
    let maxPx = (args["maxPixelDimension"] as? NSNumber)?.intValue ?? 2800
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
    guard let fullImage = loadOrientedImage(path: path, maxPixelDimension: cap) else {
      return []
    }

    var merged: [[String: Any]] = []

    if let roi = parseRoi(regionOfInterest) {
      // Loupe / focused crop: upscale + contrast, then OCR the crop itself.
      if let crop = cropAndEnhance(fullImage, roi: roi, minLongEdge: 900) {
        merged.append(contentsOf: runPass(
          cgImage: crop,
          customWords: customWords,
          roi: nil,
          boxMapRoi: roi,
          minTextHeight: 0.018,
          confidenceBoost: 0.10,
          minConfidence: 0.18,
          useLanguageCorrection: !customWords.isEmpty,
          emitExtraCandidates: true
        ))
        // Digit-friendly pass (no language model rewriting "8" → "B", etc.).
        merged.append(contentsOf: runPass(
          cgImage: crop,
          customWords: digitLexicon(from: customWords),
          roi: nil,
          boxMapRoi: roi,
          minTextHeight: 0.014,
          confidenceBoost: 0.06,
          minConfidence: 0.16,
          useLanguageCorrection: false,
          emitExtraCandidates: true
        ))
      } else {
        merged.append(contentsOf: runPass(
          cgImage: fullImage,
          customWords: customWords,
          roi: roi,
          boxMapRoi: roi,
          minTextHeight: 0.008,
          confidenceBoost: 0.08,
          minConfidence: 0.20,
          useLanguageCorrection: !customWords.isEmpty,
          emitExtraCandidates: true
        ))
      }
    } else {
      // Pass 1: center subject with roster bias (names + numbers).
      let center = CGRect(x: 0.16, y: 0.10, width: 0.68, height: 0.80)
      merged.append(contentsOf: runPass(
        cgImage: fullImage,
        customWords: customWords,
        roi: center,
        boxMapRoi: center,
        minTextHeight: 0.010,
        confidenceBoost: 0.06,
        minConfidence: 0.22,
        useLanguageCorrection: !customWords.isEmpty,
        emitExtraCandidates: true
      ))

      // Pass 2: torso band — where jersey numbers usually sit.
      let torso = CGRect(x: 0.22, y: 0.28, width: 0.56, height: 0.44)
      if let torsoCrop = cropAndEnhance(fullImage, roi: torso, minLongEdge: 1200) {
        merged.append(contentsOf: runPass(
          cgImage: torsoCrop,
          customWords: digitLexicon(from: customWords),
          roi: nil,
          boxMapRoi: torso,
          minTextHeight: 0.020,
          confidenceBoost: 0.08,
          minConfidence: 0.18,
          useLanguageCorrection: false,
          emitExtraCandidates: true
        ))
        if !customWords.isEmpty {
          merged.append(contentsOf: runPass(
            cgImage: torsoCrop,
            customWords: customWords,
            roi: nil,
            boxMapRoi: torso,
            minTextHeight: 0.018,
            confidenceBoost: 0.05,
            minConfidence: 0.20,
            useLanguageCorrection: true,
            emitExtraCandidates: false
          ))
        }
      }

      // Pass 3: full frame (edge subjects / board names as last resort).
      merged.append(contentsOf: runPass(
        cgImage: fullImage,
        customWords: customWords,
        roi: nil,
        boxMapRoi: nil,
        minTextHeight: 0.018,
        confidenceBoost: 0,
        minConfidence: 0.28,
        useLanguageCorrection: !customWords.isEmpty,
        emitExtraCandidates: false
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
    if out.count > 96 {
      return Array(out.prefix(96))
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
    let digitBonus = isJerseyDigits(text) ? 0.14 : 0
    return conf * 0.55 + centerFactor * 0.25 + sizeFactor * 0.20 + digitBonus
  }

  private static func runPass(
    cgImage: CGImage,
    customWords: [String],
    roi: CGRect?,
    boxMapRoi: CGRect?,
    minTextHeight: Float,
    confidenceBoost: Double,
    minConfidence: Double,
    useLanguageCorrection: Bool,
    emitExtraCandidates: Bool
  ) -> [[String: Any]] {
    let request = VNRecognizeTextRequest()
    if #available(macOS 13.0, *) {
      request.revision = VNRecognizeTextRequestRevision3
    }
    request.recognitionLevel = .accurate
    // Apple ignores customWords unless language correction is on.
    request.usesLanguageCorrection = useLanguageCorrection
    request.recognitionLanguages = ["en-US"]
    request.minimumTextHeight = minTextHeight
    if useLanguageCorrection, !customWords.isEmpty {
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
    let candidateCount = emitExtraCandidates ? 4 : 2

    for observation in observations {
      let candidates = observation.topCandidates(candidateCount)
      guard !candidates.isEmpty else { continue }

      // Map observation box into full-image coords when the pass used a crop/ROI.
      var box = observation.boundingBox
      if let mapRoi = boxMapRoi {
        if roi != nil {
          // Box is relative to request ROI on the full image.
          box = CGRect(
            x: mapRoi.origin.x + box.origin.x * mapRoi.size.width,
            y: mapRoi.origin.y + box.origin.y * mapRoi.size.height,
            width: box.size.width * mapRoi.size.width,
            height: box.size.height * mapRoi.size.height
          )
        } else {
          // Box is relative to an upscaled crop of mapRoi.
          box = CGRect(
            x: mapRoi.origin.x + box.origin.x * mapRoi.size.width,
            y: mapRoi.origin.y + box.origin.y * mapRoi.size.height,
            width: box.size.width * mapRoi.size.width,
            height: box.size.height * mapRoi.size.height
          )
        }
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

      for (index, candidate) in candidates.enumerated() {
        let text = normalizeOcrText(candidate.string)
        guard !text.isEmpty, text.count <= 40 else { continue }

        let rankPenalty = Double(index) * 0.04
        var confidence = min(1.0, Double(candidate.confidence) + confidenceBoost - rankPenalty)
        if isJerseyDigits(text) {
          confidence = min(1.0, confidence + 0.04)
        }
        guard confidence >= minConfidence else { continue }

        let hasLetterOrDigit = text.unicodeScalars.contains {
          CharacterSet.alphanumerics.contains($0)
        }
        guard hasLetterOrDigit else { continue }

        appendHit(text, conf: confidence)
        for token in splitTokens(text) where token != text {
          appendHit(token, conf: confidence * 0.95)
        }
        // Also emit digit-confused variants for 1–2 char tokens ("O"→"0").
        for variant in digitConfusionVariants(text) where variant != text {
          appendHit(variant, conf: confidence * 0.88)
        }
      }
    }
    return out
  }

  /// Jersey numbers from the roster lexicon (for digit-biased passes).
  private static func digitLexicon(from customWords: [String]) -> [String] {
    var out: [String] = []
    for word in customWords {
      let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.hasPrefix("#") {
        let digits = String(trimmed.dropFirst())
        if digits.range(of: #"^\d{1,2}$"#, options: .regularExpression) != nil {
          out.append(trimmed)
          out.append(digits)
        }
      } else if trimmed.range(of: #"^\d{1,2}$"#, options: .regularExpression) != nil {
        out.append(trimmed)
        out.append("#\(trimmed)")
      }
    }
    // Always include single digits — common jersey OCR misses.
    for d in 0...9 {
      out.append("\(d)")
      out.append("#\(d)")
    }
    return Array(Set(out)).sorted()
  }

  private static func digitConfusionVariants(_ raw: String) -> [String] {
    let text = normalizeOcrText(raw)
    guard text.count >= 1, text.count <= 2 else { return [] }
    let map: [Character: Character] = [
      "O": "0", "o": "0", "Q": "0", "D": "0",
      "I": "1", "l": "1", "|": "1", "i": "1",
      "Z": "2", "z": "2",
      "S": "5", "s": "5",
      "G": "6", "b": "6",
      "T": "7",
      "B": "8",
      "g": "9", "q": "9",
    ]
    var converted = ""
    var changed = false
    for ch in text {
      if ch.isNumber {
        converted.append(ch)
      } else if let digit = map[ch] {
        converted.append(digit)
        changed = true
      } else {
        return []
      }
    }
    guard changed, converted.range(of: #"^\d{1,2}$"#, options: .regularExpression) != nil else {
      return []
    }
    return [converted]
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

  /// Crop a normalized Vision ROI (origin bottom-left) and upscale + contrast-boost.
  private static func cropAndEnhance(
    _ image: CGImage,
    roi: CGRect,
    minLongEdge: CGFloat
  ) -> CGImage? {
    let imgW = CGFloat(image.width)
    let imgH = CGFloat(image.height)
    // Vision: origin bottom-left → CGImage: origin top-left.
    let pxX = roi.origin.x * imgW
    let pxW = roi.size.width * imgW
    let pxH = roi.size.height * imgH
    let pxYTop = (1.0 - roi.origin.y - roi.size.height) * imgH
    var cropRect = CGRect(x: pxX, y: pxYTop, width: pxW, height: pxH)
      .integral
      .intersection(CGRect(x: 0, y: 0, width: imgW, height: imgH))
    guard cropRect.width >= 8, cropRect.height >= 8,
          let cropped = image.cropping(to: cropRect) else {
      return nil
    }

    var working: CGImage = cropped
    let longEdge = max(CGFloat(cropped.width), CGFloat(cropped.height))
    if longEdge < minLongEdge {
      let scale = minLongEdge / longEdge
      let newW = max(1, Int((CGFloat(cropped.width) * scale).rounded()))
      let newH = max(1, Int((CGFloat(cropped.height) * scale).rounded()))
      if let scaled = resize(cropped, width: newW, height: newH) {
        working = scaled
      }
    }

    return enhanceContrast(working) ?? working
  }

  private static func resize(_ image: CGImage, width: Int, height: Int) -> CGImage? {
    guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
      return nil
    }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()
  }

  private static func enhanceContrast(_ image: CGImage) -> CGImage? {
    let ciImage = CIImage(cgImage: image)
    let filtered = ciImage
      .applyingFilter("CIColorControls", parameters: [
        kCIInputContrastKey: 1.18,
        kCIInputSaturationKey: 0.85,
        kCIInputBrightnessKey: 0.02,
      ])
      .applyingFilter("CIUnsharpMask", parameters: [
        kCIInputRadiusKey: 1.2,
        kCIInputIntensityKey: 0.45,
      ])
    return ciContext.createCGImage(filtered, from: filtered.extent)
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
