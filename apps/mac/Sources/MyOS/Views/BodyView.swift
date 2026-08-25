import SwiftUI

// The real anatomy body map (ported from fitOS): front/back SVG outlines with
// tappable muscle regions, a detail card, and the best exercises for the selected
// muscle ranked by activation. Renders from SVG path data via SVGPath → CGPath.

struct BodyView: View {
    @EnvironmentObject var state: AppState
    @State private var side = "front"
    @State private var selectedId: String?

    var body: some View {
        Group {
            if let a = state.anatomy {
                content(a)
            } else if let err = state.anatomyError {
                Card {
                    VStack(spacing: 10) {
                        Text("Couldn't load body map").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
                        Text(err).font(.caption).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                        Button("Retry") { Task { state.anatomy = nil; state.anatomyError = nil; await state.loadAnatomy() } }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
                }
            } else {
                Card {
                    HStack(spacing: 10) { ProgressView().controlSize(.small)
                        Text("Loading anatomy…").font(.footnote).foregroundStyle(Palette.muted) }
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                }
            }
        }
        .task {
            await state.loadAnatomy()
            if selectedId == nil { selectedId = state.anatomy?.groups.first?.id }
        }
    }

    @ViewBuilder private func content(_ a: AnatomyData) -> some View {
        let selected = a.groups.first { $0.id == selectedId } ?? a.groups.first
        VStack(alignment: .leading, spacing: 18) {
            Picker("", selection: $side) { ForEach([("front", "Front"), ("back", "Back")], id: \.0) { opt in Text(opt.1).tag(opt.0) } }.pickerStyle(.segmented).labelsHidden().knRise(0)
            chips(a.groups, sel: selected?.id).knRise(1)
            // The figure is the point of this screen; it used to sit small in
            // the middle of a tall card.
            Card(padding: 10) {
                BodyMapView(
                    bodyView: side == "front" ? a.front : a.back,
                    activeSlugs: Set(selected?.view == side ? (selected?.slugs ?? []) : []),
                    interactiveSlugs: Set(a.groups.filter { $0.view == side }.flatMap { $0.slugs }),
                    onSelect: { slug in
                        if let g = a.groups.first(where: { $0.view == side && $0.slugs.contains(slug) }) { selectedId = g.id }
                    }
                )
                .frame(height: 390).frame(maxWidth: .infinity)
            }.knRise(2)
            if let selected {
                MuscleDetailCard(group: selected).knRise(3)
                ActivationList(activation: a.activation[selected.id] ?? []).knRise(4)
            }
        }
    }

    private func chips(_ groups: [AnatomyGroup], sel: String?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(groups) { g in
                    let on = g.id == sel
                    Button { selectedId = g.id; side = g.view } label: {
                        Text(g.name).font(.caption.weight(.heavy))
                            .foregroundStyle(on ? .white : Palette.muted)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(on ? Palette.action : Palette.surfaceElevated.opacity(0.6), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .onHover { h in cursor(h) }
                }
            }
            .padding(.horizontal, 1)
        }
    }
}

/// Renders the body outline + muscle regions from SVG paths, scaled to fit.
struct BodyMapView: View {
    let bodyView: AnatomySide
    let activeSlugs: Set<String>
    let interactiveSlugs: Set<String>
    var onSelect: (String) -> Void = { _ in }

    @State private var muscles: [(slug: String, path: CGPath)] = []
    @State private var outline: CGPath = CGMutablePath()

    private var box: CGRect {
        let p = bodyView.viewBox.split(separator: " ").compactMap { Double($0) }
        guard p.count == 4 else { return CGRect(x: 0, y: 0, width: 724, height: 1448) }
        return CGRect(x: p[0], y: p[1], width: p[2], height: p[3])
    }

    var body: some View {
        ZStack {
            ForEach(Array(muscles.enumerated()), id: \.offset) { _, m in
                let active = activeSlugs.contains(m.slug)
                let clickable = interactiveSlugs.contains(m.slug)
                let shape = CGPathShape(cg: m.path, box: box)
                shape
                    .fill(active ? Palette.action : (clickable ? Palette.muted.opacity(0.55) : Palette.muted.opacity(0.28)))
                    .overlay(shape.stroke(active ? Palette.action.opacity(0.5) : Palette.borderStrong.opacity(0.7), lineWidth: active ? 1.5 : 1))
                    .contentShape(shape)
                    .onTapGesture { if clickable { onSelect(m.slug) } }
            }
            CGPathShape(cg: outline, box: box)
                .stroke(Palette.text.opacity(0.45), lineWidth: 1.5)
                .allowsHitTesting(false)
        }
        .task(id: bodyView.viewBox + "#\(bodyView.muscles.count)") { parse() }
    }

    private func parse() {
        muscles = bodyView.muscles.map { m in
            let cg = CGMutablePath()
            for d in m.paths { cg.addPath(SVGPath.cgPath(from: d)) }
            return (m.slug, cg)
        }
        outline = SVGPath.cgPath(from: bodyView.outline)
    }
}

/// A Shape backed by a CGPath in viewBox coords, fitted (aspect-preserving) into its rect.
struct CGPathShape: Shape {
    let cg: CGPath
    let box: CGRect
    func path(in rect: CGRect) -> Path {
        guard box.width > 0, box.height > 0 else { return Path(cg) }
        let scale = min(rect.width / box.width, rect.height / box.height)
        let ox = rect.minX + (rect.width - box.width * scale) / 2 - box.minX * scale
        let oy = rect.minY + (rect.height - box.height * scale) / 2 - box.minY * scale
        var t = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: ox, ty: oy)
        return Path(cg.copy(using: &t) ?? cg)
    }
}

/// The selected muscle group's blurb + the muscles inside it.
struct MuscleDetailCard: View {
    let group: AnatomyGroup
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text(group.name).font(.body.weight(.heavy)).foregroundStyle(Palette.text)
                Text(group.blurb).font(.footnote).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                ForEach(Array(group.muscles.enumerated()), id: \.offset) { i, m in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("\(i + 1)").font(.caption2.weight(.heavy)).frame(width: 20, height: 20)
                                .background(Palette.action.opacity(0.15), in: Circle()).foregroundStyle(Palette.action)
                            Text(m.name).font(.footnote.weight(.bold)).foregroundStyle(Palette.text)
                        }
                        Text(m.what).font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        (Text("TRAIN  ").font(.caption2.weight(.heavy)).foregroundColor(Palette.faint)
                         + Text(m.train).font(.caption).foregroundColor(Palette.text))
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }
}

/// Best exercises for the selected muscle, ranked by activation. Tap → demo.
struct ActivationList: View {
    @EnvironmentObject var state: AppState
    let activation: [Activation]
    @State private var demo: Exercise?

    private var rows: [(ex: Exercise, percent: Double)] {
        activation.compactMap { a in
            state.allExercises.first { $0.name.lowercased() == a.name.lowercased() }.map { ($0, a.percent) }
        }
    }

    var body: some View {
        if !rows.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionTitle(text: "Best builders")
                        Spacer()
                        // These come from a reference dataset, not from
                        // anything measured on you — the caption says so rather
                        // than letting "96%" imply a lab.
                        Text("reference ranking").font(.caption2).foregroundStyle(Palette.faint)
                    }
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                        Button { demo = r.ex } label: { row(i, r.ex, r.percent) }.buttonStyle(.plain)
                    }
                }
            }
            .sheet(item: $demo) { ex in ExerciseDetailSheet(exercise: ex) }
        }
    }

    private func row(_ i: Int, _ ex: Exercise, _ percent: Double) -> some View {
        HStack(spacing: 10) {
            Text("\(i + 1)").font(.caption.weight(.heavy))
                .foregroundStyle(i == 0 ? Palette.action : Palette.faint).frame(width: 16)
            ExerciseIcon(category: ex.category, size: 34)
            VStack(alignment: .leading, spacing: 5) {
                Text(ex.name).font(.footnote.weight(.semibold)).foregroundStyle(Palette.text).lineLimit(1)
                ProgressView(value: percent / 100).progressViewStyle(.linear).tint(Palette.action)
            }
            Text("\(Int(percent))%").font(.caption.weight(.heavy))
                .foregroundStyle(i == 0 ? Palette.action : Palette.muted).frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background((i == 0 ? Palette.action.opacity(0.1) : Palette.surfaceElevated.opacity(0.5)),
                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

/// Compact front+back body highlighting given muscle slugs (exercise detail sheet).
struct MiniBody: View {
    @EnvironmentObject var state: AppState
    let slugs: [String]
    var body: some View {
        Group {
            if let a = state.anatomy {
                HStack(spacing: 12) {
                    BodyMapView(bodyView: a.front, activeSlugs: Set(slugs), interactiveSlugs: [])
                    BodyMapView(bodyView: a.back, activeSlugs: Set(slugs), interactiveSlugs: [])
                }
            } else {
                Color.clear
            }
        }
        .task { await state.loadAnatomy() }
    }
}
