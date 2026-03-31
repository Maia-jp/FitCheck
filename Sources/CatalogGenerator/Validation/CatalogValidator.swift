import Foundation

enum ValidationError: Error, CustomStringConvertible {
    case duplicateModelID(String)
    case duplicateVariantID(String, model: String)
    case noVariants(model: String)
    case invalidRequirements(variant: String, reason: String)

    var description: String {
        switch self {
        case .duplicateModelID(let id):
            "Duplicate model ID: \(id)"
        case .duplicateVariantID(let id, let model):
            "Duplicate variant ID '\(id)' in model '\(model)'"
        case .noVariants(let model):
            "Model '\(model)' has no variants"
        case .invalidRequirements(let variant, let reason):
            "Invalid requirements for variant '\(variant)': \(reason)"
        }
    }
}

enum CatalogValidator {
    static func validate(_ catalog: CatalogOutput) throws {
        try checkNoDuplicateIDs(catalog)
        try checkRequirementsSanity(catalog)
        try checkAllModelsHaveVariants(catalog)
    }

    private static func checkNoDuplicateIDs(_ catalog: CatalogOutput) throws {
        var seen = Set<String>()
        for model in catalog.models {
            guard seen.insert(model.id).inserted else {
                throw ValidationError.duplicateModelID(model.id)
            }
            var variantSeen = Set<String>()
            for variant in model.variants {
                guard variantSeen.insert(variant.id).inserted else {
                    throw ValidationError.duplicateVariantID(variant.id, model: model.id)
                }
            }
        }
    }

    private static func checkRequirementsSanity(_ catalog: CatalogOutput) throws {
        for model in catalog.models {
            for variant in model.variants {
                let req = variant.requirements
                guard req.recommendedMemoryBytes > req.minimumMemoryBytes else {
                    throw ValidationError.invalidRequirements(
                        variant: variant.id,
                        reason: "recommended (\(req.recommendedMemoryBytes)) must exceed minimum (\(req.minimumMemoryBytes))"
                    )
                }
            }
        }
    }

    private static func checkAllModelsHaveVariants(_ catalog: CatalogOutput) throws {
        for model in catalog.models where model.variants.isEmpty {
            throw ValidationError.noVariants(model: model.id)
        }
    }
}
