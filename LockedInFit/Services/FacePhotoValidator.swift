import Foundation
import UIKit
import Vision

/// Measurements extracted from a face photo with Vision + a small pixel pass.
/// All values are proxies used for photo-quality and self-comparison scoring;
/// never for inferring protected traits.
struct FacePhotoMetrics {
    var faceCount: Int = 0
    /// Fraction of the image area covered by the face bounding box (0–1).
    var faceAreaFraction: Double = 0
    /// Head rotation in degrees; large values mean an angled photo.
    var yawDegrees: Double = 0
    var rollDegrees: Double = 0
    /// Laplacian-variance sharpness of the whole frame. < ~40 reads blurry.
    var sharpness: Double = 0
    /// Mean luminance 0–1 of the frame.
    var meanLuminance: Double = 0.5
    /// Luminance standard deviation inside the face box (evenness proxy).
    var faceLuminanceStdDev: Double = 0
    /// 0–1, higher = more balanced left/right landmark placement.
    var landmarkSymmetry: Double = 0.5
    /// Fraction of expected landmark regions Vision found (visibility proxy).
    var landmarkCompleteness: Double = 0
    /// Face box width / height in pixel space. Tracked per-user for puffiness self-comparison.
    var widthHeightRatio: Double = 0
}

/// One validation finding. Blockers stop the flow; warnings lower confidence but allow saving.
struct FacePhotoIssue: Identifiable {
    enum Severity { case blocker, warning }
    let severity: Severity
    let message: String
    var id: String { message }
}

struct FacePhotoValidation {
    var metrics: FacePhotoMetrics
    var issues: [FacePhotoIssue]

    var blockers: [FacePhotoIssue] { issues.filter { $0.severity == .blocker } }
    var warnings: [FacePhotoIssue] { issues.filter { $0.severity == .warning } }
    var isUsable: Bool { blockers.isEmpty }
}

enum FacePhotoValidator {

    /// Runs Vision face/landmark detection plus a sharpness/exposure pixel pass.
    /// Heavy enough to keep off the main thread; call from a background task.
    static func validate(image: UIImage) -> FacePhotoValidation {
        var metrics = FacePhotoMetrics()
        var issues: [FacePhotoIssue] = []

        guard let cgImage = image.cgImage ?? image.resized(maxDimension: 1600).cgImage else {
            return FacePhotoValidation(metrics: metrics, issues: [
                FacePhotoIssue(severity: .blocker, message: "Couldn't read this image. Try a different photo.")
            ])
        }

        // Pixel pass: sharpness + exposure on a small grayscale copy.
        if let luma = grayscalePixels(cgImage: cgImage, maxDimension: 320) {
            metrics.sharpness = laplacianVariance(luma)
            metrics.meanLuminance = luma.pixels.reduce(0.0) { $0 + Double($1) } / Double(luma.pixels.count) / 255.0
        }

        // Vision pass: face rectangles + landmarks.
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgOrientation(from: image.imageOrientation))
        do {
            try handler.perform([request])
        } catch {
            return FacePhotoValidation(metrics: metrics, issues: [
                FacePhotoIssue(severity: .blocker, message: "Face detection failed. Try a clearer photo.")
            ])
        }

        let faces = request.results ?? []
        metrics.faceCount = faces.count

        guard let face = faces.max(by: { boxArea($0) < boxArea($1) }) else {
            issues.append(FacePhotoIssue(severity: .blocker, message: "No face detected. Use a front-facing photo with your face centered."))
            return FacePhotoValidation(metrics: metrics, issues: issues)
        }
        if faces.count > 1 {
            issues.append(FacePhotoIssue(severity: .warning, message: "Multiple faces detected; scoring uses the largest one. Solo photos track better."))
        }

        let box = face.boundingBox
        metrics.faceAreaFraction = Double(box.width * box.height)
        let pixelWidth = Double(box.width) * Double(cgImage.width)
        let pixelHeight = Double(box.height) * Double(cgImage.height)
        if pixelHeight > 0 { metrics.widthHeightRatio = pixelWidth / pixelHeight }
        metrics.yawDegrees = abs(face.yaw?.doubleValue ?? 0) * 180 / .pi
        metrics.rollDegrees = abs(face.roll?.doubleValue ?? 0) * 180 / .pi

        if let landmarks = face.landmarks {
            metrics.landmarkSymmetry = symmetryScore(landmarks: landmarks)
            metrics.landmarkCompleteness = completeness(landmarks: landmarks)
        }

        // Face-region luminance evenness.
        if let luma = grayscalePixels(cgImage: cgImage, maxDimension: 320) {
            metrics.faceLuminanceStdDev = regionLuminanceStdDev(luma, normalizedBox: box)
        }

        // Thresholds → issues.
        if metrics.sharpness < 18 {
            issues.append(FacePhotoIssue(severity: .blocker, message: "This photo is too blurry to compare over time. Hold steady and retake."))
        } else if metrics.sharpness < 45 {
            issues.append(FacePhotoIssue(severity: .warning, message: "Photo is slightly soft. A sharper shot improves tracking."))
        }
        if metrics.meanLuminance < 0.18 {
            issues.append(FacePhotoIssue(severity: .warning, message: "Photo is underexposed. Face a window or light source and retake if you can."))
        } else if metrics.meanLuminance > 0.85 {
            issues.append(FacePhotoIssue(severity: .warning, message: "Photo is overexposed. Step back from direct light."))
        }
        if metrics.faceAreaFraction < 0.035 {
            issues.append(FacePhotoIssue(severity: .warning, message: "Your face is small in the frame. Move closer so the face fills more of the photo."))
        }
        if metrics.yawDegrees > 20 || metrics.rollDegrees > 20 {
            issues.append(FacePhotoIssue(severity: .warning, message: "Face is angled. A straight-on, level photo compares best day to day."))
        }

        return FacePhotoValidation(metrics: metrics, issues: issues)
    }

    // MARK: - Vision helpers

    private static func boxArea(_ observation: VNFaceObservation) -> CGFloat {
        observation.boundingBox.width * observation.boundingBox.height
    }

    /// Left/right balance from eye and mouth landmarks relative to the face midline.
    /// A framing/pose proxy (0–1), not a judgment of facial structure.
    private static func symmetryScore(landmarks: VNFaceLandmarks2D) -> Double {
        guard let leftEye = centroid(landmarks.leftEye),
              let rightEye = centroid(landmarks.rightEye) else { return 0.5 }
        let eyeMidX = (leftEye.x + rightEye.x) / 2
        var deviations: [Double] = []
        if let nose = centroid(landmarks.nose) {
            deviations.append(abs(Double(nose.x - eyeMidX)))
        }
        if let lips = centroid(landmarks.outerLips) {
            deviations.append(abs(Double(lips.x - eyeMidX)))
        }
        // Eye level difference (roll leftover after Vision normalization).
        deviations.append(abs(Double(leftEye.y - rightEye.y)))
        guard !deviations.isEmpty else { return 0.5 }
        let mean = deviations.reduce(0, +) / Double(deviations.count)
        // 0 deviation → 1.0; 0.08 (in face-normalized units) → ~0.
        return max(0, min(1, 1 - mean / 0.08))
    }

    private static func completeness(landmarks: VNFaceLandmarks2D) -> Double {
        let regions: [VNFaceLandmarkRegion2D?] = [
            landmarks.leftEye, landmarks.rightEye, landmarks.nose,
            landmarks.outerLips, landmarks.leftEyebrow, landmarks.rightEyebrow,
            landmarks.faceContour
        ]
        let found = regions.compactMap { $0 }.filter { $0.pointCount > 0 }.count
        return Double(found) / Double(regions.count)
    }

    private static func centroid(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
        guard let region, region.pointCount > 0 else { return nil }
        let points = region.normalizedPoints
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(region.pointCount), y: sum.y / CGFloat(region.pointCount))
    }

    private static func cgOrientation(from orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    // MARK: - Pixel helpers

    struct GrayBuffer {
        let pixels: [UInt8]
        let width: Int
        let height: Int
    }

    private static func grayscalePixels(cgImage: CGImage, maxDimension: Int) -> GrayBuffer? {
        let scale = min(1, Double(maxDimension) / Double(max(cgImage.width, cgImage.height)))
        let width = max(1, Int(Double(cgImage.width) * scale))
        let height = max(1, Int(Double(cgImage.height) * scale))
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return GrayBuffer(pixels: pixels, width: width, height: height)
    }

    /// Variance of the 4-neighbor Laplacian: the standard cheap blur metric.
    private static func laplacianVariance(_ buffer: GrayBuffer) -> Double {
        let w = buffer.width, h = buffer.height
        guard w > 2, h > 2 else { return 0 }
        var values: [Double] = []
        values.reserveCapacity((w - 2) * (h - 2))
        let p = buffer.pixels
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let center = Double(p[y * w + x])
                let lap = Double(p[(y - 1) * w + x]) + Double(p[(y + 1) * w + x])
                    + Double(p[y * w + x - 1]) + Double(p[y * w + x + 1]) - 4 * center
                values.append(lap)
            }
        }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance
    }

    /// Luminance standard deviation inside a Vision-normalized box (origin bottom-left).
    private static func regionLuminanceStdDev(_ buffer: GrayBuffer, normalizedBox: CGRect) -> Double {
        let w = buffer.width, h = buffer.height
        let x0 = max(0, Int(normalizedBox.minX * CGFloat(w)))
        let x1 = min(w, Int(normalizedBox.maxX * CGFloat(w)))
        // Vision Y is bottom-up; CGContext raster is top-down.
        let y0 = max(0, Int((1 - normalizedBox.maxY) * CGFloat(h)))
        let y1 = min(h, Int((1 - normalizedBox.minY) * CGFloat(h)))
        guard x1 > x0, y1 > y0 else { return 0 }
        var values: [Double] = []
        values.reserveCapacity((x1 - x0) * (y1 - y0))
        for y in y0..<y1 {
            for x in x0..<x1 {
                values.append(Double(buffer.pixels[y * w + x]))
            }
        }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance.squareRoot() / 255.0
    }
}
