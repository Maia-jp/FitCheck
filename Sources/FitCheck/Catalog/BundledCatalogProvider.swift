import Foundation

public struct BundledCatalogProvider: CatalogProvider, Sendable {
    public init() {}

    public func fetchModels() async throws -> [ModelCard] {
        guard let url = Bundle.module.url(
            forResource: "bundled-catalog",
            withExtension: "json"
        ) else {
            throw FitCheckError.resourceMissing(name: "bundled-catalog.json")
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw FitCheckError.catalogLoadFailed(underlying: error)
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let catalog = try decoder.decode(CatalogFile.self, from: data)
            return catalog.models
        } catch {
            throw FitCheckError.catalogDecodingFailed(
                path: url.path,
                underlying: error
            )
        }
    }
}
