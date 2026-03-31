import Foundation

struct ModelsDevClient: Sendable {
    static let apiURL = URL(string: "https://models.dev/api.json")!

    func fetchOpenWeightModels() async throws -> [ModelsDevEntry] {
        let (data, _) = try await URLSession.shared.data(from: Self.apiURL)
        let providers = try JSONDecoder().decode([String: ModelsDevProvider].self, from: data)

        var entries: [ModelsDevEntry] = []
        for (providerID, provider) in providers {
            for (modelID, model) in provider.models where model.openWeights == true {
                entries.append(ModelsDevEntry(
                    fullID: "\(providerID)/\(modelID)",
                    providerID: providerID,
                    modelID: modelID,
                    name: model.name ?? modelID,
                    family: model.family,
                    releaseDate: model.releaseDate,
                    providerName: provider.name,
                    providerDoc: provider.doc
                ))
            }
        }
        return entries
    }
}
