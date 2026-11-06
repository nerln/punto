import SwiftUI
import AppKit

private enum PuntoStyle {
    static let background = adaptive("PuntoBackground", light: NSColor(calibratedWhite: 0.97, alpha: 1), dark: NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.075, alpha: 1))
    static let panel = adaptive("PuntoPanel", light: .white, dark: NSColor(calibratedRed: 0.087, green: 0.102, blue: 0.113, alpha: 1))
    static let accent = adaptive("PuntoAccent", light: NSColor(calibratedRed: 0.22, green: 0.39, blue: 0.13, alpha: 1), dark: NSColor(calibratedRed: 0.73, green: 0.94, blue: 0.58, alpha: 1))
    static let actionText = adaptive("PuntoActionText", light: .white, dark: NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.075, alpha: 1))
    static let muted = Color.secondary
    static let line = Color.primary.opacity(0.1)

    private static func adaptive(_ name: String, light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name(name)) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: DisplayStore
    @State private var showPattern = false
    @State private var showModes = false
    @State private var showAdvanced = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(PuntoStyle.line).frame(width: 1)
            VStack(spacing: 0) {
                topbar
                Divider().overlay(PuntoStyle.line)
                if store.pending {
                    confirmation
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                    Divider().overlay(PuntoStyle.line)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if let display = store.selectedDisplay {
                            displayHeader(display)
                            if let error = store.error { notice(error, error: true) }
                            if let message = store.message { notice(message, error: false) }
                            metrics(display)
                            if display.isBuiltin {
                                builtinNotice
                            } else {
                                directHiDPICard
                                nativeExplanation
                                DisclosureGroup("Diagnostica del segnale") {
                                    VStack(alignment: .leading, spacing: 15) {
                                        nativeSignalCard
                                        Button("Prova RGB completo") { store.applyNativeRGB() }.disabled(!store.canApplyNativeRGB || store.pending || store.isWorking)
                                        if store.canRestoreNativeOutput {
                                            Button("Ripristina segnale precedente") { store.restoreNativeOutput() }
                                                .disabled(store.isWorking || store.pending)
                                        }
                                    }.padding(.top, 12)
                                }.font(.system(size: 12)).tint(PuntoStyle.muted)
                                advancedModes(display)
                            }
                        } else {
                            emptyState
                        }
                    }
                    .padding(30)
                    .frame(maxWidth: 1120, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                if store.selectedDisplay?.isBuiltin == false {
                    Divider().overlay(PuntoStyle.line)
                    actionBar
                        .padding(.horizontal, 30)
                        .padding(.vertical, 15)
                        .background(PuntoStyle.background)
                }
            }
        }
        .background(PuntoStyle.background)
        .foregroundStyle(Color.primary.opacity(0.94))

        .frame(minWidth: 860, minHeight: 640)
        .sheet(isPresented: $showPattern) { CalibrationSheet() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11).fill(PuntoStyle.accent).frame(width: 36, height: 36)
                    Image(systemName: "viewfinder").font(.system(size: 21, weight: .semibold)).foregroundStyle(PuntoStyle.actionText)
                }
                Text("punto").font(.system(size: 25, weight: .semibold, design: .rounded)).tracking(-0.8)
            }
            .padding(.horizontal, 22).padding(.top, 31).padding(.bottom, 38)

            Text("I TUOI SCHERMI").font(.system(size: 10, weight: .semibold)).tracking(1.5)
                .foregroundStyle(PuntoStyle.muted).padding(.horizontal, 23).padding(.bottom, 13)

            ForEach(store.displays) { display in
                Button {
                    store.selectedDisplayID = display.id
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                            .font(.system(size: 18)).frame(width: 23).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(display.name).font(.system(size: 12, weight: .medium)).lineLimit(2)
                            Text(display.isBuiltin ? L("Integrato · sola lettura") : "\(display.nativeWidth) × \(display.nativeHeight)")
                                .font(.system(size: 10)).foregroundStyle(PuntoStyle.muted)
                        }
                        Spacer(minLength: 0)
                        if display.id == store.selectedDisplayID {
                            Circle().fill(PuntoStyle.accent).frame(width: 5, height: 5).padding(.top, 7)
                        }
                    }
                    .padding(13).frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(display.id == store.selectedDisplayID ? Color.primary : PuntoStyle.muted)
                    .background(RoundedRectangle(cornerRadius: 10).fill(display.id == store.selectedDisplayID ? Color.primary.opacity(0.065) : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(display.id == store.selectedDisplayID ? PuntoStyle.line : .clear))
                }
                .buttonStyle(.plain).padding(.horizontal, 10).padding(.bottom, 5)
                .disabled(store.pending || store.isWorking)
                .accessibilityLabel(LF("Seleziona %@", display.name))
            }

            Spacer(minLength: 25)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Image(systemName: "cpu").foregroundStyle(PuntoStyle.accent)
                    Text(store.metalDeviceName).font(.system(size: 11, weight: .medium)).lineLimit(1)
                }
                Text("Controllo nativo.\nNessun motore di cattura video.")
                    .font(.system(size: 10)).foregroundStyle(PuntoStyle.muted).lineSpacing(4)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.025)))
            .padding(13)

            Button { store.exportDiagnostics() } label: {
                Label("Esporta diagnostica", systemImage: "square.and.arrow.up").font(.system(size: 11))
            }
            .buttonStyle(.plain).foregroundStyle(PuntoStyle.muted)
            .padding(.horizontal, 25).padding(.bottom, 23)
        }
        .frame(width: 204)
        .background(Color.primary.opacity(0.025))
    }

    private var topbar: some View {
        HStack {
            HStack(spacing: 7) {
                Circle().fill(store.displays.isEmpty ? Color.orange : PuntoStyle.accent).frame(width: 5, height: 5)
                Text("DISPLAY CONTROL").font(.system(size: 10, weight: .medium)).tracking(1.6)
            }.foregroundStyle(PuntoStyle.muted)
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape").font(.system(size: 12))
            }
            .buttonStyle(.plain).foregroundStyle(PuntoStyle.muted)
            .help(L("Impostazioni")).accessibilityLabel(L("Impostazioni"))
            .padding(.trailing, 15)
            Button { showPattern = true } label: {
                Label("Test nitidezza", systemImage: "square.grid.3x3").font(.system(size: 11))
            }.buttonStyle(.plain).foregroundStyle(PuntoStyle.muted).padding(.trailing, 15)
            Button { store.refresh() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 12))
            }.buttonStyle(.plain).foregroundStyle(PuntoStyle.muted).help(L("Rileva nuovamente i display"))
                .disabled(store.isWorking || store.pending)
        }
        .padding(.horizontal, 30).frame(height: 53)
    }

    private func displayHeader(_ display: DisplayInfo) -> some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 9) {
                Text(display.name.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(PuntoStyle.accent)
                Text("HiDPI diretto.\nStesse dimensioni.").font(.system(size: 34, weight: .semibold)).tracking(-1.3).lineSpacing(-2)
                Text(display.isBuiltin ? L("Il display integrato resta sotto il controllo di macOS.") : L("Rendering 2× sul tuo monitor, senza schermi virtuali."))
                    .font(.system(size: 12)).foregroundStyle(PuntoStyle.muted).fixedSize(horizontal: false, vertical: true)
                Text(display.current.isHiDPI ? L("HiDPI 2× attivo") : L("Nativo 1× attivo"))
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(PuntoStyle.accent)
            }
            Spacer(minLength: 0)
            monitorIllustration(display)
        }
        .padding(.bottom, 1)
    }

    private func monitorIllustration(_ display: DisplayInfo) -> some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.8))
                RoundedRectangle(cornerRadius: 5)
                    .fill(LinearGradient(colors: [PuntoStyle.accent.opacity(0.15), Color(red: 0.07, green: 0.14, blue: 0.13)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(6)
                VStack(spacing: 6) {
                    Image(systemName: "viewfinder").font(.system(size: 25, weight: .ultraLight)).foregroundStyle(PuntoStyle.accent.opacity(0.8))
                    Text("\(display.nativeWidth) × \(display.nativeHeight)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(PuntoStyle.accent.opacity(0.8))
                }
            }
            .frame(width: 176, height: 110).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.15)))
            Rectangle().fill(Color.primary.opacity(0.13)).frame(width: 18, height: 14)
            RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.16)).frame(width: 65, height: 3)
        }
        .accessibilityHidden(true)
    }

    private func metrics(_ display: DisplayInfo) -> some View {
        HStack(spacing: 0) {
            metric("SPAZIO DI LAVORO", "\(display.current.width) × \(display.current.height)", display.current.isHiDPI ? "punti · HiDPI" : "punti · 1×")
            Rectangle().fill(PuntoStyle.line).frame(width: 1).padding(.vertical, 18)
            metric("FRAMEBUFFER", "\(display.current.pixelWidth) × \(display.current.pixelHeight)", "pixel renderizzati")
            Rectangle().fill(PuntoStyle.line).frame(width: 1).padding(.vertical, 18)
            metric("AGGIORNAMENTO", display.current.refreshRate > 0 ? String(format: "%.0f Hz", display.current.refreshRate) : "—", display.ppi > 0 ? String(format: L("circa %.0f PPI fisici"), display.ppi) : "frequenza non dichiarata")
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: 12).fill(PuntoStyle.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(PuntoStyle.line))
    }

    private func metric(_ label: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L(label)).font(.system(size: 9, weight: .medium)).tracking(1.2).foregroundStyle(PuntoStyle.muted)
            Text(value).font(.system(size: 19, weight: .medium, design: .monospaced)).tracking(-0.7).lineLimit(1).minimumScaleFactor(0.7)
            Text(L(detail)).font(.system(size: 10)).foregroundStyle(PuntoStyle.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(17)
    }

    private var directHiDPICard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("HiDPI diretto a dimensioni native").font(.system(size: 17, weight: .medium))
                Spacer()
                Text("DIMENSIONI 100%").font(.system(size: 9, weight: .semibold)).foregroundStyle(PuntoStyle.accent)
            }
            Text(store.directHiDPIDescription ?? L("Il driver non offre la modalità 2× alle dimensioni native con la frequenza attuale."))
                .font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(PuntoStyle.accent)
                .fixedSize(horizontal: false, vertical: true)
            Text("Dimensioni 100% · rendering interno 2× · uscita alla risoluzione nativa · nessun display virtuale")
                .font(.system(size: 12)).foregroundStyle(PuntoStyle.muted).lineSpacing(4)
            Label("Nessun mirroring · nessuna cattura del desktop", systemImage: "display")
                .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.75))
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(PuntoStyle.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(PuntoStyle.accent.opacity(0.35)))
    }

    private var nativeSignalCard: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text("Formato del segnale").font(.system(size: 17, weight: .medium)).tracking(-0.3)
                Spacer()
                Label("DIMENSIONI INVARIATE", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 8, weight: .semibold)).tracking(0.6).foregroundStyle(PuntoStyle.accent)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("OUTPUT ATTUALE").font(.system(size: 9, weight: .medium)).tracking(1.2).foregroundStyle(PuntoStyle.muted)
                Text(store.nativeOutputDescription)
                    .font(.system(size: 12, weight: .medium, design: .monospaced)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().overlay(PuntoStyle.line)
            VStack(alignment: .leading, spacing: 7) {
                Text("RGB DISPONIBILE").font(.system(size: 9, weight: .medium)).tracking(1.2).foregroundStyle(PuntoStyle.muted)
                Text(store.nativeRGBDescription ?? L("Nessuna alternativa RGB selezionabile rilevata."))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(store.nativeRGBDescription == nil ? PuntoStyle.muted : PuntoStyle.accent)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            Text("Prova il segnale RGB completo mantenendo risoluzione, dimensioni e frequenza.")
                .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(PuntoStyle.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(PuntoStyle.accent.opacity(0.22)))
    }

    private var nativeExplanation: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle").foregroundStyle(PuntoStyle.muted).padding(.top, 1)
            Text("Questa modalità usa il percorso HiDPI del driver. Il rendering interno ha quattro volte i pixel del pannello e viene ricampionato da macOS. La nitidezza percepita va confrontata sul monitor: il fattore 2× non aggiunge pixel fisici né ripristina il vecchio antialiasing RGB dei caratteri.")
                .font(.system(size: 11)).foregroundStyle(PuntoStyle.muted).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func advancedModes(_ display: DisplayInfo) -> some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Questi profili cambiano lo scaling. Il rendering HiDPI più ampio del pannello usa supersampling e ricampionamento; il display virtuale richiede che Punto resti aperto.")
                    .font(.system(size: 10)).foregroundStyle(PuntoStyle.muted).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                profileSection(display)
                if let profile = store.selectedProfile { pipeline(profile, display: display) }
                advancedActionBar
                explanation(display)
            }.padding(.top, 15)
        } label: {
            HStack(spacing: 8) {
                Text("Modalità video avanzate").font(.system(size: 12, weight: .medium))
                Text("SCALING E HiDPI").font(.system(size: 8, weight: .medium)).tracking(0.8).foregroundStyle(PuntoStyle.muted)
            }
        }
        .tint(PuntoStyle.muted)
        .padding(16).background(RoundedRectangle(cornerRadius: 11).fill(Color.primary.opacity(0.025)))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(PuntoStyle.line))
    }

    private func profileSection(_ display: DisplayInfo) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(showModes ? L("Modalità del monitor") : L("Profili di scaling")).font(.system(size: 17, weight: .medium)).tracking(-0.3)
                Spacer()
                Button { showModes.toggle() } label: {
                    Text(showModes ? L("Mostra profili") : L("Tutte le modalità")).font(.system(size: 11)).foregroundStyle(PuntoStyle.muted)
                }.buttonStyle(.plain)
            }
            if showModes {
                VStack(spacing: 0) {
                    ForEach(display.modes) { mode in
                        HStack {
                            Text("\(mode.width) × \(mode.height)").font(.system(size: 12, weight: .medium, design: .monospaced))
                            if mode.isHiDPI { Text("HiDPI").font(.system(size: 9, weight: .semibold)).foregroundStyle(PuntoStyle.accent) }
                            Spacer()
                            Text("\(mode.pixelWidth) × \(mode.pixelHeight) px · \(Int(mode.refreshRate.rounded())) Hz").font(.system(size: 10)).foregroundStyle(PuntoStyle.muted)
                            Button("Prova") { store.applyMode(mode) }.font(.system(size: 10)).disabled(store.pending || store.isWorking)
                        }.padding(11)
                        Divider().overlay(PuntoStyle.line)
                    }
                }.background(RoundedRectangle(cornerRadius: 10).fill(PuntoStyle.panel))
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)], spacing: 11) {
                    ForEach(store.profiles) { profile in profileCard(profile) }
                }
            }
        }
    }

    private func profileCard(_ profile: ScalingProfile) -> some View {
        let selected = store.selectedProfileID == profile.id || (store.selectedProfileID == nil && store.selectedProfile?.id == profile.id)
        let unavailable = profile.requiresVirtual && !store.virtualAvailable
        return Button {
            store.selectedProfileID = profile.id
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Text(profile.badge.uppercased()).font(.system(size: 8, weight: .semibold)).tracking(0.7)
                        .foregroundStyle(selected ? PuntoStyle.accent : PuntoStyle.muted)
                    Spacer(minLength: 2)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15)).foregroundStyle(selected ? PuntoStyle.accent : Color.primary.opacity(0.17))
                }
                Text(profile.title).font(.system(size: 15, weight: .medium)).tracking(-0.2)
                Text(unavailable ? L("HiDPI virtuale non disponibile su questo sistema.") : profile.subtitle)
                    .font(.system(size: 10)).foregroundStyle(PuntoStyle.muted).lineLimit(2).frame(minHeight: 27, alignment: .top)
                HStack(spacing: 5) {
                    Text("\(profile.logicalWidth) × \(profile.logicalHeight)").font(.system(size: 11, weight: .medium, design: .monospaced))
                    Spacer(minLength: 0)
                    if store.activeProfileID == profile.id {
                        Text("ATTIVO").font(.system(size: 8, weight: .semibold)).foregroundStyle(PuntoStyle.accent)
                    } else {
                        Text(LF("%.2g× pixel renderizzati", profile.pixelMultiplier))
                            .font(.system(size: 9)).foregroundStyle(PuntoStyle.muted)
                            .help(L("Rapporto teorico tra i pixel del framebuffer e quelli del pannello. Non è una misura del consumo GPU."))
                    }
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 11).fill(selected ? PuntoStyle.accent.opacity(0.055) : PuntoStyle.panel))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(selected ? PuntoStyle.accent.opacity(0.65) : PuntoStyle.line, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain).disabled(unavailable || store.pending || store.isWorking).opacity(unavailable ? 0.45 : 1)
        .accessibilityLabel(LF("%@, %d per %d, %@", profile.title, profile.logicalWidth, profile.logicalHeight, profile.subtitle))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func pipeline(_ profile: ScalingProfile, display: DisplayInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PERCORSO DEI PIXEL").font(.system(size: 9, weight: .medium)).tracking(1.2).foregroundStyle(PuntoStyle.muted)
                Spacer()
                Text(profile.isExact ? L("Nessun ricampionamento previsto") : L("Ridimensionamento necessario"))
                    .font(.system(size: 9)).foregroundStyle(profile.isExact ? PuntoStyle.accent : Color.orange.opacity(0.9))
            }
            HStack(spacing: 9) {
                pipelineStep("Interfaccia", "\(profile.logicalWidth) × \(profile.logicalHeight)")
                Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(PuntoStyle.muted)
                pipelineStep("Rendering", "\(profile.renderWidth) × \(profile.renderHeight)")
                Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(PuntoStyle.muted)
                pipelineStep("Pannello fisico", "\(display.nativeWidth) × \(display.nativeHeight)")
            }
            if profile.requiresVirtual {
                Text("HiDPI tramite display virtuale e duplicazione di macOS. Punto deve restare aperto; il carico aggiuntivo dipende da WindowServer.")
                    .font(.system(size: 10)).foregroundStyle(PuntoStyle.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16).background(RoundedRectangle(cornerRadius: 11).fill(Color.primary.opacity(0.025)))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(PuntoStyle.line))
    }

    private func pipelineStep(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L(title)).font(.system(size: 10)).foregroundStyle(PuntoStyle.muted)
            Text(value).font(.system(size: 12, weight: .medium, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.75)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionBar: some View {
        HStack(spacing: 13) {
            Button { store.restoreNative() } label: {
                Label("Ripristina 1:1", systemImage: "arrow.uturn.backward").font(.system(size: 11))
            }.buttonStyle(.plain).foregroundStyle(PuntoStyle.muted).disabled(store.isWorking || store.pending)
            Spacer()
            if store.isWorking { ProgressView().controlSize(.small) }
            Button { store.applyDirectHiDPI() } label: {
                HStack(spacing: 9) {
                    Text(store.isWorking ? L("Configurazione…") : L("Prova HiDPI a dimensioni native")).font(.system(size: 12, weight: .semibold))
                    Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold))
                }.foregroundStyle(PuntoStyle.actionText).padding(.horizontal, 20).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 9).fill(PuntoStyle.accent))
            }
            .buttonStyle(.plain).disabled(store.isWorking || store.pending || !store.canApplyDirectHiDPI)
            .opacity(store.isWorking || store.pending || !store.canApplyDirectHiDPI ? 0.45 : 1)
        }
    }

    private var advancedActionBar: some View {
        HStack(spacing: 13) {
            if store.activeVirtualID != nil {
                Button { store.revert() } label: {
                    Label("Termina HiDPI", systemImage: "stop.circle").font(.system(size: 11))
                }
                .buttonStyle(.plain).foregroundStyle(PuntoStyle.accent).disabled(store.isWorking)
                .help(L("Disattiva il display virtuale e ripristina la configurazione precedente."))
            }
            Spacer()
            Button { store.applySelected() } label: {
                HStack(spacing: 9) {
                    Text(store.isWorking ? L("Configurazione…") : L("Prova profilo")).font(.system(size: 12, weight: .semibold))
                    Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold))
                }.foregroundStyle(Color.primary.opacity(0.85)).padding(.horizontal, 15).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.07)))
            }.buttonStyle(.plain).disabled(store.isWorking || store.pending || store.selectedProfile == nil)
        }
    }

    private var confirmation: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle().strokeBorder(PuntoStyle.accent.opacity(0.35), lineWidth: 2).frame(width: 39, height: 39)
                Text("\(store.secondsRemaining)").font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(PuntoStyle.accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Il risultato ti convince?").font(.system(size: 13, weight: .medium))
                Text("Senza conferma, torna la configurazione precedente.").font(.system(size: 10)).foregroundStyle(PuntoStyle.muted)
            }
            Spacer(minLength: 0)
            Button("Annulla") { store.revert() }.controlSize(.small)
            Button("Mantieni") { store.confirm() }.controlSize(.small).tint(PuntoStyle.accent).buttonStyle(.borderedProminent)
                .foregroundStyle(PuntoStyle.actionText).keyboardShortcut(.return, modifiers: [])
        }
        .padding(14).background(RoundedRectangle(cornerRadius: 11).fill(PuntoStyle.accent.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(PuntoStyle.accent.opacity(0.35)))
    }

    private func explanation(_ display: DisplayInfo) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                Text("La nitidezza parte dai pixel fisici.").fontWeight(.medium)
            }.font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.7))
            Text(LF("Su questo pannello, 1:1 significa %d × %d a 1×. Il 2× esatto offre %d × %d punti. Le dimensioni intermedie richiedono un ricampionamento: un’app non può aggiungere pixel al monitor.", display.nativeWidth, display.nativeHeight, display.nativeWidth / 2, display.nativeHeight / 2))
                .font(.system(size: 10)).foregroundStyle(PuntoStyle.muted).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            Text(LF("Risoluzione pannello: %@. Il framebuffer non misura direttamente il segnale sul cavo.", display.nativeSource))
                .font(.system(size: 9)).foregroundStyle(PuntoStyle.muted.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
        }.padding(.top, 1)
    }

    private func notice(_ message: String, error: Bool) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: error ? "exclamationmark.triangle" : "checkmark.circle").foregroundStyle(error ? Color.orange : PuntoStyle.accent)
            Text(message).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.padding(12).background(RoundedRectangle(cornerRadius: 9).fill((error ? Color.orange : PuntoStyle.accent).opacity(0.06)))
    }

    private var builtinNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Il tuo schermo Retina integrato", systemImage: "lock").font(.system(size: 15, weight: .medium))
            Text("Punto modifica soltanto gli schermi esterni. Seleziona il tuo monitor nella barra laterale per scegliere una modalità e confrontarne il rendering.")
                .font(.system(size: 12)).foregroundStyle(PuntoStyle.muted).lineSpacing(4)
        }.padding(23).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 12).fill(PuntoStyle.panel))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "display.trianglebadge.exclamationmark").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(PuntoStyle.accent)
            Text("Collega il tuo monitor.").font(.system(size: 25, weight: .medium))
            Text("Le modalità disponibili appariranno qui.").font(.system(size: 13)).foregroundStyle(PuntoStyle.muted)
            Button("Rileva display") { store.refresh() }
        }.frame(maxWidth: .infinity, minHeight: 400)
    }
}

private struct CalibrationSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Il dettaglio, da vicino.").font(.system(size: 26, weight: .semibold)).tracking(-0.7)
                    Text("Sposta questa finestra sul monitor da verificare.").font(.system(size: 12)).foregroundStyle(PuntoStyle.muted)
                }
                Spacer()
                Button("Chiudi") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            MetalPatternView().frame(minHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(PuntoStyle.line))
            HStack(alignment: .top, spacing: 30) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Aa Bb 0123456789").font(.system(size: 24))
                    Text("Testo di sistema, 13 punti.\nControlla bordi, diagonali e spazi tra le lettere.")
                        .font(.system(size: 13)).lineSpacing(5)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Text("const pixel = 1;").font(.system(size: 19, design: .monospaced))
                    Text("Il pattern usa righe da un pixel del framebuffer.\nIl confronto è significativo sul pannello fisico.")
                        .font(.system(size: 11)).foregroundStyle(PuntoStyle.muted).lineSpacing(4)
                }
            }
            Divider().overlay(PuntoStyle.line)
            Text("Il pattern viene disegnato con Metal solo quando necessario. Il desktop è composto da macOS: questo test non sostituisce né controlla il suo motore grafico.")
                .font(.system(size: 10)).foregroundStyle(PuntoStyle.muted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(28).frame(width: 800, height: 540).background(PuntoStyle.background)
    }
}
