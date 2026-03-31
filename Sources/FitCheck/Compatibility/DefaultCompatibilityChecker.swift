public struct DefaultCompatibilityChecker: CompatibilityChecker, Sendable {
    public init() {}

    public func check(
        variant: ModelVariant,
        of card: ModelCard,
        against hardware: HardwareProfile
    ) -> CompatibilityReport {
        let available = hardware.availableMemoryForInferenceBytes
        let required = variant.requirements.minimumMemoryBytes

        let headroom = Int64(available) - Int64(required)
        let usagePercent = available > 0
            ? (Double(required) / Double(available)) * 100
            : 100

        let verdict = computeVerdict(required: required, available: available)

        let warnings = computeWarnings(
            verdict: verdict,
            usagePercent: usagePercent,
            card: card,
            variant: variant
        )

        return CompatibilityReport(
            modelCardID: card.id,
            variantID: variant.id,
            verdict: verdict,
            estimatedMemoryUsageBytes: required,
            availableMemoryBytes: available,
            memoryHeadroomBytes: headroom,
            memoryUsagePercent: usagePercent,
            warnings: warnings
        )
    }

    public func checkAll(
        models: [ModelCard],
        against hardware: HardwareProfile
    ) -> [ModelMatch] {
        models.flatMap { card in
            card.variants.map { variant in
                let report = check(variant: variant, of: card, against: hardware)
                return ModelMatch(card: card, variant: variant, report: report)
            }
        }
    }

    public func compatibleModels(
        from models: [ModelCard],
        against hardware: HardwareProfile
    ) -> [ModelMatch] {
        models.compactMap { card in
            bestCompatibleVariant(of: card, against: hardware)
        }
        .sorted { lhs, rhs in
            sortOrder(lhs) > sortOrder(rhs)
        }
    }

    // MARK: - Verdict

    private func computeVerdict(
        required: UInt64,
        available: UInt64
    ) -> CompatibilityVerdict {
        guard required <= available else {
            return .incompatible(
                .insufficientMemory(requiredBytes: required, availableBytes: available)
            )
        }

        let usageRatio = Double(required) / Double(available)

        return switch usageRatio {
        case ..<0.50:    .compatible(.optimal)
        case 0.50..<0.75: .compatible(.comfortable)
        case 0.75..<0.90: .compatible(.constrained)
        default:          .marginal
        }
    }

    // MARK: - Warnings

    private func computeWarnings(
        verdict: CompatibilityVerdict,
        usagePercent: Double,
        card: ModelCard,
        variant: ModelVariant
    ) -> [CompatibilityWarning] {
        var warnings: [CompatibilityWarning] = []

        if usagePercent > 80 {
            warnings.append(.tightMemoryFit(usagePercent: usagePercent))
        }

        if case .marginal = verdict {
            warnings.append(.swappingLikely)
        }

        if usagePercent > 75 {
            let smallerVariant = card.variants
                .filter { $0.quantization < variant.quantization }
                .sorted { $0.requirements.minimumMemoryBytes < $1.requirements.minimumMemoryBytes }
                .last
            if let smaller = smallerVariant {
                warnings.append(.smallerQuantizationAvailable(smaller.quantization))
            }
        }

        return warnings
    }

    // MARK: - Best variant selection

    private func bestCompatibleVariant(
        of card: ModelCard,
        against hardware: HardwareProfile
    ) -> ModelMatch? {
        let candidates = card.variants
            .map { variant in
                (variant, check(variant: variant, of: card, against: hardware))
            }
            .filter { $0.1.verdict.isRunnable }
            .sorted { lhs, rhs in
                lhs.0.quantization > rhs.0.quantization
            }

        guard let best = candidates.first else { return nil }
        return ModelMatch(card: card, variant: best.0, report: best.1)
    }

    private func sortOrder(_ match: ModelMatch) -> Int {
        switch match.report.verdict {
        case .compatible(.optimal):     4
        case .compatible(.comfortable): 3
        case .compatible(.constrained): 2
        case .marginal:                 1
        case .incompatible:             0
        }
    }
}
