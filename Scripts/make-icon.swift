// Renders the MetriBar app icon into an asset catalog icon set.
//
// Usage: xcrun swift Scripts/make-icon.swift Resources/Assets.xcassets/AppIcon.appiconset

import AppKit
import SwiftUI

struct AppIcon: View {
    private let usage: [CGFloat] = [0.72, 0.38, 0.56]

    var body: some View {
        ZStack {
            // macOS icon grid: an 824 × 824 rounded square centered on 1024 × 1024.
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.10, green: 0.20, blue: 0.52), Color(red: 0.04, green: 0.58, blue: 0.86)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 4)
                )
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.28), radius: 18, y: 10)

            VStack(spacing: 40) {
                ForEach(usage.indices, id: \.self) { index in
                    rackUnit(usage: usage[index])
                }
            }
        }
        .frame(width: 1024, height: 1024)
    }

    private func rackUnit(usage: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .fill(.white)
            .frame(width: 560, height: 132)
            .shadow(color: .black.opacity(0.18), radius: 6, y: 4)
            .overlay {
                HStack(spacing: 34) {
                    Circle()
                        .fill(Color(red: 0.20, green: 0.80, blue: 0.40))
                        .frame(width: 40, height: 40)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(red: 0.86, green: 0.90, blue: 0.96))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.10, green: 0.42, blue: 0.85), Color(red: 0.04, green: 0.62, blue: 0.90)],
                                    startPoint: .leading, endPoint: .trailing)
                            )
                            .frame(width: 380 * usage)
                    }
                    .frame(width: 380, height: 36)
                }
            }
    }
}

@MainActor
func writeIconSet(to directory: URL) throws {
    // (file name, pixel size, point size, scale)
    let images: [(String, Int, Int, Int)] = [
        ("icon_16x16.png", 16, 16, 1), ("icon_16x16@2x.png", 32, 16, 2),
        ("icon_32x32.png", 32, 32, 1), ("icon_32x32@2x.png", 64, 32, 2),
        ("icon_128x128.png", 128, 128, 1), ("icon_128x128@2x.png", 256, 128, 2),
        ("icon_256x256.png", 256, 256, 1), ("icon_256x256@2x.png", 512, 256, 2),
        ("icon_512x512.png", 512, 512, 1), ("icon_512x512@2x.png", 1024, 512, 2),
    ]
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for (name, pixels, _, _) in images {
        let renderer = ImageRenderer(content: AppIcon())
        renderer.scale = CGFloat(pixels) / 1024
        guard let cgImage = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: directory.appending(path: name))
    }
    let entries = images.map { name, _, points, scale in
        """
            {
              "filename" : "\(name)",
              "idiom" : "mac",
              "scale" : "\(scale)x",
              "size" : "\(points)x\(points)"
            }
        """
    }
    let contents = """
        {
          "images" : [
        \(entries.joined(separator: ",\n"))
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }

        """
    try contents.write(to: directory.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    print("Usage: xcrun swift Scripts/make-icon.swift <path to AppIcon.appiconset>")
    exit(1)
}
try MainActor.assumeIsolated {
    try writeIconSet(to: URL(fileURLWithPath: arguments[1]))
}
print("Wrote icon set to \(arguments[1])")
