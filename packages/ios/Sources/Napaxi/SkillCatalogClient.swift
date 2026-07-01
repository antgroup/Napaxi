import Foundation

public protocol NapaxiCatalogHTTPTransport: Sendable {
    func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct NapaxiURLSessionCatalogHTTPTransport: NapaxiCatalogHTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NapaxiError.invalidState("Catalog request returned a non-HTTP response")
        }
        return (data, httpResponse)
    }
}

public struct NapaxiClawHubSkillCatalogClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://wry-manatee-359.convex.site")!
    public static let defaultListLimit = 50
    public static let minimumListLimit = 1
    public static let maximumListLimit = 100

    public var baseURL: URL
    public var transport: any NapaxiCatalogHTTPTransport

    public init(
        baseURL: URL = Self.defaultBaseURL,
        transport: any NapaxiCatalogHTTPTransport = NapaxiURLSessionCatalogHTTPTransport()
    ) {
        self.baseURL = baseURL
        self.transport = transport
    }

    public func listPackages(
        limit: Int = Self.defaultListLimit,
        cursor: String? = nil
    ) async throws -> NapaxiCatalogPackagePage {
        try await NapaxiSkillAPI.decodeCatalogPackagePage(from: listPackagesJSON(limit: limit, cursor: cursor))
    }

    public func listPackagesJSON(
        limit: Int = Self.defaultListLimit,
        cursor: String? = nil
    ) async throws -> NapaxiJSONValue {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return errorPage("Invalid catalog base URL: \(baseURL.absoluteString)")
        }

        let safeLimit = Self.clampedListLimit(limit)
        components.path = "/api/v1/packages"
        var queryItems = [URLQueryItem(name: "limit", value: "\(safeLimit)")]
        if let cursor = cursor?.trimmingCharacters(in: .whitespacesAndNewlines), !cursor.isEmpty {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            return errorPage("Invalid catalog packages URL")
        }

        var request = URLRequest(url: url)
        request.setValue("napaxi-sdk/1.0", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.load(request)
        } catch {
            return errorPage(String(describing: error))
        }

        let body = String(data: data, encoding: .utf8) ?? ""
        guard (200..<300).contains(response.statusCode) else {
            return errorPage("HTTP \(response.statusCode): \(body)")
        }
        return try NapaxiRawJSON(jsonString: body).value
    }

    private func errorPage(_ message: String) -> NapaxiJSONValue {
        .object([
            "items": .array([]),
            "error": .string(message),
        ])
    }

    public static func clampedListLimit(_ limit: Int) -> Int {
        min(max(limit, minimumListLimit), maximumListLimit)
    }
}
