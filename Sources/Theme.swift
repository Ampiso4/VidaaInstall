import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
    // Palette unique (colorhunt 091540 · 1B2CC1 · 7692FF · ABD2FA). Le blanc ne sert qu'au texte.
    static let navy = Color(hex: 0x091540)
    static let royal = Color(hex: 0x1B2CC1)
    static let peri = Color(hex: 0x7692FF)
    static let sky = Color(hex: 0xABD2FA)

    static let ink = navy
    /// Succès.
    static let mint = sky
    /// Attention / en cours.
    static let warn = peri
    /// Erreur : blanc pur + pictogramme, la palette n'a pas de rouge.
    static let danger = Color.white
}

/// Opacités du verre liquide.
enum GlassTint {
    static let surface = 0.16   // cartes, panneaux
    static let sidebar = 0.28
    static let control = 0.55   // boutons d'accent
    static let overlay = 0.30   // fenêtre modale
}

struct Palette: Equatable {
    let a: Color, b: Color, c: Color
    var gradient: LinearGradient { LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing) }
    var angular: AngularGradient { AngularGradient(colors: [a, b, c, a], center: .center) }
    var colors: [Color] { [a, b, c] }
}

extension Pane {
    var palette: Palette {
        switch self {
        // Mêmes quatre couleurs, dans un ordre différent par écran.
        case .tvs:     Palette(a: .peri, b: .royal, c: .sky)
        case .install: Palette(a: .royal, b: .peri, c: .sky)
        case .apps:    Palette(a: .sky, b: .royal, c: .peri)
        case .backups: Palette(a: .peri, b: .sky, c: .royal)
        }
    }
}

// MARK: - Fond animé (nuées colorées qui dérivent)

struct AnimatedBackdrop: View {
    let palette: Palette

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                ZStack {
                    Color.ink
                    blob(palette.a, w * 0.75, w * (0.22 + 0.10 * cos(t * 0.13)), h * (0.28 + 0.12 * sin(t * 0.17)), 0.85)
                    blob(palette.b, w * 0.65, w * (0.82 + 0.08 * sin(t * 0.11)), h * (0.78 + 0.10 * cos(t * 0.15)), 0.75)
                    blob(palette.c, w * 0.45, w * (0.60 + 0.14 * cos(t * 0.19)), h * (0.12 + 0.10 * sin(t * 0.09)), 0.55)
                }
                .blur(radius: 110)
                .overlay(LinearGradient(colors: [Color.navy.opacity(0.15), Color.navy.opacity(0.55)], startPoint: .top, endPoint: .bottom))
            }
        }
        .drawingGroup()
        .ignoresSafeArea()
    }

    private func blob(_ c: Color, _ size: CGFloat, _ x: CGFloat, _ y: CGFloat, _ o: Double) -> some View {
        Circle().fill(c).frame(width: size, height: size).position(x: x, y: y).opacity(o)
    }
}

// MARK: - Verre

struct Glass: ViewModifier {
    var radius: CGFloat = 22
    var highlight: Double = 0.14
    var tint: Color = .peri
    var opacity: Double = GlassTint.surface
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.clear.tint(tint.opacity(opacity)), in: shape)
                .overlay(shape.strokeBorder(LinearGradient(colors: [Color.sky.opacity(highlight + 0.12), .clear],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                .shadow(color: Color.navy.opacity(0.45), radius: 22, y: 12)
        } else {
            legacy(content)
        }
    }

    private func legacy(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial.opacity(0.75), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(highlight + 0.1), .white.opacity(0.03)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
            .shadow(color: Color.navy.opacity(0.25), radius: 24, y: 12)
    }
}

extension View {
    func glass(_ radius: CGFloat = 22, highlight: Double = 0.14, tint: Color = .peri, opacity: Double = GlassTint.surface) -> some View {
        modifier(Glass(radius: radius, highlight: highlight, tint: tint, opacity: opacity))
    }

    /// Verre liquide quelconque (capsule, cercle…), interactif pour les contrôles.
    @ViewBuilder
    func liquid<S: Shape>(_ shape: S, tint: Color = .peri, opacity: Double = GlassTint.surface, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(tint.opacity(opacity)).interactive(interactive), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape).background(tint.opacity(opacity), in: shape)
        }
    }
}

// MARK: - Secousse (erreur de saisie)

struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 9 * sin(animatableData * .pi * 6), y: 0))
    }
}

// MARK: - Point d'état pulsant

struct StatusDot: View {
    let on: Bool
    var color: Color = .mint
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !on)) { tl in
            let p = on ? tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8 : 0
            ZStack {
                Circle().fill(color.opacity(on ? 0.5 * (1 - p) : 0)).frame(width: 8 + 12 * p, height: 8 + 12 * p)
                Circle().fill(on ? color : Color.white.opacity(0.25)).frame(width: 8, height: 8)
                    .shadow(color: on ? color : .clear, radius: 4)
            }
            .frame(width: 20, height: 20)
        }
    }
}

// MARK: - Orbe centrale

struct HeroOrb: View {
    let palette: Palette
    let state: OrbState
    let icon: String
    var symbol = "tv"
    var size: CGFloat = 230

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let working = state == .working
            ZStack {
                // Halo qui respire
                Circle().fill(glowFill).frame(width: size, height: size)
                    .blur(radius: 46).opacity(working ? 0.85 : 0.55)
                    .scaleEffect(1 + 0.06 * sin(t * (working ? 4 : 1.4)))

                // Anneau extérieur lent
                Circle().stroke(ringFill, lineWidth: 2)
                    .frame(width: size * 0.9, height: size * 0.9)
                    .rotationEffect(.radians(t * 0.35))
                    .opacity(0.9)

                // Arc principal
                Circle().trim(from: 0, to: state == .success ? 1 : 0.72)
                    .stroke(ringFill, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .frame(width: size * 0.78, height: size * 0.78)
                    .rotationEffect(.radians(-t * 0.6))
                    .shadow(color: accent.opacity(0.7), radius: 10)

                // Comète de travail
                Circle().trim(from: 0, to: 0.18)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: size * 0.66, height: size * 0.66)
                    .rotationEffect(.radians(t * 5.5))
                    .opacity(working ? 1 : 0)
                    .shadow(color: .white, radius: 6)

                // Cœur en verre
                Color.clear
                    .frame(width: size * 0.56, height: size * 0.56)
                    .liquid(Circle(), tint: .royal, opacity: 0.25)
                    .overlay(Circle().strokeBorder(Color.sky.opacity(0.3), lineWidth: 1))
                    .shadow(color: Color.navy.opacity(0.3), radius: 20, y: 10)

                center.frame(width: size * 0.56, height: size * 0.56)
            }
            .frame(width: size, height: size)
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: state)
    }

    private var accent: Color {
        switch state { case .success: .mint; case .failure: .danger; default: palette.b }
    }
    private var ringFill: AnyShapeStyle {
        switch state {
        case .success: AnyShapeStyle(AngularGradient(colors: [.sky, .peri, .sky], center: .center))
        case .failure: AnyShapeStyle(AngularGradient(colors: [.white, .peri, .white], center: .center))
        default: AnyShapeStyle(palette.angular)
        }
    }
    private var glowFill: AnyShapeStyle {
        switch state {
        case .success: AnyShapeStyle(Color.sky)
        case .failure: AnyShapeStyle(Color.peri)
        default: AnyShapeStyle(palette.gradient)
        }
    }

    @ViewBuilder private var center: some View {
        switch state {
        case .success:
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.18, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .mint, radius: 12)
                .transition(.scale(scale: 0.3).combined(with: .opacity))
        case .failure:
            Image(systemName: "exclamationmark")
                .font(.system(size: size * 0.18, weight: .bold))
                .foregroundStyle(.white)
                .transition(.scale(scale: 0.3).combined(with: .opacity))
        default:
            AppIcon(url: icon, name: "", palette: palette, size: size * 0.3, symbol: symbol)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .id(icon)
        }
    }
}

// MARK: - Icône d'application (URL distante ou monogramme)

struct AppIcon: View {
    let url: String
    let name: String
    let palette: Palette
    var size: CGFloat = 56
    var symbol: String? = nil

    var body: some View {
        Group {
            if let u = URL(string: url), u.scheme?.hasPrefix("http") == true {
                AsyncImage(url: u, transaction: Transaction(animation: .easeOut(duration: 0.35))) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFit().transition(.opacity.combined(with: .scale(scale: 0.9)))
                    default: placeholder
                    }
                }
            } else { placeholder }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }

    @ViewBuilder private var placeholder: some View {
        if let symbol {
            Image(systemName: symbol)
                .font(.system(size: size * 0.62, weight: .light))
                .foregroundStyle(.white)
                .shadow(color: palette.b.opacity(0.8), radius: 10)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(palette.gradient)
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Gros bouton rond (façon « Analyser »)

struct BigRoundButton: View {
    let title: String
    let palette: Palette
    let state: OrbState
    let enabled: Bool
    let action: () -> Void
    @LocalState private var hover = false

    var body: some View {
        Button(action: action) {
            TimelineView(.animation(minimumInterval: 1 / 60)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                let p = t.truncatingRemainder(dividingBy: 2.2) / 2.2
                ZStack {
                    // Onde d'invitation
                    Circle().stroke(palette.b.opacity(enabled && state == .idle ? 0.55 * (1 - p) : 0), lineWidth: 2)
                        .frame(width: 96, height: 96).scaleEffect(1 + 0.45 * p)
                    Circle().fill(fill).opacity(0.55)
                        .frame(width: 96, height: 96)
                        .liquid(Circle(), tint: glow, opacity: GlassTint.control, interactive: true)
                        .overlay(Circle().strokeBorder(Color.sky.opacity(0.45), lineWidth: 1))
                        .shadow(color: glow.opacity(hover && enabled ? 0.9 : 0.55), radius: hover ? 30 : 20, y: 6)
                    if state == .working {
                        Circle().trim(from: 0, to: 0.28)
                            .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 110, height: 110)
                            .rotationEffect(.radians(t * 6))
                            .transition(.opacity)
                    }
                    label.foregroundStyle(.white)
                }
                .frame(width: 140, height: 140)
            }
            .saturation(enabled || state != .idle ? 1 : 0.35)
            .opacity(enabled || state != .idle ? 1 : 0.6)
            .scaleEffect(hover && enabled ? 1.06 : 1)
        }
        .buttonStyle(PressStyle())
        .focusEffectDisabled()
        .disabled(!enabled)
        .onHover { hover = $0 }
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: hover)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: state)
    }

    private var fill: AnyShapeStyle {
        switch state {
        case .success: AnyShapeStyle(LinearGradient(colors: [.sky, .peri], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .failure: AnyShapeStyle(LinearGradient(colors: [.peri, .royal], startPoint: .topLeading, endPoint: .bottomTrailing))
        default: AnyShapeStyle(palette.gradient)
        }
    }
    private var glow: Color { state == .success ? .sky : state == .failure ? .peri : palette.b }

    @ViewBuilder private var label: some View {
        switch state {
        case .working: Image(systemName: "arrow.down.to.line").font(.system(size: 22, weight: .semibold)).symbolEffect(.pulse)
        case .success: Image(systemName: "checkmark").font(.system(size: 26, weight: .bold)).transition(.scale.combined(with: .opacity))
        case .failure: Image(systemName: "arrow.clockwise").font(.system(size: 22, weight: .bold)).transition(.scale.combined(with: .opacity))
        case .idle: Text(title).font(.system(size: 15, weight: .semibold)).transition(.scale.combined(with: .opacity))
        }
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Bouton pilule secondaire.
struct PillButton: View {
    let title: String
    let icon: String
    var palette: Palette? = nil
    var busy = false
    var role: ButtonRole? = nil
    let action: () -> Void
    @LocalState private var hover = false

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 7) {
                if busy { ProgressView().controlSize(.small).tint(.white) }
                else { Image(systemName: icon).font(.system(size: 12, weight: .semibold)) }
                Text(title).font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).frame(height: 32)
            .liquid(Capsule(), tint: palette?.b ?? .peri,
                    opacity: palette == nil ? (hover ? 0.22 : 0.12) : GlassTint.control, interactive: true)
            .overlay(Capsule().strokeBorder(Color.sky.opacity(0.22), lineWidth: 1))
            .shadow(color: (palette?.b ?? .clear).opacity(hover ? 0.6 : 0.3), radius: hover ? 14 : 8, y: 3)
            .scaleEffect(hover ? 1.03 : 1)
        }
        .buttonStyle(PressStyle())
        .focusEffectDisabled()
        .onHover { hover = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hover)
        .animation(.easeInOut, value: busy)
    }
}

// MARK: - Champ de saisie

struct FancyField: View {
    let label: String
    let icon: String
    let placeholder: String
    @Binding var text: String
    let error: String?
    let palette: Palette
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(1.2)
                .foregroundStyle(.white.opacity(0.5))
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(focused ? AnyShapeStyle(palette.gradient) : AnyShapeStyle(Color.white.opacity(0.4)))
                    .frame(width: 16)
                TextField("", text: $text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.28)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .focused($focused)
                    .autocorrectionDisabled()
                if !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12).frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(focused ? 0.1 : 0.055)))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(error != nil ? AnyShapeStyle(Color.danger.opacity(0.8))
                                  : focused ? AnyShapeStyle(palette.gradient) : AnyShapeStyle(Color.white.opacity(0.1)),
                                  lineWidth: focused || error != nil ? 1.5 : 1)
            )
            .shadow(color: focused ? palette.b.opacity(0.35) : .clear, radius: 12)
            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.danger)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: focused)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: error)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: text.isEmpty)
    }
}

// MARK: - Explosion de particules (succès)

struct ParticleBurst: View {
    let start: Date?
    let colors: [Color]
    private let count = 34
    private let duration = 1.3

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: start == nil)) { tl in
            let p = start.map { min(1, tl.date.timeIntervalSince($0) / duration) } ?? 1
            if p < 1 {
                let e = 1 - pow(1 - p, 3)
                ZStack {
                    ForEach(0..<count, id: \.self) { i in
                        let angle = Double(i) / Double(count) * 2 * .pi + Double((i * 53) % 17) / 17 * 0.4
                        let dist = 110 + Double((i * 37) % 90)
                        let s = CGFloat(4 + (i % 4) * 2)
                        RoundedRectangle(cornerRadius: i % 3 == 0 ? 1 : s / 2)
                            .fill(colors[i % colors.count])
                            .frame(width: s, height: i % 3 == 0 ? s * 2.2 : s)
                            .rotationEffect(.radians(angle + p * 6))
                            .offset(x: cos(angle) * dist * e, y: sin(angle) * dist * e + 40 * p * p)
                            .opacity(1 - p)
                    }
                    Circle().stroke(colors[0].opacity(0.6 * (1 - p)), lineWidth: 2)
                        .frame(width: 120 + 260 * e, height: 120 + 260 * e)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Bloc squelette scintillant pendant le chargement.
struct Shimmer: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(
            TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                let p = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                GeometryReader { g in
                    LinearGradient(colors: [.clear, .white.opacity(0.12), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: g.size.width * 0.6)
                        .offset(x: -g.size.width * 0.6 + g.size.width * 1.6 * p)
                }
            }
            .mask(content)
        )
    }
}

// MARK: - Défilement avec marge de survol

/// Un ScrollView rogne tout ce qui dépasse de ses bords : une carte qui grandit au
/// survol (zoom, ombre, halo) y est coupée. On ajoute une marge intérieure, compensée
/// à l'extérieur : au repos le contenu ne bouge pas, au survol il a la place de grandir.
/// `top` doit rester plus petit que l'espace au-dessus, sinon le contenu passe sous l'en-tête.
struct RoomyScroll<Content: View>: View {
    var horizontal: CGFloat = 12
    var top: CGFloat = 12
    var bottom: CGFloat = 30
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, horizontal)
                .padding(.top, top)
                .padding(.bottom, bottom)
        }
        .scrollIndicators(.never)
        .padding(.horizontal, -horizontal)
        .padding(.top, -top)
    }
}

// MARK: - État local sans macro

/// Remplace `@State` : la macro SwiftUI n'est pas disponible avec les seuls
/// Command Line Tools (pas de plugin SwiftUIMacros).
@propertyWrapper
struct LocalState<Value>: DynamicProperty {
    final class Box: ObservableObject {
        @Published var value: Value
        init(_ v: Value) { value = v }
    }
    @StateObject private var box: Box

    init(wrappedValue: Value) { _box = StateObject(wrappedValue: Box(wrappedValue)) }

    var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }
    var projectedValue: Binding<Value> { $box.value }
}
