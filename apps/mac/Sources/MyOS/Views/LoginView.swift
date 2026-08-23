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
            Brandmark.green.ignoresSafeArea()

            // The block is centred in the window and the name sits on the floor.
            // `minHeight` tied to the viewport is what makes the spacers push:
            // inside a scroll view, content otherwise collapses to its own height
            // and stacks at the top. It still scrolls when the viewport is too
            // short for all of it — a small phone with the keyboard up.
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 24)

                        Image("LogoMark")
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: 190)

                        wordmark.padding(.top, 4)
                        form.padding(.top, 18)

                        Spacer(minLength: 24)

                        Text("Berjil Jacob")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.95))
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

    /// Name and promise, on black — the one place the green stops.
    private var wordmark: some View {
        VStack(spacing: 3) {
            Text("MyOS")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Your second brain. Money · Body · Mind.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
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
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button { Task { await submit() } } label: {
                HStack(spacing: 8) {
                    if state.isWorking { ProgressView().controlSize(.small).tint(Brandmark.ink) }
                    Text(isRegister ? "CREATE ACCOUNT" : "LOG IN")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .tracking(0.6)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(Brandmark.ink)
                .background(
                    LinearGradient(colors: [Color(hex: 0x7BE07B), Color(hex: 0x4FCB6B)],
                                   startPoint: .leading, endPoint: .trailing),
                    in: Capsule()
                )
            }
            .buttonStyle(KPressStyle())
            .disabled(state.isWorking)
            .padding(.top, 4)

            Button {
                withAnimation(.knFast) { isRegister.toggle(); state.authError = nil }
            } label: {
                Text(isRegister ? "Have an account? Log in" : "New here? Create your account")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(KPressStyle())
            .padding(.top, 2)
        }
        .padding(.horizontal, 4)
    }

    private func submit() async {
        let u = username.trimmingCharacters(in: .whitespaces).lowercased()
        guard u.count >= 3 else { state.authError = "Username must be at least 3 characters."; return }
        guard password.count >= 4 else { state.authError = "Password must be at least 4 characters."; return }
        if isRegister { await state.register(username: u, password: password) }
        else { await state.login(username: u, password: password) }
    }

    // The app's own field chrome is tuned for a dark surface; on this card it
    // needs its own, darker still than the card it sits on.
    private func field(_ placeholder: String, text: Binding<String>, field: Field) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.42)))
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .foregroundStyle(.white)
            .focused($focus, equals: field)
            .modifier(BrandField(focused: focus == field))
    }

    private func secureField(_ placeholder: String, text: Binding<String>) -> some View {
        SecureField("", text: text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.42)))
            .textFieldStyle(.plain)
            .foregroundStyle(.white)
            .focused($focus, equals: .password)
            .modifier(BrandField(focused: focus == .password))
    }
}

private struct BrandField: ViewModifier {
    var focused: Bool

    func body(content: Content) -> some View {
        content
            .font(.system(size: 16, design: .rounded))
            .padding(.horizontal, 18).padding(.vertical, 14)
            .background(Brandmark.ink, in: Capsule())
            .overlay(
                Capsule().strokeBorder(focused ? .white.opacity(0.55) : .clear,
                                       lineWidth: 1.5)
            )
            .animation(.knFast, value: focused)
    }
}
