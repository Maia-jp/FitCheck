public struct MetalSupport: Sendable, Equatable, Codable {
    public let isSupported: Bool
    public let maxBufferLengthBytes: UInt64
    public let recommendedMaxWorkingSetSizeBytes: UInt64

    public init(
        isSupported: Bool,
        maxBufferLengthBytes: UInt64,
        recommendedMaxWorkingSetSizeBytes: UInt64
    ) {
        self.isSupported = isSupported
        self.maxBufferLengthBytes = maxBufferLengthBytes
        self.recommendedMaxWorkingSetSizeBytes = recommendedMaxWorkingSetSizeBytes
    }

    public var maxBufferLengthGB: Double {
        Double(maxBufferLengthBytes) / 1_073_741_824
    }

    public var recommendedMaxWorkingSetSizeGB: Double {
        Double(recommendedMaxWorkingSetSizeBytes) / 1_073_741_824
    }
}
