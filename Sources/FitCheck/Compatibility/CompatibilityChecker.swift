public protocol CompatibilityChecker: Sendable {
    func check(
        variant: ModelVariant,
        of card: ModelCard,
        against hardware: HardwareProfile,
        contextLength: UInt64
    ) -> CompatibilityReport

    func checkAll(
        models: [ModelCard],
        against hardware: HardwareProfile,
        contextLength: UInt64
    ) -> [ModelMatch]

    func compatibleModels(
        from models: [ModelCard],
        against hardware: HardwareProfile,
        contextLength: UInt64
    ) -> [ModelMatch]
}

extension CompatibilityChecker {
    public func check(
        variant: ModelVariant,
        of card: ModelCard,
        against hardware: HardwareProfile
    ) -> CompatibilityReport {
        check(variant: variant, of: card, against: hardware, contextLength: ModelRequirements.defaultContextLength)
    }

    public func checkAll(
        models: [ModelCard],
        against hardware: HardwareProfile
    ) -> [ModelMatch] {
        checkAll(models: models, against: hardware, contextLength: ModelRequirements.defaultContextLength)
    }

    public func compatibleModels(
        from models: [ModelCard],
        against hardware: HardwareProfile
    ) -> [ModelMatch] {
        compatibleModels(from: models, against: hardware, contextLength: ModelRequirements.defaultContextLength)
    }
}
