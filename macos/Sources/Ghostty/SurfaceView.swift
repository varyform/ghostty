import SwiftUI
import UserNotifications
import GhosttyKit

extension Ghostty {
    /// Render a terminal for the active app in the environment.
    struct Terminal: View {
        @EnvironmentObject private var ghostty: Ghostty.App
        @FocusedValue(\.ghosttySurfaceTitle) private var surfaceTitle: String?

        var body: some View {
            if let app = self.ghostty.app {
                SurfaceForApp(app) { surfaceView in
                    SurfaceWrapper(surfaceView: surfaceView)
                }
                .navigationTitle(surfaceTitle ?? "Ghostty")
            }
        }
    }

    /// Yields a SurfaceView for a ghostty app that can then be used however you want.
    struct SurfaceForApp<Content: View>: View {
        let content: ((SurfaceView) -> Content)

        @StateObject private var surfaceView: SurfaceView

        init(_ app: ghostty_app_t, @ViewBuilder content: @escaping ((SurfaceView) -> Content)) {
            _surfaceView = StateObject(wrappedValue: SurfaceView(app))
            self.content = content
        }

        var body: some View {
            content(surfaceView)
        }
    }

    struct SurfaceWrapper: View {
        // The surface to create a view for. This must be created upstream. As long as this
        // remains the same, the surface that is being rendered remains the same.
        @ObservedObject var surfaceView: SurfaceView

        // True if this surface is part of a split view. This is important to know so
        // we know whether to dim the surface out of focus.
        var isSplit: Bool = false

        // Maintain whether our view has focus or not
        @FocusState private var surfaceFocus: Bool

        // Maintain whether our window has focus (is key) or not
        @State private var windowFocus: Bool = true

        // True if we're hovering over the left URL view, so we can show it on the right.
        @State private var isHoveringURLLeft: Bool = false

        #if canImport(AppKit)
        // Observe SecureInput to detect when its enabled
        @ObservedObject private var secureInput = SecureInput.shared
        #endif

        @EnvironmentObject private var ghostty: Ghostty.App

        var body: some View {
            let center = NotificationCenter.default

            ZStack {
                // We use a GeometryReader to get the frame bounds so that our metal surface
                // is up to date. See TerminalSurfaceView for why we don't use the NSView
                // resize callback.
                GeometryReader { geo in
                    #if canImport(AppKit)
                    let pubBecomeKey = center.publisher(for: NSWindow.didBecomeKeyNotification)
                    let pubResign = center.publisher(for: NSWindow.didResignKeyNotification)
                    #endif

                    Surface(view: surfaceView, size: geo.size)
                        .focused($surfaceFocus)
                        .focusedValue(\.ghosttySurfaceTitle, surfaceView.title)
                        .focusedValue(\.ghosttySurfacePwd, surfaceView.pwd)
                        .focusedValue(\.ghosttySurfaceView, surfaceView)
                        .focusedValue(\.ghosttySurfaceCellSize, surfaceView.cellSize)
                    #if canImport(AppKit)
                        .backport.pointerStyle(surfaceView.pointerStyle)
                        .onReceive(pubBecomeKey) { notification in
                            guard let window = notification.object as? NSWindow else { return }
                            guard let surfaceWindow = surfaceView.window else { return }
                            windowFocus = surfaceWindow == window
                        }
                        .onReceive(pubResign) { notification in
                            guard let window = notification.object as? NSWindow else { return }
                            guard let surfaceWindow = surfaceView.window else { return }
                            if (surfaceWindow == window) {
                                windowFocus = false
                            }
                        }
                    #endif

                    // If our geo size changed then we show the resize overlay as configured.
                    if let surfaceSize = surfaceView.surfaceSize {
                        SurfaceResizeOverlay(
                            geoSize: geo.size,
                            size: surfaceSize,
                            overlay: ghostty.config.resizeOverlay,
                            position: ghostty.config.resizeOverlayPosition,
                            duration: ghostty.config.resizeOverlayDuration,
                            focusInstant: surfaceView.focusInstant)

                    }
                }
                .ghosttySurfaceView(surfaceView)

#if canImport(AppKit)
                // If we are in the middle of a key sequence, then we show a visual element. We only
                // support this on macOS currently although in theory we can support mobile with keyboards!
                if !surfaceView.keySequence.isEmpty {
                    let padding: CGFloat = 5
                    VStack {
                        Spacer()

                        HStack {
                            Text(verbatim: "Pending Key Sequence:")
                            ForEach(0..<surfaceView.keySequence.count, id: \.description) { index in
                                let key = surfaceView.keySequence[index]
                                Text(verbatim: key.description)
                                    .font(.system(.body, design: .monospaced))
                                    .padding(3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(Color(NSColor.selectedTextBackgroundColor))
                                    )
                            }
                        }
                        .padding(.init(top: padding, leading: padding, bottom: padding, trailing: padding))
                        .frame(maxWidth: .infinity)
                        .background(.background)
                    }
                }
#endif

                // If we have a URL from hovering a link, we show that.
                if let url = surfaceView.hoverUrl {
                    let padding: CGFloat = 5
                    let cornerRadius: CGFloat = 9
                    ZStack {
                        HStack {
                            Spacer()
                            VStack(alignment: .leading) {
                                Spacer()

                                Text(verbatim: url)
                                    .padding(.init(top: padding, leading: padding, bottom: padding, trailing: padding))
                                    .background(
                                        UnevenRoundedRectangle(cornerRadii: .init(topLeading: cornerRadius))
                                            .fill(.background)
                                    )
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .opacity(isHoveringURLLeft ? 1 : 0)
                            }
                        }

                        HStack {
                            VStack(alignment: .leading) {
                                Spacer()

                                Text(verbatim: url)
                                    .padding(.init(top: padding, leading: padding, bottom: padding, trailing: padding))
                                    .background(
                                        UnevenRoundedRectangle(cornerRadii: .init(topTrailing: cornerRadius))
                                            .fill(.background)
                                    )
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .opacity(isHoveringURLLeft ? 0 : 1)
                                    .onHover(perform: { hovering in
                                        isHoveringURLLeft = hovering
                                    })
                            }
                            Spacer()
                        }
                    }
                }

                #if canImport(AppKit)
                // If we have secure input enabled and we're the focused surface and window
                // then we want to show the secure input overlay.
                if (ghostty.config.secureInputIndication &&
                    secureInput.enabled &&
                    surfaceFocus &&
                    windowFocus) {
                    SecureInputOverlay()
                }
                #endif

                // If our surface is not healthy, then we render an error view over it.
                if (!surfaceView.healthy) {
                    Rectangle().fill(ghostty.config.backgroundColor)
                    SurfaceRendererUnhealthyView()
                } else if (surfaceView.error != nil) {
                    Rectangle().fill(ghostty.config.backgroundColor)
                    SurfaceErrorView()
                }

                // If we're part of a split view and don't have focus, we put a semi-transparent
                // rectangle above our view to make it look unfocused. We use "surfaceFocus"
                // because we want to keep our focused surface dark even if we don't have window
                // focus.
                if (isSplit && !surfaceFocus) {
                    let overlayOpacity = ghostty.config.unfocusedSplitOpacity;
                    if (overlayOpacity > 0) {
                        Rectangle()
                            .fill(ghostty.config.unfocusedSplitFill)
                            .allowsHitTesting(false)
                            .opacity(overlayOpacity)
                    }
                }
            }
        }
    }

    struct SurfaceRendererUnhealthyView: View {
        var body: some View {
            HStack {
                Image("AppIconImage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 128, height: 128)

                VStack(alignment: .leading) {
                    Text("Oh, no. 😭").font(.title)
                    Text("""
                        The renderer has failed. This is usually due to exhausting
                        available GPU memory. Please free up available resources.
                        """.replacingOccurrences(of: "\n", with: " ")
                    )
                    .frame(maxWidth: 350)
                }
            }
            .padding()
        }
    }

    struct SurfaceErrorView: View {
        var body: some View {
            HStack {
                Image("AppIconImage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 128, height: 128)

                VStack(alignment: .leading) {
                    Text("Oh, no. 😭").font(.title)
                    Text("""
                        The terminal failed to initialize. Please check the logs for
                        more information. This is usually a bug.
                        """.replacingOccurrences(of: "\n", with: " ")
                    )
                    .frame(maxWidth: 350)
                }
            }
            .padding()
        }
    }

    // This is the resize overlay that shows on top of a surface to show the current
    // size during a resize operation.
    struct SurfaceResizeOverlay: View {
        let geoSize: CGSize
        let size: ghostty_surface_size_s
        let overlay: Ghostty.Config.ResizeOverlay
        let position: Ghostty.Config.ResizeOverlayPosition
        let duration: UInt
        let focusInstant: ContinuousClock.Instant?

        // This is the last size that we processed. This is how we handle our
        // timer state.
        @State var lastSize: CGSize? = nil

        // Ready is set to true after a short delay. This avoids some of the
        // challenges of initial view sizing from SwiftUI.
        @State var ready: Bool = false

        // Fixed value set based on personal taste.
        private let padding: CGFloat = 5

        // This computed boolean is set to true when the overlay should be hidden.
        private var hidden: Bool {
            // If we aren't ready yet then we wait...
            if (!ready) { return true; }

            // Hidden if we already processed this size.
            if (lastSize == geoSize) { return true; }

            // If we were focused recently we hide it as well. This avoids showing
            // the resize overlay when SwiftUI is lazily resizing.
            if let instant = focusInstant {
                let d = instant.duration(to: ContinuousClock.now)
                if (d < .milliseconds(500)) {
                    // Avoid this size completely.
                    lastSize = geoSize
                    return true;
                }
            }

            // Hidden depending on overlay config
            switch (overlay) {
            case .never: return true;
            case .always: return false;
            case .after_first: return lastSize == nil;
            }
        }

        var body: some View {
            VStack {
                if (!position.top()) {
                    Spacer()
                }

                HStack {
                    if (!position.left()) {
                        Spacer()
                    }

                    Text(verbatim: "\(size.columns)c ⨯ \(size.rows)r")
                        .padding(.init(top: padding, leading: padding, bottom: padding, trailing: padding))
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.background)
                                .shadow(radius: 3)
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if (!position.right()) {
                        Spacer()
                    }
                }

                if (!position.bottom()) {
                    Spacer()
                }
            }
            .allowsHitTesting(false)
            .opacity(hidden ? 0 : 1)
            .task {
                // Sleep chosen arbitrarily... a better long term solution would be to detect
                // when the size stabilizes (coalesce a value) for the first time and then after
                // that show the resize overlay consistently.
                try? await Task.sleep(nanoseconds: 500 * 1_000_000)
                ready = true
            }
            .task(id: geoSize) {
                // By ID-ing the task on the geoSize, we get the task to restart if our
                // geoSize changes. This also ensures that future resize overlays are shown
                // properly.

                // We only sleep if we're ready. If we're not ready then we want to set
                // our last size right away to avoid a flash.
                if (ready) {
                    try? await Task.sleep(nanoseconds: UInt64(duration) * 1_000_000)
                }

                lastSize = geoSize
            }
        }
    }

    /// A surface is terminology in Ghostty for a terminal surface, or a place where a terminal is actually drawn
    /// and interacted with. The word "surface" is used because a surface may represent a window, a tab,
    /// a split, a small preview pane, etc. It is ANYTHING that has a terminal drawn to it.
    ///
    /// We just wrap an AppKit NSView here at the moment so that we can behave as low level as possible
    /// since that is what the Metal renderer in Ghostty expects. In the future, it may make more sense to
    /// wrap an MTKView and use that, but for legacy reasons we didn't do that to begin with.
    struct Surface: OSViewRepresentable {
        /// The view to render for the terminal surface.
        let view: SurfaceView

        /// The size of the frame containing this view. We use this to update the the underlying
        /// surface. This does not actually SET the size of our frame, this only sets the size
        /// of our Metal surface for drawing.
        ///
        /// Note: we do NOT use the NSView.resize function because SwiftUI on macOS 12
        /// does not call this callback (macOS 13+ does).
        ///
        /// The best approach is to wrap this view in a GeometryReader and pass in the geo.size.
        let size: CGSize

        func makeOSView(context: Context) -> SurfaceView {
            // We need the view as part of the state to be created previously because
            // the view is sent to the Ghostty API so that it can manipulate it
            // directly since we draw on a render thread.
            return view;
        }

        func updateOSView(_ view: SurfaceView, context: Context) {
            view.sizeDidChange(size)
        }
    }

    /// The configuration for a surface. For any configuration not set, defaults will be chosen from
    /// libghostty, usually from the Ghostty configuration.
    struct SurfaceConfiguration {
        /// Explicit font size to use in points
        var fontSize: Float32? = nil

        /// Explicit working directory to set
        var workingDirectory: String? = nil

        /// Explicit command to set
        var command: String? = nil

        init() {}

        init(from config: ghostty_surface_config_s) {
            self.fontSize = config.font_size
            self.workingDirectory = String.init(cString: config.working_directory, encoding: .utf8)
            self.command = String.init(cString: config.command, encoding: .utf8)
        }

        /// Returns the ghostty configuration for this surface configuration struct. The memory
        /// in the returned struct is only valid as long as this struct is retained.
        func ghosttyConfig(view: SurfaceView) -> ghostty_surface_config_s {
            var config = ghostty_surface_config_new()
            config.userdata = Unmanaged.passUnretained(view).toOpaque()
            #if os(macOS)
            config.platform_tag = GHOSTTY_PLATFORM_MACOS
            config.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
                nsview: Unmanaged.passUnretained(view).toOpaque()
            ))
            config.scale_factor = NSScreen.main!.backingScaleFactor

            #elseif os(iOS)
            config.platform_tag = GHOSTTY_PLATFORM_IOS
            config.platform = ghostty_platform_u(ios: ghostty_platform_ios_s(
                uiview: Unmanaged.passUnretained(view).toOpaque()
            ))
            // Note that UIScreen.main is deprecated and we're supposed to get the
            // screen through the view hierarchy instead. This means that we should
            // probably set this to some default, then modify the scale factor through
            // libghostty APIs when a UIView is attached to a window/scene. TODO.
            config.scale_factor = UIScreen.main.scale
            #else
            #error("unsupported target")
            #endif

            if let fontSize = fontSize { config.font_size = fontSize }
            if let workingDirectory = workingDirectory {
                config.working_directory = (workingDirectory as NSString).utf8String
            }
            if let command = command {
                config.command = (command as NSString).utf8String
            }

            return config
        }
    }
}

// MARK: Surface Environment Keys

private struct GhosttySurfaceViewKey: EnvironmentKey {
    static let defaultValue: Ghostty.SurfaceView? = nil
}

extension EnvironmentValues {
    var ghosttySurfaceView: Ghostty.SurfaceView? {
        get { self[GhosttySurfaceViewKey.self] }
        set { self[GhosttySurfaceViewKey.self] = newValue }
    }
}

extension View {
    func ghosttySurfaceView(_ surfaceView: Ghostty.SurfaceView?) -> some View {
        environment(\.ghosttySurfaceView, surfaceView)
    }
}

// MARK: Surface Focus Keys

extension FocusedValues {
    var ghosttySurfaceView: Ghostty.SurfaceView? {
        get { self[FocusedGhosttySurface.self] }
        set { self[FocusedGhosttySurface.self] = newValue }
    }

    struct FocusedGhosttySurface: FocusedValueKey {
        typealias Value = Ghostty.SurfaceView
    }

    var ghosttySurfaceTitle: String? {
        get { self[FocusedGhosttySurfaceTitle.self] }
        set { self[FocusedGhosttySurfaceTitle.self] = newValue }
    }

    struct FocusedGhosttySurfaceTitle: FocusedValueKey {
        typealias Value = String
    }

    var ghosttySurfacePwd: String? {
        get { self[FocusedGhosttySurfacePwd.self] }
        set { self[FocusedGhosttySurfacePwd.self] = newValue }
    }

    struct FocusedGhosttySurfacePwd: FocusedValueKey {
        typealias Value = String
    }

    var ghosttySurfaceZoomed: Bool? {
        get { self[FocusedGhosttySurfaceZoomed.self] }
        set { self[FocusedGhosttySurfaceZoomed.self] = newValue }
    }

    struct FocusedGhosttySurfaceZoomed: FocusedValueKey {
        typealias Value = Bool
    }

    var ghosttySurfaceCellSize: OSSize? {
        get { self[FocusedGhosttySurfaceCellSize.self] }
        set { self[FocusedGhosttySurfaceCellSize.self] = newValue }
    }

    struct FocusedGhosttySurfaceCellSize: FocusedValueKey {
        typealias Value = OSSize
    }
}
