import Foundation

struct SetInfo: Equatable, Sendable {
    let code: String
    let name: String
    let setType: String
    let iconSVGURI: String?
    let releasedAt: String?
}
