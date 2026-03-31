public struct ModelMatch: Sendable, Identifiable, Equatable {
    public let id: String
    public let card: ModelCard
    public let variant: ModelVariant
    public let report: CompatibilityReport

    public init(card: ModelCard, variant: ModelVariant, report: CompatibilityReport) {
        self.id = "\(card.id):\(variant.id)"
        self.card = card
        self.variant = variant
        self.report = report
    }
}
