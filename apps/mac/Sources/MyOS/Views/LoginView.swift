import SwiftUI

/// The way in. The mark sits on its own green, and everything you actually
/// operate sits on black on top of it — so the eye goes to the two fields and
/// the button, not to the branding.
struct LoginView: View {
    @EnvironmentObject var state: AppState
    @State private var username = ""
    @State private var password = ""
    @State private var isRegister = false
    @FocusState private var focus: Field?

    private enum Field { case username, password }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            // The block is centred in the window and the name sits on the floor.
            // `minHeight` tied to the viewport is what makes the spacers push:
            // inside a scroll view, content otherwise collapses to its own height
            // and stacks at the top. It still scrolls when the viewport is too
            // short for all of it — a small phone with the keyboard up.
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 24)

                        // The mark has its green baked in, so on the black
                        // canvas it is drawn as a tile rather than bled to the
                        // edges. See `Brandmark`.
                        Image("LogoMark")
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(1, contentMode: .fit)
                            .frame(width: 108, height: 108)
                            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                        wordmark.padding(.top, 4)
                        form.padding(.top, 18)

                        Spacer(minLength: 24)

                        Text("Berjil Jacob")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.faint)
                            .padding(.bottom, 30)
                    }
                    .frame(maxWidth: 420)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .onSubmit { Task { await submit() } }
    }

    /// Name and promise. Palette tokens, not hardcoded white — light mode
    /// is a white canvas, and white type on it is invisible.
    private var wordmark: some View {
        VStack(spacing: 3) {
            Text("MyOS")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Palette.text)
            Text("Your second brain. Money · Body · Mind.")
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 26).padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }

    private var form: some View {
        VStack(spacing: 12) {
            field("Username", text: $username, field: .username)
            secureField("Password", text: $password)

            if let err = state.authError {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(Palette.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button { Task { await submit() } } label: {
                HStack(spacing: 8) {
                    if state.isWorking { ProgressView().controlSize(.small).tint(Brandmark.ink) }
                    Text(isRegister ? "CREATE ACCOUNT" : "LOG IN")
                        .font(.subheadline.weight(.heavy))
                        .tracking(0.6)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(Brandmark.ink)
                .background(Palette.action, in: Capsule())
            }
            .buttonStyle(.plain)
            .fluidPressable()
            .disabled(state.isWorking)
            .padding(.top, 4)

            Button {
                withAnimation(.knFast) { isRegister.toggle(); state.authError = nil }
            } label: {
                Text(isRegister ? "Have an account? Log in" : "New here? Create your account")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.muted)
            }
            .buttonStyle(.plain)
            .fluidPressable(scale: 0.99)
            .padding(.top, 2)
        }
        .padding(.horizontal, 4)
    }

    private func submit() async {
        let u = username.trimmingCharacters(in: .whitespaces).lowercased()
        guard u.count >= 3 else { state.authError = "Username must be at least 3 characters."; return }
        // Matches the server, and the vault passphrase minimum two screens later.
        guard password.count >= 8 else { state.authError = "Password must be at least 8 characters."; return }
        if isRegister { await state.register(username: u, password: password) }
        else { await state.login(username: u, password: password) }
    }

    // The login fields sit directly on the canvas rather than inside a card, so
    // they take the elevated surface and a hairline — a near-black pill on a
    // black screen would be invisible.
    private func field(_ placeholder: String, text: Binding<String>, field: Field) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundColor(Palette.faint))
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .foregroundStyle(Palette.text)
            .focused($focus, equals: field)
            .modifier(BrandField(focused: focus == field))
    }

    private func secureField(_ placeholder: String, text: Binding<String>) -> some View {
        SecureField("", text: text, prompt: Text(placeholder).foregroundColor(Palette.faint))
            .textFieldStyle(.plain)
            .foregroundStyle(Palette.text)
            .focused($focus, equals: .password)
            .modifier(BrandField(focused: focus == .password))
    }
}

private struct BrandField: ViewModifier {
    var focused: Bool

    func body(content: Content) -> some View {
        content
            .font(.callout)
            .padding(.horizontal, 18).padding(.vertical, 14)
            .background(Palette.surfaceElevated, in: Capsule())
            .overlay(
                Capsule().strokeBorder(focused ? Palette.action : Palette.border,
                                       lineWidth: focused ? 2 : 1)
            )
            .animation(.knFast, value: focused)
    }
}
