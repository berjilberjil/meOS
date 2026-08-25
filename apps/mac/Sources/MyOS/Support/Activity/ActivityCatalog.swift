import Foundation

/// What an app *is*.
///
/// Three passes, most specific first: a rule Berjil set, then an exact bundle
/// identifier, then a loose match on the app's name. The name pass exists
/// because bundle ids are not knowable for every app on every platform — an
/// iPhone automation reports "WhatsApp", not `net.whatsapp.WhatsApp` — and a
/// session classified as "other" is a session the intelligence layer cannot say
/// anything useful about.
///
/// Productivity is stored per seed rather than taken from the category, because
/// the two genuinely diverge: a browser is research by category but neutral in
/// worth, and music is entertainment by category but not a distraction while
/// you work.
enum ActivityCatalog {

    struct Seed {
        /// Exact bundle identifiers.
        var ids: [String] = []
        /// Lowercased substrings matched against the app's name.
        var names: [String] = []
        var category: ActivityCategory
        var productivity: ProductivityType
    }

    static let seeds: [Seed] = [
        // — Development
        Seed(ids: ["com.microsoft.VSCode", "com.apple.dt.Xcode", "com.todesktop.230313mzl4w4u92",
                   "com.googlecode.iterm2", "com.apple.Terminal", "dev.warp.Warp-Stable",
                   "com.jetbrains.intellij", "com.sublimetext.4", "com.github.GitHubClient"],
             names: ["vs code", "visual studio", "xcode", "cursor", "terminal", "iterm", "warp",
                     "supacode", "claude code", "ghostty", "nova", "zed", "sublime", "github", "tower"],
             category: .development, productivity: .productive),

        // — Content creation
        Seed(ids: ["com.lemon.lvoverseas", "com.bytedance.capcut", "com.apple.FinalCut",
                   "com.adobe.PremierePro", "com.adobe.AfterEffects", "com.blackmagic-design.DaVinciResolve"],
             names: ["capcut", "final cut", "premiere", "after effects", "davinci", "resolve",
                     "screenflow", "descript", "obs"],
             category: .contentCreation, productivity: .productive),

        // — Design
        Seed(ids: ["com.figma.Desktop", "com.canva.CanvaDesktop", "com.bohemiancoding.sketch3",
                   "com.adobe.Photoshop", "com.adobe.illustrator"],
             names: ["figma", "canva", "sketch", "photoshop", "illustrator", "affinity", "pixelmator"],
             category: .design, productivity: .productive),

        // — Writing / notes
        Seed(ids: ["notion.id", "md.obsidian", "com.apple.Notes", "com.apple.iWork.Pages",
                   "com.literatureandlatte.scrivener3"],
             names: ["notion", "obsidian", "bear", "ulysses", "scrivener", "pages", "docs", "myos"],
             category: .writing, productivity: .productive),

        // — Communication. Neutral by default: Slack at 10am is work and Slack
        //   at 11pm is not, and that is a question the rules engine answers from
        //   *when* and *how long*, not one the catalogue can answer from *what*.
        Seed(ids: ["com.tinyspeck.slackmacgap", "net.whatsapp.WhatsApp", "com.apple.MobileSMS",
                   "com.apple.mail", "com.readdle.smartemail-Mac", "com.hnc.Discord",
                   "ru.keepcoder.Telegram", "us.zoom.xos", "com.microsoft.teams2",
                   "com.google.Chrome.app.kjbdgfilnfhdoflbpgamdcdgpehopbep"],
             names: ["slack", "whatsapp", "messages", "mail", "spark", "superhuman", "discord",
                     "telegram", "zoom", "teams", "meet", "facetime"],
             category: .communication, productivity: .neutral),

        // — Browsers and assistants. Research by shape, neutral in worth: MyOS
        //   cannot see the tab, so calling a browser productive would be a guess
        //   dressed up as a measurement.
        Seed(ids: ["com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser",
                   "org.mozilla.firefox", "com.microsoft.edgemac", "com.brave.Browser",
                   "com.openai.chat", "com.anthropic.claudefordesktop", "com.perplexity.app"],
             names: ["chrome", "safari", "arc", "firefox", "edge", "brave", "chatgpt", "claude",
                     "perplexity", "stack overflow"],
             category: .research, productivity: .neutral),

        // — Reading
        Seed(ids: ["com.apple.iBooksX", "com.readwise.reader", "com.apple.news"],
             names: ["books", "kindle", "readwise", "instapaper", "pocket", "news"],
             category: .reading, productivity: .neutral),

        // — Finance
        Seed(ids: ["com.zerodha.kite", "in.fold.app"],
             names: ["fold", "zerodha", "kite", "groww", "coin", "banking", "numbers", "excel", "sheets"],
             category: .finance, productivity: .productive),

        // — Health
        Seed(ids: ["com.apple.Health", "com.apple.Fitness"],
             names: ["health", "fitness", "strava", "whoop", "hevy"],
             category: .health, productivity: .neutral),

        // — Utility. Neutral, and short by nature: the rules engine flags a long
        //   utility session rather than the catalogue pre-judging it.
        Seed(ids: ["com.apple.finder", "com.apple.systempreferences", "com.apple.Preview",
                   "com.apple.ActivityMonitor", "com.apple.calculator", "com.apple.iCal",
                   "com.apple.Photos", "com.apple.reminders", "com.1password.1password"],
             names: ["finder", "settings", "system preferences", "preview", "activity monitor",
                     "calculator", "calendar", "photos", "reminders", "1password", "files"],
             category: .utility, productivity: .neutral),

        // — Social
        Seed(ids: ["com.burbn.instagram", "com.atebits.Tweetie2", "com.reddit.Reddit",
                   "com.zhiliaoapp.musically", "com.linkedin.LinkedIn", "com.facebook.Facebook"],
             names: ["instagram", "twitter", " x ", "reddit", "tiktok", "linkedin", "facebook",
                     "threads", "snapchat"],
             category: .social, productivity: .distracting),

        // — Entertainment. Music is the exception and is carved out below.
        Seed(ids: ["com.google.ios.youtube", "com.apple.TV", "com.netflix.Netflix",
                   "com.amazon.aiv.AIVApp", "com.hotstar.hotstar", "com.valvesoftware.steam"],
             names: ["youtube", "netflix", "prime video", "hotstar", "disney", "twitch", "steam"],
             category: .entertainment, productivity: .distracting),

        // — Music, deliberately last so it beats nothing above it and is not
        //   swept up by "entertainment". Music while working is not a leak.
        Seed(ids: ["com.spotify.client", "com.apple.Music"],
             names: ["spotify", "apple music", "soundcloud"],
             category: .entertainment, productivity: .neutral),
    ]

    /// Bundle id → seed, built once. The name pass stays linear; it only runs
    /// when the id misses.
    private static let byId: [String: Seed] = {
        var map: [String: Seed] = [:]
        for seed in seeds {
            for id in seed.ids where map[id] == nil { map[id] = seed }
        }
        return map
    }()

    /// Classify one app. `rules` are Berjil's own overrides and always win.
    static func classify(appId: String, appName: String,
                         rules: [String: AppRule] = [:]) -> (category: ActivityCategory, productivity: ProductivityType) {
        if let rule = rules[appId] { return (rule.category, rule.productivity) }
        if let seed = byId[appId] { return (seed.category, seed.productivity) }

        let name = " " + appName.lowercased() + " "
        for seed in seeds {
            for needle in seed.names where name.contains(needle) {
                return (seed.category, seed.productivity)
            }
        }
        return (.other, .neutral)
    }

    /// A stable id for an app that has no bundle identifier — an iPhone
    /// automation reports a display name and nothing else.
    static func slug(_ appName: String) -> String {
        let allowed = appName.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return "app." + String(allowed).split(separator: "-").joined(separator: "-")
    }
}
