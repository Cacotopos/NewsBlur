//
//  ForkBranding.swift
//  NewsBlur iPad fork — fork-only file, never upstreamed. See fork-docs/.
//

import UIKit

/// The Cacotopic Edition logo in place of upstream's orange sun inside the app.
///
/// Used by hook H13 in `Classes/OnboardingAccountViewController.swift` (login screen) and
/// `Classes/OnboardingViewController.swift` (onboarding header). The image is the app icon as a rounded
/// badge (`ForkLogo` in `Fork/ForkAssets.xcassets`), drawn by `fork-docs/artwork/render_cacotopic.swift`.
enum ForkBranding {
    /// The badge while the fork is active, or nil to keep upstream's logo.
    static var logo: UIImage? {
        guard ForkUI.isActive else { return nil }
        return UIImage(named: "ForkLogo")
    }
}
