import SwiftUI

/// "Where did that number come from?" — answered in one place, because a
/// dashboard you can't interrogate is a dashboard you shouldn't trust.
struct MacroMethodSheet: View {
    var regime: [MacroScore] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let content = ScrollView {
            VStack(alignment: .leading, spacing: Gap.screen) {
                header

                block("WHERE THE NUMBERS COME FROM") {
                    VStack(alignment: .leading, spacing: 10) {
                        badge(.verified, "Pulled from FRED's published series (St. Louis Fed). Real dates, real revisions — every change below is computed off the series itself, not asserted.")
                        badge(.estimated, "Read off the web by a search-grounded model, because nothing free publishes them: RBI repo, India CPI, the India 10Y, NIFTY, India VIX, gold and silver. Each carries the source it came from. Treat it as a reading, not a feed.")
                        badge(.unavailable, "No figure was found, or the date is before MyOS started taking snapshots. Nothing is substituted in.")
                    }
                }

                block("HOW CHANGES ARE WORKED OUT") {
                    VStack(alignment: .leading, spacing: 8) {
                        line("Rates move in basis points.", "6.50% → 6.59% is +9 bp. Calling it +1.38% would read like a market move rather than a policy one.")
                        line("Prices and indices move in percent.", "Against the previous observation — the previous trading day for a daily series, the previous month for a monthly one.")
                        line("Verified metrics reconstruct any date.", "The series has the history, so picking a past date recomputes rather than guesses.")
                        line("Estimated metrics only change once snapshotted twice.", "Their history is MyOS's own record. Until there are two days of it, the change shows as —.")
                    }
                }

                block("GOLD AND SILVER") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Spot is quoted in dollars per troy ounce. MyOS shows what you'd actually pay in:")
                            .font(.system(size: 13)).foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("₹/g  =  $/oz × USD/INR ÷ 31.1035")
                            .font(.system(size: 13, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Palette.brand)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.surface2, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                        Text("That is the metal only. A jeweller's rate adds making charges and GST, so expect their number to be higher.")
                            .font(.system(size: 12)).foregroundStyle(Palette.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                block("HOW THE REGIME SCORES ARE BUILT") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Each is 0–100, computed from named inputs and printed with them underneath so it can be argued with. They are an analytical reading by the OS, not financial advice.")
                            .font(.system(size: 13)).foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        formula("Global risk", "VIX scaled between 11 and 34. Above 25 reads as risk, above 17 as watch.")
                        formula("Rupee pressure", "Starts at 50, then USD/INR's 1-month move weighted 12× and the dollar index's weighted 6×. Rupee weakening pushes it up.")
                        formula("Inflation pressure", "US CPI year-on-year against a 6% ceiling, plus Brent's 1-month move weighted 1.5×.")
                        formula("Market stress", "Starts at 50, less the S&P's 1-month move weighted 3×, plus 25 if the 10Y–2Y spread is inverted.")
                        if !regime.isEmpty {
                            Divider().overlay(Palette.border)
                            ForEach(regime) { s in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(s.score)")
                                        .font(.system(size: 12, weight: .heavy, design: .rounded)).monospacedDigit()
                                        .foregroundStyle(s.tint).frame(width: 26, alignment: .trailing)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(s.label).font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Palette.text)
                                        Text(s.inputs.joined(separator: "  ·  "))
                                            .font(.system(size: 11)).foregroundStyle(Palette.faint)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Palette.bg)

        #if os(iOS)
        content.presentationDetents([.large]).presentationBackground(Palette.bg)
        #else
        content.frame(width: 520, height: 660)
        #endif
    }

    private var header: some View {
        HStack {
            Text("How this is worked out")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.text)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
            }
            .buttonStyle(KIconButtonStyle(size: 28))
        }
    }

    private func block<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.8)
                .foregroundStyle(Palette.faint)
            content()
        }
    }

    private func badge(_ q: MacroQuality, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(q.label.uppercased())
                .font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(0.5)
                .foregroundStyle(q.tint)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(q.tint.opacity(0.14), in: Capsule())
                .frame(width: 92, alignment: .leading)
            Text(text).font(.system(size: 12)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func line(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
            Text(body).font(.system(size: 12)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func formula(_ name: String, _ how: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.blue)
            Text(how).font(.system(size: 12)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
