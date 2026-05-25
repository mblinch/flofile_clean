import AppKit
import CoreImage
import FlutterMacOS
import ImageIO

/// Decodes JPEG/HEIC/etc. with system color management (ICC / wide gamut),
/// applies EXIF orientation, rasterizes to sRGB PNG for Flutter [Image.memory].
class ColorManagedPreviewPlugin: NSObject, FlutterPlugin {
  /// Reused context; Core Image color-matches source ICC → sRGB on render.
  private static let ciContext: CIContext = {
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    let working =
      CGColorSpace(name: CGColorSpace.extendedSRGB) ?? sRGB
    return CIContext(options: [
      .workingColorSpace: working,
      .outputColorSpace: sRGB,
      .cacheIntermediates: false,
    ])
  }()

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "caption_writer/color_managed_preview",
      binaryMessenger: registrar.messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "decodePng" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterError(code: "bad_args", message: "Expected path", details: nil))
        return
      }
      let maxPx = (args["maxPixelDimension"] as? NSNumber)?.intValue ?? 4096

      DispatchQueue.global(qos: .userInitiated).async {
        let data = Self.makePngPreview(path: path, maxPixelDimension: maxPx)
        DispatchQueue.main.async {
          if let data = data {
            result(FlutterStandardTypedData(bytes: data))
          } else {
            result(FlutterError(code: "decode_failed", message: "Could not decode image", details: path))
          }
        }
      }
    }
  }

  private static func makePngPreview(path: String, maxPixelDimension: Int) -> Data? {
    let cap = CGFloat(max(512, min(maxPixelDimension, 16384)))
    if let png = makePngViaCoreImage(path: path, maxPixelDimension: cap) {
      return png
    }
    if let png = makePngViaImageIO(path: path, maxPixelDimension: cap) {
      return png
    }
    return makePngViaAppKit(path: path, maxPixelDimension: cap)
  }

  /// Core Image: EXIF orientation + ICC-aware render to sRGB.
  private static func makePngViaCoreImage(path: String, maxPixelDimension: CGFloat) -> Data? {
    let url = URL(fileURLWithPath: path)
    guard var ciImage = CIImage(
      contentsOf: url,
      options: [.applyOrientationProperty: true]
    ) else {
      return nil
    }

    var extent = ciImage.extent
    guard extent.width > 1, extent.height > 1 else { return nil }

    let maxSide = max(extent.width, extent.height)
    if maxSide > maxPixelDimension {
      let scale = maxPixelDimension / maxSide
      ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
      extent = ciImage.extent
    }

    guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
          let cgImage = ciContext.createCGImage(ciImage, from: extent, format: .RGBA8, colorSpace: sRGB)
    else {
      return nil
    }

    return pngData(from: cgImage)
  }

  /// ImageIO thumbnail + draw into sRGB bitmap (ICC conversion on draw).
  private static func makePngViaImageIO(path: String, maxPixelDimension: CGFloat) -> Data? {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let src = CGImageSourceCreateWithURL(url, nil) else { return nil }

    let thumbOpts: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
    ]

    guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary) else {
      return nil
    }

    guard let oriented = drawIntoSRGB(cgImage: thumb) else { return nil }
    return pngData(from: oriented)
  }

  /// NSImage draw path; rasterize through sRGB context.
  private static func makePngViaAppKit(path: String, maxPixelDimension: CGFloat) -> Data? {
    let url = URL(fileURLWithPath: path)
    guard let source = NSImage(contentsOf: url) else { return nil }
    guard source.size.width > 0, source.size.height > 0 else { return nil }

    var drawSize = source.size
    let maxSide = max(drawSize.width, drawSize.height)
    if maxSide > maxPixelDimension {
      let scale = maxPixelDimension / maxSide
      drawSize = NSSize(
        width: floor(drawSize.width * scale),
        height: floor(drawSize.height * scale)
      )
    }

    guard let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: Int(drawSize.width),
      pixelsHigh: Int(drawSize.height),
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ) else {
      return nil
    }

    rep.size = drawSize
    NSGraphicsContext.saveGraphicsState()
    if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
      NSGraphicsContext.current = ctx
      ctx.imageInterpolation = .high
      ctx.shouldAntialias = true
      source.draw(
        in: NSRect(origin: .zero, size: drawSize),
        from: NSRect.zero,
        operation: .copy,
        fraction: 1.0
      )
      NSGraphicsContext.restoreGraphicsState()
    } else {
      NSGraphicsContext.restoreGraphicsState()
      return nil
    }

    guard let cgImage = rep.cgImage,
          let srgbImage = drawIntoSRGB(cgImage: cgImage) else {
      return rep.representation(using: .png, properties: [:])
    }
    return pngData(from: srgbImage)
  }

  /// Renders [cgImage] into an sRGB bitmap so embedded ICC profiles are applied.
  private static func drawIntoSRGB(cgImage: CGImage) -> CGImage? {
    let width = cgImage.width
    let height = cgImage.height
    guard width > 0, height > 0,
          let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else {
      return nil
    }

    guard let ctx = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: sRGB,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return nil
    }

    ctx.interpolationQuality = .high
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()
  }

  private static func pngData(from cgImage: CGImage) -> Data? {
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    return bitmap.representation(using: .png, properties: [:])
  }
}
