// OpenHoop's Finder icons: a small Quick Look extension that shows each saved project's design as its icon. OpenHoop
// draws a picture of the design into every project it saves (QuickLook/Thumbnail.png, see DesignDocument.fileWrapper);
// this hands that picture to Finder, which doesn't look inside packages for it by itself. Built by scripts/build.sh.
import AppKit
import QuickLookThumbnailing

/// Answers Finder's "what does this file look like?" for OpenHoop projects.
@objc(ThumbnailProvider)
final class ThumbnailProvider: QLThumbnailProvider {
    /// Draws the project's saved picture as large as the requested size allows, or fails (and Finder shows the plain
    /// document icon) for projects saved before OpenHoop drew one.
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let file = request.fileURL.appendingPathComponent("QuickLook/Thumbnail.png")
        guard let picture = NSImage(contentsOf: file), picture.size.width > 0, picture.size.height > 0 else {
            handler(nil, CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: file.path])); return
        }
        // Fit the picture inside the size Finder asks for, keeping its shape.
        let fit = min(request.maximumSize.width / picture.size.width, request.maximumSize.height / picture.size.height)
        let size = CGSize(width: picture.size.width * fit, height: picture.size.height * fit)
        handler(QLThumbnailReply(contextSize: size, currentContextDrawing: {
            picture.draw(in: CGRect(origin: .zero, size: size)); return true
        }), nil)
    }
}
