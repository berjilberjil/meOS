import SwiftUI

// Three gates in front of anything that wipes data: hold the capsule, type the
// passphrase, type it again. One accidental click can't get past step one, and a
// borrowed unlocked device can't get past step two.

/// The three-step confirm. Shared by Mac and iPhone.
struct DangerConfirmSheet: View {
    let title: String
    var message: String = "This can't be undone."
    var confirmLabel: String = "Hold to continue"
    var actionLabel: String = "Delete forever"
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @EnvironmentObject private var state: AppState
    @State private var step = 0            // 0 hold · 1 passphrase · 2 repeat it
    @State private var pass = ""
    @State private var passAgain = ""
    @State private var error: String?
    @State private var checking = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(Palette.red.opacity(0.14))
                Image(systemName: step == 0 ? "trash.fill" : "lock.fill")
                    .font(.title2.weight(.semibold)).foregroundStyle(Palette.red)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 64, height: 64)
            .padding(.bottom, 14)

            Text(title)
                .font(.title3.weight(.semibold)).foregroundStyle(Palette.text)
                .multilineTextAlignment(.center)
            Text(stepMessage)
                .font(.footnote).foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            stepDots.padding(.top, 14).padding(.bottom, 18)

            Group {
                switch step {
                case 0: holdStep
                case 1: passStep
                default: repeatStep
                }
            }
            .frame(maxWidth: .infinity)

            if let error {
                Text(error).font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }

            Button("Cancel", action: onCancel)
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.muted)
                .padding(.top, 16)
        }
        .padding(.horizontal, 26)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background(Palette.bg)
        .animation(.knNormal, value: step)
    }

    private var stepMessage: String {
        switch step {
        case 0:  return message
        case 1:  return "Step 2 of 3 — type your MyOS passphrase to prove it's you."
        default: return "Step 3 of 3 — type it once more, then it's gone."
        }
    }

    private var stepDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Palette.red : Palette.border)
                    .frame(width: i == step ? 22 : 8, height: 6)
            }
        }
        .animation(.knFast, value: step)
    }

    private var holdStep: some View {
        HoldToConfirmButton(label: confirmLabel) {
            error = nil
            step = 1
            fieldFocused = true
        }
    }

    private var passStep: some View {
        VStack(spacing: 12) {
            SecureField("", text: $pass, prompt: Text("Your passphrase").foregroundColor(Palette.faint))
                .textFieldStyle(.plain).foregroundStyle(Palette.text)
                .focused($fieldFocused)
                .onSubmit { Task { await checkPass() } }
                .knField(focused: fieldFocused)
            Button { Task { await checkPass() } } label: {
                HStack(spacing: 8) {
                    if checking { ProgressView().controlSize(.small) }
                    Text(checking ? "Checking…" : "Continue")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(KSecondaryButtonStyle(fullWidth: true))
            .disabled(pass.isEmpty || checking)
            .opacity(pass.isEmpty || checking ? 0.55 : 1)
        }
    }

    private var repeatStep: some View {
        VStack(spacing: 12) {
            SecureField("", text: $passAgain, prompt: Text("Passphrase again").foregroundColor(Palette.faint))
                .textFieldStyle(.plain).foregroundStyle(Palette.text)
                .focused($fieldFocused)
                .onSubmit(finish)
                .knField(focused: fieldFocused)
            Button(action: finish) {
                HStack(spacing: 8) {
                    Image(systemName: "trash.fill").font(.footnote.weight(.bold))
                    Text(actionLabel)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(KPrimaryButtonStyle(tint: Palette.red, fullWidth: true))
            .disabled(passAgain.isEmpty)
            .opacity(passAgain.isEmpty ? 0.55 : 1)
        }
    }

    private func checkPass() async {
        guard !pass.isEmpty, !checking else { return }
        checking = true
        error = nil
        let ok = await state.verifyPassphrase(pass)
        checking = false
        if ok {
            step = 2
            passAgain = ""
            fieldFocused = true
        } else {
            error = "That's not your passphrase."
            Haptics.warning()
        }
    }

    private func finish() {
        // Step 2 already proved the passphrase; step 3 only has to match it, so a
        // slip of the fingers on the last gate can't wipe anything.
        guard passAgain == pass else {
            error = "The two don't match."
            Haptics.warning()
            return
        }
        Haptics.warning()
        onConfirm()
    }
}

extension View {
    /// Guard a wipe behind hold → passphrase → passphrase.
    func dangerConfirm(isPresented: Binding<Bool>, title: String,
                       message: String = "This can't be undone.",
                       confirmLabel: String = "Hold to continue",
                       actionLabel: String = "Delete forever",
                       action: @escaping () -> Void) -> some View {
        sheet(isPresented: isPresented) {
            let card = DangerConfirmSheet(
                title: title, message: message,
                confirmLabel: confirmLabel, actionLabel: actionLabel,
                onCancel: { isPresented.wrappedValue = false },
                onConfirm: {
                    action()
                    isPresented.wrappedValue = false
                })
            #if os(iOS)
            card.presentationDetents([.height(470)]).presentationDragIndicator(.visible)
            #else
            card.frame(width: 420)
            #endif
        }
    }
}

// MARK: - Data management (the reset rows, shared by both Settings screens)

/// Every wipe in MyOS lives here, behind `dangerConfirm`.
struct DataManagementCard: View {
    @EnvironmentObject var state: AppState
    var boxed = true

    var body: some View {
        if boxed {
            Card { inner }
        } else {
            inner
        }
    }

    private var inner: some View {
        VStack(alignment: .leading, spacing: 12) {
            if boxed { SectionTitle(text: "Data management") }
            Text("Three gates: hold to confirm, then your passphrase twice. Nothing here can be undone.")
                .font(.footnote).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)

            DangerResetRow(title: "Reset journal",
                           subtitle: "Every day's entries",
                           confirmTitle: "Reset the journal?",
                           confirmMessage: "Deletes all reflections, wins, mistakes, lessons and gratitude.",
                           actionLabel: "Reset journal") {
                state.resetJournal()
            }
            DangerResetRow(title: "Reset notes",
                           subtitle: "Every note",
                           confirmTitle: "Delete all notes?",
                           confirmMessage: "Deletes every note you've written.",
                           actionLabel: "Delete notes") {
                state.resetNotes()
            }
            DangerResetRow(title: "Reset fitness",
                           subtitle: "Logs + fitness profile",
                           confirmTitle: "Reset fitness data?",
                           confirmMessage: "Deletes every logged day and clears your fitness profile.",
                           actionLabel: "Reset fitness") {
                state.resetFitness()
            }
            Divider().overlay(Palette.border).padding(.vertical, 2)
            DangerResetRow(title: "Reset everything",
                           subtitle: "All data — keeps your profile & chips",
                           confirmTitle: "Reset ALL data?",
                           confirmMessage: "Wipes journal, notes, fitness and your day plans. Your profile identity and journal chips are kept.",
                           actionLabel: "Wipe everything",
                           emphatic: true) {
                state.resetEverything()
            }
        }
    }
}

/// A destructive reset row — label + a Reset button that opens the three-step gate.
struct DangerResetRow: View {
    let title: String
    let subtitle: String
    let confirmTitle: String
    let confirmMessage: String
    var actionLabel: String = "Delete forever"
    var tint: Color = Palette.red
    var emphatic: Bool = false
    let action: () -> Void
    @State private var show = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: emphatic ? .heavy : .semibold,
                                         design: emphatic ? .rounded : .default))
                    .foregroundStyle(emphatic ? tint : Palette.text)
                Text(subtitle).font(.footnote).foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button { show = true } label: {
                Label("Reset", systemImage: "trash")
            }
            .buttonStyle(KSoftButtonStyle(tint: tint))
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(emphatic ? tint.opacity(0.06) : Color.clear,
                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .dangerConfirm(isPresented: $show, title: confirmTitle, message: confirmMessage,
                       confirmLabel: "Hold to confirm", actionLabel: actionLabel) { action() }
    }
}
