import AppKit
import CoreImage
import FlutterMacOS
import ImageIO
import Vision

/// On-device jersey / name OCR via Apple Vision (not generative AI).
class JerseyOcrPlugin: NSObject, FlutterPlugin {
  private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

  /// Two lanes so the loupe never cancels the frame scan:
  ///  • frame lane — one scan at a time; a newer frame bumps its generation
  ///    (and the loupe's, since loupe reads of the old frame are stale).
  ///  • loupe lane — a newer loupe position bumps only the loupe generation.
  ///  • prescan lane — background warm-up of upcoming frames at utility QoS;
  ///    never cancelled by (or cancelling) the other lanes.
  /// In-flight passes check their ticket between Vision requests.
  private let scanQueue = DispatchQueue(
    label: "caption_writer.jersey_ocr",
    qos: .userInitiated
  )
  private let loupeQueue = DispatchQueue(
    label: "caption_writer.jersey_ocr.loupe",
    qos: .userInteractive
  )
  private let prescanQueue = DispatchQueue(
    label: "caption_writer.jersey_ocr.prescan",
    qos: .utility
  )
  private let generationLock = NSLock()
  private var generation = 0
  private var loupeGeneration = 0

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "caption_writer/jersey_ocr",
      binaryMessenger: registrar.messenger
    )
    let instance = JerseyOcrPlugin()
    channel.setMethodCallHandler(instance.handle)
  }

  private struct Ticket {
    /// nil → prescan: always current.
    let frame: Int?
    let loupe: Int?
  }

  private func bumpGeneration(loupe: Bool, prescan: Bool) -> Ticket {
    if prescan { return Ticket(frame: nil, loupe: nil) }
    generationLock.lock()
    defer { generationLock.unlock() }
    if loupe {
      loupeGeneration += 1
      return Ticket(frame: generation, loupe: loupeGeneration)
    }
    generation += 1
    loupeGeneration += 1
    return Ticket(frame: generation, loupe: nil)
  }

  private func isCurrent(_ ticket: Ticket) -> Bool {
    guard let frame = ticket.frame else { return true }
    generationLock.lock()
    defer { generationLock.unlock() }
    guard generation == frame else { return false }
    if let loupe = ticket.loupe { return loupeGeneration == loupe }
    return true
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
    let sport = ((args["sport"] as? String) ?? "").lowercased()
    let isLoupe = roi != nil
    let isPrescan = !isLoupe && ((args["prescan"] as? Bool) ?? false)
    let ticket = bumpGeneration(loupe: isLoupe, prescan: isPrescan)
    let queue = isPrescan ? prescanQueue : (isLoupe ? loupeQueue : scanQueue)

    queue.async { [weak self] in
      guard let self else {
        DispatchQueue.main.async { result([]) }
        return
      }
      let hits = Self.recognizeText(
        path: path,
        maxPixelDimension: maxPx,
        customWords: customWords,
        regionOfInterest: roi,
        sport: sport,
        shouldContinue: { self.isCurrent(ticket) }
      )
      DispatchQueue.main.async {
        result(self.isCurrent(ticket) ? hits : [])
      }
    }
  }

  /// Returns `[{ text, confidence, boundingBox: {x,y,width,height} }]`.
  private static func recognizeText(
    path: String,
    maxPixelDimension: Int,
    customWords: [String],
    regionOfInterest: [String: Any]?,
    sport: String = "",
    shouldContinue: () -> Bool = { true }
  ) -> [[String: Any]] {
    guard shouldContinue() else { return [] }
    let cap = CGFloat(max(256, min(maxPixelDimension, 4096)))
    guard let fullImage = loadOrientedImage(path: path, maxPixelDimension: cap) else {
      return []
    }

    var merged: [[String: Any]] = []
    let names = nameLexicon(from: customWords)
    let preferHelmet = sport == "hockey"

    if let roi = parseRoi(regionOfInterest) {
      // Loupe: tight crop, heavy upscale, digit-first (user is aiming at a number).
      let focus = padRoi(roi, scale: 1.12)
      // Jersey tone around the loupe target (fabric dominates the ring).
      let loupeTone = sampleTone(fullImage, rect: padRoi(roi, scale: 2.2))
      defer {
        merged = tag(merged, region: "loupe", tone: loupeTone, onPerson: false)
      }
      if let crop = cropAndEnhance(fullImage, roi: focus, minLongEdge: 2200) {
        let digits = digitLexicon(from: customWords)
        // 1) White-on-dark first — navy/black jerseys are the common miss.
        if let lifted = enhanceWhiteOnDark(crop) {
          merged.append(contentsOf: runPass(
            cgImage: lifted,
            customWords: digits,
            roi: nil,
            boxMapRoi: focus,
            minTextHeight: 0.012,
            confidenceBoost: 0.12,
            minConfidence: 0.10,
            useLanguageCorrection: false,
            emitExtraCandidates: true
          ))
        }
        guard shouldContinue() else { return [] }
        // 2) Standard + inverted digit passes on the upscaled crop.
        merged.append(contentsOf: runDigitPasses(
          cgImage: crop,
          customWords: customWords,
          boxMapRoi: focus,
          includeNamePass: false,
          includeInverted: true
        ))
        guard shouldContinue() else { return [] }
        // 3) Hard-threshold passes — kills fabric texture, mesh and stripes
        // so a twill number becomes solid strokes. Both polarities.
        for inverted in [false, true] {
          guard shouldContinue() else { return [] }
          if let binary = enhanceHardThreshold(crop, inverted: inverted) {
            merged.append(contentsOf: runPass(
              cgImage: binary,
              customWords: digits,
              roi: nil,
              boxMapRoi: focus,
              minTextHeight: 0.012,
              confidenceBoost: 0.08,
              minConfidence: 0.10,
              useLanguageCorrection: false,
              emitExtraCandidates: true
            ))
          }
        }
        guard shouldContinue() else { return [] }
        // 4) Nameplate secondary. Language correction OFF — with it on,
        // Vision rewrites brands like "Bauer" into nearby roster names.
        if !names.isEmpty {
          merged.append(contentsOf: runPass(
            cgImage: crop,
            customWords: [],
            roi: nil,
            boxMapRoi: focus,
            minTextHeight: 0.010,
            confidenceBoost: 0.04,
            minConfidence: 0.26,
            useLanguageCorrection: false,
            emitExtraCandidates: true
          ))
        }
        guard shouldContinue() else { return [] }
        // 5) Wider context crop — a number half outside the loupe ring, or a
        // name arched above it, is still read. Lower boost: less targeted.
        let wide = padRoi(roi, scale: 1.9)
        if wide != focus,
           let wideCrop = cropAndEnhance(fullImage, roi: wide, minLongEdge: 2000) {
          if let lifted = enhanceWhiteOnDark(wideCrop) {
            merged.append(contentsOf: runPass(
              cgImage: lifted,
              customWords: digits,
              roi: nil,
              boxMapRoi: wide,
              minTextHeight: 0.012,
              confidenceBoost: 0.06,
              minConfidence: 0.12,
              useLanguageCorrection: false,
              emitExtraCandidates: true
            ))
          }
          guard shouldContinue() else { return [] }
          merged.append(contentsOf: runDigitPasses(
            cgImage: wideCrop,
            customWords: customWords,
            boxMapRoi: wide,
            includeNamePass: false,
            includeInverted: true
          ))
          guard shouldContinue() else { return [] }
          if !names.isEmpty {
            merged.append(contentsOf: runPass(
              cgImage: wideCrop,
              customWords: [],
              roi: nil,
              boxMapRoi: wide,
              minTextHeight: 0.010,
              confidenceBoost: 0.02,
              minConfidence: 0.28,
              useLanguageCorrection: false,
              emitExtraCandidates: true
            ))
          }
        }
      } else {
        merged.append(contentsOf: runPass(
          cgImage: fullImage,
          customWords: customWords,
          roi: focus,
          boxMapRoi: focus,
          minTextHeight: 0.008,
          confidenceBoost: 0.08,
          minConfidence: 0.18,
          useLanguageCorrection: !customWords.isEmpty,
          emitExtraCandidates: true
        ))
      }
    } else {
      let people = detectPeople(fullImage, includeHelmet: preferHelmet)
      if !people.isEmpty {
        // Read numbers and names on the players, not the boards behind them.
        for person in people {
          guard shouldContinue() else { return [] }
          merged.append(contentsOf: ocrPerson(
            fullImage,
            regions: person,
            customWords: customWords,
            names: names,
            preferHelmet: preferHelmet
          ))
        }
      } else {
        // No person found — fall back to the middle of the frame.
        let center = CGRect(x: 0.16, y: 0.10, width: 0.68, height: 0.80)
        merged.append(contentsOf: runPass(
          cgImage: fullImage,
          customWords: names.isEmpty ? customWords : names,
          roi: center,
          boxMapRoi: center,
          minTextHeight: 0.010,
          confidenceBoost: 0.06,
          minConfidence: 0.22,
          useLanguageCorrection: !names.isEmpty,
          emitExtraCandidates: true
        ))
        guard shouldContinue() else { return [] }

        if preferHelmet {
          // Hockey close-ups often crop the body; still hunt helmet stickers.
          let helmetBand = CGRect(x: 0.18, y: 0.52, width: 0.64, height: 0.38)
          merged.append(contentsOf: ocrHelmetRoi(
            fullImage,
            roi: helmetBand,
            customWords: customWords
          ))
          guard shouldContinue() else { return [] }
        }

        let torso = CGRect(x: 0.18, y: 0.20, width: 0.64, height: 0.52)
        if let torsoCrop = cropAndEnhance(fullImage, roi: torso, minLongEdge: 1600) {
          merged.append(contentsOf: runDigitPasses(
            cgImage: torsoCrop,
            customWords: customWords,
            boxMapRoi: torso,
            includeNamePass: true,
            includeInverted: true
          ))
        }
        guard shouldContinue() else { return [] }

        let nameplate = CGRect(x: 0.16, y: 0.40, width: 0.68, height: 0.34)
        if !names.isEmpty,
           let nameCrop = cropAndEnhance(fullImage, roi: nameplate, minLongEdge: 1400) {
          merged.append(contentsOf: runPass(
            cgImage: nameCrop,
            customWords: names,
            roi: nil,
            boxMapRoi: nameplate,
            minTextHeight: 0.011,
            confidenceBoost: 0.07,
            minConfidence: 0.18,
            useLanguageCorrection: true,
            emitExtraCandidates: true
          ))
        }
      }
    }

    // Dedupe by normalized text + roughly same box; keep best confidence.
    var bestByKey: [String: [String: Any]] = [:]
    for hit in merged {
      let text = (hit["text"] as? String ?? "").lowercased()
      guard !text.isEmpty else { continue }
      // Equipment brands, league marks, and rink sponsors are never a player.
      if isBrandOrSponsor(text) { continue }
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
      spatialScore($0, preferHelmet: preferHelmet) >
        spatialScore($1, preferHelmet: preferHelmet)
    }
    if out.count > 96 {
      return Array(out.prefix(96))
    }
    return out
  }

  /// Prefer large, central, high-confidence hits (jersey over board ads).
  private static func spatialScore(
    _ hit: [String: Any],
    preferHelmet: Bool = false
  ) -> Double {
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
    // Scorebugs and lower-thirds sit on the extreme top/bottom edges.
    let edgePenalty = (cy > 0.90 || cy < 0.06) ? 0.22 : 0
    // Wide, short runs are dasher ads ("B Be"), not a jersey number.
    let aspect = h > 0.001 ? w / h : 1
    let bannerPenalty = aspect > 2.8 ? 0.28 : 0
    // Hockey helmet stickers: small digits high in the player crop.
    var helmetBonus = 0.0
    if preferHelmet, isJerseyDigits(text), cy >= 0.55, area <= 0.05 {
      helmetBonus = 0.16
    }
    return conf * 0.55 + centerFactor * 0.25 + sizeFactor * 0.20
      + digitBonus + helmetBonus - edgePenalty - bannerPenalty
  }

  /// One detected player: body crop plus pose-derived sub-regions and the
  /// jersey tone sampled on the torso (home/away disambiguation downstream).
  private struct PersonRegions {
    let body: CGRect
    /// Between the shoulders and hips — back / chest number. Nil without pose.
    let torso: CGRect?
    let helmet: CGRect
    let sleeves: [CGRect]
    /// Fabric sample from the torso. Label is dark / light / unknown.
    let tone: FabricSample
    let fromPose: Bool
  }

  private static let unitRect = CGRect(x: 0, y: 0, width: 1, height: 1)

  /// Largest people in frame. Skips the distant crowd so boards behind them
  /// are not what gets read. Body pose (when found) tightens the torso,
  /// sleeve, and helmet crops to the actual skater instead of fixed bands.
  private static func detectPeople(
    _ image: CGImage,
    includeHelmet: Bool = false
  ) -> [PersonRegions] {
    let rectRequest = VNDetectHumanRectanglesRequest()
    if #available(macOS 12.0, *) {
      rectRequest.upperBodyOnly = false
    }
    let poseRequest = VNDetectHumanBodyPoseRequest()
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    do {
      try handler.perform([rectRequest, poseRequest])
    } catch {
      return []
    }
    let boxes = rectRequest.results?.map(\.boundingBox) ?? []
    let poses = poseRequest.results ?? []
    let readable = boxes.filter { $0.width >= 0.05 && $0.height >= 0.09 }
    let sorted = readable.sorted {
      ($0.width * $0.height) > ($1.width * $1.height)
    }

    var out: [PersonRegions] = []
    var usedPoses = Set<Int>()
    for raw in sorted.prefix(3) {
      let loose = raw.insetBy(dx: -raw.width * 0.18, dy: -raw.height * 0.18)
      var matched: VNHumanBodyPoseObservation?
      for (index, pose) in poses.enumerated() where !usedPoses.contains(index) {
        guard let anchor = poseAnchor(pose), loose.contains(anchor) else { continue }
        matched = pose
        usedPoses.insert(index)
        break
      }
      out.append(makeRegions(
        image,
        rawBody: raw,
        pose: matched,
        includeHelmet: includeHelmet
      ))
    }

    // Rectangle detector missed a tightly cropped skater but pose found one.
    if out.isEmpty {
      for (index, pose) in poses.enumerated() where !usedPoses.contains(index) {
        guard let body = poseBodyRect(pose) else { continue }
        out.append(makeRegions(
          image,
          rawBody: body,
          pose: pose,
          includeHelmet: includeHelmet
        ))
        if out.count >= 3 { break }
      }
    }
    return out
  }

  private static func joint(
    _ pose: VNHumanBodyPoseObservation,
    _ name: VNHumanBodyPoseObservation.JointName,
    minConfidence: Float = 0.25
  ) -> CGPoint? {
    guard let point = try? pose.recognizedPoint(name),
          point.confidence >= minConfidence else {
      return nil
    }
    return CGPoint(x: point.location.x, y: point.location.y)
  }

  /// Neck / shoulder midpoint used to pair a pose with a person rectangle.
  private static func poseAnchor(_ pose: VNHumanBodyPoseObservation) -> CGPoint? {
    if let neck = joint(pose, .neck) { return neck }
    if let l = joint(pose, .leftShoulder), let r = joint(pose, .rightShoulder) {
      return CGPoint(x: (l.x + r.x) / 2, y: (l.y + r.y) / 2)
    }
    return nil
  }

  /// Rough body rect from confident joints (fallback when no rectangle).
  private static func poseBodyRect(_ pose: VNHumanBodyPoseObservation) -> CGRect? {
    let names: [VNHumanBodyPoseObservation.JointName] = [
      .nose, .neck, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
      .leftWrist, .rightWrist, .leftHip, .rightHip, .leftKnee, .rightKnee,
    ]
    let points = names.compactMap { joint(pose, $0) }
    guard points.count >= 4,
          let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
          let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else {
      return nil
    }
    let w = max(0.06, maxX - minX)
    let h = max(0.10, maxY - minY)
    let rect = CGRect(x: minX - w * 0.2, y: minY - h * 0.1, width: w * 1.4, height: h * 1.3)
      .intersection(unitRect)
    return rect.width >= 0.05 && rect.height >= 0.09 ? rect : nil
  }

  private static func makeRegions(
    _ image: CGImage,
    rawBody: CGRect,
    pose: VNHumanBodyPoseObservation?,
    includeHelmet: Bool
  ) -> PersonRegions {
    let body = padPerson(rawBody, includeHelmet: includeHelmet)
    var torso: CGRect?
    var helmet = helmetRoi(body)
    var sleeves = sleeveRois(body)
    var fromPose = false

    if let pose,
       let ls = joint(pose, .leftShoulder),
       let rs = joint(pose, .rightShoulder) {
      let shoulderW = max(0.02, abs(ls.x - rs.x))
      let midX = (ls.x + rs.x) / 2
      let shoulderY = (ls.y + rs.y) / 2
      let hipY: CGFloat
      if let lh = joint(pose, .leftHip), let rh = joint(pose, .rightHip) {
        hipY = (lh.y + rh.y) / 2
      } else {
        hipY = shoulderY - shoulderW * 1.5
      }

      // Back / chest number sits between the shoulders and the hips.
      let torsoW = shoulderW * 1.5
      let torsoTop = shoulderY + shoulderW * 0.18
      let torsoBottom = min(hipY, shoulderY - shoulderW * 0.6) - shoulderW * 0.05
      let torsoRect = CGRect(
        x: midX - torsoW / 2,
        y: torsoBottom,
        width: torsoW,
        height: max(0.03, torsoTop - torsoBottom)
      ).intersection(unitRect)
      if torsoRect.width > 0.03, torsoRect.height > 0.03 {
        torso = torsoRect
        fromPose = true
      }

      // Sleeves: shoulder → elbow, padded for the arm's width.
      var poseSleeves: [CGRect] = []
      let arms: [(CGPoint, CGPoint?)] = [
        (ls, joint(pose, .leftElbow)),
        (rs, joint(pose, .rightElbow)),
      ]
      for (shoulder, elbowOpt) in arms {
        let outward: CGFloat = shoulder.x < midX ? -1 : 1
        let elbow = elbowOpt ?? CGPoint(
          x: shoulder.x + outward * shoulderW * 0.35,
          y: shoulder.y - shoulderW * 0.9
        )
        let minX = min(shoulder.x, elbow.x) - shoulderW * 0.34
        let maxX = max(shoulder.x, elbow.x) + shoulderW * 0.34
        let minY = min(shoulder.y, elbow.y) - shoulderW * 0.2
        let maxY = max(shoulder.y, elbow.y) + shoulderW * 0.24
        let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
          .intersection(unitRect)
        if rect.width > 0.025, rect.height > 0.025 {
          poseSleeves.append(rect)
        }
      }
      if !poseSleeves.isEmpty { sleeves = poseSleeves }

      // Helmet: around the head joints, or neck-up when the face is hidden.
      if includeHelmet {
        let headNames: [VNHumanBodyPoseObservation.JointName] = [
          .nose, .leftEye, .rightEye, .leftEar, .rightEar,
        ]
        let headPts = headNames.compactMap { joint(pose, $0, minConfidence: 0.2) }
        let neck = joint(pose, .neck) ?? CGPoint(x: midX, y: shoulderY)
        let headW = shoulderW * 1.0
        let headCenterX = headPts.isEmpty
          ? neck.x
          : headPts.map(\.x).reduce(0, +) / CGFloat(headPts.count)
        let headTopY = headPts.isEmpty
          ? neck.y + shoulderW * 0.95
          : (headPts.map(\.y).max() ?? neck.y) + shoulderW * 0.5
        let headBottomY = neck.y - shoulderW * 0.05
        let helmetRect = CGRect(
          x: headCenterX - headW / 2,
          y: headBottomY,
          width: headW,
          height: max(0.03, headTopY - headBottomY)
        ).intersection(unitRect)
        if helmetRect.width > 0.03, helmetRect.height > 0.03 {
          helmet = helmetRect
        }
      }
    }

    // Jersey tone: sample the torso (not sleeves/helmet — those carry logos).
    let toneRect = torso.map {
      $0.insetBy(dx: $0.width * 0.2, dy: $0.height * 0.15)
    } ?? CGRect(
      x: rawBody.midX - rawBody.width * 0.2,
      y: rawBody.minY + rawBody.height * 0.42,
      width: rawBody.width * 0.4,
      height: rawBody.height * 0.28
    )
    let tone = sampleTone(image, rect: toneRect.intersection(unitRect))

    return PersonRegions(
      body: body,
      torso: torso,
      helmet: helmet,
      sleeves: sleeves,
      tone: tone,
      fromPose: fromPose
    )
  }

  /// Torso fabric: median luminance plus the colour of pixels near that median.
  private struct FabricSample {
    let label: String
    let red: Double
    let green: Double
    let blue: Double
    let sampled: Bool

    static let unknown = FabricSample(
      label: "unknown", red: 0, green: 0, blue: 0, sampled: false
    )
  }

  /// Median luminance of a region → "dark" / "light" / "unknown". Numbers
  /// and logos are a small fraction of the torso so the median is the fabric.
  /// RGB is the average of pixels close to that median, so a number or crest
  /// does not tint the swatch.
  private static func sampleTone(_ image: CGImage, rect: CGRect) -> FabricSample {
    guard rect.width > 0.01, rect.height > 0.01 else { return .unknown }
    let imgW = CGFloat(image.width)
    let imgH = CGFloat(image.height)
    let crop = CGRect(
      x: rect.origin.x * imgW,
      y: (1.0 - rect.origin.y - rect.height) * imgH,
      width: rect.width * imgW,
      height: rect.height * imgH
    ).integral.intersection(CGRect(x: 0, y: 0, width: imgW, height: imgH))
    guard crop.width >= 4, crop.height >= 4,
          let cropped = image.cropping(to: crop) else {
      return .unknown
    }
    let side = 16
    guard let ctx = CGContext(
      data: nil,
      width: side,
      height: side,
      bitsPerComponent: 8,
      bytesPerRow: side * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return .unknown
    }
    ctx.interpolationQuality = .medium
    ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: side, height: side))
    guard let data = ctx.data else { return .unknown }
    let buf = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
    struct Px { let r, g, b, l: Double }
    var pixels: [Px] = []
    pixels.reserveCapacity(side * side)
    for i in 0..<(side * side) {
      let r = Double(buf[i * 4]) / 255
      let g = Double(buf[i * 4 + 1]) / 255
      let b = Double(buf[i * 4 + 2]) / 255
      pixels.append(Px(r: r, g: g, b: b, l: 0.2126 * r + 0.7152 * g + 0.0722 * b))
    }
    let median = pixels.map(\.l).sorted()[pixels.count / 2]
    var sr = 0.0, sg = 0.0, sb = 0.0, n = 0.0
    for px in pixels where abs(px.l - median) <= 0.08 {
      sr += px.r
      sg += px.g
      sb += px.b
      n += 1
    }
    if n < 1 {
      sr = pixels.map(\.r).reduce(0, +)
      sg = pixels.map(\.g).reduce(0, +)
      sb = pixels.map(\.b).reduce(0, +)
      n = Double(pixels.count)
    }
    let label: String
    if median < 0.40 { label = "dark" }
    else if median > 0.62 { label = "light" }
    else { label = "unknown" }
    return FabricSample(
      label: label,
      red: sr / n,
      green: sg / n,
      blue: sb / n,
      sampled: true
    )
  }

  /// Attach where-on-the-player + jersey tone to every hit from a pass.
  private static func tag(
    _ hits: [[String: Any]],
    region: String,
    tone: FabricSample,
    onPerson: Bool
  ) -> [[String: Any]] {
    hits.map { hit in
      var copy = hit
      copy["region"] = region
      copy["jerseyTone"] = tone.label
      copy["onPerson"] = onPerson
      if tone.sampled {
        copy["jerseyRed"] = tone.red
        copy["jerseyGreen"] = tone.green
        copy["jerseyBlue"] = tone.blue
      }
      return copy
    }
  }

  /// Body plus sleeves. A tight torso box misses a number sitting on the arm.
  /// For hockey, expand upward so helmet stickers stay inside the crop.
  private static func padPerson(
    _ person: CGRect,
    includeHelmet: Bool = false
  ) -> CGRect {
    let topExpand = includeHelmet ? person.height * 0.22 : 0
    let expanded = CGRect(
      x: person.origin.x - person.width * 0.28,
      y: person.origin.y + person.height * 0.05,
      width: person.width * 1.56,
      height: person.height * 0.92 + topExpand
    )
    let clamped = expanded.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    guard clamped.width > 0.04, clamped.height > 0.04 else { return person }
    return clamped
  }

  /// Top of the person box — helmet / headband sticker numbers (hockey).
  /// Vision origin is bottom-left, so the head is near [person.maxY].
  private static func helmetRoi(_ person: CGRect) -> CGRect {
    let height = max(0.04, person.height * 0.34)
    let width = max(0.04, person.width * 0.78)
    let x = person.midX - width * 0.5
    let y = person.maxY - height
    let rect = CGRect(x: x, y: y, width: width, height: height)
      .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    guard rect.width > 0.03, rect.height > 0.03 else { return person }
    return rect
  }

  /// Left and right arm bands, where a sleeve number like 92 usually sits.
  private static func sleeveRois(_ person: CGRect) -> [CGRect] {
    let y = person.origin.y + person.height * 0.18
    let height = person.height * 0.62
    let width = person.width * 0.46
    return [
      CGRect(x: person.minX, y: y, width: width, height: height),
      CGRect(x: person.maxX - width, y: y, width: width, height: height),
    ]
      .map { $0.intersection(CGRect(x: 0, y: 0, width: 1, height: 1)) }
      .filter { $0.width > 0.03 && $0.height > 0.04 }
  }

  /// Digit-first OCR on a helmet sticker crop (small, often light-on-dark).
  private static func ocrHelmetRoi(
    _ image: CGImage,
    roi: CGRect,
    customWords: [String]
  ) -> [[String: Any]] {
    guard let crop = cropAndEnhance(image, roi: roi, minLongEdge: 1200) else {
      return []
    }
    let digits = digitLexicon(from: customWords)
    var hits: [[String: Any]] = []
    // White / silver sticker digits on dark helmet shells.
    if let lifted = enhanceWhiteOnDark(crop) {
      hits.append(contentsOf: runPass(
        cgImage: lifted,
        customWords: digits,
        roi: nil,
        boxMapRoi: roi,
        minTextHeight: 0.022,
        confidenceBoost: 0.14,
        minConfidence: 0.10,
        useLanguageCorrection: false,
        emitExtraCandidates: true
      ))
    }
    hits.append(contentsOf: runDigitPasses(
      cgImage: crop,
      customWords: customWords,
      boxMapRoi: roi,
      includeNamePass: false,
      includeInverted: true
    ))
    // Dark digits on light stickers.
    if let inverted = enhanceForDigits(crop, inverted: true) {
      hits.append(contentsOf: runPass(
        cgImage: inverted,
        customWords: digits,
        roi: nil,
        boxMapRoi: roi,
        minTextHeight: 0.020,
        confidenceBoost: 0.10,
        minConfidence: 0.12,
        useLanguageCorrection: false,
        emitExtraCandidates: true
      ))
    }
    // Slight confidence bump so helmet digits outrank dasher ads.
    return hits.map { hit in
      guard isJerseyDigits(hit["text"] as? String ?? "") else { return hit }
      var copy = hit
      let conf = hit["confidence"] as? Double ?? 0
      copy["confidence"] = min(1.0, conf + 0.08)
      return copy
    }
  }

  private static func ocrPerson(
    _ image: CGImage,
    regions: PersonRegions,
    customWords: [String],
    names: [String],
    preferHelmet: Bool = false
  ) -> [[String: Any]] {
    let person = regions.body
    let tone = regions.tone
    guard let crop = cropAndEnhance(image, roi: person, minLongEdge: 1400) else {
      return []
    }
    var hits: [[String: Any]] = []

    // Pose torso: tight crop between shoulders and hips, heavier upscale.
    // This is where the big back number lives.
    if let torso = regions.torso,
       let torsoCrop = cropAndEnhance(image, roi: torso, minLongEdge: 1500) {
      var torsoHits = runDigitPasses(
        cgImage: torsoCrop,
        customWords: customWords,
        boxMapRoi: torso,
        includeNamePass: false,
        includeInverted: true
      )
      if let lifted = enhanceWhiteOnDark(torsoCrop) {
        torsoHits.append(contentsOf: runPass(
          cgImage: lifted,
          customWords: digitLexicon(from: customWords),
          roi: nil,
          boxMapRoi: torso,
          minTextHeight: 0.014,
          confidenceBoost: 0.10,
          minConfidence: 0.12,
          useLanguageCorrection: false,
          emitExtraCandidates: true
        ))
      }
      hits.append(contentsOf: tag(torsoHits, region: "torso", tone: tone, onPerson: true))
    }

    let bodyHits = runDigitPasses(
      cgImage: crop,
      customWords: customWords,
      boxMapRoi: person,
      includeNamePass: false,
      includeInverted: false
    )
    hits.append(contentsOf: tag(bodyHits, region: "body", tone: tone, onPerson: true))

    // White numbers on a dark jersey (the 92 on a navy sleeve).
    if let lifted = enhanceWhiteOnDark(crop) {
      let liftedHits = runPass(
        cgImage: lifted,
        customWords: digitLexicon(from: customWords),
        roi: nil,
        boxMapRoi: person,
        minTextHeight: 0.008,
        confidenceBoost: 0.06,
        minConfidence: 0.14,
        useLanguageCorrection: false,
        emitExtraCandidates: true
      )
      hits.append(contentsOf: tag(liftedHits, region: "body", tone: tone, onPerson: true))
    }

    // Hockey: always scan the helmet — sticker numbers are the common ID.
    if preferHelmet {
      let helmetHits = ocrHelmetRoi(
        image,
        roi: regions.helmet,
        customWords: customWords
      )
      hits.append(contentsOf: tag(helmetHits, region: "helmet", tone: tone, onPerson: true))
    }

    // Sleeves: hockey has numbers on both shoulders. With pose we know where
    // the arms are, so scan them always (not just when the back failed).
    let scanSleeves = regions.fromPose || !containsJerseyDigit(hits, minConfidence: 0.45)
    if scanSleeves {
      for sleeve in regions.sleeves {
        guard let sleeveCrop = cropAndEnhance(image, roi: sleeve, minLongEdge: 1000) else {
          continue
        }
        let prepared = enhanceWhiteOnDark(sleeveCrop) ?? sleeveCrop
        var sleeveHits = runPass(
          cgImage: prepared,
          customWords: digitLexicon(from: customWords),
          roi: nil,
          boxMapRoi: sleeve,
          minTextHeight: 0.02,
          confidenceBoost: 0.08,
          minConfidence: 0.12,
          useLanguageCorrection: false,
          emitExtraCandidates: true
        )
        if let inverted = enhanceForDigits(sleeveCrop, inverted: true) {
          sleeveHits.append(contentsOf: runPass(
            cgImage: inverted,
            customWords: digitLexicon(from: customWords),
            roi: nil,
            boxMapRoi: sleeve,
            minTextHeight: 0.02,
            confidenceBoost: 0.05,
            minConfidence: 0.14,
            useLanguageCorrection: false,
            emitExtraCandidates: true
          ))
        }
        hits.append(contentsOf: tag(sleeveHits, region: "sleeve", tone: tone, onPerson: true))
      }
    }

    if !containsJerseyDigit(hits, minConfidence: 0.4),
       let inverted = enhanceForDigits(crop, inverted: true) {
      let invertedHits = runPass(
        cgImage: inverted,
        customWords: digitLexicon(from: customWords),
        roi: nil,
        boxMapRoi: person,
        minTextHeight: 0.012,
        confidenceBoost: 0.02,
        minConfidence: 0.18,
        useLanguageCorrection: false,
        emitExtraCandidates: false
      )
      hits.append(contentsOf: tag(invertedHits, region: "body", tone: tone, onPerson: true))
    }

    if !names.isEmpty {
      // Nameplate is on the torso when we have pose; otherwise whole body.
      let nameRoi = regions.torso ?? person
      let nameSource: CGImage? = regions.torso == nil
        ? crop
        : cropAndEnhance(image, roi: nameRoi, minLongEdge: 1500)
      if let nameSource {
        let nameHits = runPass(
          cgImage: nameSource,
          customWords: names,
          roi: nil,
          boxMapRoi: nameRoi,
          minTextHeight: 0.012,
          confidenceBoost: 0.06,
          minConfidence: 0.18,
          useLanguageCorrection: true,
          emitExtraCandidates: true
        )
        hits.append(contentsOf: tag(nameHits, region: "torso", tone: tone, onPerson: true))
      }
    }
    return hits
  }

  /// Digit-biased passes. Language correction stays off so "8" is not rewritten as "B".
  private static func runDigitPasses(
    cgImage: CGImage,
    customWords: [String],
    boxMapRoi: CGRect,
    includeNamePass: Bool,
    includeInverted: Bool
  ) -> [[String: Any]] {
    let digits = digitLexicon(from: customWords)
    var hits: [[String: Any]] = []
    hits.append(contentsOf: runPass(
      cgImage: cgImage,
      customWords: digits,
      roi: nil,
      boxMapRoi: boxMapRoi,
      minTextHeight: 0.012,
      confidenceBoost: 0.08,
      minConfidence: 0.15,
      useLanguageCorrection: false,
      emitExtraCandidates: true
    ))
    if let contrast = enhanceForDigits(cgImage, inverted: false) {
      hits.append(contentsOf: runPass(
        cgImage: contrast,
        customWords: digits,
        roi: nil,
        boxMapRoi: boxMapRoi,
        minTextHeight: 0.010,
        confidenceBoost: 0.05,
        minConfidence: 0.14,
        useLanguageCorrection: false,
        emitExtraCandidates: true
      ))
    }
    if includeInverted, let inverted = enhanceForDigits(cgImage, inverted: true) {
      hits.append(contentsOf: runPass(
        cgImage: inverted,
        customWords: digits,
        roi: nil,
        boxMapRoi: boxMapRoi,
        minTextHeight: 0.010,
        confidenceBoost: 0.02,
        minConfidence: 0.18,
        useLanguageCorrection: false,
        emitExtraCandidates: false
      ))
    }
    let names = nameLexicon(from: customWords)
    if includeNamePass, !names.isEmpty {
      hits.append(contentsOf: runPass(
        cgImage: cgImage,
        customWords: names,
        roi: nil,
        boxMapRoi: boxMapRoi,
        minTextHeight: 0.014,
        confidenceBoost: 0.05,
        minConfidence: 0.20,
        useLanguageCorrection: true,
        emitExtraCandidates: false
      ))
    }
    return hits
  }

  private static func containsJerseyDigit(
    _ hits: [[String: Any]],
    minConfidence: Double
  ) -> Bool {
    for hit in hits {
      let conf = hit["confidence"] as? Double ?? 0
      if conf < minConfidence { continue }
      if isJerseyDigits(hit["text"] as? String ?? "") { return true }
    }
    return false
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
      request.automaticallyDetectsLanguage = false
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
    var letterAtoms: [LetterAtom] = []
    let candidateCount = emitExtraCandidates ? 4 : 2

    func appendHit(_ value: String, conf: Double, hitBox: CGRect) {
      out.append([
        "text": value,
        "confidence": conf,
        "boundingBox": [
          "x": Double(hitBox.origin.x),
          "y": Double(hitBox.origin.y),
          "width": Double(hitBox.size.width),
          "height": Double(hitBox.size.height),
        ] as [String: Double],
      ])
    }

    for observation in observations {
      let candidates = observation.topCandidates(candidateCount)
      guard !candidates.isEmpty else { continue }

      // Map observation box into full-image coords when the pass used a crop/ROI.
      var box = observation.boundingBox
      if let mapRoi = boxMapRoi {
        box = CGRect(
          x: mapRoi.origin.x + box.origin.x * mapRoi.size.width,
          y: mapRoi.origin.y + box.origin.y * mapRoi.size.height,
          width: box.size.width * mapRoi.size.width,
          height: box.size.height * mapRoi.size.height
        )
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

        appendHit(text, conf: confidence, hitBox: box)
        if index == 0, isSingleLetter(text) {
          letterAtoms.append(LetterAtom(text: text, confidence: confidence, box: box))
        }
        for token in splitTokens(text) where token != text {
          // Keep "23" from "JUDGE 23" and real name parts. Drop lone letters
          // ("B" from a board logo "B Be") so they are not re-read as digits.
          let hasDigit = token.range(of: #"\d"#, options: .regularExpression) != nil
          if !hasDigit && token.count < 3 { continue }
          appendHit(token, conf: confidence * 0.95, hitBox: box)
        }
        // Also emit digit-confused variants for 1–2 char tokens ("O"→"0").
        for variant in digitConfusionVariants(text) where variant != text {
          appendHit(variant, conf: confidence * 0.88, hitBox: box)
        }
      }
    }

    // Arched jersey names often come back as separate letters. Join a short run.
    for stitched in stitchLetterRuns(letterAtoms) {
      appendHit(stitched.text, conf: stitched.confidence, hitBox: stitched.box)
    }
    return out
  }

  private struct LetterAtom {
    let text: String
    let confidence: Double
    let box: CGRect
  }

  /// Join single-letter observations that sit on one baseline into a name.
  private static func stitchLetterRuns(_ letters: [LetterAtom]) -> [LetterAtom] {
    guard letters.count >= 3 else { return [] }
    let sorted = letters.sorted { $0.box.midX < $1.box.midX }
    var used = Set<Int>()
    var stitched: [LetterAtom] = []

    for start in sorted.indices where !used.contains(start) {
      var cluster = [sorted[start]]
      used.insert(start)
      var grew = true
      while grew {
        grew = false
        let last = cluster[cluster.count - 1]
        for nextIndex in sorted.indices where !used.contains(nextIndex) {
          let next = sorted[nextIndex]
          if next.box.midX + 0.004 < last.box.midX { continue }
          let height = max(last.box.height, next.box.height)
          guard height > 0.004 else { continue }
          let dy = abs(last.box.midY - next.box.midY)
          if dy > height * 0.7 { continue }
          let gap = next.box.minX - last.box.maxX
          if gap > height * 1.45 || gap < -height * 0.5 { continue }
          let shorter = min(last.box.height, next.box.height)
          let taller = max(last.box.height, next.box.height)
          if taller > 0, shorter / taller < 0.45 { continue }
          cluster.append(next)
          used.insert(nextIndex)
          grew = true
          break
        }
      }
      guard cluster.count >= 3, cluster.count <= 16 else { continue }
      let word = cluster.map(\.text).joined()
      guard word.count >= 3 else { continue }
      let avg = cluster.reduce(0.0) { $0 + $1.confidence } / Double(cluster.count)
      let minX = cluster.map(\.box.minX).min() ?? 0
      let minY = cluster.map(\.box.minY).min() ?? 0
      let maxX = cluster.map(\.box.maxX).max() ?? minX
      let maxY = cluster.map(\.box.maxY).max() ?? minY
      stitched.append(LetterAtom(
        text: word,
        confidence: min(1.0, avg * 0.94),
        box: CGRect(x: minX, y: minY, width: max(0.01, maxX - minX), height: max(0.01, maxY - minY))
      ))
    }
    return stitched
  }

  /// Last names only. Digit strings steal lexicon slots and language correction.
  private static func nameLexicon(from customWords: [String]) -> [String] {
    var out: [String] = []
    for word in customWords {
      let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.count < 2 { continue }
      let stripped = trimmed.replacingOccurrences(of: "#", with: "")
      if stripped.range(of: #"^\d+$"#, options: .regularExpression) != nil { continue }
      out.append(trimmed)
    }
    return Array(Set(out)).sorted()
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
    // "AI" on an Air Canada board must not become 41. Only fix a letter
    // when the read already contains a digit ("4I" → "41").
    guard text.range(of: #"\d"#, options: .regularExpression) != nil else { return [] }
    let map: [Character: Character] = [
      "O": "0", "o": "0", "Q": "0", "D": "0", "U": "0",
      "I": "1", "l": "1", "|": "1", "i": "1",
      "Z": "2", "z": "2",
      "E": "3",
      "A": "4", "H": "4",
      "S": "5", "s": "5",
      "G": "6", "b": "6", "C": "6",
      "T": "7", "Y": "7",
      "B": "8",
      "g": "9", "q": "9", "P": "9",
    ]
    // A lone "A" or "H" is usually a letter, not jersey 4.
    let ambiguousAlone: Set<Character> = ["A", "H", "E", "Y", "P", "U", "C"]
    if text.count == 1, let only = text.first, ambiguousAlone.contains(only) {
      return []
    }
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

  /// Grow a Vision ROI slightly so a number under the cursor isn't clipped.
  private static func padRoi(_ roi: CGRect, scale: CGFloat) -> CGRect {
    let grow = max(1.0, scale)
    let cx = roi.midX
    let cy = roi.midY
    let w = min(1.0, roi.width * grow)
    let h = min(1.0, roi.height * grow)
    let x = max(0, min(1 - w, cx - w * 0.5))
    let y = max(0, min(1 - h, cy - h * 0.5))
    let rect = CGRect(x: x, y: y, width: w, height: h)
      .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    return rect.width > 0.02 && rect.height > 0.02 ? rect : roi
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
    let cropRect = CGRect(x: pxX, y: pxYTop, width: pxW, height: pxH)
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

  /// Lift a dark frame so white sleeve numbers separate from a navy jersey.
  private static func enhanceWhiteOnDark(_ image: CGImage) -> CGImage? {
    let filtered = CIImage(cgImage: image)
      .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 1.35])
      .applyingFilter("CIColorControls", parameters: [
        kCIInputContrastKey: 1.85,
        kCIInputSaturationKey: 0,
        kCIInputBrightnessKey: 0.06,
      ])
      .applyingFilter("CIUnsharpMask", parameters: [
        kCIInputRadiusKey: 1.4,
        kCIInputIntensityKey: 0.75,
      ])
    return ciContext.createCGImage(filtered, from: filtered.extent)
  }

  /// Near-binary: grayscale, crushed to black/white with a mild blur first
  /// so jersey mesh and twill stitching don't survive as speckle.
  private static func enhanceHardThreshold(_ image: CGImage, inverted: Bool) -> CGImage? {
    var ciImage = CIImage(cgImage: image)
    if inverted {
      ciImage = ciImage.applyingFilter("CIColorInvert")
    }
    let filtered = ciImage
      .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.1])
      .applyingFilter("CIColorControls", parameters: [
        kCIInputContrastKey: 4.0,
        kCIInputSaturationKey: 0,
        kCIInputBrightnessKey: 0.0,
      ])
      .applyingFilter("CIUnsharpMask", parameters: [
        kCIInputRadiusKey: 2.0,
        kCIInputIntensityKey: 0.5,
      ])
      .cropped(to: ciImage.extent)
    return ciContext.createCGImage(filtered, from: filtered.extent)
  }

  /// Grayscale, high contrast, sharpened. Inverted pass turns white-on-dark
  /// numbers into the dark-on-light shape Vision reads more reliably.
  private static func enhanceForDigits(_ image: CGImage, inverted: Bool) -> CGImage? {
    var ciImage = CIImage(cgImage: image)
    if inverted {
      ciImage = ciImage.applyingFilter("CIColorInvert")
    }
    let filtered = ciImage
      .applyingFilter("CIColorControls", parameters: [
        kCIInputContrastKey: 1.65,
        kCIInputSaturationKey: 0,
        kCIInputBrightnessKey: inverted ? 0.04 : 0.02,
      ])
      .applyingFilter("CIUnsharpMask", parameters: [
        kCIInputRadiusKey: 1.5,
        kCIInputIntensityKey: 0.65,
      ])
    return ciContext.createCGImage(filtered, from: filtered.extent)
  }

  /// Exact (letters-only, lowercased) brand / league / sponsor words.
  /// Kept free of common surnames (Bell, Rogers) so a real nameplate survives.
  private static let brandBlocklist: Set<String> = [
    // Equipment
    "bauer", "ccm", "warrior", "sherwood", "reebok", "adidas", "fanatics",
    "easton", "jofa", "tackla", "koho", "graf", "vaughn", "brians", "itech",
    "oakley", "nike", "underarmour", "truehockey", "truetemper",
    // Equipment lines
    "vapor", "supreme", "nexus", "hyperlite", "jetspeed", "ribcor", "tacks",
    "covert", "alpha", "ultrasonic", "mach", "proto", "ag", "hzrdus",
    // Leagues / marks
    "nhl", "nhlpa", "ahl", "ohl", "whl", "qmjhl", "chl", "pwhl", "ncaa",
    "usntdp", "iihf", "echl", "ushl",
    // Sponsors common on boards / glass / helmet decals
    "scotiabank", "sportsnet", "gatorade", "budweiser", "molson", "labatt",
    "canadiantire", "timhortons", "pepsi", "cocacola", "geico", "verizon",
    "ticketmaster", "espn", "tsn", "rds", "honda", "toyota", "lexus",
    "discover", "enterprise", "dunkin", "mcdonalds", "kraken", "upperdeck",
  ]

  /// Partial matches for brands Vision often pads with junk ("Bauer.", "BAUER X").
  private static let brandStems: [String] = [
    "bauer", "warrior", "sherwood", "reebok", "adidas", "fanatics",
    "scotiabank", "sportsnet", "gatorade", "budweiser", "canadiantire",
    "timhortons", "ticketmaster",
  ]

  private static func isBrandOrSponsor(_ raw: String) -> Bool {
    let letters = raw.lowercased().filter { $0.isLetter }
    guard letters.count >= 2 else { return false }
    if brandBlocklist.contains(letters) { return true }
    for stem in brandStems where letters.contains(stem) && letters.count <= stem.count + 4 {
      return true
    }
    return false
  }

  private static func isSingleLetter(_ text: String) -> Bool {
    guard text.count == 1, let scalar = text.unicodeScalars.first else { return false }
    return CharacterSet.letters.contains(scalar)
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
