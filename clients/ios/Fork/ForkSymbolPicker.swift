//
//  ForkSymbolPicker.swift
//  NewsBlur iPad fork — fork-only file, never upstreamed. See fork-docs/.
//

import SwiftUI
import UIKit

/// Grid of SF Symbols for a folder's squircle, with a search field.
///
/// iOS has no public list of every SF Symbol, so this is a curated set of topics a feed folder is
/// likely to hold. Names the running iOS doesn't have are dropped.
struct ForkSymbolPicker: View {
    let folderTitle: String
    let current: String?
    let onPick: (String) -> Void
    let onCancel: () -> Void

    @State private var query = ""

    static let symbols: [String] = [
        // News and writing
        "newspaper", "newspaper.fill", "doc.text", "text.book.closed", "book", "book.closed", "books.vertical",
        "magazine", "pencil", "pencil.and.scribble", "highlighter", "quote.bubble", "text.quote", "character.book.closed",
        "envelope", "tray.full", "archivebox", "bookmark", "tag", "megaphone", "mic", "radio", "antenna.radiowaves.left.and.right",
        // Technology
        "desktopcomputer", "laptopcomputer", "ipad", "iphone", "applelogo", "keyboard", "cpu", "memorychip",
        "server.rack", "network", "wifi", "terminal", "chevron.left.forwardslash.chevron.right", "curlybraces",
        "apple.terminal", "gearshape.2", "wrench.and.screwdriver", "hammer", "cable.connector", "externaldrive",
        "sparkles", "brain", "brain.head.profile", "lock.shield", "key",
        // Games, comics and entertainment
        "gamecontroller", "dice", "puzzlepiece", "theatermasks", "face.smiling", "paintpalette", "paintbrush",
        "photo", "camera", "film", "tv", "play.rectangle", "music.note", "headphones", "guitars", "popcorn",
        "ticket", "star", "crown", "trophy",
        // World, politics and money
        "globe", "globe.americas", "globe.europe.africa", "globe.asia.australia", "map", "flag", "building.columns",
        "building.2", "house", "briefcase", "chart.line.uptrend.xyaxis", "chart.bar", "dollarsign.circle",
        "banknote", "cart", "bag", "creditcard", "scalemass",
        // Science, health and nature
        "atom", "flask", "testtube.2", "microscope", "stethoscope", "cross.case", "heart", "leaf", "tree",
        "mountain.2", "sun.max", "moon.stars", "cloud.sun", "drop", "flame", "bolt", "snowflake",
        "pawprint", "hare", "tortoise", "bird", "fish", "ant", "ladybug",
        // Sport, travel and life
        "sportscourt", "figure.run", "bicycle", "soccerball", "basketball", "tennisball", "car", "airplane",
        "tram", "sailboat", "fork.knife", "cup.and.saucer", "wineglass", "graduationcap", "backpack",
        "person.2", "figure.2.and.child.holdinghands", "calendar", "clock", "lightbulb", "bell", "bubble.left.and.bubble.right",
    ].filter { UIImage(systemName: $0) != nil }

    private var filtered: [String] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return Self.symbols }
        return Self.symbols.filter { name in words.allSatisfy { name.contains($0) } }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 12)], spacing: 12) {
                    ForEach(filtered, id: \.self) { name in
                        Button { onPick(name) } label: {
                            Image(systemName: name)
                                .font(.system(size: 24))
                                .frame(width: 64, height: 64)
                                .background(
                                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                                        .fill(name == current ? Color.accentColor.opacity(0.2) : Color(uiColor: .secondarySystemBackground))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(name.replacingOccurrences(of: ".", with: " "))
                        .accessibilityIdentifier("fork-symbol-\(name)")
                    }
                }
                .padding(16)
                if filtered.isEmpty {
                    Text(NSLocalizedString("No matching symbols", comment: "Fork symbol picker empty search"))
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: NSLocalizedString("Search symbols", comment: "Fork symbol picker search prompt"))
            .navigationTitle(folderTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "Fork symbol picker cancel"), action: onCancel)
                }
            }
        }
    }

    /// Presents the picker as a form sheet from `presenter`.
    static func present(from presenter: UIViewController, folderTitle: String, current: String?,
                        onPick: @escaping (String) -> Void) {
        weak var host: UIViewController?
        let picker = ForkSymbolPicker(folderTitle: folderTitle, current: current,
                                      onPick: { name in host?.dismiss(animated: true); onPick(name) },
                                      onCancel: { host?.dismiss(animated: true) })
        let controller = UIHostingController(rootView: picker)
        controller.modalPresentationStyle = .formSheet
        host = controller
        presenter.present(controller, animated: true)
    }
}
