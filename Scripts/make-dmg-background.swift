// Renders the background of the MetriBar disk image window as a Retina TIFF.
//
// Usage: xcrun swift Scripts/make-dmg-background.swift Resources/DiskImage/background.tiff
//
// The layout constants must match Scripts/make-dmg.sh: a 660 × 400 pt window
// with the app icon centered at (180, 190) and Applications at (480, 190).

import AppKit
import SwiftUI

let canvas = CGSize(width: 660, height: 400)
let appCenter = CGPoint(x: 180, y: 190)
let applicationsCenter = CGPoint(x: 480, y: 190)

/// Finder draws icon labels in black on any custom background, in light and dark
/// appearance alike, so the background and the glass plates behind the labels are light.
struct Background: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.84, green: 0.91, blue: 1.00), Color(red: 0.90, green: 0.86, blue: 0.99)],
                startPoint: .topLeading, endPoint: .bottomTrailing)

            // Soft light, like a refraction behind glass.
            Circle()
                .fill(Color(red: 0.36, green: 0.68, blue: 0.98).opacity(0.55))
                .frame(width: 360, height: 360)
                .blur(radius: 90)
                .position(x: 120, y: 40)
            Circle()
                .fill(Color(red: 0.68, green: 0.52, blue: 0.96).opacity(0.45))
                .frame(width: 340, height: 340)
                .blur(radius: 90)
                .position(x: 560, y: 380)

            glassPlate.position(appCenter)
            glassPlate.position(applicationsCenter)
            arrow.position(x: (appCenter.x + applicationsCenter.x) / 2, y: appCenter.y)

            Text("Drag MetriBar to Applications to install")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(red: 0.15, green: 0.20, blue: 0.36).opacity(0.80))
                .position(x: canvas.width / 2, y: 352)
        }
        .frame(width: canvas.width, height: canvas.height)
        .clipped()
    }

    /// A rounded pane of glass: translucent body, bright rim at the top, soft shadow.
    private var glassPlate: some View {
        RoundedRectangle(cornerRadius: 40, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.white.opacity(0.70), .white.opacity(0.32)],
                    startPoint: .top, endPoint: .bottom)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.95), .white.opacity(0.35), .white.opacity(0.70)],
                            startPoint: .top, endPoint: .bottom),
                        lineWidth: 1.2)
            )
            .frame(width: 184, height: 204)
            .shadow(color: Color(red: 0.12, green: 0.20, blue: 0.50).opacity(0.18), radius: 20, y: 10)
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(Color(red: 0.10, green: 0.36, blue: 0.82))
            .frame(width: 64, height: 64)
            .background(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.80), .white.opacity(0.40)],
                            startPoint: .top, endPoint: .bottom)
                    )
                    .overlay(
                        Circle().strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.95), .white.opacity(0.35), .white.opacity(0.70)],
                                startPoint: .top, endPoint: .bottom),
                            lineWidth: 1.2)
                    )
                    .shadow(color: Color(red: 0.12, green: 0.20, blue: 0.50).opacity(0.16), radius: 10, y: 6)
            )
    }
}

@MainActor
func render(scale: CGFloat) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: Background())
    renderer.scale = scale
    guard let cgImage = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    // Finder uses the point size to place the background, so 2x must report 660 × 400.
    rep.size = canvas
    return rep
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    print("Usage: xcrun swift Scripts/make-dmg-background.swift <output .tiff>")
    exit(1)
}
let output = URL(fileURLWithPath: arguments[1])
try MainActor.assumeIsolated {
    try FileManager.default.createDirectory(
        at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    let image = NSImage(size: canvas)
    image.addRepresentation(try render(scale: 1))
    image.addRepresentation(try render(scale: 2))
    guard let data = image.tiffRepresentation(using: .lzw, factor: 1) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: output)
}
print("Wrote \(output.path)")
