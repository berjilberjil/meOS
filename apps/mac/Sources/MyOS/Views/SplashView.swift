import SwiftUI

/// Launch / lock canvas: Catherine coming online. Black, a point of green, the
/// form it opens into, her name. No lock glyph, no "MyOS is locked" — Face ID
/// runs underneath and this screen never says so.
///
/// It is both screens on purpose. Launch and unlock are the same moment from the
/// user's side — the system becoming ready — so they get the same face, and only
/// the words underneath change.
struct SplashView: View {
    var failed = false
    var retryTitle: String = "Try again"
    /// Real startup state, or nil. Never a fake progress line: when the cache is
    /// warm this stays empty and the splash is gone before it would have shown.
    var status: String? = nil
    var onRetry: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal: Double = 0
    @State private var breathing = false
    @State private var word: Double = 0
    @State private var line: Double = 0

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                CatherinePresence(reveal: reveal, breathing: breathing)

                Text("Catherine")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(Palette.text.opacity(0.86))
                    .opacity(word)
                    .offset(y: (1 - word) * 6)
                    .padding(.top, 22)

                // Fixed height: the line arriving must not shove the name upward.
                statusLine
                    .frame(height: 16)
                    .padding(.top, 10)

                Spacer(minLength: 0)

                if failed, let onRetry {
                    Button(retryTitle, action: onRetry)
                        .buttonStyle(KPrimaryButtonStyle())
                        .padding(.bottom, 44)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 32)
        }
        .onAppear { play() }
    }

    @ViewBuilder private var statusLine: some View {
        let text = failed ? "Face not recognised" : (status ?? "")
        Text(text)
            .font(.system(size: 12, weight: .regular, design: .rounded))
            .tracking(0.2)
            .foregroundStyle(failed ? Palette.faint : Palette.faint.opacity(0.8))
            .opacity(text.isEmpty ? 0 : line)
    }

    /// 0.20 a point · 0.32 it opens · 0.72 it breathes · 0.80 her name.
    /// Everything has landed by ~1.35s, and none of it gates the app: RootView
    /// swaps this out the moment bootstrap finishes, mid-animation if that is
    /// when it happens.
    private func play() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(SplashTimeline.point * 1_000_000_000))
            #if os(macOS)
            // iOS voices the launch from RootView's scene phase; doing it here too
            // would double it up.
            SoundPlayer.drop()
            #endif
        }

        guard !reduceMotion else {
            reveal = 1; word = 1; line = 1; breathing = false
            return
        }

        withAnimation(.easeOut(duration: 0.14).delay(SplashTimeline.point)) { reveal = 0.10 }
        withAnimation(.easeOut(duration: SplashTimeline.formDuration).delay(SplashTimeline.form)) { reveal = 1 }
        withAnimation(.easeOut(duration: SplashTimeline.fade).delay(SplashTimeline.word)) { word = 1 }
        withAnimation(.easeOut(duration: SplashTimeline.fade).delay(SplashTimeline.status)) { line = 1 }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(SplashTimeline.breathe * 1_000_000_000))
            breathing = true
        }
    }
}
