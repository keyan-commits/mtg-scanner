import Foundation

extension Card {
    /// Returns the preferred image URL using a priority fallback chain.
    /// - Parameter priority: Which image size to prefer first.
    func preferredImageURL(_ priority: ImagePriority = .normal) -> URL? {
        let urlString: String?
        switch priority {
        case .artCrop:
            urlString = imageURIs["art_crop"]
                ?? imageURIs["normal"]
                ?? imageURIs["small"]
                ?? imageURIs["large"]
        case .normal:
            urlString = imageURIs["normal"]
                ?? imageURIs["small"]
                ?? imageURIs["large"]
        case .small:
            urlString = imageURIs["small"]
                ?? imageURIs["normal"]
                ?? imageURIs["large"]
        }
        return urlString.flatMap(URL.init(string:))
    }

    enum ImagePriority {
        case artCrop
        case normal
        case small
    }
}

extension String {
    /// Generates a URL-safe slug for tcgph.com card lookups.
    func toTCGPHSlug() -> String {
        lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "'", with: "")
    }

    /// Generates a Facebook MTG Tambayan search URL for this card name.
    func toMTGTambayURL() -> URL? {
        let query = addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.facebook.com/groups/135914699791891/search/?q=\(query)")
    }
}
