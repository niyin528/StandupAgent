import Foundation
import AppKit

// MARK: - Message Model

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    var content: String
    var isStreaming: Bool = false
    var images: [AttachedImage] = []

    enum Role { case user, assistant }
}

struct AttachedImage: Identifiable {
    let id = UUID()
    let nsImage: NSImage
    var base64: String {
        guard let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return "" }
        return png.base64EncodedString()
    }
    var mediaType: String { "image/jpeg" }
}
