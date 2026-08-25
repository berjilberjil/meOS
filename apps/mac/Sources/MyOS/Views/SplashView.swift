import SwiftUI

/// The logo's own green.
///
/// `logo.png` has no alpha — the green is baked into the file — so the mark
/// cannot simply be dropped on a black screen without its square showing. The
/// answer is to stop hiding the square: the mark is drawn as a rounded tile, the
/// way an app icon sits on a home screen, and the canvas behind it is the same
/// true black as the rest of MyOS. That keeps one background colour across the
/// whole app instead of two branded screens that are the exception.
enum Brandmark {
    /// Sampled from the logo file. The only place this exact green appears is
    /// inside the mark itself and on the controls that sit on top of it.
    static let green = Color(hex: 0x56BB06)
    /// Legible on that green — it is far too light to carry white text.
    static let ink = Color(hex: 0x0B0B0B)
    static let inkSoft = Color(hex: 0x1A1A1A)
}

/// Launch / lock canvas: the mark on its green, and whose OS this is. No lock
/// glyph, no "MyOS is locked" — Face ID runs underneath and this never says so.
///
/// It is both screens on purpose. Launch and unlock are the same moment from the
/// user's side, so they get the same face and only the words underneath change.
struct SplashView: View {
    var failed = false
    var retryTitle: String = "Try again"
    /// Real startup state, or nil. Never a fake progress line: when the cache is
    /// warm this stays empty and the splash is gone before it would have shown.
    var status: String? = nil
    var onRetry: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mark: Double = 0
    @State private var name: Double = 0

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                Image("LogoMark")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(width: 132, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .opacity(mark)
                    // Arrives from just under full size. Anything more than this
                    // reads as a bounce, and a logo should not bounce.
                    .scaleEffect(0.94 + 0.06 * mark)

                statusLine
                    .frame(height: 18)
                    .padding(.top, Space.xl)

                Spacer(minLength: 0)

                if failed, let onRetry {
                    Button(retryTitle, action: onRetry)
                        .buttonStyle(.bordered)
                        .padding(.bottom, 28)
                        .transition(.opacity)
                }

                Text("Berjil Jacob")
                    .font(.myCaption)
                    .foregroundStyle(Palette.faint)
                    .opacity(name)
                    .padding(.bottom, 34)
            }
            .padding(.horizontal, 32)
        }
        .onAppear { play() }
    }

    @ViewBuilder private var statusLine: some View {
        let text = failed ? "Face not recognised" : (status ?? "")
        Text(text)
            .font(.myBody)
            .foregroundStyle(failed ? Palette.warning : Palette.muted)
            .opacity(text.isEmpty ? 0 : name)
    }

    /// 0.10 the mark · 0.45 the name. Everything has landed by 0.8s, and none of
    /// it gates the app: RootView swaps this out the moment bootstrap finishes,
    /// mid-animation if that is when it happens.
    private func play() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(SplashTimeline.mark * 1_000_000_000))
            #if os(macOS)
            // iOS voices the launch from RootView's scene phase; doing it here
            // too would double it up.
            SoundPlayer.drop()
            #endif
        }

        guard !reduceMotion else { mark = 1; name = 1; return }
        withAnimation(.easeOut(duration: SplashTimeline.markDuration).delay(SplashTimeline.mark)) { mark = 1 }
        withAnimation(.easeOut(duration: SplashTimeline.fade).delay(SplashTimeline.name)) { name = 1 }
    }
}

/// When each beat of the launch lands. Kept out of the view so the one promise
/// that matters — the splash is never what makes the app feel slow — is a thing
/// tests can hold us to.
enum SplashTimeline {
    /// The mark arrives.
    static let mark = 0.10
    static let markDuration = 0.40
    /// Whose OS this is.
    static let name = 0.45
    static let fade = 0.35

    /// Everything has landed by here.
    static var settled: Double { name + fade }
}

/// A black pill on the branded green screens, where the app's own button tokens
/// are tuned for a dark background and read as invisible.
struct KDarkPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 26).padding(.vertical, 13)
            .background(Brandmark.ink.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.knFast, value: configuration.isPressed)
    }
}
