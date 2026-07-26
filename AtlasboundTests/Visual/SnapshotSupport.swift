import XCTest
import SwiftUI
import UIKit
@testable import Atlasbound

enum SnapshotSupport {
    static let canvasSize = CGSize(width: 390, height: 844)
    static let scale: CGFloat = 3
    /// Absolute per-channel tolerance (0–255) for PNG golden comparisons.
    static let pixelTolerance: UInt8 = 8
    /// Allow a tiny fraction of pixels to differ (antialiasing / font rasterization).
    static let maxDifferentPixelFraction: Double = 0.01

    static var isRecording: Bool {
        ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
            || ProcessInfo.processInfo.environment["BOOTSTRAP_SNAPSHOTS"] == "1"
    }

    static func referenceDirectory(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__", isDirectory: true)
    }

    static func failureDirectory() -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AtlasboundSnapshotFailures", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    @MainActor
    static func render<V: View>(_ view: V, size: CGSize = canvasSize) throws -> UIImage {
        let wrapped = view
            .environment(\.colorScheme, .light)
            .environment(\.locale, Locale(identifier: "en_US"))
            .frame(width: size.width, height: size.height)
            .background(AtlasTheme.canvas)

        let renderer = ImageRenderer(content: wrapped)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)

        guard let image = renderer.uiImage else {
            throw SnapshotError.renderFailed
        }
        return image
    }

    @MainActor
    static func assertSnapshot<V: View>(
        of view: V,
        named name: String,
        size: CGSize = canvasSize,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let image = try render(view, size: size)
        let directory = referenceDirectory(file: file)
        let referenceURL = directory.appendingPathComponent("\(name).png")

        guard let png = image.pngData() else {
            XCTFail("Failed to encode PNG for \(name)", file: file, line: line)
            return
        }

        if isRecording {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: referenceURL, options: .atomic)
            return
        }

        guard FileManager.default.fileExists(atPath: referenceURL.path) else {
            let failureURL = failureDirectory().appendingPathComponent("\(name)-missing-ref.png")
            try? png.write(to: failureURL)
            XCTFail(
                "Missing snapshot reference \(referenceURL.path). Run with RECORD_SNAPSHOTS=1 to create it. Wrote \(failureURL.path)",
                file: file,
                line: line
            )
            return
        }

        let referenceData = try Data(contentsOf: referenceURL)
        guard let referenceImage = UIImage(data: referenceData) else {
            XCTFail("Could not decode reference PNG \(referenceURL.path)", file: file, line: line)
            return
        }

        if let mismatch = compare(image, referenceImage) {
            let failureURL = failureDirectory().appendingPathComponent("\(name)-failed.png")
            try? png.write(to: failureURL)
            XCTFail("\(mismatch) Diff written to \(failureURL.path)", file: file, line: line)
        }
    }

    /// Samples a few pixels and asserts they are close to expected theme colors (no golden file required).
    @MainActor
    static func assertThemePresence<V: View>(
        of view: V,
        expectedColors: [(CGPoint, UIColor)],
        size: CGSize,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let image = try render(view, size: size)
        guard let cgImage = image.cgImage else {
            XCTFail("No CGImage for theme sample", file: file, line: line)
            return
        }

        for (point, expected) in expectedColors {
            let px = Int(point.x * scale)
            let py = Int(point.y * scale)
            guard let actual = pixelColor(in: cgImage, x: px, y: py) else {
                XCTFail("Could not sample pixel at \(point)", file: file, line: line)
                continue
            }
            XCTAssertTrue(
                colorsMatch(actual, expected, tolerance: 40),
                "Theme color mismatch at \(point): got \(actual) expected \(expected)",
                file: file,
                line: line
            )
        }
    }

    private static func compare(_ actual: UIImage, _ reference: UIImage) -> String? {
        guard let actualCG = actual.cgImage, let referenceCG = reference.cgImage else {
            return "Missing CGImage for comparison"
        }
        guard actualCG.width == referenceCG.width, actualCG.height == referenceCG.height else {
            return "Size mismatch actual=\(actualCG.width)x\(actualCG.height) reference=\(referenceCG.width)x\(referenceCG.height)"
        }

        let width = actualCG.width
        let height = actualCG.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let total = width * height

        var actualBytes = [UInt8](repeating: 0, count: total * bytesPerPixel)
        var referenceBytes = [UInt8](repeating: 0, count: total * bytesPerPixel)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard
            let actualContext = CGContext(
                data: &actualBytes,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ),
            let referenceContext = CGContext(
                data: &referenceBytes,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        else {
            return "Failed to create bitmap contexts"
        }

        actualContext.draw(actualCG, in: CGRect(x: 0, y: 0, width: width, height: height))
        referenceContext.draw(referenceCG, in: CGRect(x: 0, y: 0, width: width, height: height))

        var different = 0
        for index in stride(from: 0, to: total * bytesPerPixel, by: bytesPerPixel) {
            let dr = abs(Int(actualBytes[index]) - Int(referenceBytes[index]))
            let dg = abs(Int(actualBytes[index + 1]) - Int(referenceBytes[index + 1]))
            let db = abs(Int(actualBytes[index + 2]) - Int(referenceBytes[index + 2]))
            let da = abs(Int(actualBytes[index + 3]) - Int(referenceBytes[index + 3]))
            if dr > Int(pixelTolerance) || dg > Int(pixelTolerance) || db > Int(pixelTolerance) || da > Int(pixelTolerance) {
                different += 1
            }
        }

        let fraction = Double(different) / Double(total)
        if fraction > maxDifferentPixelFraction {
            return String(format: "Pixel mismatch %.2f%% (limit %.2f%%)", fraction * 100, maxDifferentPixelFraction * 100)
        }
        return nil
    }

    private static func pixelColor(in image: CGImage, x: Int, y: Int) -> UIColor? {
        guard x >= 0, y >= 0, x < image.width, y < image.height else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: -x, y: -y, width: image.width, height: image.height))
        return UIColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: CGFloat(pixel[3]) / 255
        )
    }

    private static func colorsMatch(_ a: UIColor, _ b: UIColor, tolerance: CGFloat) -> Bool {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let scale: CGFloat = 255
        return abs(ar - br) * scale <= tolerance
            && abs(ag - bg) * scale <= tolerance
            && abs(ab - bb) * scale <= tolerance
    }

    enum SnapshotError: Error {
        case renderFailed
    }
}

extension UIColor {
    static var atlasBlue: UIColor {
        UIColor(red: 0.20, green: 0.48, blue: 0.98, alpha: 1)
    }

    static var atlasCanvas: UIColor {
        UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1)
    }

    static var atlasTeal: UIColor {
        UIColor(red: 0.35, green: 0.78, blue: 0.72, alpha: 1)
    }
}
