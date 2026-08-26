import Foundation

/// What an app *is*.
///
/// Four passes, most specific first: a rule Berjil set, then the site, then an
/// exact bundle identifier, then a loose match on the app's name. The name pass
/// exists because a compacted day keeps only display names, and a session
/// classified as "other" is a session the intelligence layer cannot say
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

    /// What a *site* is.
    ///
    /// This is the pass that makes the browser legible. Without it every hour in
    /// Chrome is "research, neutral" — a shrug — because the catalogue is being
    /// asked what a window is worth when the only honest answer is that it
    /// depends entirely on the tab. Registrable domain, so `m.youtube.com` and
    /// `www.youtube.com` are one place.
    static let siteSeeds: [(hosts: [String], category: ActivityCategory, productivity: ProductivityType)] = [
        (["github.com", "gitlab.com", "stackoverflow.com", "developer.apple.com", "npmjs.com",
          "developers.cloudflare.com", "dash.cloudflare.com", "vercel.com", "netlify.com",
          "supabase.com", "swift.org", "developer.mozilla.org", "regex101.com"],
         .development, .productive),
        (["chatgpt.com", "openai.com", "claude.ai", "anthropic.com", "perplexity.ai",
          "gemini.google.com", "google.com", "duckduckgo.com", "wikipedia.org", "arxiv.org"],
         .research, .productive),
        (["figma.com", "canva.com", "dribbble.com", "behance.net", "unsplash.com"],
         .design, .productive),
        (["docs.google.com", "notion.so", "notion.site", "obsidian.md", "medium.com",
          "substack.com", "sheets.google.com"],
         .writing, .productive),
        (["mail.google.com", "gmail.com", "web.whatsapp.com", "slack.com", "teams.microsoft.com",
          "discord.com", "web.telegram.org", "outlook.com", "zoom.us", "meet.google.com"],
         .communication, .neutral),
        (["kite.zerodha.com", "zerodha.com", "groww.in", "fold.money", "coin.zerodha.com",
          "incometax.gov.in", "npci.org.in"],
         .finance, .productive),
        (["youtube.com", "netflix.com", "primevideo.com", "hotstar.com", "twitch.tv",
          "disneyplus.com", "jiocinema.com"],
         .entertainment, .distracting),
        (["instagram.com", "x.com", "twitter.com", "reddit.com", "tiktok.com", "linkedin.com",
          "facebook.com", "threads.net", "snapchat.com", "quora.com"],
         .social, .distracting),
        (["news.ycombinator.com", "bbc.com", "theverge.com", "nytimes.com", "readwise.io",
          "getpocket.com", "goodreads.com"],
         .reading, .neutral),
        (["amazon.in", "amazon.com", "flipkart.com", "myntra.com", "swiggy.com", "zomato.com",
          "blinkit.com", "zeptonow.com"],
         .other, .neutral),
        // Music is not a leak, on the web any more than on the desktop.
        (["open.spotify.com", "spotify.com", "music.apple.com", "soundcloud.com"],
         .entertainment, .neutral),
    ]

    private static let bySite: [String: (category: ActivityCategory, productivity: ProductivityType)] = {
        var map: [String: (ActivityCategory, ProductivityType)] = [:]
        for seed in siteSeeds {
            for host in seed.hosts where map[host] == nil { map[host] = (seed.category, seed.productivity) }
        }
        return map
    }()

    /// Classify one session. Most specific first: Berjil's own rule, then the
    /// site, then the app.
    ///
    /// A site beats the app it was opened in on purpose — "Chrome" is a room,
    /// not an activity, and calling two hours of it neutral because MyOS could
    /// not see the tab is exactly the shrug this is here to stop.
    static func classify(appId: String, appName: String, site: String? = nil,
                         rules: [String: AppRule] = [:]) -> (category: ActivityCategory, productivity: ProductivityType) {
        if let site {
            if let rule = rules["web." + site] { return (rule.category, rule.productivity) }
            if let seed = matchSite(site) { return seed }
            // A site MyOS has never heard of is still a site — it must not
            // inherit "research, neutral" from the browser it was opened in, or
            // every unknown domain would quietly read as work.
            return (.other, .neutral)
        }
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

    /// Exact host, then parent domain — `open.spotify.com` is Spotify and
    /// `gist.github.com` is GitHub without either needing its own row.
    static func matchSite(_ host: String) -> (category: ActivityCategory, productivity: ProductivityType)? {
        if let hit = bySite[host] { return hit }
        var parts = host.split(separator: ".")
        while parts.count > 2 {
            parts.removeFirst()
            if let hit = bySite[parts.joined(separator: ".")] { return hit }
        }
        return nil
    }

    /// A stable id for an app that has no bundle identifier, and for a rollup
    /// row that only kept a display name.
    static func slug(_ appName: String) -> String {
        let allowed = appName.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return "app." + String(allowed).split(separator: "-").joined(separator: "-")
    }
}
