import SwiftUI
import PDFKit

struct PDFFocus: Equatable {
    let id = UUID()
    let query: String
}

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    let focus: PDFFocus?
    let onResult: (Bool) -> Void

    final class Coordinator {
        var lastFocus: UUID?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.document = document
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = UIColor.clear
        v.pageShadowsEnabled = false
        return v
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
        guard let focus = focus, context.coordinator.lastFocus != focus.id else { return }
        context.coordinator.lastFocus = focus.id

        let variants = [focus.query,
                        focus.query.replacingOccurrences(of: "-", with: "–"),
                        focus.query.replacingOccurrences(of: "-", with: " ")]
        var found: PDFSelection? = nil
        for q in variants {
            if let sel = document.findString(q, withOptions: [.caseInsensitive]).first {
                found = sel
                break
            }
        }
        if let sel = found {
            sel.color = UIColor.systemYellow.withAlphaComponent(0.55)
            view.autoScales = false
            view.scaleFactor = max(view.scaleFactorForSizeToFit * 2.4, view.scaleFactor)
            view.go(to: sel)
            view.highlightedSelections = [sel]
            DispatchQueue.main.async { onResult(true) }
        } else {
            DispatchQueue.main.async { onResult(false) }
        }
    }
}

/// Оригинал PDF (для сверки или если таблицу не удалось разобрать автоматически).
struct PDFSheet: View {
    let document: PDFDocument?
    let group: String?
    var inline: Bool = false

    @State private var focus: PDFFocus?

    var body: some View {
        if inline {
            viewer
        } else {
            NavigationStack {
                ZStack {
                    AppBackground()
                    viewer
                        .padding(.horizontal, 14)
                        .padding(.bottom, 20)
                }
                .navigationTitle("Оригинал графика")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    @ViewBuilder
    private var viewer: some View {
        if let d = document {
            PDFKitView(document: d, focus: focus) { _ in }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Theme.glassEdge, lineWidth: 1))
                .shadow(color: Color.black.opacity(0.4), radius: 14, y: 8)
                .onAppear {
                    if let g = group { focus = PDFFocus(query: g) }
                }
        } else {
            Text("PDF недоступен")
                .foregroundStyle(Color.white.opacity(0.6))
        }
    }
}
