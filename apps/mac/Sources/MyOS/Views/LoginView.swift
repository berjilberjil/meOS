import SwiftUI

struct LoginView: View {
    @EnvironmentObject var state: AppState
    @State private var username = ""
    @State private var password = ""
    @State private var isRegister = false
    @FocusState private var focus: Field?

    private enum Field { case username, password }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Palette.brand)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: "command")
                            .font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                    )
                    .knShadow()
                VStack(spacing: 5) {
                    Text("MyOS")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Palette.text)
                    Text("Your second brain. Money · Body · Mind.")
                        .font(.system(size: 14)).foregroundStyle(Palette.muted)
                }
            }
            .padding(.bottom, 32)

            VStack(spacing: 12) {
                field("Username", text: $username, field: .username)
                secureField("Password", text: $password)

                if let err = state.authError {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                PrimaryButton(title: isRegister ? "Create account" : "Log in",
                              loading: state.isWorking) {
                    Task { await submit() }
                }
                .padding(.top, 4)

                Button {
                    withAnimation(.knFast) { isRegister.toggle(); state.authError = nil }
                } label: {
                    Text(isRegister ? "Have an account? Log in" : "New here? Create your account")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.muted)
                }
                .buttonStyle(KPressStyle())
                .padding(.top, 2)
            }
            .padding(24)
            .frame(width: 340)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(Palette.ring, lineWidth: 1)
            )
            .knShadow(true)

            Spacer(); Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg.ignoresSafeArea())
        .onSubmit { Task { await submit() } }
    }

    private func submit() async {
        let u = username.trimmingCharacters(in: .whitespaces).lowercased()
        guard u.count >= 3 else { state.authError = "Username must be at least 3 characters."; return }
        guard password.count >= 4 else { state.authError = "Password must be at least 4 characters."; return }
        if isRegister { await state.register(username: u, password: password) }
        else { await state.login(username: u, password: password) }
    }

    private func field(_ placeholder: String, text: Binding<String>, field: Field) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundColor(Palette.faint))
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .foregroundStyle(Palette.text)
            .focused($focus, equals: field)
            .knField(focused: focus == field)
    }

    private func secureField(_ placeholder: String, text: Binding<String>) -> some View {
        SecureField("", text: text, prompt: Text(placeholder).foregroundColor(Palette.faint))
            .textFieldStyle(.plain)
            .foregroundStyle(Palette.text)
            .focused($focus, equals: .password)
            .knField(focused: focus == .password)
    }
}
