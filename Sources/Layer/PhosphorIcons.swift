import AppKit
import SwiftUI

enum PhosphorIcon {
    static let selection = image(named: "selection")
    static let layerLogo = image(named: "logo", isTemplate: false)

    private static let resourceRoot: URL = {
        if let resourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("Layer_Layer.bundle"),
           FileManager.default.fileExists(atPath: resourceURL.path) {
            return resourceURL
        }

        return Bundle.module.bundleURL
    }()

    private static func image(named name: String, isTemplate: Bool = true) -> Image {
        let subdirectory = "Phosphor.xcassets/\(name).imageset"
        let url = resourceRoot
            .appendingPathComponent(subdirectory)
            .appendingPathComponent("\(name).svg")

        guard let image = NSImage(contentsOf: url) else {
            assertionFailure("Missing Phosphor icon: \(name)")
            return Image(systemName: "questionmark.square.dashed")
        }

        image.isTemplate = isTemplate
        return Image(nsImage: image)
    }
}
