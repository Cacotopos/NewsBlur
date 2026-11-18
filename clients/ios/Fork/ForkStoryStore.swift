//
//  ForkStoryStore.swift
//  NewsBlur iPad fork — fork-only file, never upstreamed. See fork-docs/.
//

import Foundation

/// One story as the feed column shows it.
struct ForkStory: Equatable {
    let hash: String
    let feedId: String
    let title: String
    let date: String
    var isRead: Bool
}

/// Loaded stories for one feed under one read filter.
final class ForkFeedStories {
    let feedId: String
    let readFilter: String
    private(set) var stories: [ForkStory] = []
    private(set) var nextPage = 1
    private(set) var isLoading = false
    private(set) var reachedEnd = false
    private(set) var failed = false

    init(feedId: String, readFilter: String) {
        self.feedId = feedId
        self.readFilter = readFilter
    }

    /// Fetches the next page from `/reader/feed/<id>/` (the same endpoint upstream's story list uses).
    func loadNextPage(completion: @escaping () -> Void) {
        guard !isLoading, !reachedEnd, let app = NewsBlurAppDelegate.shared else { return }
        isLoading = true
        failed = false
        let url = "\(app.url ?? "")/reader/feed/\(feedId)/?page=\(nextPage)&order=newest&read_filter=\(readFilter)"
        app.get(url, parameters: nil, success: { [weak self] _, response in
            guard let self else { return }
            self.isLoading = false
            let raw = (response as? [String: Any])?["stories"] as? [[String: Any]] ?? []
            let known = Set(self.stories.map(\.hash))
            let parsed = raw.compactMap(Self.parse).filter { !known.contains($0.hash) }
            self.stories.append(contentsOf: parsed)
            self.nextPage += 1
            if raw.isEmpty { self.reachedEnd = true }
            completion()
        }, failure: { [weak self] _, _ in
            self?.isLoading = false
            self?.failed = true
            completion()
        })
    }

    /// Copies read state that upstream changed (story opened in the reader, marked read elsewhere).
    /// Returns true when anything changed.
    func syncReadState(from upstreamStories: [String: Bool]) -> Bool {
        var changed = false
        for index in stories.indices {
            if let read = upstreamStories[stories[index].hash], read != stories[index].isRead {
                stories[index].isRead = read
                changed = true
            }
        }
        return changed
    }

    func markRead(hash: String) {
        if let index = stories.firstIndex(where: { $0.hash == hash }) { stories[index].isRead = true }
    }

    private static func parse(_ story: [String: Any]) -> ForkStory? {
        guard let hash = story["story_hash"] as? String else { return nil }
        // Upstream hides stories the user's training scored negative.
        let score = NewsBlurAppDelegate.computeStoryScore(story["intelligence"] as? [AnyHashable: Any])
        guard score >= 0 else { return nil }
        let feedId = story["story_feed_id"].map { "\($0)" } ?? ""
        let title = (story["story_title"] as? NSString)?.decodingHTMLEntities().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let read = (story["read_status"] as? NSNumber)?.boolValue ?? false
        return ForkStory(hash: hash, feedId: feedId, title: title.isEmpty ? "(untitled)" : title,
                         date: story["short_parsed_date"] as? String ?? "", isRead: read)
    }
}
