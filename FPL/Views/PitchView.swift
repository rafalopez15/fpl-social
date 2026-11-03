//
//  PitchView.swift
//  FPL
//

import SwiftUI

/// The starting XI lined up on a drawn half pitch (goalkeeper at the top,
/// forwards on the halfway line), with the bench on a strip below. Each card
/// opens the stats popover.
struct SquadPitch: View {
    let picks: ManagerPicks
    let players: [Int: Element]
    let livePoints: LivePoints?
    @ObservedObject var lookups: TeamsAndFixturesStore

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                ForEach(picks.startingLines(players: players), id: \.position) { line in
                    HStack(alignment: .top, spacing: 4) {
                        ForEach(line.picks) { pick in
                            card(pick)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 22)
            .padding(.horizontal, 6)
            .background(PitchBackground())

            if !picks.bench.isEmpty {
                bench
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// The bench in substitution order, each labelled with its position (GKP,
    /// DEF, MID, FWD). VoiceOver still reads the order: "bench 1" etc.
    private var bench: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(Array(picks.bench.enumerated()), id: \.element.id) { index, pick in
                VStack(spacing: 4) {
                    Text(players[pick.element]?.position?.shortTitle ?? "")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    card(pick, benchLabel: index == 0 ? "backup goalkeeper" : "bench \(index)")
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Theme.background)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Bench")
    }

    @ViewBuilder
    private func card(_ pick: ManagerPicks.Pick, benchLabel: String? = nil) -> some View {
        if let element = players[pick.element] {
            PitchPlayerCard(pick: pick, element: element,
                            team: lookups.teams[element.team],
                            fixtures: lookups.schedule?.upcoming(for: element.team) ?? [],
                            teams: lookups.teams,
                            subbedIn: picks.subbedIn.contains(pick.element),
                            subbedOut: picks.subbedOut.contains(pick.element),
                            score: livePoints?.score(for: pick, team: element.team),
                            benchLabel: benchLabel)
        }
    }
}

/// One player: a shirt in his club's colors (goalkeepers in one fixed color),
/// the name on a navy plate, and his gameweek points (or the next fixture colored by difficulty
/// when points couldn't load). Captain badge top left; an automatic sub or an
/// injury flag top right.
private struct PitchPlayerCard: View {
    let pick: ManagerPicks.Pick
    let element: Element
    let team: Team?
    /// The next 3 gameweeks, for the popover; the card shows the first.
    let fixtures: [GameweekFixtures]
    let teams: [Int: Team]
    let subbedIn: Bool
    let subbedOut: Bool
    /// Points this gameweek, or "–" yet to play. Nil shows the next fixture instead.
    let score: PickScore?
    /// "bench 2" etc. for VoiceOver, nil for starters.
    let benchLabel: String?

    @State private var showingStats = false
    /// Whether the card sits in the top half of the visible screen: the popover
    /// then opens below it, otherwise above, so it has room either way.
    @State private var inUpperHalf = true

    private var flagColor: Color? { element.availabilityFlag.map(Theme.color(for:)) }
    private var next: GameweekFixtures? { fixtures.first }

    var body: some View {
        Button {
            showingStats = true
        } label: {
            VStack(spacing: 0) {
                shirt
                    .frame(maxWidth: .infinity, minHeight: 46)

                Text(element.webName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(flagColor ?? Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity)
                    .background(Theme.background)

                if let score {
                    pointsLine(score)
                } else {
                    fixtureLine
                }
            }
            .frame(maxWidth: 74)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(alignment: .topLeading) { badge }
            .overlay(alignment: .topTrailing) { corner }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: Bool.self) { proxy in
            guard let height = proxy.bounds(of: .scrollView)?.height else { return true }
            return proxy.frame(in: .scrollView).midY < height / 2
        } action: { inUpperHalf = $0 }
        .statsPopover(isPresented: $showingStats, element: element, team: team,
                      fixtures: fixtures, teams: teams, showsStats: false,
                      arrowEdge: inUpperHalf ? .top : .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Shows stats and news")
        .accessibilityAddTraits(.isButton)
    }

    /// The club's kit: flat, in its primary color with the secondary as collar
    /// trim. Goalkeepers wear `Theme.goalkeeperShirt`; a club without colors is grey.
    private var shirt: some View {
        let kit: KitColors = element.position == .goalkeeper
            ? .goalkeeper
            : KitColors(primary: team?.primaryColor, secondary: team?.secondaryColor)
        return KitShirt(kit: kit)
            .accessibilityHidden(true)
    }

    /// "12", or "–" while yet to play. Captain points are already doubled.
    private func pointsLine(_ score: PickScore) -> some View {
        Text(score.text)
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(Theme.text)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity)
            .background(Theme.surface)
    }

    /// "NFO (A)" on its difficulty color, "NFO +1" for a double, "–" for a blank.
    @ViewBuilder
    private var fixtureLine: some View {
        let first = next?.fixtures.first
        let colors = first.map { Theme.difficultyColors($0.difficulty) }
        Text(fixtureText)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(colors?.foreground ?? Theme.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity)
            .background(colors?.background ?? Theme.surface)
    }

    private var fixtureText: String {
        guard let fixtures = next?.fixtures, let first = fixtures.first,
              let name = teams[first.opponent]?.shortName else { return "–" }
        if fixtures.count > 1 { return "\(name) +\(fixtures.count - 1)" }
        return "\(name) (\(first.isHome ? "H" : "A"))"
    }

    @ViewBuilder
    private var badge: some View {
        if let badge = pick.badge {
            Text(badge)
                .font(.caption2.weight(.bold))
                .foregroundStyle(pick.isCaptain == true ? Theme.onAccent : Theme.text)
                .padding(.horizontal, badge.count > 1 ? 3 : 0)
                .frame(minWidth: 18, minHeight: 18)
                .background(pick.isCaptain == true ? Theme.accent : Theme.background, in: Capsule())
                .padding(3)
        }
    }

    /// An automatic sub wins over an injury flag; the name's color still shows the flag.
    @ViewBuilder
    private var corner: some View {
        if subbedIn {
            cornerIcon("arrow.up.circle.fill", Theme.accent)
        } else if subbedOut {
            cornerIcon("arrow.down.circle.fill", Theme.danger)
        } else if let flagColor {
            cornerIcon("exclamationmark.triangle.fill", flagColor)
        }
    }

    private func cornerIcon(_ name: String, _ color: Color) -> some View {
        Image(systemName: name)
            .font(.footnote)
            .foregroundStyle(color)
            .background(Circle().fill(Theme.background).padding(-2))
            .padding(4)
    }

    /// e.g. "Haaland, Man City, forward, captain, 16 points, subbed in, 75% chance
    /// of playing". Without points, the next fixture: "next Nottingham Forest away, difficulty 3".
    private var accessibilityLabel: String {
        var parts = [element.webName]
        if let team { parts.append(team.name) }
        if let benchLabel {
            parts.append(benchLabel)
        } else if let position = element.position {
            parts.append(position.singularTitle.lowercased())
        }
        switch pick.badge {
        case "TC": parts.append("triple captain")
        case "C": parts.append("captain")
        case "V": parts.append("vice-captain")
        default: break
        }
        if let score {
            parts.append(score.accessibilityDescription)
        } else if let fixtures = next?.fixtures, !fixtures.isEmpty {
            let games = fixtures.map { fixture in
                let name = teams[fixture.opponent]?.name ?? "unknown team"
                return "\(name) \(fixture.isHome ? "home" : "away"), difficulty \(fixture.difficulty)"
            }
            parts.append("next " + games.joined(separator: " and "))
        } else if next != nil {
            parts.append("no fixture next gameweek")
        }
        if subbedIn { parts.append("subbed in") }
        if subbedOut { parts.append("subbed out") }
        if element.availabilityFlag != nil { parts.append(element.availabilityDescription) }
        return parts.joined(separator: ", ")
    }
}

/// A shirt's colors, as hex so the hairline can be decided by contrast.
struct KitColors: Equatable {
    let primary: UInt32
    let secondary: UInt32?

    static let goalkeeper = KitColors(primary: Theme.goalkeeperShirtHex, secondary: nil)

    /// Grey when the club has no colors yet.
    init(primary: String?, secondary: String?) {
        if let value = UInt32(hexValue: primary) {
            self.primary = value
            self.secondary = UInt32(hexValue: secondary)
        } else {
            self.primary = Theme.shirtHex
            self.secondary = nil
        }
    }

    init(primary: UInt32, secondary: UInt32?) {
        self.primary = primary
        self.secondary = secondary
    }

    /// Dark kits (Newcastle's black, Everton's navy) fall below 3:1 against the
    /// pitch or the navy bench, so they get a faint hairline. Light and bright
    /// kits, white included, stand out on their own.
    var needsHairline: Bool {
        min(Self.contrast(primary, Theme.pitchHex), Self.contrast(primary, Theme.backgroundHex)) < 3
    }

    /// WCAG contrast ratio between two sRGB colors.
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    static func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let c = Double((hex >> shift) & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }
}

/// A flat shirt silhouette: one fill, a thin collar in the secondary color, and
/// a hairline only for dark kits. Drawn rather than an SF Symbol so it has no
/// outline and sits flat like the rest of the pitch.
private struct KitShirt: View {
    let kit: KitColors

    var body: some View {
        ZStack {
            ShirtShape()
                .fill(Color(hex: kit.primary))
            if kit.needsHairline {
                ShirtShape()
                    .stroke(.white.opacity(0.28), lineWidth: 1)
            }
            if let secondary = kit.secondary {
                CollarShape()
                    .stroke(Color(hex: secondary), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .frame(width: 34, height: 30)
    }
}

/// A short-sleeved shirt from the front, in a unit square scaled to the rect.
private struct ShirtShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: p(0.37, 0))
        path.addQuadCurve(to: p(0.63, 0), control: p(0.5, 0.16))
        path.addLine(to: p(0.86, 0.07))
        path.addLine(to: p(1, 0.33))
        path.addLine(to: p(0.81, 0.42))
        path.addLine(to: p(0.81, 1))
        path.addLine(to: p(0.19, 1))
        path.addLine(to: p(0.19, 0.42))
        path.addLine(to: p(0, 0.33))
        path.addLine(to: p(0.14, 0.07))
        path.closeSubpath()
        return path
    }
}

/// The neckline of `ShirtShape`, for the collar trim.
private struct CollarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 0.37 * rect.width, y: rect.minY + 1))
        path.addQuadCurve(to: CGPoint(x: rect.minX + 0.63 * rect.width, y: rect.minY + 1),
                          control: CGPoint(x: rect.midX, y: rect.minY + 0.16 * rect.height + 1))
        return path
    }
}

/// A top-down half pitch: mowing stripes, the penalty box with its arc, the
/// six-yard box, and the halfway line with the top of the centre circle along
/// the bottom edge. Muted to sit in the dark theme.
private struct PitchBackground: View {
    var body: some View {
        Canvas { context, size in
            let stripes = 8
            let stripeHeight = size.height / CGFloat(stripes)
            for index in 0..<stripes {
                let rect = CGRect(x: 0, y: CGFloat(index) * stripeHeight, width: size.width, height: stripeHeight)
                context.fill(Path(rect), with: .color(index.isMultiple(of: 2) ? Theme.pitch : Theme.pitchStripe))
            }

            let field = CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6)
            var lines = Path()
            // Touchlines, goal line, and the halfway line along the bottom.
            lines.addRect(field)

            let box = CGRect(x: field.midX - field.width * 0.3, y: field.minY,
                             width: field.width * 0.6, height: field.height * 0.17)
            lines.addRect(box)
            lines.addRect(CGRect(x: field.midX - field.width * 0.15, y: field.minY,
                                 width: field.width * 0.3, height: field.height * 0.06))

            // The arc is the part of a circle around the penalty spot outside the box.
            let spot = CGPoint(x: field.midX, y: field.minY + box.height * 0.68)
            let radius = field.width * 0.14
            let angle = asin(min((box.maxY - spot.y) / radius, 1))
            lines.move(to: CGPoint(x: spot.x + radius * cos(angle), y: spot.y + radius * sin(angle)))
            lines.addArc(center: spot, radius: radius, startAngle: .radians(angle),
                         endAngle: .radians(.pi - angle), clockwise: false)

            let centreRadius = field.width * 0.16
            lines.move(to: CGPoint(x: field.midX - centreRadius, y: field.maxY))
            lines.addArc(center: CGPoint(x: field.midX, y: field.maxY), radius: centreRadius,
                         startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)

            context.stroke(lines, with: .color(.white.opacity(0.22)), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
    }
}
