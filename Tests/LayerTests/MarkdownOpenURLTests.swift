import Foundation
import Testing
@testable import Layer

struct MarkdownOpenURLTests {
    @Test
    func allowsOnlyHttpAndHttps() {
        #expect(allowsMarkdownOpenURL(URL(string: "https://example.com/a")!))
        #expect(allowsMarkdownOpenURL(URL(string: "HTTP://example.com")!))
        #expect(!allowsMarkdownOpenURL(URL(string: "file:///etc/passwd")!))
        #expect(!allowsMarkdownOpenURL(URL(string: "javascript:alert(1)")!))
        #expect(!allowsMarkdownOpenURL(URL(string: "mailto:a@b.c")!))
    }
}
