import SwiftUI

// MARK: - Racine

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            AnimatedBackdrop(palette: model.section.palette)
                .animation(.easeInOut(duration: 1.1), value: model.section)

            HStack(spacing: 0) {
                Sidebar(model: model)
                    .frame(width: 252)
                ZStack {
                    switch model.section {
                    case .tvs: TVsScreen(model: model).transition(screenTransition)
                    case .install: InstallScreen(model: model).transition(screenTransition)
                    case .apps: AppsScreen(model: model).transition(screenTransition)
                    case .backups: BackupsScreen(model: model).transition(screenTransition)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.spring(response: 0.55, dampingFraction: 0.86), value: model.section)
            }

            if let session = model.pairing {
                PairingOverlay(model: model, session: session)
                    .transition(.opacity)
                    .zIndex(5)
            }

            ToastHost(toast: model.toast).zIndex(6)
        }
        .frame(minWidth: 980, minHeight: 640)
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
    }

    private var screenTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 24)).combined(with: .scale(scale: 0.98)),
            removal: .opacity.combined(with: .scale(scale: 1.02))
        )
    }
}

// MARK: - Barre latérale

struct Sidebar: View {
    @ObservedObject var model: AppModel
    @Namespace private var ns
    @LocalState private var hovered: Pane? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandHeader()
                .padding(.top, 50).padding(.horizontal, 14)

            // Séparation nette entre la marque et la navigation.
            VStack(alignment: .leading, spacing: 10) {
                LinearGradient(colors: [Color.sky.opacity(0.35), Color.sky.opacity(0)], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 1)
                Text("NAVIGATION").font(.system(size: 9.5, weight: .bold)).tracking(1.4).foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 8)

            VStack(spacing: 4) {
                ForEach(Pane.allCases) { s in item(s) }
            }
            .padding(.horizontal, 10)

            Spacer()

            LinkChainCard(model: model)
                .padding(12)
        }
        .frame(maxHeight: .infinity)
        // Panneau flottant en verre liquide, façon barre latérale macOS 26.
        .glass(24, highlight: 0.1, tint: .navy, opacity: GlassTint.sidebar)
        .padding(10)
    }

    private func item(_ s: Pane) -> some View {
        let selected = model.section == s
        return Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { model.section = s }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? AnyShapeStyle(s.palette.gradient) : AnyShapeStyle(Color.white.opacity(0.08)))
                    Image(systemName: s.icon).font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(selected ? 1 : 0.7))
                }
                .frame(width: 28, height: 28)
                .shadow(color: selected ? s.palette.b.opacity(0.6) : .clear, radius: 8, y: 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.title).font(.system(size: 13, weight: .semibold))
                    Text(s.subtitle).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.42)).lineLimit(1)
                }
                Spacer()
                if s == .tvs, model.scanning {
                    ProgressView().controlSize(.mini).tint(.white).transition(.scale.combined(with: .opacity))
                } else if s == .apps, model.appsLoaded {
                    Text("\(model.apps.count)")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(.white.opacity(0.12)))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.11))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.1)))
                        .matchedGeometryEffect(id: "selection", in: ns)
                } else if hovered == s {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.05))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovered = h ? s : (hovered == s ? nil : hovered) } }
    }

}

// MARK: - Marque (en haut de la barre latérale)

struct BrandHeader: View {
    @LocalState private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            // La vraie icône de l'app, plus grande que les pictos du menu, avec un halo.
            ZStack {
                Circle().fill(Color.peri).frame(width: 40, height: 40).blur(radius: 16).opacity(hover ? 0.8 : 0.5)
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().interpolation(.high)
                    .frame(width: 52, height: 52)
                    .rotationEffect(.degrees(hover ? -6 : 0))
                    .scaleEffect(hover ? 1.06 : 1)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                    // Reflet lent qui balaie « Install ».
                    let p = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) / 6
                    HStack(spacing: 0) {
                        Text("Vidaa").font(.system(size: 20, weight: .light)).foregroundStyle(.white)
                        Text("Install").font(.system(size: 20, weight: .heavy))
                            .foregroundStyle(LinearGradient(
                                stops: [.init(color: .peri, location: 0),
                                        .init(color: .sky, location: max(0.01, min(0.99, p * 1.6 - 0.3))),
                                        .init(color: .peri, location: 1)],
                                startPoint: .leading, endPoint: .trailing))
                    }
                    .tracking(-0.4)
                }
                Text("HISENSE · VIDAA").font(.system(size: 9, weight: .bold)).tracking(1.8)
                    .foregroundStyle(Color.sky.opacity(0.6))
            }
        }
        .onHover { h in withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { hover = h } }
    }
}

// MARK: - Chaîne de liaison (état, bas de la barre latérale)

enum NodeState: Equatable { case on, standby, off }

struct LinkChainCard: View {
    @ObservedObject var model: AppModel
    @LocalState private var hover = false

    /// Pas encore prêt et sans erreur = en train de démarrer, pas « arrêté ».
    private var server: NodeState { model.serverUp ? .on : (model.fatal != nil ? .off : .standby) }
    // La page agent s'ouvre à la demande : « en veille » n'est pas une panne.
    private var agent: NodeState { model.agentLive ? .on : .standby }
    private var tv: NodeState {
        if model.activeTV == nil { return .off }
        if model.tvAuthorized { return .on }
        return model.tvConnected ? .standby : .off
    }

    var body: some View {
        Button { withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { model.section = .tvs } } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 0) {
                    node("laptopcomputer", "Mac", .on, help: "Ce Mac")
                    segment(server)
                    node("server.rack", ":\(httpPort)", server, help: model.serverUp ? "Serveur local actif sur le port \(httpPort)" : "Serveur arrêté")
                    segment(agent == .on ? .on : (server == .on ? .standby : .off))
                    node("globe", "Agent", agent, help: model.agentLive ? "Page agent ouverte sur le TV" : "Page agent en veille : elle s'ouvre toute seule au besoin")
                    segment(tv)
                    node("tv", "TV", tv, help: model.activeTV.map { "\($0.displayName) · \($0.ip) · \(model.linkLabel)" } ?? "Aucun téléviseur")
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.activeTV.map { "\($0.displayName)" } ?? "Aucun téléviseur")
                        .font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 6) {
                        Circle().fill(summaryColor).frame(width: 6, height: 6).shadow(color: summaryColor, radius: 3)
                        Text(summary).font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62)).lineLimit(1)
                            .contentTransition(.opacity)
                    }
                    if let f = model.fatal {
                        Label(f, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10)).foregroundStyle(Color.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(18, highlight: hover ? 0.2 : 0.08)
            .scaleEffect(hover ? 1.015 : 1)
        }
        .buttonStyle(PressStyle()).focusEffectDisabled()
        .onHover { h in withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { hover = h } }
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: model.link)
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: model.agentLive)
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: model.serverUp)
        .animation(.easeInOut, value: model.fatal)
    }

    private var summary: String {
        if !model.serverUp { return model.fatal != nil ? "Serveur local arrêté" : "Démarrage…" }
        guard model.activeTV != nil else { return "Lance un scan pour trouver le TV" }
        switch model.link {
        case .connected(true): return model.agentLive ? "Tout est prêt · agent actif" : "Tout est prêt"
        case .connected(false): return "Connecté · à appairer"
        case .connecting: return "Connexion au téléviseur…"
        case .offline, .rejected: return "Téléviseur injoignable"
        case .idle: return "En attente"
        }
    }
    private var summaryColor: Color {
        if server == .off || tv == .off { return .danger }
        if server == .standby { return .warn }
        return tv == .on ? .sky : .warn
    }

    private func node(_ icon: String, _ label: String, _ state: NodeState, help: String) -> some View {
        VStack(spacing: 5) {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: state != .on)) { tl in
                let p = state == .on ? tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4 : 0
                ZStack {
                    // Onde : le maillon « respire » quand il est actif.
                    Circle().strokeBorder(Color.sky.opacity(state == .on ? 0.5 * (1 - p) : 0), lineWidth: 1.5)
                        .frame(width: 30 + 12 * p, height: 30 + 12 * p)
                    Circle()
                        .fill(state == .on ? AnyShapeStyle(LinearGradient(colors: [.royal, .peri], startPoint: .topLeading, endPoint: .bottomTrailing))
                              : AnyShapeStyle(Color.navy.opacity(0.4)))
                        .frame(width: 30, height: 30)
                        .overlay(Circle().strokeBorder(state == .off ? Color.white.opacity(0.25) : Color.sky.opacity(state == .on ? 0.6 : 0.35),
                                                       style: StrokeStyle(lineWidth: 1, dash: state == .off ? [2, 3] : [])))
                        .shadow(color: state == .on ? Color.peri.opacity(0.7) : .clear, radius: 8)
                    Image(systemName: icon).font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(state == .off ? 0.35 : state == .standby ? 0.7 : 1))
                }
                .frame(width: 34, height: 34)
            }
            Text(label).font(.system(size: 9, weight: .semibold)).lineLimit(1).fixedSize()
                .foregroundStyle(.white.opacity(state == .off ? 0.35 : 0.65))
        }
        .help(help)
    }

    /// Segment entre deux maillons : flux de points lumineux s'il est actif,
    /// pointillé calme en veille, quasi éteint s'il est coupé.
    private func segment(_ state: NodeState) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: state != .on)) { tl in
            let phase = CGFloat(tl.date.timeIntervalSinceReferenceDate * 22).truncatingRemainder(dividingBy: 12)
            ZStack {
                Capsule().fill(Color.sky.opacity(state == .on ? 0.25 : state == .standby ? 0.12 : 0.05)).frame(height: 2)
                if state != .off {
                    Line().stroke(state == .on ? Color.sky : Color.sky.opacity(0.4),
                                  style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: state == .on ? [2, 10] : [1, 4],
                                                     dashPhase: state == .on ? -phase : 0))
                        .frame(height: 2)
                        .shadow(color: state == .on ? Color.sky : .clear, radius: 3)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
        }
        .padding(.horizontal, -3)
        .frame(maxWidth: .infinity, alignment: .top)
        .alignmentGuide(.top) { $0[.top] }
        .offset(y: -9) // aligné sur le centre des cercles, pas sur les libellés
    }
}

private struct Line: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); return p
    }
}

// MARK: - En-tête d'écran

struct ScreenHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 28, weight: .bold))
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            trailing
        }
        .foregroundStyle(.white)
    }
}

// MARK: - Installer

struct InstallScreen: View {
    @ObservedObject var model: AppModel
    @LocalState private var appeared = false

    var body: some View {
        let palette = Pane.install.palette
        VStack(spacing: 0) {
            Spacer(minLength: 30)
            HStack(alignment: .center, spacing: 34) {
                // Héros
                VStack(spacing: 18) {
                    ZStack {
                        HeroOrb(palette: palette, state: model.installState, icon: model.iconURL, size: 220)
                        ParticleBurst(start: model.burstAt, colors: [.mint, palette.a, palette.b, Color.sky, .white])
                    }
                    VStack(spacing: 8) {
                        Text(heroTitle)
                            .font(.system(size: 26, weight: .bold))
                            .contentTransition(.interpolate)
                        Text(model.installMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.62))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 300, minHeight: 36, alignment: .top)
                            .id(model.installMessage)
                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                    removal: .opacity))
                    }
                    .foregroundStyle(.white)
                }
                .frame(minWidth: 250, maxWidth: 320)
                .scaleEffect(appeared ? 1 : 0.9)
                .opacity(appeared ? 1 : 0)

                // Formulaire
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Nouvelle application").font(.system(size: 15, weight: .semibold))
                        Spacer()
                        if !(model.appName.isEmpty && model.appID.isEmpty && model.appURL.isEmpty && model.iconURL.isEmpty) {
                            Button("Effacer") { model.resetForm() }
                                .buttonStyle(.plain)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                                .transition(.opacity)
                        }
                    }
                    FancyField(label: "Nom affiché", icon: "textformat", placeholder: "Mon application",
                               text: nameBinding, error: model.error(for: .name), palette: palette)
                    FancyField(label: "Identifiant", icon: "number", placeholder: "monapp",
                               text: $model.appID, error: model.error(for: .id), palette: palette)
                    FancyField(label: "URL", icon: "link", placeholder: "http://192.168.1.20:8080/index.html",
                               text: $model.appURL, error: model.error(for: .url), palette: palette)
                    FancyField(label: "Icône", icon: "photo", placeholder: "http://192.168.1.20:8080/icon.png (optionnel)",
                               text: $model.iconURL, error: model.error(for: .icon), palette: palette)
                }
                .foregroundStyle(.white)
                .padding(22)
                .frame(minWidth: 330, maxWidth: 420)
                .glass(24)
                .modifier(Shake(animatableData: CGFloat(model.failCount)))
                .offset(x: appeared ? 0 : 30)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.appName.isEmpty)
            }
            Spacer(minLength: 20)

            TargetChip(model: model)
                .opacity(appeared ? 1 : 0)
                .padding(.bottom, 6)

            VStack(spacing: 8) {
                BigRoundButton(title: "Installer", palette: palette, state: model.installState,
                               enabled: !model.busy || model.installState == .working) { model.install() }
                    .keyboardShortcut(.return, modifiers: .command)
                Text("⌘↩  ·  le téléviseur doit être allumé")
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.35))
            }
            .offset(y: appeared ? 0 : 30)
            .opacity(appeared ? 1 : 0)
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 36)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: model.installMessage)
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.05)) { appeared = true } }
    }

    private var heroTitle: String {
        switch model.installState {
        case .idle: model.appName.isEmpty ? "Prêt à installer" : model.appName
        case .working: "Installation…"
        case .success: "C'est installé"
        case .failure: "Ça n'a pas marché"
        }
    }

    private var nameBinding: Binding<String> {
        Binding(get: { model.appName }, set: { new in
            let old = model.appName
            model.appName = new
            model.suggestID(from: new, previous: old)
        })
    }
}

struct SearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            TextField("", text: $text, prompt: Text("Rechercher").foregroundColor(.white.opacity(0.35)))
                .textFieldStyle(.plain).font(.system(size: 12.5)).foregroundStyle(.white).focused($focused)
        }
        .padding(.horizontal, 12).frame(width: focused || !text.isEmpty ? 220 : 160, height: 32)
        .liquid(Capsule(), tint: .peri, opacity: focused ? 0.22 : 0.1, interactive: true)
        .overlay(Capsule().strokeBorder(Color.sky.opacity(focused ? 0.35 : 0.15)))
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: focused)
    }
}

struct EmptyState: View {
    let icon: String
    let palette: Palette
    let title: String
    let text: String
    let action: (String, () -> Void)?
    @LocalState private var float = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle().fill(palette.gradient).frame(width: 120, height: 120).blur(radius: 40).opacity(0.6)
                Image(systemName: icon).font(.system(size: 46, weight: .light)).foregroundStyle(.white)
                    .offset(y: float ? -6 : 6)
            }
            Text(title).font(.system(size: 19, weight: .semibold))
            Text(text).font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center).frame(maxWidth: 380)
            if let action {
                PillButton(title: action.0, icon: "arrow.down.circle", palette: palette, action: action.1).padding(.top, 6)
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .onAppear { withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { float = true } }
    }
}

// MARK: - Sauvegardes

struct BackupsScreen: View {
    @ObservedObject var model: AppModel
    @LocalState private var appeared = false

    var body: some View {
        let palette = Pane.backups.palette
        VStack(alignment: .leading, spacing: 20) {
            ScreenHeader(title: "Sauvegardes",
                         subtitle: "Une copie d'Appinfo.json est faite automatiquement avant chaque modification.") {
                HStack(spacing: 10) {
                    PillButton(title: "Dossier", icon: "folder") { model.openBackupsFolder() }
                    PillButton(title: "Sauvegarder", icon: "arrow.down.doc.fill", palette: palette, busy: model.backupBusy) {
                        model.backupNow()
                    }
                    .disabled(model.busy)
                }
            }
            .padding(.top, 46)

            if model.backups.isEmpty {
                EmptyState(icon: "clock.arrow.circlepath", palette: palette, title: "Aucune sauvegarde",
                           text: "Crée une copie d'Appinfo.json avant tes premières installations.",
                           action: ("Sauvegarder maintenant", { model.backupNow() }))
            } else {
                RoomyScroll {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(model.backups.enumerated()), id: \.element.id) { i, b in
                            BackupRow(backup: b, palette: palette, latest: i == 0, restoring: model.restoring == b.url,
                                      onRestore: { model.confirmRestore = b }, onReveal: { model.reveal(b) })
                                .opacity(appeared ? 1 : 0)
                                .offset(x: appeared ? 0 : -20)
                                .animation(.spring(response: 0.5, dampingFraction: 0.82).delay(Double(min(i, 15)) * 0.04), value: appeared)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 36)
        .onAppear {
            model.loadBackups()
            DispatchQueue.main.async { appeared = true }
        }
        .alert(item: $model.confirmRestore) { b in
            Alert(title: Text("Restaurer cette sauvegarde ?"),
                  message: Text("Appinfo.json sur le téléviseur sera remplacé par la version du \(b.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(fr))). L'état actuel est sauvegardé avant."),
                  primaryButton: .destructive(Text("Restaurer")) { model.restore(b) },
                  secondaryButton: .cancel(Text("Annuler")))
        }
    }
}

struct BackupRow: View {
    let backup: BackupFile
    let palette: Palette
    let latest: Bool
    let restoring: Bool
    let onRestore: () -> Void
    let onReveal: () -> Void
    @LocalState private var hover = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous).fill(latest ? AnyShapeStyle(palette.gradient) : AnyShapeStyle(Color.white.opacity(0.09)))
                Image(systemName: icon).font(.system(size: 15, weight: .semibold))
            }
            .frame(width: 40, height: 40)
            .shadow(color: latest ? palette.b.opacity(0.5) : .clear, radius: 10, y: 3)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(backup.date.formatted(.relative(presentation: .named).locale(fr)).capitalizedFirst)
                        .font(.system(size: 13, weight: .semibold))
                    if latest {
                        Text("DERNIÈRE").font(.system(size: 9, weight: .bold)).tracking(0.8)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(.white.opacity(0.14)))
                    }
                }
                Text("\(backup.reason) · \(backup.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(fr)))")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(backup.appCount.map { "\($0) apps" } ?? "—").font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(frenchSize(backup.size))
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.42))
            }
            HStack(spacing: 6) {
                PillButton(title: "Finder", icon: "magnifyingglass", action: onReveal)
                PillButton(title: "Restaurer", icon: "arrow.uturn.backward", palette: palette, busy: restoring, action: onRestore)
                    .disabled(backup.appCount == nil)
            }
            .opacity(hover || restoring ? 1 : 0)
            .offset(x: hover || restoring ? 0 : 12)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .glass(16, highlight: hover ? 0.2 : 0.1)
        .scaleEffect(hover ? 1.005 : 1)
        .onHover { hover = $0 }
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: hover)
    }

    private var icon: String {
        switch backup.reason {
        case "Avant une installation": "plus.app"
        case "Avant une désinstallation": "minus.square"
        case "Avant une restauration": "arrow.uturn.backward.square"
        default: "doc.badge.clock"
        }
    }
}

let fr = Locale(identifier: "fr_FR")

func frenchSize(_ n: Int) -> String {
    if n < 1024 { return "\(n) octets" }
    if n < 1 << 20 { return String(format: "%.0f Ko", Double(n) / 1024) }
    return String(format: "%.1f Mo", Double(n) / 1048576).replacingOccurrences(of: ".", with: ",")
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Toast

struct ToastHost: View {
    let toast: Toast?
    var body: some View {
        VStack {
            Spacer()
            if let toast {
                HStack(spacing: 10) {
                    Image(systemName: icon(toast.kind))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(color(toast.kind))
                        .symbolEffect(.bounce, value: toast.id)
                    Text(toast.text).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white)
                }
                .padding(.horizontal, 18).padding(.vertical, 11)
                .liquid(Capsule(), tint: .royal, opacity: 0.35)
                .overlay(Capsule().strokeBorder(color(toast.kind).opacity(0.45)))
                .shadow(color: color(toast.kind).opacity(0.35), radius: 18, y: 6)
                .padding(.bottom, 24)
                .padding(.leading, 252)
                .id(toast.id)
                .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
            }
        }
        .allowsHitTesting(false)
    }
    private func icon(_ k: Toast.Kind) -> String {
        switch k { case .success: "checkmark.circle.fill"; case .failure: "xmark.octagon.fill"; case .info: "info.circle.fill" }
    }
    private func color(_ k: Toast.Kind) -> Color {
        switch k { case .success: .mint; case .failure: .danger; case .info: Color.peri }
    }
}
