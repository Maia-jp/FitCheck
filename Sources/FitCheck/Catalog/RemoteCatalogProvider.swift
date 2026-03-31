import Foundation

public struct RemoteCatalogProvider: CatalogProvider, Sendable {
    public static let defaultURL = URL(
        string: "https://raw.githubusercontent.com/nicklama/FitCheck/main/data/catalog.json"
    )!

    private let url: URL
    private let session: URLSession
    private let timeoutSeconds: TimeInterval

    public init(
        url: URL = Self.defaultURL,
        session: URLSession = .shared,
        timeoutSeconds: TimeInterval = 10
    ) {
        self.url = url
        self.session = session
        self.timeoutSeconds = timeoutSeconds
    }

    public func fetchModels() async throws -> [ModelCard] {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeoutSeconds
        request.cachePolicy = .reloadRevalidatingCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FitCheckError.networkUnavailable(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw FitCheckError.catalogLoadFailed(
                underlying: URLError(.badServerResponse)
            )
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let catalog = try decoder.decode(CatalogFile.self, from: data)
            return catalog.models
        } catch {
            throw FitCheckError.catalogDecodingFailed(
                path: url.absoluteString,
                underlying: error
            )
        }
    }
}
