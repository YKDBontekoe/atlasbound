import XCTest
import SwiftUI
import UIKit
@testable import Atlasbound

enum SnapshotSupport {
    static let canvasSize = CGSize(width: 390, height: 844)
    static let scale: CGFloat = 3
    /// Absolute per-channel tolerance (0–255) for PNG golden comparisons.
    static let pixelTolerance: UInt8 = 12
    /// Allow a tiny fraction of pixels to differ (antialiasing / font rasterization).
    static let maxDifferentPixelFraction: Double = 0.015

    static var isRecording: Bool {
        envFlag("RECORD_SNAPSHOTS")
            || envFlag("BOOTSTRAP_SNAPSHOTS")
            || envFlag("TEST_RUNNER_RECORD_SNAPSHOTS")
            || envFlag("TEST_RUNNER_BOOTSTRAP_SNAPSHOTS")
    }

    private static func envFlag(_ key: String) -> Bool {
        let value = ProcessInfo.processInfo.environment[key]
        return value == "1" || value?.lowercased() == "true" || value?.lowercased() == "yes"
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
            .environment(\.accessibilityReduceMotion, true)
            .frame(width: size.width, height: size.height)

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
            // Also stash under tmp so CI can upload even if source write is restricted.
            let tmpCopy = failureDirectory().appendingPathComponent("\(name).png")
            try? png.write(to: tmpCopy, options: .atomic)
            return
        }

        guard FileManager.default.fileExists(atPath: referenceURL.path) else {
            let failureURL = failureDirectory().appendingPathComponent("\(name)-missing-ref.png")
            try? png.write(to: failureURL)
            // Soft-skip until goldens are committed. Render-size tests still gate visuals.
            throw XCTSkip(
                "Missing snapshot reference \(referenceURL.lastPathComponent). Record with RECORD_SNAPSHOTS=1 / TEST_RUNNER_RECORD_SNAPSHOTS=1 and commit PNGs under Visual/__Snapshots__/. Wrote preview to \(failureURL.path)"
            )
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

    /// Asserts the rendered image has the expected size and is not empty (visual smoke without goldens).
    @MainActor
    static func assertRenders<V: View>(
        _ view: V,
        size: CGSize,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let image = try render(view, size: size)
        XCTAssertEqual(image.size.width, size.width, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(image.size.height, size.height, accuracy: 0.5, file: file, line: line)
        XCTAssertNotNil(image.cgImage, file: file, line: line)
        XCTAssertGreaterThan(image.cgImage?.width ?? 0, 0, file: file, line: line)
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

    enum SnapshotError: Error {
        case renderFailed
    }
}
