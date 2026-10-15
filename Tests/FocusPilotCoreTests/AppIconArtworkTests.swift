import Foundation
import Testing
@testable import FocusPilotCore

@Suite("App icon artwork")
struct AppIconArtworkTests {
    private func writeIcon() throws -> URL {
        let url = try makeTemporaryDirectory().appending(path: "AppIcon.icon")
        try AppIconArtwork.writeIconComposerFile(to: url)
        return url
    }

    private func iconJSON(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url.appending(path: "icon.json"))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func backgroundIsFlatSystemBlueWithADarkVariant() throws {
        let json = try iconJSON(at: writeIcon())
        let specializations = try #require(json["fill-specializations"] as? [[String: Any]])

        let light = specializations.first { $0["appearance"] == nil }?["value"] as? [String: String]
        let dark = specializations.first { $0["appearance"] as? String == "dark" }?["value"] as? [String: String]
        #expect(light == ["solid": "srgb:0.00000,0.47843,1.00000,1.00000"])  // #007AFF
        #expect(dark == ["solid": "srgb:0.03922,0.51765,1.00000,1.00000"])  // #0A84FF
    }

    @Test func everyLayerImageExists() throws {
        let url = try writeIcon()
        let groups = try #require(try iconJSON(at: url)["groups"] as? [[String: Any]])
        let layers = groups.flatMap { $0["layers"] as? [[String: Any]] ?? [] }
        let names = layers.compactMap { $0["image-name"] as? String }

        #expect(Set(names) == ["ring.svg", "dot.svg"])
        for name in names {
            #expect(FileManager.default.fileExists(atPath: url.appending(path: "Assets/\(name)").path))
        }
    }

    @Test func layersFollowTheTwoAConstruction() throws {
        let assets = try writeIcon().appending(path: "Assets")
        let ring = try String(contentsOf: assets.appending(path: "ring.svg"), encoding: .utf8)
        let dot = try String(contentsOf: assets.appending(path: "dot.svg"), encoding: .utf8)

        #expect(ring.contains(#"viewBox="0 0 1024 1024""#))
        #expect(ring.contains(#"r="256""#) && ring.contains(#"stroke-width="76""#))
        #expect(dot.contains(#"r="77""#) && dot.contains(##"fill="#FFFFFF""##))
    }
}
