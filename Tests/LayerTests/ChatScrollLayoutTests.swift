import CoreGraphics
import Testing
@testable import Layer

struct ChatScrollLayoutTests {
    private let viewport: CGFloat = 800

    @Test
    func reservesEnoughSpaceToParkAShortMessageBelowTheTopQuarter() {
        let spacer = ChatScrollLayout.tailSpacerHeight(
            viewportHeight: viewport,
            newMessageTop: 1_000,
            contentBottom: 1_060
        )

        let messageTopFromViewportTop = viewport - (60 + spacer)
        #expect(messageTopFromViewportTop == viewport * ChatScrollLayout.newMessageTopInset)
    }

    @Test
    func spacerShrinksAsTheReplyGrows() {
        let short = ChatScrollLayout.tailSpacerHeight(
            viewportHeight: viewport,
            newMessageTop: 0,
            contentBottom: 100
        )
        let longer = ChatScrollLayout.tailSpacerHeight(
            viewportHeight: viewport,
            newMessageTop: 0,
            contentBottom: 400
        )

        #expect(short == 500)
        #expect(longer == 200)
    }

    @Test
    func reservesNothingWhenTheTailAlreadyFillsTheViewport() {
        let spacer = ChatScrollLayout.tailSpacerHeight(
            viewportHeight: viewport,
            newMessageTop: 0,
            contentBottom: 2_000
        )

        #expect(spacer == 0)
    }

    @Test
    func reservesNothingBeforeMeasurementsLand() {
        #expect(
            ChatScrollLayout.tailSpacerHeight(
                viewportHeight: viewport,
                newMessageTop: nil,
                contentBottom: 100
            ) == 0
        )
        #expect(
            ChatScrollLayout.tailSpacerHeight(
                viewportHeight: viewport,
                newMessageTop: 0,
                contentBottom: nil
            ) == 0
        )
        #expect(
            ChatScrollLayout.tailSpacerHeight(
                viewportHeight: 0,
                newMessageTop: 0,
                contentBottom: 100
            ) == 0
        )
    }
}
