import Foundation

@main
struct CatalogGenerator {
    static func main() async throws {
        let args = Set(CommandLine.arguments.dropFirst())
        let dryRun = args.contains("--dry-run")
        let discover = args.contains("--discover")
        let offline = args.contains("--offline")
        let verbose = args.contains("--verbose")

        func log(_ message: String) {
            if verbose { print("  → \(message)") }
        }

        let modelsDevClient = ModelsDevClient()
        let modelMapLoader = ModelMapLoader()

        // Layer 0: models.dev
        let openWeightModels: [ModelsDevEntry]
        if offline {
            print("Offline mode: skipping models.dev fetch")
            openWeightModels = []
        } else {
            print("Fetching models.dev/api.json...")
            openWeightModels = try await modelsDevClient.fetchOpenWeightModels()
            log("\(openWeightModels.count) open-weight models found on models.dev")
        }

        // Layer 1: Model map
        let modelMap = try modelMapLoader.load(from: "data/model-map.json")
        log("\(modelMap.count) entries in model-map.json")

        if discover {
            printDiscovery(openWeightModels: openWeightModels, modelMap: modelMap)
            return
        }

        // Match models.dev entries with model map
        var catalogModels: [CatalogModel] = []

        if offline {
            for (fullID, mapping) in modelMap {
                let parts = fullID.split(separator: "/", maxSplits: 1)
                let providerID = parts.first.map(String.init) ?? ""
                let modelID = parts.count > 1 ? String(parts[1]) : fullID
                let entry = ModelsDevEntry(
                    fullID: fullID,
                    providerID: providerID,
                    modelID: modelID,
                    name: modelID,
                    family: nil,
                    releaseDate: nil,
                    providerName: String(parts.first ?? ""),
                    providerDoc: nil
                )
                let card = CatalogBuilder.buildCard(from: entry, mapping: mapping)
                catalogModels.append(card)
            }
        } else {
            let mapped = openWeightModels.filter { modelMap[$0.fullID] != nil }
            log("\(mapped.count) models matched with model map")

            var seenOllama = Set<String>()
            for entry in mapped {
                guard let mapping = modelMap[entry.fullID] else { continue }
                let ollamaBase = mapping.ollama.split(separator: ":").first.map(String.init) ?? mapping.ollama
                guard seenOllama.insert(ollamaBase).inserted else { continue }
                let card = CatalogBuilder.buildCard(from: entry, mapping: mapping)
                catalogModels.append(card)
            }
        }

        let catalog = CatalogOutput(
            version: "1.0.0",
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            models: catalogModels.sorted { $0.name < $1.name }
        )

        try CatalogValidator.validate(catalog)
        log("Validation passed")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(catalog)

        if dryRun {
            let variantCount = catalog.models.flatMap(\.variants).count
            print("Dry run: \(catalog.models.count) models, \(variantCount) variants. Validation passed.")
            return
        }

        try jsonData.write(to: URL(fileURLWithPath: "data/catalog.json"))
        try jsonData.write(to: URL(fileURLWithPath: "Sources/FitCheck/Resources/bundled-catalog.json"))

        let variantCount = catalog.models.flatMap(\.variants).count
        print("Generated \(catalog.models.count) models, \(variantCount) variants.")
    }

    private static func printDiscovery(
        openWeightModels: [ModelsDevEntry],
        modelMap: [String: ModelMapEntry]
    ) {
        let unmapped = openWeightModels.filter { modelMap[$0.fullID] == nil }

        if unmapped.isEmpty {
            print("All open-weight models on models.dev are mapped.")
            return
        }

        print("Open-weight models on models.dev without FitCheck mappings:\n")
        for entry in unmapped.sorted(by: { $0.fullID < $1.fullID }) {
            let family = entry.family.map { "family: \($0)" } ?? ""
            let date = entry.releaseDate.map { "released: \($0)" } ?? ""
            let detail = [family, date].filter { !$0.isEmpty }.joined(separator: ", ")
            print("  \(entry.fullID.padding(toLength: 45, withPad: " ", startingAt: 0)) \(detail)")
        }

        print("\n\(unmapped.count) unmapped models found.")
        print("To add: create an entry in data/model-map.json")
    }
}
