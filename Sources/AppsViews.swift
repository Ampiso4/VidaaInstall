import SwiftUI
import AppKit

// MARK: - Images distantes (cache partagé : l'icône sert aussi au halo)

final class RemoteImage: ObservableObject {
    private static let cache = NSCache<NSString, NSImage>()
    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 8
        c.urlCache = URLCache(memoryCapacity: 16 << 20, diskCapacity: 64 << 20)
        return URLSession(configuration: c)
    }()

    @Published private(set) var image: NSImage?
    private var current: String?

    func load(_ url: String) {
        guard url != current else { return }
        current = url
        if let hit = Self.cache.object(forKey: url as NSString) { image = hit; return }
        image = nil
        guard let u = URL(string: url), u.scheme?.hasPrefix("http") == true else { return }
        Self.session.dataTask(with: u) { [weak self] data, _, _ in
            guard let data, let img = NSImage(data: data) else { return }
            Self.cache.setObject(img, forKey: url as NSString)
            DispatchQueue.main.async {
                guard self?.current == url else { return }
                withAnimation(.easeOut(duration: 0.35)) { self?.image = img }
            }
        }.resume()
    }
}

// MARK: - Écran Applications

struct AppsScreen: View {
    @ObservedObject var model: AppModel
    @LocalState private var appeared = false
    @Namespace private var chipNS
    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 186), spacing: 18)]

    var body: some View {
        let palette = Pane.apps.palette
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(title: "Applications", subtitle: subtitle) {
                HStack(spacing: 10) {
                    if model.appsLoaded { SearchField(text: $model.search).transition(.opacity.combined(with: .scale(scale: 0.9))) }
                    PillButton(title: model.appsLoaded ? "Actualiser" : "Charger", icon: "arrow.clockwise",
                               palette: palette, busy: model.appsLoading) { model.refreshApps() }
                        .disabled(model.busy)
                }
            }
            .padding(.top, 46)

            if model.appsLoaded { toolbar.transition(.opacity.combined(with: .move(edge: .top))) }

            if model.appsLoading && !model.appsLoaded {
                RoomyScroll(horizontal: 24, top: 14, bottom: 34) {
                    LazyVGrid(columns: columns, spacing: 20) { ForEach(0..<10, id: \.self) { _ in SkeletonTile() } }.padding(.top, 4)
                }
                    .transition(.opacity)
            } else if !model.appsLoaded {
                EmptyState(icon: "square.grid.2x2", palette: palette,
                           title: model.appsError == nil ? "Aucune liste chargée" : "Impossible de lire la liste",
                           text: model.appsError ?? "VidaaInstall ouvre la page agent sur le téléviseur et récupère les applications installées.",
                           action: ("Charger depuis le téléviseur", { model.refreshApps() }))
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if model.filteredApps.isEmpty {
                EmptyState(icon: model.search.isEmpty ? model.appFilter.icon : "magnifyingglass", palette: palette,
                           title: "Aucune application",
                           text: model.search.isEmpty ? "Rien dans « \(model.appFilter.title) »." : "Rien ne correspond à « \(model.search) ».",
                           action: nil)
                    .transition(.opacity)
            } else {
                // Les tuiles se soulèvent et projettent un halo : 24 pt sur les côtés,
                // 14 pt en haut (l'écart avec les filtres est de 16 pt).
                RoomyScroll(horizontal: 24, top: 14, bottom: 34) {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(Array(model.filteredApps.enumerated()), id: \.element.id) { i, app in
                            AppTile(app: app, palette: palette, removing: model.removing.contains(app.id),
                                    onEdit: { model.edit(app) }, onDelete: { model.confirmUninstall = app })
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 22)
                                .scaleEffect(appeared ? 1 : 0.94)
                                .animation(.spring(response: 0.55, dampingFraction: 0.78).delay(Double(min(i, 24)) * 0.035), value: appeared)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                    }
                    .padding(.top, 4)
                }
                .transition(.opacity)
                .onAppear { appeared = false; DispatchQueue.main.async { appeared = true } }
                .onChange(of: model.appsVersion) { _, _ in
                    appeared = false
                    DispatchQueue.main.async { appeared = true }
                }
            }
        }
        .padding(.horizontal, 30)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: model.appsLoaded)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: model.appsLoading)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: model.search)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: model.appFilter)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: model.appSort)
        .alert(item: $model.confirmUninstall) { app in
            Alert(title: Text("Désinstaller « \(app.name) » ?"),
                  message: Text(app.preinstalled
                                ? "C'est une application préinstallée du téléviseur. Une sauvegarde d'Appinfo.json est faite automatiquement avant."
                                : "Une sauvegarde d'Appinfo.json est faite automatiquement avant la suppression."),
                  primaryButton: .destructive(Text("Désinstaller")) { model.uninstall(app) },
                  secondaryButton: .cancel(Text("Annuler")))
        }
        .onAppear { if !model.appsLoaded && !model.busy && (model.tvConnected || model.agentLive) { model.refreshApps() } }
    }

    private var subtitle: String {
        guard model.appsLoaded else { return "Lis la liste directement sur le téléviseur." }
        let mine = model.count(.custom)
        return "\(model.apps.count) applications sur le téléviseur" + (mine > 0 ? " · \(mine) à toi" : "")
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            ForEach(AppSource.allCases) { f in chip(f) }
            Spacer()
            HStack(spacing: 2) {
                ForEach(AppSort.allCases) { s in
                    Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { model.appSort = s } } label: {
                        Text(s.title).font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(model.appSort == s ? 1 : 0.55))
                            .padding(.horizontal, 10).frame(height: 24)
                            .background {
                                if model.appSort == s {
                                    Capsule().fill(Color.peri.opacity(0.35)).matchedGeometryEffect(id: "sort", in: chipNS)
                                }
                            }
                    }
                    .buttonStyle(.plain).focusEffectDisabled()
                }
            }
            .padding(3)
            .liquid(Capsule(), tint: .navy, opacity: 0.2)
        }
    }

    private func chip(_ f: AppSource) -> some View {
        let on = model.appFilter == f
        let n = model.count(f)
        return Button { withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { model.appFilter = f } } label: {
            HStack(spacing: 6) {
                Image(systemName: f.icon).font(.system(size: 10.5, weight: .semibold))
                Text(f.title).font(.system(size: 12, weight: .semibold))
                Text("\(n)").font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.sky.opacity(on ? 0.3 : 0.12)))
                    .contentTransition(.numericText())
            }
            .foregroundStyle(.white.opacity(on ? 1 : 0.65))
            .padding(.horizontal, 12).frame(height: 30)
            .background {
                if on {
                    Capsule().fill(LinearGradient(colors: [.royal, .peri], startPoint: .leading, endPoint: .trailing))
                        .opacity(0.75)
                        .matchedGeometryEffect(id: "filter", in: chipNS)
                }
            }
            .liquid(Capsule(), tint: .peri, opacity: on ? 0.2 : 0.08, interactive: true)
        }
        .buttonStyle(.plain).focusEffectDisabled()
        .opacity(n == 0 && f != .all ? 0.45 : 1)
    }
}

// MARK: - Tuile TV

struct AppTile: View {
    let app: TVApp
    let palette: Palette
    let removing: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    @StateObject private var loader = RemoteImage()
    @LocalState private var hover = false
    @LocalState private var tilt = CGSize.zero
    @LocalState private var glare = UnitPoint(x: 0.5, y: 0)

    private let radius: CGFloat = 22

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack(alignment: .bottom) {
            artwork
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(shape)

            // Reflet qui suit la souris
            shape.fill(RadialGradient(colors: [.white.opacity(hover ? 0.28 : 0), .clear], center: glare,
                                      startRadius: 0, endRadius: 160))
                .blendMode(.plusLighter)
                .allowsHitTesting(false)

            infoBar
        }
        .overlay(shape.strokeBorder(LinearGradient(colors: [Color.sky.opacity(hover ? 0.6 : 0.28), Color.sky.opacity(0.04)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        .overlay(alignment: .topLeading) { badge.padding(9) }
        .overlay(alignment: .topTrailing) { actions.padding(8) }
        .overlay { if removing { removingOverlay(shape) } }
        .background {
            // Halo : l'icône elle-même, floutée, déborde de la carte.
            artwork
                .clipShape(shape)
                .scaleEffect(hover ? 1.08 : 0.96)
                .blur(radius: hover ? 30 : 22)
                .opacity(hover ? 0.85 : 0.5)
                .offset(y: hover ? 14 : 10)
        }
        .rotation3DEffect(.degrees(Double(tilt.height) * -9), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        .rotation3DEffect(.degrees(Double(tilt.width) * 9), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .scaleEffect(hover ? 1.035 : 1)
        .offset(y: hover ? -6 : 0)
        .zIndex(hover ? 1 : 0)
        .contentShape(shape)
        .onContinuousHover { phase in
            switch phase {
            case .active(let p):
                let size = CGSize(width: 170, height: 170)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    hover = true
                    tilt = CGSize(width: max(-1, min(1, (p.x / size.width - 0.5) * 2)), height: max(-1, min(1, (p.y / size.height - 0.5) * 2)))
                    glare = UnitPoint(x: p.x / size.width, y: p.y / size.height)
                }
            case .ended:
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { hover = false; tilt = .zero }
            }
        }
        .onHover { inside in
            // Filet de sécurité : onContinuousHover rate parfois la sortie quand la souris file.
            if !inside { withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { hover = false; tilt = .zero } }
        }
        .contextMenu {
            if app.custom { Button("Modifier", action: onEdit) }
            Button("Copier l'URL") { copy(app.url) }
            Button("Copier l'identifiant") { copy(app.id) }
            Divider()
            Button("Désinstaller…", role: .destructive, action: onDelete)
        }
        .animation(.easeInOut, value: removing)
        .onAppear { loader.load(app.icon) }
        .onChange(of: app.icon) { _, new in loader.load(new) }
        .help("\(app.name)\n\(app.url)")
    }

    @ViewBuilder private var artwork: some View {
        if let img = loader.image {
            Image(nsImage: img).resizable().interpolation(.high).scaledToFill()
                .transition(.opacity)
        } else {
            ZStack {
                LinearGradient(colors: [.royal, .peri], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(String(app.name.prefix(1)).uppercased())
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private var infoBar: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(app.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Text(app.category ?? sourceLabel).font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.sky.opacity(0.85)).lineLimit(1)
            if hover {
                VStack(alignment: .leading, spacing: 2) {
                    if !app.host.isEmpty { Label(app.host, systemImage: "link").lineLimit(1) }
                    if let d = app.installed {
                        Label(d.formatted(Date.FormatStyle(date: .abbreviated).locale(fr)), systemImage: "calendar")
                    }
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .labelStyle(TightLabel())
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11).padding(.vertical, 9)
        // Verre dépoli (regular) + navy : le texte reste lisible quel que soit l'icône dessous.
        .liquid(RoundedRectangle(cornerRadius: 15, style: .continuous), tint: .navy, opacity: 0.62)
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Color.sky.opacity(0.18)))
        .padding(7)
    }

    private var sourceLabel: String {
        switch app.source { case .custom: "Ajoutée par toi"; case .store: "VIDAA Store"; default: "Hisense" }
    }

    @ViewBuilder private var badge: some View {
        if app.custom {
            Label("Perso", systemImage: "sparkles")
                .font(.system(size: 9, weight: .bold)).labelStyle(TightLabel())
                .foregroundStyle(Color.navy)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Color.sky))
                .shadow(color: Color.sky.opacity(0.6), radius: 6)
        }
    }

    @ViewBuilder private var actions: some View {
        if hover && !removing {
            HStack(spacing: 5) {
                if app.custom { circleButton("pencil", action: onEdit) }
                circleButton("trash", action: onDelete)
            }
            .transition(.scale(scale: 0.5, anchor: .topTrailing).combined(with: .opacity))
        }
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .liquid(Circle(), tint: .navy, opacity: 0.45, interactive: true)
                .overlay(Circle().strokeBorder(Color.sky.opacity(0.3)))
        }
        .buttonStyle(PressStyle()).focusEffectDisabled()
    }

    private func removingOverlay(_ shape: RoundedRectangle) -> some View {
        shape.fill(Color.navy.opacity(0.6))
            .overlay(VStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(.white)
                Text("Désinstallation…").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.8))
            })
            .transition(.opacity)
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon; configuration.title }
    }
}

struct SkeletonTile: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: [Color.peri.opacity(0.18), Color.royal.opacity(0.12)], startPoint: .top, endPoint: .bottom))
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.14)).frame(width: 80, height: 9)
                    RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.08)).frame(width: 52, height: 7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.navy.opacity(0.35)))
                .padding(7)
            }
            .modifier(Shimmer())
    }
}
