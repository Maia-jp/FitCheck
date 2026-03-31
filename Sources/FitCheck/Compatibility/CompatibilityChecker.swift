public protocol CompatibilityChecker: Sendable {
    func check(
        variant: ModelVariant,
        of card: ModelCard,
        against hardware: HardwareProfile
    ) -> CompatibilityReport

    func checkAll(
        models: [ModelCard],
        against hardware: HardwareProfile
    ) -> [ModelMatch]

    func compatibleModels(
        from models: [ModelCard],
        against hardware: HardwareProfile
    ) -> [ModelMatch]
}
