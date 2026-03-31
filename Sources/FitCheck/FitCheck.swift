import Foundation
import OSLog

public actor FitCheck {
    private let hardwareProfiler: any HardwareProfiler
    private let catalogProvider: any CatalogProvider
    private let compatibilityChecker: any CompatibilityChecker
    private let downloadProviders: [any DownloadProvider]

    private var cachedProfile: HardwareProfile?
    private var cachedCatalog: [ModelCard]?

    public init(
        hardwareProfiler: any HardwareProfiler = SystemHardwareProfiler(),
        catalogProvider: any CatalogProvider = CompositeCatalogProvider(
            primary: RemoteCatalogProvider(),
            fallback: BundledCatalogProvider()
        ),
        compatibilityChecker: any CompatibilityChecker = DefaultCompatibilityChecker(),
        downloadProviders: [any DownloadProvider] = [
            OllamaProvider(),
            LMStudioProvider(),
        ]
    ) {
        self.hardwareProfiler = hardwareProfiler
        self.catalogProvider = catalogProvider
        self.compatibilityChecker = compatibilityChecker
        self.downloadProviders = downloadProviders
    }

    // MARK: - Hardware

    public func hardwareProfile() throws -> HardwareProfile {
        if let cached = cachedProfile { return cached }
        let profile = try hardwareProfiler.profile()
        cachedProfile = profile
        Log.api.debug("Hardware profile loaded: \(String(describing: profile.chip)), \(profile.totalMemoryGB) GB")
        return profile
    }

    // MARK: - Catalog

    public func allModels() async throws -> [ModelCard] {
        if let cached = cachedCatalog { return cached }
        let models = try await catalogProvider.fetchModels()
        cachedCatalog = models
        Log.api.debug("Catalog loaded: \(models.count) models")
        return models
    }

    public func model(id: String) async throws -> ModelCard {
        let models = try await allModels()
        guard let card = models.first(where: { $0.id == id }) else {
            throw FitCheckError.modelNotFound(identifier: id)
        }
        return card
    }

    // MARK: - Compatibility

    public func compatibleModels() async throws -> [CompatibleModel] {
        let profile = try hardwareProfile()
        let models = try await allModels()
        let matches = compatibilityChecker.compatibleModels(from: models, against: profile)
        return matches.map { enrichedModel(match: $0, hardware: profile) }
    }

    public func allModelsWithCompatibility() async throws -> [CompatibleModel] {
        let profile = try hardwareProfile()
        let models = try await allModels()
        let matches = compatibilityChecker.checkAll(models: models, against: profile)
        return matches.map { enrichedModel(match: $0, hardware: profile) }
    }

    public func check(modelID: String) async throws -> [VariantReport] {
        let card = try await model(id: modelID)
        let profile = try hardwareProfile()
        return card.variants.map { variant in
            let report = compatibilityChecker.check(variant: variant, of: card, against: profile)
            let perf = PerformanceCalculator.estimate(modelSizeGB: variant.sizeGB, hardware: profile)
            return VariantReport(
                variant: variant,
                report: report,
                performanceEstimate: perf,
                downloadActions: downloadActions(for: variant, of: card)
            )
        }
    }

    private func enrichedModel(match: ModelMatch, hardware: HardwareProfile) -> CompatibleModel {
        let perf = PerformanceCalculator.estimate(modelSizeGB: match.variant.sizeGB, hardware: hardware)
        return CompatibleModel(
            match: match,
            performanceEstimate: perf,
            downloadActions: downloadActions(for: match.variant, of: match.card)
        )
    }

    // MARK: - Download Providers

    public func providers() async throws -> [ProviderInfo] {
        var results: [ProviderInfo] = []
        for provider in downloadProviders {
            let installation = try await provider.detectInstallation()
            let installed = try await provider.installedModels()
            results.append(ProviderInfo(
                name: provider.name,
                type: provider.providerType,
                installation: installation,
                installationURL: provider.installationURL,
                installedModelCount: installed.count,
                installedModels: installed
            ))
        }
        return results
    }

    public func installedModels() async throws -> [InstalledModel] {
        var all: [InstalledModel] = []
        for provider in downloadProviders {
            let models = try await provider.installedModels()
            all.append(contentsOf: models)
        }
        return all
    }

    // MARK: - Filtering

    public func models(family: ModelFamily) async throws -> [ModelCard] {
        try await allModels().filter { $0.family == family }
    }

    public func models(maxParameters: Double) async throws -> [ModelCard] {
        try await allModels().filter { $0.parameterCount.billions <= maxParameters }
    }

    public func models(matching query: String) async throws -> [ModelCard] {
        let lowered = query.lowercased()
        return try await allModels().filter { card in
            card.name.lowercased().contains(lowered)
                || card.family.displayName.lowercased().contains(lowered)
                || card.description.lowercased().contains(lowered)
                || card.id.lowercased().contains(lowered)
        }
    }

    // MARK: - Custom Model Checking

    /// Check whether an arbitrary model (not in the catalog) can run on this machine.
    /// Useful for evaluating custom fine-tunes, new releases, or models from any source.
    public func checkCustom(
        parametersBillion: Double,
        quantization: QuantizationFormat = .q4KM,
        contextLength: UInt64 = ModelRequirements.defaultContextLength
    ) throws -> CustomModelReport {
        let profile = try hardwareProfile()

        let diskSizeBytes = UInt64(parametersBillion * quantization.gbPerBillionParams * 1_073_741_824)
        let requirements = ModelRequirements.estimated(
            parameterCount: ParameterCount(billions: parametersBillion),
            quantization: quantization,
            diskSizeBytes: diskSizeBytes,
            contextLength: contextLength
        )

        let available = profile.availableMemoryForInferenceBytes
        let required = requirements.minimumMemoryBytes
        let headroom = Int64(available) - Int64(required)
        let usagePercent = available > 0
            ? (Double(required) / Double(available)) * 100
            : 100

        let verdict: CompatibilityVerdict
        if required > available {
            verdict = .incompatible(.insufficientMemory(requiredBytes: required, availableBytes: available))
        } else {
            let ratio = Double(required) / Double(available)
            verdict = switch ratio {
            case ..<0.50:     .compatible(.optimal)
            case 0.50..<0.75: .compatible(.comfortable)
            case 0.75..<0.90: .compatible(.constrained)
            default:          .marginal
            }
        }

        let perf = PerformanceCalculator.estimate(
            modelSizeGB: Double(diskSizeBytes) / 1_073_741_824,
            hardware: profile
        )

        return CustomModelReport(
            parametersBillion: parametersBillion,
            quantization: quantization,
            contextLength: contextLength,
            requirements: requirements,
            verdict: verdict,
            memoryUsagePercent: usagePercent,
            memoryHeadroomBytes: headroom,
            performanceEstimate: perf,
            hardware: profile
        )
    }

    // MARK: - Cache Management

    public func refreshCatalog() async throws {
        cachedCatalog = nil
        _ = try await allModels()
    }

    public func invalidateHardwareCache() {
        cachedProfile = nil
    }

    // MARK: - Private

    private func downloadActions(for variant: ModelVariant, of card: ModelCard) -> [DownloadAction] {
        downloadProviders.compactMap { $0.downloadAction(for: variant, of: card) }
    }
}

// MARK: - Result types

public struct CompatibleModel: Sendable, Identifiable {
    public let id: String
    public let card: ModelCard
    public let variant: ModelVariant
    public let report: CompatibilityReport
    public let performanceEstimate: PerformanceEstimate
    public let downloadActions: [DownloadAction]

    public init(id: String, card: ModelCard, variant: ModelVariant, report: CompatibilityReport, performanceEstimate: PerformanceEstimate, downloadActions: [DownloadAction]) {
        self.id = id
        self.card = card
        self.variant = variant
        self.report = report
        self.performanceEstimate = performanceEstimate
        self.downloadActions = downloadActions
    }

    internal init(match: ModelMatch, performanceEstimate: PerformanceEstimate, downloadActions: [DownloadAction]) {
        self.id = match.id
        self.card = match.card
        self.variant = match.variant
        self.report = match.report
        self.performanceEstimate = performanceEstimate
        self.downloadActions = downloadActions
    }

    public var isRunnable: Bool { report.verdict.isRunnable }

    public var ollamaAction: DownloadAction? {
        downloadActions.first { $0.providerType == .ollama }
    }

    public var lmStudioAction: DownloadAction? {
        downloadActions.first { $0.providerType == .lmStudio }
    }
}

public struct VariantReport: Sendable {
    public let variant: ModelVariant
    public let report: CompatibilityReport
    public let performanceEstimate: PerformanceEstimate
    public let downloadActions: [DownloadAction]

    public init(variant: ModelVariant, report: CompatibilityReport, performanceEstimate: PerformanceEstimate, downloadActions: [DownloadAction]) {
        self.variant = variant
        self.report = report
        self.performanceEstimate = performanceEstimate
        self.downloadActions = downloadActions
    }

    public var isRunnable: Bool { report.verdict.isRunnable }
}

/// Result of checking a custom model specification against the current hardware.
public struct CustomModelReport: Sendable {
    public let parametersBillion: Double
    public let quantization: QuantizationFormat
    public let contextLength: UInt64
    public let requirements: ModelRequirements
    public let verdict: CompatibilityVerdict
    public let memoryUsagePercent: Double
    public let memoryHeadroomBytes: Int64
    public let performanceEstimate: PerformanceEstimate
    public let hardware: HardwareProfile

    public init(
        parametersBillion: Double, quantization: QuantizationFormat,
        contextLength: UInt64, requirements: ModelRequirements,
        verdict: CompatibilityVerdict, memoryUsagePercent: Double,
        memoryHeadroomBytes: Int64, performanceEstimate: PerformanceEstimate,
        hardware: HardwareProfile
    ) {
        self.parametersBillion = parametersBillion
        self.quantization = quantization
        self.contextLength = contextLength
        self.requirements = requirements
        self.verdict = verdict
        self.memoryUsagePercent = memoryUsagePercent
        self.memoryHeadroomBytes = memoryHeadroomBytes
        self.performanceEstimate = performanceEstimate
        self.hardware = hardware
    }

    public var isRunnable: Bool { verdict.isRunnable }

    public var summary: String {
        let params = ParameterCount(billions: parametersBillion).displayString
        let mem = String(format: "%.1f", requirements.minimumMemoryGB)
        let speed = String(format: "%.1f", performanceEstimate.estimatedTokensPerSecond)
        return "\(params) \(quantization.displayName): \(verdict) — \(mem) GB, ~\(speed) tok/s"
    }
}

public struct ProviderInfo: Sendable {
    public let name: String
    public let type: DownloadProviderType
    public let installation: ProviderInstallation
    public let installationURL: URL
    public let installedModelCount: Int
    public let installedModels: [InstalledModel]

    public init(name: String, type: DownloadProviderType, installation: ProviderInstallation, installationURL: URL, installedModelCount: Int, installedModels: [InstalledModel]) {
        self.name = name
        self.type = type
        self.installation = installation
        self.installationURL = installationURL
        self.installedModelCount = installedModelCount
        self.installedModels = installedModels
    }
}
