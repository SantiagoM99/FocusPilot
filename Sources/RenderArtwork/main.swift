import Foundation
import FocusPilotCore

// Usage:
//   RenderArtwork icon <AppIcon.icon>     Icon Composer file for actool
//   RenderArtwork glyphs <directory>      menu bar glyph review images

let arguments = Array(CommandLine.arguments.dropFirst())

switch (arguments.first, arguments.count) {
case ("icon", 2):
    try AppIconArtwork.writeIconComposerFile(to: URL(filePath: arguments[1]))
case ("glyphs", 2):
    try MainActor.assumeIsolated { try GlyphPreviews.write(to: URL(filePath: arguments[1])) }
default:
    FileHandle.standardError.write(Data("usage: RenderArtwork icon <out.icon> | glyphs <directory>\n".utf8))
    exit(64)
}
