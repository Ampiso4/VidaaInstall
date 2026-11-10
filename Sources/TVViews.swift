import SwiftUI

// MARK: - Écran Téléviseurs

struct TVsScreen: View {
    @ObservedObject var model: AppModel
    @LocalState private var appeared = false

    var body: some View {
        let palette = Pane.tvs.palette
        VStack(alignment: .leading, spacing: 18) {
            ScreenHeader(title: "Téléviseurs", subtitle: subtitle) {
                PillButton(title: model.scanning ? "Recherche…" : "Rechercher", icon: "dot.radiowaves.left.and.right",
                           palette: palette, busy: model.scanning) { model.startScan() }
                    .disabled(model.scanning)
            }
            .padding(.top, 46)

            HStack(alignment: .top, spacing: 30) {
                VStack(spacing: 14) {
                    Radar(palette: palette, scanning: model.scanning, startedAt: model.scanStartedAt,
                          blips: model.tvs.filter { model.nearby.contains($0.mac) }.map { Blip(id: $0.mac, active: $0.mac == model.activeMAC) })
                        .frame(width: 270, height: 270)
                    Text(radarCaption)
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center).frame(width: 250)
                        .contentTransition(.opacity)
                }
                .scaleEffect(appeared ? 1 : 0.85).opacity(appeared ? 1 : 0)

                if model.tvs.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: model.scanning ? "antenna.radiowaves.left.and.right" : "tv.slash")
                            .font(.system(size: 40, weight: .light))
                            .symbolEffect(.variableColor.iterative, isActive: model.scanning)
                        Text(model.scanning ? "Recherche des téléviseurs VIDAA…" : "Aucun téléviseur pour l'instant")
                            .font(.system(size: 17, weight: .semibold))
                        Text("Le Mac et le téléviseur doivent être sur le même réseau, téléviseur allumé.")
                            .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.55))
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
                } else {
                    RoomyScroll {
                        VStack(spacing: 12) {
                            ForEach(Array(model.tvRows.enumerated()), id: \.element.id) { i, tv in
                                TVCard(tv: tv, palette: palette, active: tv.mac == model.activeMAC,
                                       nearby: model.nearby.contains(tv.mac), scanning: model.scanning,
                                       link: tv.mac == model.activeMAC ? model.link : .idle,
                                       onUse: { model.use(tv) }, onPair: { model.startPairing(tv) },
                                       onForget: { model.confirmForget = tv })
                                    .opacity(appeared ? 1 : 0)
                                    .offset(x: appeared ? 0 : 24)
                                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(i) * 0.06), value: appeared)
                                    .transition(.asymmetric(insertion: .scale(scale: 0.85).combined(with: .opacity),
                                                            removal: .opacity.combined(with: .scale(scale: 0.95))))
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 36)
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: model.tvs)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { appeared = true }
            if model.lastScanAt == nil { model.startScan(quiet: true) }
        }
        .alert(item: $model.confirmForget) { tv in
            Alert(title: Text("Oublier « \(tv.displayName) » ?"),
                  message: Text("Le jeton d'appairage est supprimé de ce Mac. Il faudra saisir un nouveau code pour le réutiliser."),
                  primaryButton: .destructive(Text("Oublier")) { model.forget(tv) },
                  secondaryButton: .cancel(Text("Annuler")))
        }
    }

    private var subtitle: String {
        let n = model.tvs.filter(\.paired).count
        return n == 0 ? "Trouve un téléviseur VIDAA sur le réseau et appaire-le avec le code affiché à l'écran."
                      : "\(n) téléviseur\(n > 1 ? "s" : "") appairé\(n > 1 ? "s" : ""). L'adresse IP est suivie automatiquement."
    }

    private var radarCaption: String {
        if model.scanning { return "Balayage du réseau local…" }
        let n = model.nearby.count
        if let d = model.lastScanAt {
            return n == 0 ? "Aucun téléviseur détecté" : "\(n) téléviseur\(n > 1 ? "s" : "") détecté\(n > 1 ? "s" : "") · \(d.formatted(Date.FormatStyle(time: .shortened).locale(fr)))"
        }
        return "Lance une recherche pour voir les téléviseurs autour de toi."
    }
}

// MARK: - Radar

struct Blip: Identifiable, Hashable { let id: String; let active: Bool }

struct Radar: View {
    let palette: Palette
    let scanning: Bool
    let startedAt: Date?
    let blips: [Blip]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let sweep = Angle.radians(t * 2.2)
            GeometryReader { g in
                let r = min(g.size.width, g.size.height) / 2
                let c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
                ZStack {
                    Circle().fill(palette.gradient).blur(radius: 50).opacity(scanning ? 0.45 : 0.25)
                    Color.clear.liquid(Circle(), tint: .navy, opacity: 0.25)
                    ForEach(1..<4) { k in
                        Circle().strokeBorder(.white.opacity(0.09), lineWidth: 1)
                            .frame(width: r * 2 * CGFloat(k) / 3, height: r * 2 * CGFloat(k) / 3)
                    }
                    Path { p in p.move(to: CGPoint(x: c.x - r, y: c.y)); p.addLine(to: CGPoint(x: c.x + r, y: c.y))
                        p.move(to: CGPoint(x: c.x, y: c.y - r)); p.addLine(to: CGPoint(x: c.x, y: c.y + r)) }
                        .stroke(.white.opacity(0.06), lineWidth: 1)

                    // Faisceau
                    Circle()
                        .fill(AngularGradient(colors: [palette.a.opacity(0), palette.a.opacity(0), palette.a.opacity(0.05), palette.a.opacity(0.55)],
                                              center: .center, startAngle: .degrees(0), endAngle: .degrees(360)))
                        .rotationEffect(sweep)
                        .opacity(scanning ? 1 : 0)
                    Rectangle().fill(LinearGradient(colors: [palette.c, palette.c.opacity(0)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: r, height: 2)
                        .offset(x: r / 2)
                        .rotationEffect(sweep)
                        .opacity(scanning ? 0.9 : 0)
                        .shadow(color: palette.c, radius: 6)

                    // Ondes au repos
                    if !scanning {
                        let p = t.truncatingRemainder(dividingBy: 3) / 3
                        Circle().strokeBorder(palette.a.opacity(0.4 * (1 - p)), lineWidth: 1.5)
                            .frame(width: r * 2 * p, height: r * 2 * p)
                    }

                    // Le Mac au centre
                    ZStack {
                        Circle().fill(.white.opacity(0.12)).frame(width: 46, height: 46)
                        Image(systemName: "laptopcomputer").font(.system(size: 18, weight: .medium)).foregroundStyle(.white)
                    }

                    ForEach(blips) { b in
                        let pos = position(for: b.id, radius: r * 0.72)
                        BlipView(palette: palette, active: b.active)
                            .position(x: c.x + pos.x, y: c.y + pos.y)
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    }
                }
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.5), value: scanning)
        .animation(.spring(response: 0.6, dampingFraction: 0.6), value: blips)
    }

    /// Position stable dérivée de la MAC : un TV garde sa place sur le radar.
    private func position(for id: String, radius: CGFloat) -> CGPoint {
        var h: UInt64 = 1469598103934665603
        for b in id.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        let angle = Double(h % 360) * .pi / 180
        let dist = radius * (0.55 + CGFloat((h >> 12) % 45) / 100)
        return CGPoint(x: cos(angle) * dist, y: sin(angle) * dist)
    }
}

struct BlipView: View {
    let palette: Palette
    let active: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            let p = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            ZStack {
                Circle().fill((active ? Color.mint : palette.c).opacity(0.5 * (1 - p))).frame(width: 14 + 26 * p, height: 14 + 26 * p)
                Circle().fill(active ? Color.mint : palette.c).frame(width: 26, height: 26)
                    .shadow(color: active ? .mint : palette.c, radius: 8)
                Image(systemName: "tv.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.ink)
            }
        }
    }
}

// MARK: - Carte téléviseur

struct TVCard: View {
    let tv: TVDevice
    let palette: Palette
    let active: Bool
    let nearby: Bool
    let scanning: Bool
    let link: LinkState
    let onUse: () -> Void
    let onPair: () -> Void
    let onForget: () -> Void
    @LocalState private var hover = false

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(active ? AnyShapeStyle(palette.gradient) : AnyShapeStyle(Color.white.opacity(0.09)))
                Image(systemName: "tv").font(.system(size: 22, weight: .medium))
                if active, case .connecting = link {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.6), lineWidth: 2)
                        .modifier(Shimmer())
                }
            }
            .frame(width: 54, height: 54)
            .shadow(color: active ? palette.b.opacity(0.55) : .clear, radius: 12, y: 4)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(tv.displayName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    badge
                }
                HStack(spacing: 10) {
                    Label(tv.ip, systemImage: "network").contentTransition(.numericText())
                    Label(tv.shortMAC, systemImage: "barcode")
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                Text(detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.42))
            }
            Spacer()
            HStack(spacing: 8) {
                if tv.paired {
                    if !active { PillButton(title: "Utiliser", icon: "checkmark.circle", palette: palette, action: onUse) }
                    Menu {
                        Button("Ré-appairer", action: onPair)
                        Button("Oublier", role: .destructive, action: onForget)
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 32, height: 32).background(Circle().fill(.white.opacity(0.1)))
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                } else {
                    PillButton(title: "Appairer", icon: "key.fill", palette: palette, action: onPair)
                        .disabled(!nearby && !scanning)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .glass(18, highlight: active ? 0.26 : hover ? 0.2 : 0.1)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(active ? AnyShapeStyle(palette.gradient) : AnyShapeStyle(Color.clear), lineWidth: 1.5)
        )
        .opacity(nearby || tv.paired ? 1 : 0.55)
        .scaleEffect(hover ? 1.01 : 1)
        .onHover { hover = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: hover)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: active)
    }

    private var detail: String {
        var parts = ["VIDAA · protocole \(tv.transport)"]
        if let t = tv.token, tv.paired { parts.append("jeton valable jusqu'au \(t.refreshExpiry.formatted(Date.FormatStyle(date: .abbreviated).locale(fr)))") }
        if !nearby, !scanning, let s = tv.lastSeen { parts.append("vu \(s.formatted(.relative(presentation: .named).locale(fr)))") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var badge: some View {
        if active {
            switch link {
            case .connected(true): chip("CONNECTÉ", .mint)
            case .connected(false): chip("À APPAIRER", Color.warn)
            case .connecting: chip("CONNEXION…", .white.opacity(0.6))
            case .offline, .rejected: chip("HORS LIGNE", .danger)
            case .idle: chip("ACTIF", .mint)
            }
        } else if tv.paired {
            chip("APPAIRÉ", .white.opacity(0.7))
        } else if nearby {
            chip("NOUVEAU", palette.c)
        }
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(Capsule().fill(color.opacity(0.14)))
            .overlay(Capsule().strokeBorder(color.opacity(0.35)))
            .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - Fenêtre d'appairage (code PIN)

struct PairingOverlay: View {
    @ObservedObject var model: AppModel
    let session: PairingSession
    @FocusState private var focused: Bool
    @LocalState private var appeared = false

    var body: some View {
        let palette = Pane.tvs.palette
        ZStack {
            Color.navy.opacity(0.55).ignoresSafeArea()
                .onTapGesture { focused = true }

            VStack(spacing: 22) {
                ZStack {
                    HeroOrb(palette: palette, state: orbState, icon: "", symbol: "tv", size: 150)
                    ParticleBurst(start: model.pairBurstAt, colors: [.mint, palette.a, palette.b, palette.c, .white])
                }
                .frame(height: 150)

                VStack(spacing: 6) {
                    Text(title).font(.system(size: 21, weight: .bold)).contentTransition(.interpolate)
                    Text(subtitle).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center).frame(maxWidth: 330)
                        .id(subtitle).transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                ZStack {
                    TextField("", text: Binding(get: { model.pin }, set: { v in
                        let digits = String(v.filter(\.isNumber).prefix(4))
                        model.pin = digits
                        if digits.count == 4 { model.submitPIN() }
                    }))
                    .textFieldStyle(.plain).foregroundStyle(.clear).tint(.clear)
                    .focused($focused).frame(width: 1, height: 1).opacity(0.01)
                    .onSubmit { model.submitPIN() }

                    HStack(spacing: 12) {
                        ForEach(0..<4, id: \.self) { i in digit(i, palette) }
                    }
                    .modifier(Shake(animatableData: CGFloat(model.pinShake)))
                    .onTapGesture { focused = true }
                }
                .opacity(session.step == .connecting || session.step == .failed ? 0.35 : 1)
                .allowsHitTesting(session.step == .waitingPIN)

                if let e = session.error {
                    Label(e, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.danger)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                HStack(spacing: 10) {
                    PillButton(title: "Annuler", icon: "xmark") { model.cancelPairing() }
                    PillButton(title: "Nouveau code", icon: "arrow.clockwise") { model.resendPIN(); focused = true }
                        .disabled(session.step == .verifying || session.step == .success)
                }
                .opacity(session.step == .success ? 0 : 1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 40).padding(.vertical, 30)
            .frame(width: 440)
            .glass(28, highlight: 0.22, tint: .royal, opacity: GlassTint.overlay)
            .scaleEffect(appeared ? 1 : 0.88)
            .opacity(appeared ? 1 : 0)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: session)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { appeared = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { focused = true }
        }
        .onChange(of: session.step) { _, s in if s == .waitingPIN { focused = true } }
        .onExitCommand { model.cancelPairing() }
    }

    private var orbState: OrbState {
        switch session.step {
        case .connecting, .verifying: .working
        case .success: .success
        case .failed: .failure
        case .waitingPIN: .idle
        }
    }

    private var title: String {
        switch session.step {
        case .connecting: "Connexion au téléviseur…"
        case .waitingPIN: "Saisis le code"
        case .verifying: "Vérification…"
        case .success: "Appairé !"
        case .failed: "Connexion impossible"
        }
    }

    private var subtitle: String {
        switch session.step {
        case .connecting: "\(session.tv.displayName) · \(session.tv.ip)"
        case .waitingPIN: "Un code à 4 chiffres vient de s'afficher sur l'écran du téléviseur."
        case .verifying: "Le téléviseur valide le code et émet un jeton d'accès."
        case .success: "VidaaInstall peut maintenant piloter ce téléviseur."
        case .failed: "Vérifie que le téléviseur est allumé puis demande un nouveau code."
        }
    }

    private func digit(_ i: Int, _ palette: Palette) -> some View {
        let chars = Array(model.pin)
        let filled = i < chars.count
        let current = i == chars.count && session.step == .waitingPIN
        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(filled ? 0.14 : 0.06))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(current ? AnyShapeStyle(palette.gradient)
                              : session.step == .success ? AnyShapeStyle(Color.mint)
                              : AnyShapeStyle(Color.white.opacity(filled ? 0.3 : 0.12)),
                              lineWidth: current || session.step == .success ? 2 : 1)
            if filled {
                Text(String(chars[i])).font(.system(size: 28, weight: .bold, design: .rounded))
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            } else if current {
                TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                    let on = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) < 0.55
                    RoundedRectangle(cornerRadius: 1).fill(.white).frame(width: 2, height: 26).opacity(on && focused ? 0.9 : 0)
                }
            }
        }
        .frame(width: 58, height: 68)
        .shadow(color: current ? palette.b.opacity(0.5) : .clear, radius: 12)
        .scaleEffect(filled ? 1 : current ? 1.04 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: model.pin)
    }
}

// MARK: - Pastille « TV cible » sur l'écran Installer

struct TargetChip: View {
    @ObservedObject var model: AppModel
    @LocalState private var hover = false

    var body: some View {
        Button { withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { model.section = .tvs } } label: {
            HStack(spacing: 8) {
                StatusDot(on: model.tvAuthorized || model.agentLive,
                          color: model.tvAuthorized || model.agentLive ? .mint : Color.warn)
                Text(model.activeTV.map { "Vers \($0.displayName) · \($0.ip)" } ?? "Aucun téléviseur — appuie pour en chercher un")
                    .font(.system(size: 11.5, weight: .medium))
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).opacity(hover ? 0.9 : 0.4)
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.leading, 6).padding(.trailing, 12).frame(height: 28)
            .background(Capsule().fill(.white.opacity(hover ? 0.13 : 0.07)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}
