import Foundation

struct ModelMapLoader: Sendable {
    func load(from path: String) throws -> [String: ModelMapEntry] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode([String: ModelMapEntry].self, from: data)
    }
}
