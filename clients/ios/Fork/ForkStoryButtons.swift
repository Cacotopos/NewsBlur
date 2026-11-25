//  ForkStoryButtons.swift
//  NewsBlur
//
//  Fork replacement for the story-button preference half of upstream's
//  Listen/ListenPreferences.swift + Listen/ListenStoryBridge.swift, which the
//  fork stripped with the rest of the Listen audio subsystem. Keeps the
//  show_sideoption_* toggles (Share / Save) working in
//  StoryDetailObjCViewController and syncing via /profile/set_preference.
//

import Foundation

@objcMembers
final class ForkStoryButtons: NSObject {
    /// Local UserDefaults key per button name; the names match the server keys.
    private static let storyButtons: [(name: String, localKey: String)] = [
        ("share", "show_sideoption_share"),
        ("save", "show_sideoption_save"),
    ]

    static let didChange = Notification.Name("ListenPreferencesDidChange")

    private static var defaults: UserDefaults { .standard }

    @discardableResult
    private static func store(_ value: Any, forKey key: String) -> Bool {
        if let current = defaults.object(forKey: key) as? NSObject,
           let new = value as? NSObject, current.isEqual(new) {
            return false
        }
        defaults.set(value, forKey: key)
        return true
    }

    /// Whether the story button named share or save is shown. Unknown names show.
    static func showsStoryButton(_ name: String) -> Bool {
        guard let key = storyButtons.first(where: { $0.name == name })?.localKey else { return true }
        return defaults.object(forKey: key) == nil || defaults.bool(forKey: key)
    }

    static func serverKey(forLocalKey key: String) -> String {
        key
    }

    static func isStoryButtonKey(_ key: String) -> Bool {
        storyButtons.contains { $0.localKey == key }
    }

    // MARK: - Called from upstream code

    /// FeedsObjCViewController.m hands over the profile from /reader/feeds.
    static func syncFromUserProfile(_ userProfile: [AnyHashable: Any]?) {
        guard let userProfile,
              let preferences = jsonObject(from: userProfile["preferences"]) else { return }
        var changed: [String] = []

        for button in storyButtons {
            let serverKey = serverKey(forLocalKey: button.localKey)
            if let value = jsonBool(preferences[serverKey]), store(value, forKey: button.localKey) {
                changed.append(button.localKey)
            }
        }

        if !changed.isEmpty {
            NotificationCenter.default.post(name: didChange, object: nil, userInfo: ["keys": changed])
        }
    }

    /// PreferencesView.swift changed a value. Returns whether it was a story button preference.
    static func preferenceDidChange(_ key: String?) -> Bool {
        guard let key, isStoryButtonKey(key), let value = defaults.object(forKey: key) else { return false }
        NotificationCenter.default.post(name: didChange, object: nil, userInfo: ["keys": [key]])
        send([serverKey(forLocalKey: key): serverString(value)])
        return true
    }

    // MARK: - Server write

    private static func send(_ values: [String: String]) {
        guard !values.isEmpty else { return }
        updateCachedProfile(values)
        guard let appDelegate = NewsBlurAppDelegate.shared() else { return }
        appDelegate.post("\(appDelegate.url)/profile/set_preference", parameters: values,
                         success: { _, _ in },
                         failure: { _, error in
            NSLog("Failed to save story button preferences %@: %@",
                  values.keys.joined(separator: ", "), (error as NSError?) ?? NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown))
        })
    }

    /// Mirrors FeedsObjCViewController.m's updateCachedUserProfilePreferenceWithKey: so later reads see the change.
    private static func updateCachedProfile(_ values: [String: String]) {
        guard let appDelegate = NewsBlurAppDelegate.shared(),
              let profile = appDelegate.dictUserProfile, !profile.isEmpty else { return }
        var userProfile = profile
        var preferences = jsonObject(from: userProfile["preferences"]) ?? [:]
        for (key, value) in values {
            switch value {
            case "true": preferences[key] = true
            case "false": preferences[key] = false
            default: preferences[key] = value
            }
        }
        userProfile["preferences"] = preferences
        appDelegate.dictUserProfile = userProfile
    }

    // MARK: - JSON helpers (subset of upstream's ListenJSON)

    private static func jsonObject(from value: Any?) -> [String: Any]? {
        if let string = value as? String, let data = string.data(using: .utf8) {
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        return value as? [String: Any]
    }

    private static func jsonBool(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool: return bool
        case let number as NSNumber: return number.boolValue
        case let string as String:
            if string == "true" { return true }
            if string == "false" { return false }
            return nil
        default: return nil
        }
    }

    private static func serverString(_ value: Any) -> String {
        if let bool = value as? Bool { return bool ? "true" : "false" }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return "\(number)"
        }
        return "\(value)"
    }
}
