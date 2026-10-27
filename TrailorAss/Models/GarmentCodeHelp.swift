import Foundation

/// The guide is an owner-private preview, not a public or offline help bundle.
/// Hash routes keep every topic reachable on the static website.
enum GarmentCodeHelp {
    enum Topic: String {
        case home = "start"
        case basic
        case parameters
        case garments
        case body
        case printing
    }

    static func url(for topic: Topic) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "tailorass-pattern-guide-20261024.wellbud33.chatgpt.site"
        components.path = "/"
        components.fragment = "/\(topic.rawValue)"
        // All components are compile-time constants from the deployed guide.
        return components.url!
    }
}
