import Foundation

/// The outcome of checking a cleaned file against what was asked for.
public struct VerificationResult: Codable, Sendable {
    /// Asked to be removed but still found by a fresh scan. Any entry fails verification.
    public var stillPresent: [MetadataField]
    /// The text of a removed value still appears somewhere in the file's bytes.
    /// Any entry fails verification and needs review.
    public var residue: [MetadataField]
    /// Asked to be kept but gone (for example maker notes, which can't be kept
    /// on their own). Shown to the user; doesn't fail verification.
    public var alsoRemoved: [MetadataField]

    public var passed: Bool { stillPresent.isEmpty && residue.isEmpty }
}

/// Compares scans of a file before and after cleaning, and searches the
/// cleaned bytes for any removed text. It never parses the file, so it is
/// safe to run in the main app.
public enum Verifier {
    /// Removed values shorter than this aren't searched for in the bytes,
    /// because short text turns up by chance in compressed data.
    public static let minimumResidueLength = 6

    public static func verify(
        before: [MetadataField], removed: Set<String>, after: [MetadataField], output: Data
    ) -> VerificationResult {
        let afterIDs = Set(after.map(\.id))
        let stillPresent = before.filter { removed.contains($0.id) && afterIDs.contains($0.id) }
        let alsoRemoved = before.filter { !removed.contains($0.id) && !afterIDs.contains($0.id) }

        // Text that legitimately remains (kept fields) is not residue.
        let keptValues = Set(after.map(\.value))
        let residue = before.filter { field in
            guard removed.contains(field.id), !afterIDs.contains(field.id), field.literal
            else { return false }
            let needle = field.value.hasSuffix("…") ? String(field.value.dropLast()) : field.value
            guard needle.count >= minimumResidueLength, !keptValues.contains(field.value)
            else { return false }
            return contains(output, text: needle)
        }
        return VerificationResult(
            stillPresent: stillPresent, residue: residue, alsoRemoved: alsoRemoved)
    }

    /// Searches for text stored as UTF-8 or UTF-16 in either byte order.
    static func contains(_ data: Data, text: String) -> Bool {
        let encodings: [String.Encoding] = [.utf8, .utf16LittleEndian, .utf16BigEndian]
        return encodings.contains { encoding in
            guard let needle = text.data(using: encoding), !needle.isEmpty else { return false }
            return data.range(of: needle) != nil
        }
    }
}
