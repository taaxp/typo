import SwiftUI

@main
struct TypoWatchApp: App {
    @State private var store = WatchStore()
    @State private var path: [UUID] = []

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                WatchHomeView()
                    .navigationDestination(for: UUID.self) { id in
                        if let card = store.pack.cards.first(where: { $0.id == id }) {
                            CardFullView(card: card)
                        }
                    }
            }
            .environment(store)
            .task { store.start() }
            // Complications open a card directly: typowatch://card/<uuid>
            .onOpenURL { url in
                guard url.scheme == "typowatch", url.host() == "card",
                      let id = UUID(uuidString: url.lastPathComponent) else { return }
                path = [id]
            }
        }
    }
}

struct WatchHomeView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        List {
            if store.pack.cards.isEmpty && store.pack.snippets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "iphone.and.arrow.forward").font(.title3)
                    Text("On your iPhone, open Typo › Codes and choose Show on Apple Watch. Pinned snippets appear here too.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }
            if !store.pack.cards.isEmpty {
                Section("Cards") {
                    ForEach(store.pack.cards) { card in
                        NavigationLink(value: card.id) { CardRow(card: card) }
                            .listRowBackground(Color.clear)
                    }
                }
            }
            if !store.pack.snippets.isEmpty {
                Section("Pinned") {
                    ForEach(store.pack.snippets) { snippet in
                        NavigationLink { SnippetView(snippet: snippet) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(snippet.title).font(.headline).lineLimit(1)
                                Text(snippet.text).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Typo")
    }
}

/// A glass hue card in the list.
private struct CardRow: View {
    let card: WatchCard

    var body: some View {
        let hue = Hues.named(card.hueName)
        HStack(spacing: 10) {
            Image(systemName: card.symbol)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(hue.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(card.title).font(.headline).lineLimit(1)
                Text(card.kind == .member ? "Member card" : card.kind == .wifi ? "Guest Wi-Fi" : "QR code")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hue.softGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .glassEffect(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// The code as large as the screen allows, on white for the scanner.
struct CardFullView: View {
    let card: WatchCard
    @Environment(WatchStore.self) private var store

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            if let image = store.image(for: card) {
                image.resizable().interpolation(.none).scaledToFit().padding(4)
            } else {
                ProgressView("Waiting for iPhone…").tint(.black).foregroundStyle(.black)
            }
        }
        .navigationTitle(card.title)
        .accessibilityLabel("\(card.title). \(card.caption)")
    }
}

/// Pinned snippets are for reading: the watch has no clipboard.
struct SnippetView: View {
    let snippet: WatchSnippet

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(snippet.text).font(.title3).fontWeight(.medium)
                Text("Read-only on Apple Watch").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(snippet.title)
    }
}
