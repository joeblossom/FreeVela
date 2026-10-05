import SwiftUI

// MARK: - Tyre panel and rim line

/// The black rim inside the cream tyre: a line along the top edge with rounded top corners.
struct RimLine: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(radius, rect.height, rect.width / 2)
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + r, y: rect.minY), radius: r)
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r), radius: r)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return p
    }
}

/// The cream "tyre" sheet: rounded top corners with the rim line inset inside them.
struct TyreBackground: View {
    @Environment(\.theme) private var theme
    var corner: CGFloat = 36
    var rimHeight: CGFloat = 30

    var body: some View {
        UnevenRoundedRectangle(topLeadingRadius: corner, topTrailingRadius: corner)
            .fill(theme.cream)
            .overlay(alignment: .top) {
                RimLine(radius: corner - 8)
                    .stroke(theme.ink, lineWidth: 3)
                    .frame(height: rimHeight)
                    .padding(.horizontal, 9)
                    .padding(.top, 9)
            }
    }
}

// MARK: - Status

extension Session.Status {
    var chipLabel: String {
        switch self {
        case .connected: "Connected"
        case .locked: "Locked"
        case .searching: "Searching…"
        case .connecting: "Connecting…"
        case .unlocking: "Unlocking…"
        case .bluetooth: "Bluetooth off"
        case .asleep: "Asleep"
        }
    }
}

/// "● CONNECTED" in the painted header.
struct StatusChip: View {
    @EnvironmentObject private var session: Session
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(theme.paint.frame).frame(width: 6, height: 6)
            Text(session.status.chipLabel)
                .font(.archivo(11, weight: 700))
                .tracking(11 * 0.12)
                .textCase(.uppercase)
        }
        .foregroundStyle(theme.paint.frame)
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background(theme.paint.on, in: Capsule())
    }
}

// MARK: - Rows

/// The square row icon: an ink square with a cream symbol.
struct SettingsIcon: View {
    @Environment(\.theme) private var theme
    var symbol: String
    /// Kept for call sites; all row icons are ink in the paint style.
    init(_ symbol: String, _ color: Color = .clear) { self.symbol = symbol }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(theme.onInk)
            .frame(width: 30, height: 30)
            .background(theme.ink, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Icon + title. Action rows (buttons, share links) end in a chevron, with an optional detail before it;
/// `plain` rows (toggles, navigation links, values) don't. Titles are ink, or red for destructive actions,
/// so they read on every paint in light and dark.
struct SettingsRow: View {
    @Environment(\.theme) private var theme
    var title: String
    var symbol: String
    var plain = false
    var destructive = false
    var detail: String?
    init(_ title: String, _ symbol: String, _ color: Color = .clear, plain: Bool = false, destructive: Bool = false,
         detail: String? = nil) {
        self.title = title; self.symbol = symbol; self.plain = plain; self.destructive = destructive; self.detail = detail
    }

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol)
            Text(title)
                .font(.archivo(16, weight: 500))
                .foregroundStyle(destructive ? Color.red : theme.ink)
            if !plain {
                Spacer(minLength: 4)
                if let detail { Text(detail).font(.archivo(14, weight: 400)).foregroundStyle(theme.inkMuted) }
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkMuted)
            }
        }
        .contentShape(Rectangle())
    }
}

extension Theme {
    /// Accent on the cream panel: the paint, or ink if it's too pale to read there; on the dark
    /// palette, the paint's lit shade (made for dark backgrounds).
    var actionColor: Color { dark ? paint.lit : paint.isLight ? ink : paint.frame }
}

/// Section header: condensed caps in muted ink, with an optional value on the right.
struct SectionHeader: View {
    @Environment(\.theme) private var theme
    var title: String
    var trailing: String?
    init(_ title: String, trailing: String? = nil) { self.title = title; self.trailing = trailing }

    var body: some View {
        HStack {
            Text(title).foregroundStyle(theme.inkMuted)
            Spacer()
            if let trailing { Text(trailing).foregroundStyle(theme.ink) }
        }
        .display(15, weight: 700, tracking: 0.08)
    }
}

// MARK: - Controls

/// On: paint track with an `on` knob. Off: muted track with a light knob.
struct PaintToggleStyle: ToggleStyle {
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Capsule()
                .fill(configuration.isOn ? theme.paint.frame : theme.toggleOff)
                .frame(width: 51, height: 31)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(configuration.isOn ? theme.paint.on : theme.surface)
                        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                        .frame(width: 27, height: 27)
                        .padding(2)
                }
                .animation(.easeInOut(duration: 0.18), value: configuration.isOn)
                .onTapGesture { configuration.isOn.toggle() }
                .accessibilityElement()
                .accessibilityAddTraits(.isButton)
                .accessibilityValue(configuration.isOn ? "On" : "Off")
                .accessibilityAction { configuration.isOn.toggle() }
        }
    }
}

/// A slider with a 6 pt track, the filled part in the paint, and a light thumb ringed in ink.
/// `onEditingChanged(false)` fires when the finger lifts, like `Slider`'s.
struct PaintSlider: View {
    @Environment(\.theme) private var theme
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var onEditingChanged: (Bool) -> Void = { _ in }
    @State private var editing = false

    private let thumb: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let track = geo.size.width - thumb
            let frac = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .leading) {
                Capsule().fill(theme.tile).frame(height: 6).padding(.horizontal, thumb / 2)
                Capsule().fill(theme.paint.frame).frame(width: thumb / 2 + track * frac, height: 6)
                Circle()
                    .fill(theme.surface)
                    .overlay(Circle().stroke(theme.ink, lineWidth: 2))
                    .frame(width: thumb, height: thumb)
                    .offset(x: track * frac)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if !editing { editing = true; onEditingChanged(true) }
                    let f = min(max((g.location.x - thumb / 2) / track, 0), 1)
                    let raw = range.lowerBound + f * (range.upperBound - range.lowerBound)
                    value = min(max((raw / step).rounded() * step, range.lowerBound), range.upperBound)
                }
                .onEnded { _ in editing = false; onEditingChanged(false) })
        }
        .frame(height: 32)
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement()
        .accessibilityValue("\(value.formatted())")
        .accessibilityAdjustableAction { direction in
            let next = direction == .increment ? value + step : value - step
            value = min(max(next, range.lowerBound), range.upperBound)
            onEditingChanged(false)
        }
    }
}

/// Segmented control: ink outline, the selected segment filled with ink.
struct PaintSegmented<T: Hashable>: View {
    @Environment(\.theme) private var theme
    @Binding var selection: T
    var options: [(T, String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, label in
                let on = value == selection
                Text(label)
                    .display(14, tracking: 0.02)
                    .foregroundStyle(on ? theme.onInk : theme.ink)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .background(on ? theme.ink : .clear, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                    .onTapGesture { selection = value }
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.ink, lineWidth: 2))
        .fixedSize()
        .animation(.easeInOut(duration: 0.15), value: selection)
    }
}

/// The dark "Start ride" style bar button: condensed caps, left-aligned, with an optional trailing symbol.
struct InkBarButton: View {
    @Environment(\.theme) private var theme
    var title: String
    var symbol: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).display(24, tracking: 0.05)
                Spacer()
                if let symbol { Image(systemName: symbol).font(.system(size: 22, weight: .bold)) }
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, minHeight: 60)
            .foregroundStyle(theme.onInk)
            .background(theme.ink, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Lists and navigation

/// Grouped lists (Settings, Developer tools, Firmware update): cream background, light cards.
struct PaintList: ViewModifier {
    @Environment(\.theme) private var theme
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(theme.cream)
            .font(.archivo(16, weight: 500))
            .foregroundStyle(theme.ink)
            .toggleStyle(PaintToggleStyle())
            .environment(\.defaultMinListRowHeight, 48)
            .listSectionSpacing(18)
    }
}

/// Rows in a paint-style list: card background and dividers.
struct PaintRows: ViewModifier {
    @Environment(\.theme) private var theme
    func body(content: Content) -> some View {
        content
            .listRowBackground(theme.surface)
            .listRowSeparatorTint(theme.tile)
    }
}

/// Navigation bar: painted (Settings) with the status bar following the paint, or cream with an ink title.
struct PaintNavBar: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    var title: String?
    var painted = false

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(painted ? theme.paint.frame : theme.cream, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(painted ? (theme.paint.isLight ? .light : .dark) : scheme, for: .navigationBar)
            .toolbar {
                if let title {
                    ToolbarItem(placement: .principal) {
                        Text(title).display(20, tracking: 0.04).foregroundStyle(painted ? theme.paint.on : theme.ink)
                    }
                }
            }
    }
}

extension View {
    func paintList() -> some View { modifier(PaintList()) }
    func paintRows() -> some View { modifier(PaintRows()) }
    func paintNavBar(_ title: String? = nil, painted: Bool = false) -> some View {
        modifier(PaintNavBar(title: title, painted: painted))
    }
}

/// `Section` in the paint style: condensed caps header, muted footer, card rows. Same initializers.
struct PaintSection<Content: View, Header: View, Footer: View>: View {
    @Environment(\.theme) private var theme
    let content: Content
    let header: Header
    let footer: Footer

    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header, @ViewBuilder footer: () -> Footer) {
        self.content = content(); self.header = header(); self.footer = footer()
    }

    var body: some View {
        Section {
            content
        } header: {
            header.font(.display(15, weight: 700)).tracking(1.2).textCase(.uppercase).foregroundStyle(theme.inkMuted)
        } footer: {
            footer.font(.archivo(13, weight: 400)).foregroundStyle(theme.inkMuted)
        }
        .paintRows()
    }
}

extension PaintSection where Header == EmptyView, Footer == EmptyView {
    init(@ViewBuilder content: () -> Content) { self.init(content: content, header: { EmptyView() }, footer: { EmptyView() }) }
}

extension PaintSection where Footer == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {
        self.init(content: content, header: header, footer: { EmptyView() })
    }
}

extension PaintSection where Header == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(content: content, header: { EmptyView() }, footer: footer)
    }
}

extension PaintSection where Header == Text, Footer == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { Text(title) }, footer: { EmptyView() })
    }
}

// MARK: - Status bar

/// The status bar is set by hand (UIViewControllerBasedStatusBarAppearance is off): SwiftUI's
/// color-scheme modifiers can't give dark status-bar text on a light paint while the app is in dark mode.
enum StatusBar {
    static func set(lightText: Bool) {
        let style: UIStatusBarStyle = lightText ? .lightContent : .darkContent
        UIApplication.shared.setValue(style.rawValue, forKey: "statusBarStyle")
    }
}

private struct PaintStatusBar: ViewModifier {
    @Environment(\.theme) private var theme
    func body(content: Content) -> some View {
        content
            .onAppear { StatusBar.set(lightText: !theme.paint.isLight) }
            .onChange(of: theme.paint.isLight) { StatusBar.set(lightText: !theme.paint.isLight) }
    }
}

extension View {
    /// Status-bar text that reads on the paint (light on dark paints, dark on light ones).
    func paintStatusBar() -> some View { modifier(PaintStatusBar()) }
}
