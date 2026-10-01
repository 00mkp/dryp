import DrypIcon
import Foundation

// Writes the app icon's .iconset for `iconutil`. Run by scripts/build-app.sh, so no binary icon is checked
// in and the app icon can't drift from the menu-bar glyph.
guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: dryp-icon <out.iconset>\n".utf8))
    exit(2)
}
do {
    try DrypIcon.writeIconset(to: URL(fileURLWithPath: CommandLine.arguments[1]))
} catch {
    FileHandle.standardError.write(Data("dryp-icon: \(error.localizedDescription)\n".utf8))
    exit(1)
}
