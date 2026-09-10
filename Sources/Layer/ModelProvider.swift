import Foundation

enum ModelProviderKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case openAI
    case liteLLM

    var id: Self { self }

    var name: String {
        switch self {
        case .openAI: "OpenAI"
        case .liteLLM: "LiteLLM"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAI: "https://api.openai.com"
        case .liteLLM: "http://localhost:4000"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: "gpt-5.6-terra"
        case .liteLLM: ""
        }
    }

    var supportsRealtimeVoice: Bool {
        self == .openAI
    }
}

struct ModelProviderConfiguration: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var kind: ModelProviderKind
    var name: String
    var baseURL: String
    var apiKey: String
    var model: String

    init(
        id: UUID = UUID(),
        kind: ModelProviderKind,
        name: String? = nil,
        baseURL: String? = nil,
        apiKey: String = "",
        model: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name ?? kind.name
        self.baseURL = baseURL ?? kind.defaultBaseURL
        self.apiKey = apiKey
        self.model = model ?? kind.defaultModel
    }

    var isReady: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && apiRootURL != nil
    }

    var apiRootURL: URL? {
        let rawURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: rawURL),
              components.scheme == "http" || components.scheme == "https",
              components.host?.isEmpty == false else {
            return nil
        }

        components.query = nil
        components.fragment = nil
        var path = components.path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        if path.isEmpty || path == "/" {
            path = "/v1"
        } else if !path.hasSuffix("/v1") {
            path += "/v1"
        }
        components.path = path
        return components.url
    }

    func endpointURL(_ endpoint: String) -> URL? {
        apiRootURL?.appendingPathComponent(endpoint)
    }

    func cleaned() -> Self {
        var copy = self
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }
}

@MainActor
protocol ModelProviderProviding {
    func loadActiveProvider() -> ModelProviderConfiguration?
}

@MainActor
struct StoredModelProviderAdapter: ModelProviderProviding {
    func loadActiveProvider() -> ModelProviderConfiguration? {
        ModelProviderPreferences.activeConfiguration()
    }
}

enum ModelProviderPreferences {
    static let configurationsKey = "modelProviderConfigurations"
    static let selectedConfigurationIDKey = "selectedModelProviderConfigurationID"

    static func configurations(
        in defaults: UserDefaults = .standard
    ) -> [ModelProviderConfiguration] {
        guard let encoded = defaults.string(forKey: configurationsKey),
              let data = encoded.data(using: .utf8),
              let configurations = try? JSONDecoder().decode(
                [ModelProviderConfiguration].self,
                from: data
              ) else {
            return []
        }
        return configurations
    }

    static func saveConfigurations(
        _ configurations: [ModelProviderConfiguration],
        in defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(configurations),
              let encoded = String(data: data, encoding: .utf8) else {
            return
        }
        defaults.set(encoded, forKey: configurationsKey)
    }

    static func selectedConfigurationID(
        in defaults: UserDefaults = .standard
    ) -> UUID? {
        defaults.string(forKey: selectedConfigurationIDKey).flatMap(UUID.init(uuidString:))
    }

    static func select(
        _ id: UUID?,
        in defaults: UserDefaults = .standard
    ) {
        defaults.set(id?.uuidString, forKey: selectedConfigurationIDKey)
    }

    static func activeConfiguration(
        in defaults: UserDefaults = .standard
    ) -> ModelProviderConfiguration? {
        let configurations = configurations(in: defaults)
        guard let selectedID = selectedConfigurationID(in: defaults),
              let selected = configurations.first(where: { $0.id == selectedID }),
              selected.isReady else {
            return nil
        }
        return selected.cleaned()
    }
}

enum ModelProviderClientError: LocalizedError, Sendable {
    case invalidConfiguration(String)
    case invalidResponse(String)
    case api(message: String)
    case streamEndedUnexpectedly(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            message
        case .invalidResponse(let provider):
            "\(provider) returned an invalid response."
        case .api(let message):
            message
        case .streamEndedUnexpectedly(let provider):
            "The \(provider) response stream ended before completion."
        }
    }
}

struct ModelCatalogClient {
    func models(for provider: ModelProviderConfiguration) async throws -> [String] {
        let provider = provider.cleaned()
        guard let url = provider.endpointURL("models") else {
            throw ModelProviderClientError.invalidConfiguration(
                "Enter a valid provider URL using http or https."
            )
        }
        guard !provider.apiKey.isEmpty else {
            throw ModelProviderClientError.invalidConfiguration(
                "Enter an API key before loading models."
            )
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelProviderClientError.invalidResponse(provider.kind.name)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ModelProviderClientError.api(
                message: ProviderResponseParsing.errorMessage(in: data)
                    ?? "Could not load models (HTTP \(httpResponse.statusCode))."
            )
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["data"] as? [[String: Any]] else {
            throw ModelProviderClientError.invalidResponse(provider.kind.name)
        }
        return Set(entries.compactMap { $0["id"] as? String }.filter { !$0.isEmpty })
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

enum ProviderResponseParsing {
    nonisolated static func errorMessage(in data: Data) -> String? {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return errorMessage(in: json)
    }

    nonisolated static func errorMessage(in json: [String: Any]?) -> String? {
        if let message = (json?["error"] as? [String: Any])?["message"] as? String {
            return message
        }
        if let message = json?["error"] as? String {
            return message
        }
        return json?["message"] as? String
    }
}
