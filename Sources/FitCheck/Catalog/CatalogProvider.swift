import Foundation

public protocol CatalogProvider: Sendable {
    func fetchModels() async throws -> [ModelCard]
}

// MARK: - CompositeCatalogProvider

public struct CompositeCatalogProvider: CatalogProvider, Sendable {
    private let primary: any CatalogProvider
    private let fallback: any CatalogProvider

    public init(primary: any CatalogProvider, fallback: any CatalogProvider) {
        self.primary = primary
        self.fallback = fallback
    }

    public func fetchModels() async throws -> [ModelCard] {
        let fallbackModels = try await fallback.fetchModels()

        let primaryModels: [ModelCard]
        do {
            primaryModels = try await primary.fetchModels()
        } catch {
            Log.catalog.info("Primary catalog unavailable, using fallback only: \(error)")
            return fallbackModels
        }

        var modelsByID: [String: ModelCard] = [:]
        for model in fallbackModels {
            modelsByID[model.id] = model
        }
        for model in primaryModels {
            modelsByID[model.id] = model
        }

        return Array(modelsByID.values).sorted { $0.name < $1.name }
    }
}

// MARK: - CatalogFile (internal decode wrapper)

internal struct CatalogFile: Codable, Sendable {
    let version: String
    let generatedAt: String
    let models: [ModelCard]
}
