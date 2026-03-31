public protocol HardwareProfiler: Sendable {
    func profile() throws -> HardwareProfile
}
