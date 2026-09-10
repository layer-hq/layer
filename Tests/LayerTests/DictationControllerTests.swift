import Foundation
import Testing
@testable import Layer

struct DictationControllerTests {
    @Test
    func buildsTranscriptionRequestAndParsesResponse() throws {
        let body = DictationController.multipartBody(
            audio: Data([1, 2, 3]),
            boundary: "test-boundary"
        )
        let bodyText = String(decoding: body, as: UTF8.self)

        #expect(bodyText.contains("name=\"model\"\r\n\r\ngpt-transcribe"))
        #expect(bodyText.contains("filename=\"dictation.m4a\""))
        #expect(bodyText.contains("Content-Type: audio/mp4"))
        #expect(bodyText.hasSuffix("--test-boundary--\r\n"))

        let response = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let transcript = try DictationController.transcript(
            from: Data(#"{"text":"Hello Layer."}"#.utf8),
            response: response
        )
        #expect(transcript == "Hello Layer.")
    }

    @Test
    func appendsDictationWithoutChangingExistingPrompt() {
        #expect(appendingDictation("Hello.", to: "") == "Hello.")
        #expect(appendingDictation("world.", to: "Hello") == "Hello world.")
        #expect(appendingDictation("world.", to: "Hello ") == "Hello world.")
        #expect(appendingDictation("  ", to: "Keep me") == "Keep me")
    }
}
