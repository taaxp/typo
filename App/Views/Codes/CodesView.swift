import SwiftUI
import SwiftData

/// Saved QR codes and member cards.
struct CodesView: View {
    enum Section: String, CaseIterable { case qr = "QR Codes", member = "Member Cards" }

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \CodeItem.sortIndex, order: .reverse) private var codes: [CodeItem]
    @State private var section: Section = .qr
    @State private var editing: CodeItem?
    @State private var presenting: CodeDraft?
    @State private var creating = false

    private var library: CodeLibrary { CodeLibrary(context: context) }

    private var visible: [CodeItem] {
        let filtered = codes.filter { section == .member ? $0.isMemberCard : !$0.isMemberCard }
        return filtered.filter(\.isPinned) + filtered.filter { !$0.isPinned }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Show", selection: $section) {
                    ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if visible.isEmpty {
                    ContentUnavailableView(section == .qr ? "No QR codes yet" : "No member cards yet",
                                           systemImage: section == .qr ? "qrcode" : "barcode",
                                           description: Text(section == .qr
                                                ? "Make one for your guest Wi-Fi, a link or your contact details."
                                                : "Add a gym, library or rewards card, or scan one with the camera."))
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14)], spacing: 14) {
                        ForEach(visible) { item in
                            CodeTile(item: item, draft: library.draft(for: item))
                                .onTapGesture { presenting = library.draft(for: item) }
                                .contextMenu { menu(for: item) }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background { AmbientBackground(hues: [Hues.named("Lagoon"), Hues.named("Mist"), Hues.named("Amber")]) }
        .navigationTitle("Codes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(section == .qr ? "New QR Code" : "New Member Card", systemImage: "plus") { creating = true }
            }
        }
        .sheet(isPresented: $creating) {
            NavigationStack { QRStudioView(draft: newDraft()) }
        }
        .sheet(item: $editing) { item in
            NavigationStack { QRStudioView(draft: library.draft(for: item), editing: item) }
        }
        #if os(iOS)
        .fullScreenCover(item: $presenting) { PresentCodeView(draft: $0) }
        #else
        .sheet(item: $presenting) { PresentCodeView(draft: $0).frame(minWidth: 520, minHeight: 640) }
        #endif
    }

    private func newDraft() -> CodeDraft {
        var draft = CodeDraft()
        if section == .member {
            draft.isMember = true
            draft.symbology = .code128
            draft.style = CodeStyle(fillHue: nil, showFrame: false)
        }
        return draft
    }

    @ViewBuilder
    private func menu(for item: CodeItem) -> some View {
        Button("Present", systemImage: "rectangle.portrait.and.arrow.forward") { presenting = library.draft(for: item) }
        Button("Edit…", systemImage: "slider.horizontal.3") { editing = item }
        Button(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin") {
            item.isPinned.toggle(); try? context.save()
        }
        #if os(iOS)
        Button(item.showOnWidget ? "Remove from Widget" : "Show on Widget", systemImage: "square.grid.2x2") {
            library.setOnWidget(item, !item.showOnWidget)
            model.show(item.showOnWidget ? "On your widget" : "Removed from widget")
        }
        #endif
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { library.delete(item) }
    }
}

extension CodeDraft: Identifiable {
    var id: String { message + title }
}

private struct CodeTile: View {
    let item: CodeItem
    let draft: CodeDraft

    var body: some View {
        let hue = Hues.named(item.hueName)
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let m = try? CodeGenerator.matrix(for: draft.message, symbology: draft.symbology, correction: draft.style.correction) {
                    CodeCanvas(matrix: m, symbology: draft.symbology, style: draft.style)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    HueTile(hue: hue, symbol: "qrcode", size: 64).frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            HStack(spacing: 6) {
                if item.isPinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Hues.named("Amber").gradient) }
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
                if item.showOnWidget { Image(systemName: "square.grid.2x2.fill").font(.caption2).foregroundStyle(.secondary) }
            }
            HueChip(title: item.isMemberCard ? (Symbology(rawValue: item.symbologyRaw)?.title ?? "Card") : draft.type.title,
                    hue: hue, compact: true)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.45), lineWidth: 0.5))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
