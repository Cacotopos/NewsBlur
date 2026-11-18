//
//  ForkStoryContent.swift
//  NewsBlur iPad fork — fork-only file, never upstreamed. See fork-docs/.
//

import Foundation

/// Fills in the picture for teaser-only stories (e.g. Penny Arcade's "New Comic: Gunn Jamm").
///
/// Some feeds put only a short teaser in the story body while the NewsBlur server still finds the
/// image on the page and stores it in `image_urls`. Upstream's reader renders only the body, so the
/// cartoon never shows. Called from hook H5 in `StoryDetailObjCViewController.m`.
@objcMembers
final class ForkStoryContent: NSObject {
    /// Bodies with at most this much visible text count as teasers. Longer posts are left alone:
    /// their `image_urls` can be an author avatar rather than the story's picture.
    static let teaserMaxCharacters = 200

    /// Returns `content`, with the story's first image appended when the body is a teaser without images.
    static func content(_ content: String?, story: [AnyHashable: Any]?, inTextView: Bool) -> String? {
        guard ForkUI.isActive, !inTextView, let story,
              let imageURL = (story["image_urls"] as? [Any])?.first as? String,
              imageURL.lowercased().hasPrefix("http") else { return content }
        let body = content ?? ""
        guard body.range(of: "<img", options: .caseInsensitive) == nil,
              visibleText(of: body).count <= teaserMaxCharacters else { return content }
        let escaped = imageURL
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
        return body + "<p class=\"NB-fork-teaser-image\"><img src=\"\(escaped)\"></p>"
    }

    private static func visibleText(of html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
