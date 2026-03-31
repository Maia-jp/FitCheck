import Foundation

public struct ModelLicense: Sendable, Codable, Equatable {
    public let identifier: String
    public let name: String
    public let url: URL?
    public let isOpenSource: Bool

    public init(identifier: String, name: String, url: URL?, isOpenSource: Bool) {
        self.identifier = identifier
        self.name = name
        self.url = url
        self.isOpenSource = isOpenSource
    }
}
