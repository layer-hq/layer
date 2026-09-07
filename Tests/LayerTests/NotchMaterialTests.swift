import AppKit
import Testing
@testable import Layer

@Suite
@MainActor
struct NotchMaterialTests {
    @Test
    func usesRegularSystemLiquidGlassOnMacOS26() throws {
        guard #available(macOS 26.0, *) else { return }

        let expectedClass: AnyClass = try #require(
            NSClassFromString("NSGlassEffectView")
        )
        let contentView = NSView()
        let view = NotchMaterialFactory.makeView(
            cornerRadius: 12,
            contentView: contentView
        )

        #expect(view.isKind(of: expectedClass))
        #expect(view.value(forKey: "style") as? Int == 0)
        #expect(view.value(forKey: "cornerRadius") as? CGFloat == 12)
        #expect(view.value(forKey: "contentView") as? NSView === contentView)
    }
}
