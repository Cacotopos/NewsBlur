//
//  ForkRailViewController.swift
//  NewsBlur iPad fork — fork-only file, never upstreamed. See fork-docs/.
//

import UIKit

/// Column 1: one squircle per top-level folder, "Other" and Settings pinned at the bottom.
final class ForkRailViewController: UIViewController, UIContextMenuInteractionDelegate {
    /// Fixed rail width: squircle (56) plus room for the badge and a 12pt label like "Technology".
    static let railWidth: CGFloat = 88

    /// Called when the user picks a folder (or Other).
    var onSelect: ((ForkFolder) -> Void)?

    private static let selectedKeyDefaults = "fork_selected_folder"

    private let scrollView = UIScrollView()
    private let folderStack = UIStackView()
    private let bottomStack = UIStackView()
    private let border = UIView()
    private let otherButton = ForkRailButton()
    private let settingsButton = UIButton(type: .system)

    private var folders: [ForkFolder] = []
    private var other: ForkFolder?
    private var folderButtons: [ForkRailButton] = []
    private var lastTheme = ""

    /// The user's saved choice. Only written by a tap, never by a fallback, so a launch that sees
    /// partial or stale folder data can't overwrite it.
    private var savedKey: String? {
        get { UserDefaults.standard.string(forKey: Self.selectedKeyDefaults) }
        set { UserDefaults.standard.set(newValue, forKey: Self.selectedKeyDefaults) }
    }

    /// The saved folder if it exists right now, otherwise the first folder (or Other).
    var selectedFolder: ForkFolder? {
        if let key = savedKey {
            if key == other?.key, let other, !other.feedIds.isEmpty { return other }
            if let match = folders.first(where: { $0.key == key }) { return match }
        }
        return folders.first ?? other
    }

    var selectedKey: String? { selectedFolder?.key }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "fork-rail"

        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        folderStack.axis = .vertical
        folderStack.alignment = .center
        folderStack.spacing = 6
        folderStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(folderStack)

        bottomStack.axis = .vertical
        bottomStack.alignment = .center
        bottomStack.spacing = 6
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomStack)

        otherButton.symbolName = "tray"
        otherButton.addTarget(self, action: #selector(otherTapped), for: .touchUpInside)
        bottomStack.addArrangedSubview(otherButton)

        settingsButton.setImage(UIImage(systemName: "gearshape",
                                        withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)),
                                for: .normal)
        settingsButton.accessibilityLabel = NSLocalizedString("Settings", comment: "Fork rail settings button")
        settingsButton.accessibilityIdentifier = "fork-rail-settings"
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        bottomStack.addArrangedSubview(settingsButton)

        border.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(border)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: guide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: border.leadingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomStack.topAnchor, constant: -6),

            folderStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 10),
            folderStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -6),
            folderStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
            folderStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),

            bottomStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomStack.trailingAnchor.constraint(equalTo: border.leadingAnchor),
            bottomStack.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -8),
            settingsButton.widthAnchor.constraint(equalToConstant: 48),
            settingsButton.heightAnchor.constraint(equalToConstant: 48),

            border.topAnchor.constraint(equalTo: view.topAnchor),
            border.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            border.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            border.widthAnchor.constraint(equalToConstant: 1 / max(1, traitCollection.displayScale)),
        ])

        refresh(force: true)
    }

    /// Re-reads folders and counts from upstream. Cheap when nothing changed.
    func refresh(force: Bool = false) {
        guard isViewLoaded else { return }
        let newFolders = ForkFolderStore.topLevelFolders()
        let newOther = ForkFolderStore.otherFolder()
        let theme = ForkTheme.current
        let themeChanged = theme != lastTheme
        guard force || themeChanged || newFolders != folders || newOther != other else { return }

        let structureChanged = newFolders.map(\.key) != folders.map(\.key)
        folders = newFolders
        other = newOther
        lastTheme = theme

        if structureChanged || folderButtons.isEmpty {
            folderButtons.forEach { $0.removeFromSuperview() }
            folderButtons = folders.map { _ in
                let button = ForkRailButton()
                button.addTarget(self, action: #selector(folderTapped(_:)), for: .touchUpInside)
                button.addInteraction(UIContextMenuInteraction(delegate: self))
                folderStack.addArrangedSubview(button)
                return button
            }
        }
        applyContent()
        applyTheme()
    }

    private func applyContent() {
        for (button, folder) in zip(folderButtons, folders) {
            button.configure(folder: folder, label: ForkFolderAppearance.label(for: folder),
                             glyph: glyph(for: folder), selected: folder.key == selectedKey)
        }
        if let other {
            otherButton.configure(folder: other, label: other.shortLabel, glyph: .symbol("tray"),
                                  selected: other.key == selectedKey)
            otherButton.isHidden = other.feedIds.isEmpty
        }
    }

    private func glyph(for folder: ForkFolder) -> ForkRailButton.Glyph {
        switch ForkFolderAppearance.icon(for: folder.key) {
        case .initials:
            return .initials(ForkFolderAppearance.initials(for: folder))
        case .symbol(let name):
            return UIImage(systemName: name) == nil ? .initials(ForkFolderAppearance.initials(for: folder)) : .symbol(name)
        case .firstFeed:
            guard let feedId = folder.feedIds.first, let image = NewsBlurAppDelegate.shared?.getFavicon(feedId) else {
                return .initials(ForkFolderAppearance.initials(for: folder))
            }
            return .image(image)
        }
    }

    // MARK: - Long-press menu (M8)

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let button = interaction.view as? ForkRailButton,
              let index = folderButtons.firstIndex(of: button), folders.indices.contains(index) else { return nil }
        let folder = folders[index]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            self?.menu(for: folder)
        }
    }

    private func menu(for folder: ForkFolder) -> UIMenu {
        let current = ForkFolderAppearance.icon(for: folder.key)
        let initials = UIAction(title: NSLocalizedString("Initials", comment: "Fork folder icon menu"),
                                image: UIImage(systemName: "textformat"),
                                state: current == .initials ? .on : .off) { [weak self] _ in
            self?.setIcon(.initials, for: folder)
        }
        var symbolState: UIMenuElement.State = .off
        var currentSymbol: String?
        if case .symbol(let name) = current { symbolState = .on; currentSymbol = name }
        let symbol = UIAction(title: NSLocalizedString("Symbol…", comment: "Fork folder icon menu"),
                              image: UIImage(systemName: currentSymbol ?? "square.grid.3x3"),
                              state: symbolState) { [weak self] _ in
            guard let self else { return }
            ForkSymbolPicker.present(from: self, folderTitle: folder.title, current: currentSymbol) { [weak self] name in
                self?.setIcon(.symbol(name), for: folder)
            }
        }
        let firstFeed = UIAction(title: NSLocalizedString("First Feed's Icon", comment: "Fork folder icon menu"),
                                 image: UIImage(systemName: "photo"),
                                 state: current == .firstFeed ? .on : .off) { [weak self] _ in
            self?.setIcon(.firstFeed, for: folder)
        }
        let iconMenu = UIMenu(title: NSLocalizedString("Icon", comment: "Fork folder icon menu"),
                              options: .displayInline, children: [initials, symbol, firstFeed])

        var labelActions: [UIMenuElement] = [
            UIAction(title: NSLocalizedString("Rename Label…", comment: "Fork folder label menu"),
                     image: UIImage(systemName: "character.cursor.ibeam")) { [weak self] _ in
                self?.promptForLabel(folder)
            },
        ]
        if ForkFolderAppearance.customLabel(for: folder.key) != nil {
            labelActions.append(UIAction(title: NSLocalizedString("Reset Label", comment: "Fork folder label menu"),
                                         image: UIImage(systemName: "arrow.uturn.backward")) { [weak self] _ in
                ForkFolderAppearance.setCustomLabel(nil, for: folder.key)
                self?.refresh(force: true)
            })
        }
        let labelMenu = UIMenu(title: "", options: .displayInline, children: labelActions)
        return UIMenu(title: folder.title, children: [iconMenu, labelMenu])
    }

    private func setIcon(_ icon: ForkFolderIcon, for folder: ForkFolder) {
        ForkFolderAppearance.setIcon(icon, for: folder.key)
        refresh(force: true)
    }

    private func promptForLabel(_ folder: ForkFolder) {
        let alert = UIAlertController(title: NSLocalizedString("Rail Label", comment: "Fork folder label prompt title"),
                                      message: folder.title, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = ForkFolderAppearance.label(for: folder)
            field.placeholder = folder.shortLabel
            field.clearButtonMode = .whileEditing
            field.autocapitalizationType = .words
            field.accessibilityIdentifier = "fork-label-field"
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Fork folder label prompt"), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Save", comment: "Fork folder label prompt"), style: .default) { [weak self, weak alert] _ in
            ForkFolderAppearance.setCustomLabel(alert?.textFields?.first?.text, for: folder.key)
            self?.refresh(force: true)
        })
        present(alert, animated: true)
    }

    private func applyTheme() {
        view.backgroundColor = ForkTheme.railBackground
        border.backgroundColor = ForkTheme.railBorder
        settingsButton.tintColor = ForkTheme.railLabel
        (folderButtons + [otherButton]).forEach { $0.applyTheme() }
    }

    private func select(_ folder: ForkFolder) {
        savedKey = folder.key
        applyContent()
        onSelect?(folder)
    }

    @objc private func folderTapped(_ sender: ForkRailButton) {
        guard let index = folderButtons.firstIndex(of: sender), folders.indices.contains(index) else { return }
        select(folders[index])
    }

    @objc private func otherTapped() {
        guard let other else { return }
        select(other)
    }

    @objc private func settingsTapped() {
        NewsBlurAppDelegate.shared?.showPreferences()
    }
}

/// One squircle + label in the rail.
final class ForkRailButton: UIControl {
    enum Glyph { case initials(String), symbol(String), image(UIImage) }

    static let squircleSize: CGFloat = 56

    var symbolName: String?

    private let squircle = UIView()
    private let initialsLabel = UILabel()
    private let symbolView = UIImageView()
    private let imageView = UIImageView()
    private let badge = ForkBadgeLabel()
    private let titleLabel = UILabel()
    private var isChosen = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .button

        squircle.isUserInteractionEnabled = false
        squircle.layer.cornerRadius = 17
        squircle.layer.cornerCurve = .continuous
        squircle.layer.shadowColor = UIColor.black.cgColor
        squircle.layer.shadowOpacity = 0.10
        squircle.layer.shadowRadius = 1
        squircle.layer.shadowOffset = CGSize(width: 0, height: 1)
        squircle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(squircle)

        initialsLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        initialsLabel.textAlignment = .center
        initialsLabel.translatesAutoresizingMaskIntoConstraints = false
        squircle.addSubview(initialsLabel)

        symbolView.contentMode = .scaleAspectFit
        symbolView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        squircle.addSubview(symbolView)

        imageView.contentMode = .scaleAspectFit
        imageView.layer.cornerRadius = 6
        imageView.layer.cornerCurve = .continuous
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        squircle.addSubview(imageView)

        badge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge)

        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8
        titleLabel.adjustsFontForContentSizeCategory = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isUserInteractionEnabled = false
        addSubview(titleLabel)

        let size = Self.squircleSize
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: ForkRailViewController.railWidth - 1),
            squircle.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            squircle.centerXAnchor.constraint(equalTo: centerXAnchor),
            squircle.widthAnchor.constraint(equalToConstant: size),
            squircle.heightAnchor.constraint(equalToConstant: size),

            initialsLabel.centerXAnchor.constraint(equalTo: squircle.centerXAnchor),
            initialsLabel.centerYAnchor.constraint(equalTo: squircle.centerYAnchor),
            symbolView.centerXAnchor.constraint(equalTo: squircle.centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: squircle.centerYAnchor),
            imageView.centerXAnchor.constraint(equalTo: squircle.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: squircle.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 32),
            imageView.heightAnchor.constraint(equalToConstant: 32),

            badge.topAnchor.constraint(equalTo: squircle.topAnchor, constant: -7),
            // Pinned by its trailing edge so the wider "3/663" stays inside the 88 pt rail.
            badge.trailingAnchor.constraint(equalTo: squircle.trailingAnchor, constant: 10),

            titleLabel.topAnchor.constraint(equalTo: squircle.bottomAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(folder: ForkFolder, label: String, glyph: Glyph, selected: Bool) {
        isChosen = selected
        titleLabel.text = label
        initialsLabel.isHidden = true
        symbolView.isHidden = true
        imageView.isHidden = true
        switch glyph {
        case .initials(let text):
            initialsLabel.text = text
            initialsLabel.isHidden = false
        case .symbol(let name):
            symbolView.image = UIImage(systemName: name)
            symbolView.isHidden = false
        case .image(let image):
            imageView.image = image
            imageView.isHidden = false
        }
        // "feeds/stories": 3/12 = three publications with something unread, twelve unread stories.
        badge.text = folder.unread > 0
            ? "\(NBLocalization.formattedCount(folder.unreadFeeds))/\(NBLocalization.formattedCount(folder.unread))" : nil
        badge.isHidden = folder.unread == 0
        accessibilityIdentifier = "fork-rail-\(folder.key)"
        accessibilityLabel = folder.title
        accessibilityValue = folder.unread > 0
            ? String.localizedStringWithFormat(NSLocalizedString("%d unread in %d feeds", comment: "Fork rail badge"),
                                               folder.unread, folder.unreadFeeds) : nil
        accessibilityTraits = selected ? [.button, .selected] : .button
        applyTheme()
    }

    func applyTheme() {
        squircle.backgroundColor = isChosen ? ForkTheme.squircleSelected : ForkTheme.squircle
        let glyphColor = isChosen ? ForkTheme.squircleSelectedText : ForkTheme.squircleText
        initialsLabel.textColor = glyphColor
        symbolView.tintColor = glyphColor
        titleLabel.textColor = isChosen ? ForkTheme.railLabelSelected : ForkTheme.railLabel
        titleLabel.font = .systemFont(ofSize: 12, weight: isChosen ? .semibold : .medium)
        badge.backgroundColor = ForkTheme.badge
        badge.textColor = ForkTheme.badgeText
        badge.layer.borderColor = ForkTheme.railBackground.cgColor
    }

    override var isHighlighted: Bool {
        didSet { squircle.alpha = isHighlighted ? 0.7 : 1 }
    }
}

/// Pill-shaped unread count.
final class ForkBadgeLabel: UILabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
        font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        textAlignment = .center
        layer.borderWidth = 2
        layer.masksToBounds = true
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: CGSize {
        let base = super.intrinsicContentSize
        let height = base.height + 8
        return CGSize(width: max(height, base.width + 14), height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}
