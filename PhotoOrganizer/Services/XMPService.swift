import Foundation

/// Writes XMP sidecar files alongside exported photos.
/// Encodes rating (1–5 stars) and pick/reject status in a format
/// compatible with Lightroom Classic and Capture One.
enum XMPService {

    /// Write an XMP sidecar next to `photoURL`.
    /// - Parameters:
    ///   - photoURL: The destination photo file URL.
    ///   - decision: The culling decision for this photo.
    ///   - rating: Star rating 1–5, or 0 for none.
    static func writeSidecar(
        for photoURL: URL,
        decision: DecisionState,
        rating: Int
    ) {
        let xmpURL = photoURL.deletingPathExtension().appendingPathExtension("xmp")
        let xmpRating = xmpRatingValue(decision: decision, starRating: rating)
        let label = labelValue(for: decision)
        let content = buildXMP(rating: xmpRating, label: label)
        try? content.write(to: xmpURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Private

    private static func xmpRatingValue(decision: DecisionState, starRating: Int) -> Int {
        switch decision {
        case .rejected:
            return -1
        case .kept:
            return starRating > 0 ? starRating : 1
        case .undecided:
            return 0
        }
    }

    private static func labelValue(for decision: DecisionState) -> String {
        switch decision {
        case .kept: return "Green"
        case .rejected: return "Red"
        case .undecided: return ""
        }
    }

    private static func buildXMP(rating: Int, label: String) -> String {
        let labelAttr = label.isEmpty ? "" : "\n        xmp:Label=\"\(label)\""
        return """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Photo Organizer">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about=""
                xmlns:xmp="http://ns.adobe.com/xap/1.0/"
                xmp:Rating="\(rating)"\(labelAttr)>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
    }
}
