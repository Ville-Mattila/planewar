# R3: Platform, store and legal requirements

- Status: research input for the planning phase. Written 2026-10-09.
- Scope: Apple App Store, Google Play, Steam, browser portals, cross-platform play, EU/UK/US law.
- Not legal advice. Check the cited primary text before acting.

Legend used throughout:

- **[P]** primary page read in this pass
- **[S]** secondary or third-party source only
- **[K]** general knowledge, not re-checked in this pass
- **[U]** sources conflict or the point is unresolved

## 0. Key findings

- Several rules are already in force (today is 2026-10-09): Apple requires the iOS 26 SDK since 28 Apr 2026 [P]; Google requires target API 36 for new uploads and updates since the 31 Aug 2026 deadline [P]; Apple's new age-rating questionnaire was due 31 Jan 2026 [P]; the amended US COPPA Rule compliance date was 22 Apr 2026 [S].
- Account deletion is mandatory on both mobile stores. The deletion pipeline must exist before login code is written.
- iOS builds need macOS with Xcode [P]. The Windows development machine cannot produce or sign an iOS build.
- Browser builds should use Godot's single-threaded web export [P]. Browsers cannot open raw UDP, so the server needs a WebSocket (WSS) transport for web clients [P, S].
- Steam's relay network (SDR) is partner-gated and cost-unclear [P]. Our internet multiplayer needs its own matchmaking and relay.
- Avoid randomised paid loot boxes in v1. Belgium treats them as gambling and several EU states are tightening rules for minors [S].
- "Triplane Turmoil" is a trademark and code question. Its source and assets have been GPLv3 since 2009 [P, Wikipedia]. Do not use the name or copy code or assets.

## 1. Apple App Store

| Topic | Requirement | Architecture impact |
|---|---|---|
| Account deletion, guideline 5.1.1(v) | "if your app supports account creation, you must also offer account deletion within the app" [P]. Apple's help page says temporary deactivation does not satisfy the rule and deletion should sit in account settings [P, S for forum quotes]. Apps outside regulated sectors should not send users to a phone, email or chat flow [P]. | One server-side delete endpoint that purges the account and linked data, with a tested job. |
| Login services, guideline 4.8 | Third-party or social login (Google, Facebook and similar) requires an equivalent option that limits data to name and email, lets users hide their email, and collects no app-interaction data for advertising without consent [P, summary]. Sign in with Apple is the standard option [K]. | Auth design: email or passkey, plus Sign in with Apple on iOS if any social login ships. |
| In-app purchase, guidelines 3.1.1 and 3.1.3 | Digital goods must use IAP. Apps may not use their own unlock mechanisms [P]. Loot boxes must disclose item odds before purchase [P]. External purchase links are allowed for the US storefront only (3.1.3) [P]. | Store-agnostic entitlement service with server-side receipt validation. |
| Privacy nutrition labels | Declare data collected by us and by third-party SDKs. Required for submissions. A public privacy policy URL is required. Answers must stay accurate [P]. | Keep the SDK list short and audit each SDK's data collection. |
| App Tracking Transparency, guideline 5.1.2(i) | Explicit permission through ATT is required before tracking [P]. | v1 with no ad or cross-app tracking SDK means no ATT prompt. |
| Privacy manifest | Required-reason API declarations have been required since 1 May 2024, including third-party SDKs [P]. | Ship PrivacyInfo.xcprivacy with the export. Confirm Godot's iOS template includes it [U]. |
| User-generated content, guideline 1.2 | Filter objectionable content. Provide a report mechanism with timely responses. Let users block abusive users. Publish contact information [P]. | Chat moderation hooks are required on iOS from the first online build. |
| Age ratings | New 13+, 16+ and 18+ tiers replace 12+ and 17+. Questionnaire answers were due 31 Jan 2026 to keep updates shipping [P]. | Questionnaire answers belong in the product spec. Open chat with strangers affects the rating. |
| Build SDK | From 28 Apr 2026, uploads must use Xcode 26 or later with the iOS 26 SDK [P]. | CI image pinned to Xcode 26 or later. |
| Minimum OS | Apple's upload floor is "target iOS 13 or later" from 9 Sep 2026 [P]. | Our deployment target is a choice. Proposed planning assumption: iOS 16 minimum. Confirm against Godot's template. |
| macOS for iOS | Godot iOS export must run "from a computer running macOS with Xcode installed". The output is an Xcode project. A Team ID and bundle ID are required. The iOS simulator supports only the Compatibility renderer [P]. | A Mac or macOS CI runner is needed for iOS builds and signing. Feeds the renderer decision in section 7. |

Sources: [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/); [Apple 5.1.1 account deletion help](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion); [Apple upcoming requirements](https://developer.apple.com/news/upcoming-requirements/); [Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/); [Godot iOS export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html).

## 2. Google Play

- **Target API [P].** New apps and updates must target Android 16 (API 36). Google's page (last updated 1 Oct 2026) gives 31 Aug 2026 as the deadline, which has passed. Extension requests to 1 Nov 2026 are said to arrive in Play Console later this year. Apps below API 35 are limited to devices running their target version or lower for new users. A forum post gives 30 Aug [S]. Treat Google's page as authoritative. The next bump (API 37) is expected in 2027 [K].
- **Account deletion [P].** Apps that allow in-app account creation need an in-app deletion path (prominent, e.g. account settings) and a web deletion link. The web page must work without reinstalling the app and must name the developer as listed on Play. Deletion covers the account and its associated data. Retention exceptions for security, fraud or legal reasons must be disclosed. The Data safety form asks deletion questions and requires the web link [P].
- **Data safety form [K].** Declare collected data types, purposes, sharing, encryption in transit and deletion. The answers must match what the SDKs actually do.
- **Billing [P].** From 30 Jun 2026 in the US, UK and EEA, Google separates the service fee from the billing fee. The service fee is 10% on the first $1M of annual earnings and on auto-renewing subscriptions. The billing fee is 5% and applies only to transactions through Google Play Billing. Alternative billing and external web links avoid it. Rates for other transactions are in an image on the page and were not readable. Games Level Up rate cards become available 30 Sep 2026 [P]. Billing rules differ by market [U].
- **App bundle and size limits [P, conflicting].** Google's current page lists a base module limit of 500 MB, 1.5 GB per asset pack, 4 GB for install-time content, 30 GB for on-demand and fast-follow content, and 34 GB overall, all measured on compressed size. Older documentation cites a 200 MB base module [S]. Verify in Play Console before the first upload.
- **64-bit [P].** Apps with native code must include the 64-bit ABI for each 32-bit ABI they ship (arm64-v8a with armeabi-v7a, x86_64 with x86). Export arm64-v8a. Confirm which ABIs the Godot Android template ships [U].

Sources: [Google target API requirements](https://developer.android.com/google/play/requirements/target-sdk); [Google Play account deletion](https://support.google.com/googleplay/android-developer/answer/13327111); [Google billing and fee changes](https://developer.android.com/blog/posts/expanded-billing-choice-and-lower-fees-on-google-play); [Play size limits](https://support.google.com/googleplay/android-developer/answer/9859372); [Play 64-bit requirement](https://developer.android.com/google/play/requirements/64-bit).

## 3. Steam

- **Steam Direct fee [P].** $100 per app. Non-refundable, but recouped from the first payment after the product reaches $1,000 Adjusted Gross Revenue from Steam Store and in-app purchases. Only Admins on the partner account can pay. Third-party guides wrongly describe it as refunded [S].
- **Revenue share [S].** Third-party sources give 70/30 on the first $10M per game, 75/25 up to $50M and 80/20 above that. The official table was not retrieved [U].
- **Steam Deck Verified [P].** Requirements:
  - Default settings reach all content without enabling controller support.
  - Button glyphs follow the active input. Keyboard and mouse glyphs do not appear during controller use.
  - Text entry uses the Steamworks text-entry API (on-screen keyboard) or built-in controller entry.
  - Default config runs at 30 fps at 800p on Deck.
  - Native 1280x800 is preferred, or 1280x720.
  - Smallest on-screen text is never below 9 px at 1280x800. Valve recommends 12 px.
  - No warnings about unsupported Linux or hardware. Launchers must be controller-navigable.
  - Ratings: Verified, Playable, Unsupported, Unknown.
- **Steam Cloud [P].** The developer sets a per-user byte quota and file-count quota per game. One write is capped at 100 MB. Files of 256 MB or more may use a slower storage endpoint. Use smaller files, split by change frequency, and wrap writes in BeginFileWriteBatch and EndFileWriteBatch. Dynamic Cloud Sync covers Deck suspend and resume.
- **Steam Datagram Relay [P].** Requires contacting Valve for the SDKs and terms. The game must ship on Steam, have a matchmaking service that issues credentials, and accept that "we cannot promise that this service will always be available to non-Steam players". The cost is not stated on the page. Games without access can use the open-source GameNetworkingSockets library, which has no relay access.

Architecture consequence: Steam networking cannot be the cross-platform backbone. The project needs its own matchmaking and relay, with Steam networking as an optional later addition.

Sources: [Steam Direct fee](https://partner.steamgames.com/doc/gettingstarted/appfee); [Steam revenue share, third-party](https://fungies.io/steam-revenue-share-explained.md); [Steam Deck compatibility](https://partner.steamgames.com/doc/steamdeck/compat); [Steam Cloud](https://partner.steamgames.com/doc/features/cloud); [Steam Datagram Relay](https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay).

## 4. Browser portals and the web build

| Portal | Size and file limits [P unless marked] | Threads and isolation | Ads and SDK | Revenue |
|---|---|---|---|---|
| itch.io | 200 MB per file; 500 MB extracted total; at most 1,000 files; ZIP must contain index.html [P]. A single .pck above 200 MB breaks the per-file rule. | SharedArrayBuffer is an experimental opt-in in embed settings [S]. | No mandatory SDK. | 10% default platform share, adjustable from 0% to 100%. Card fees via Stripe or PayPal [S]. |
| Poki | No numeric size limit on the current requirements page. Secondary sources cite an 8 MB initial-download target, which was not found on Poki's page [U]. Players leave after about 10 s of loading [P]. | Not stated. | Mandatory gameplay start and stop events. No SDK events during midrolls or rewarded ads. External requests blocked by default. Wrap localStorage in try/catch [P]. | Ad system only. No revenue split published [P]. |
| CrazyGames | Initial download 50 MB (basic). 20 MB for mobile homepage eligibility. Total 250 MB with SDK (50 MB without). At most 1,500 files. Gameplay within 20 s for externally hosted files [P]. | Not mentioned on the technical page [P]. | Ads only through the SDK. No external ad networks. Game must work with ad blockers. Basic launch carries no ads. Full launch depends on engagement metrics [P]. | Split not in official docs [U]. Payouts via a third-party guide only [S]. |
| Newgrounds | HTML5 ZIP with entry file at the top of the archive [S]. | Not researched. | Newgrounds.io API [S]. | Conflicting accounts. Ad share versus Supporter funding [U]. Lowest priority. |

Godot-specific points [P]:

- Threaded exports need `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp`. Those headers block third-party resources and ads.
- Single-threaded export is the default since Godot 4.3. The Godot docs say it is more compatible with itch.io, Poki and CrazyGames.
- The web build supports only the Compatibility renderer. It needs WebGL 2. Safari has known issues.
- Web clients cannot use the ENet-based high-level multiplayer. HTML5 exports support WebSocket and WebRTC but not raw TCP or UDP. The server therefore needs a WebSocket listener for browser clients [P, S].

Decision: v1 web uses single-threaded export and the Compatibility renderer, with no COOP/COEP headers and WSS multiplayer.

Sources: [itch.io HTML5 docs](https://itch.io/docs/creators/html5); [itch.io payments, third-party summary](https://itch.io/docs/creators/payments); [Poki requirements](https://developers.poki.com/guide/requirements-quality); [CrazyGames technical requirements](https://docs.crazygames.com/requirements/technical); [Godot web export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html); [Godot high-level multiplayer](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html).

## 5. Cross-platform play

- **Input fairness precedent.** Fortnite's input-based matchmaking (2018 to 2019 sources [S]) matched controller against controller and keyboard and mouse against keyboard and mouse. A keyboard and mouse player in a party pulled the whole party into the PC pool. Rainbow Six Siege's July 2026 patch [S] lets the squad leader's pool setting decide matchmaking for the squad, and shows a pre-match notice of allowed devices.
- **Recommendation.**
  - Matchmaking key: region, mode, skill band and input class (touch, gamepad, pointer).
  - Input class comes from the device used to queue.
  - Parties adopt the leader's input class, with a visible notice. This matches the Siege pattern.
  - An opt-in "any input" pool can exist, but it is not the default.
  - Bots fill empty slots, so input-class pools stay viable at low population.
  - Assist settings are tuned per input class, not per player. Pointer play gets no aim assist.
- **Cross-progression.** Progression belongs to our account, not to a platform. Steam, Apple, Google and email must all link to one account. Account deletion then has to cascade across every linked identity.
- **Cross-play default:** on. Platform-specific opt-outs and store requirements were not researched [U].

## 6. Legal

### 6.1 GDPR and Finland

- We are the controller. Required measures: lawful basis per processing purpose, privacy by design and default (Art. 25), a DPIA for chat moderation, voice and behavioural analytics (Art. 35), erasure on request (Art. 17), and safeguards for transfers outside the EEA (Chapter V). [K for article content]
- Age of digital consent in Finland is 13 under section 5 of the Data Protection Act (Tietosuojalaki 1050/2018). Younger children need parental consent, and the controller must make reasonable efforts to verify it [S, parliamentary document; section number not confirmed on Finlex].
- Supervisory authority: the Office of the Data Protection Ombudsman (Tietosuojavaltuutettu) [K].

### 6.2 COPPA (United States)

- The amended Rule was published 22 Apr 2025. Most operators had until 22 Apr 2026 to comply [S, law-firm and trade sources].
- The FTC FAQ says the Rule applies to general-audience services with "actual knowledge" that they collect personal information from under-13s. Mixed-audience services may age-screen but may not block under-13s from participating [P].
- A screen or user name is personal information only when it works as online contact information. Persistent identifiers are personal information unless used solely for internal operations [P].
- Audio files of a child's voice are personal information [P].
- Implication: a neutral age prompt at sign-up, no persistent identifiers or ads for users known to be under 13, and generated chat names.

### 6.3 Digital Services Act (EU)

- An online platform is a hosting service that stores user information and publicly disseminates it. Sharing within a closed, pre-determined group is not public dissemination [S, springlex summary of Art. 19 and Recital 14].
- Likely outside the platform definition: 1:1 chat and party chat. Likely inside: public lobbies, public player profiles and any public user uploads. Group chats with invite links are contested [S].
- Micro and small enterprises (fewer than 10 or 50 staff, with turnover of at most EUR 2M or EUR 10M) are exempt from Section 3 of the DSA (Arts. 20 to 28) under Art. 19 [S]. They are not exempt from the hosting rules, including notice-and-action under Art. 16 [S].
- Build a report and moderation queue from day one.

### 6.4 European Accessibility Act

- Applies since 28 Jun 2025 [S]. Games are not listed. The e-commerce channel (online sales, web store, account pages) is in scope [S].
- Microenterprises providing services (fewer than 10 staff and at most EUR 2M turnover) are exempt [S].
- Sources do not establish whether in-game UI is in scope [U].
- Recommendation: meet WCAG 2.1 AA on web store and account pages. In-game: colour-blind-safe team colours with shape or icon cues, scalable text, subtitles, and remappable controls.

### 6.5 Loot boxes and monetisation

- Belgium's Gaming Commission classed paid loot boxes as gambling in 2018 [S].
- The Dutch 2020 ban was overturned by a court. Later parliamentary motions have not been confirmed as enacted [S, U].
- Spain's draft would ban loot box use by under-18s and require ID verification. The consultation closed in 2022. Enactment is unconfirmed [S, U].
- Brazil's under-18 sales ban was reported to take effect in March 2026 [S].
- The European Parliament committee asked the Digital Fairness Act to ban loot boxes, in-app currency and pay-to-progress for minors. The Commission's consultation summary was published 19 Dec 2025. Publication of a draft proposal is unconfirmed [S, U].
- Apple requires odds disclosure (3.1.1) [P].
- Recommendation: no randomised paid items in v1. Sell cosmetics directly. Keep competitive modes free of pay-to-win.

### 6.6 UK Online Safety Act

- Matchmaking and in-game chat are user-to-user features. Children's codes applied from 25 Jul 2025 [S].
- Government proposals of 15 Jun 2026 would block under-16s from communicating with strangers in games. This is a plan, not law [S, U].
- Relevant only if the UK is a market. Design the age-band model so chat and voice can be restricted by band.

### 6.7 Name and IP: "Triplane Turmoil" and "Planewar"

- Triplane Turmoil (1996) was made by Dodekaedron Software (Finland). Its authors were Markku Rankala, Teemu J. Takanen and Henrikki Merikallio. The sequel (2006) was by Draconus Entertainment [P, Wikipedia].
- In 2009 the source, documentation, images and sounds were released under GPLv3 [P, Wikipedia].
- Trademark status was not checked [U].
- Recommendations:
  - Do not use "Triplane" in the product name, store listing or marketing.
  - Do not copy code, art or sounds from the GPLv3 release into our closed-source client. Mechanics are not copyrightable, but treat the original as design inspiration only, with a clean-room rule for implementation.
  - Run a trademark clearance on the working title "Planewar" and on the final name (EUIPO, USPTO, Finnish Patent and Registration Office) [K].

## 7. Requirements that must shape the architecture early

1. **Account and deletion pipeline.** One delete endpoint serves in-app deletion, the Play web link and Apple's rule. It cascades to server data, linked identities and analytics IDs. Keep a retention register for legal holds.
2. **Store-independent identity.** Accounts link Steam, Apple (with Sign in with Apple), Google and email or passkey. Needed for cross-progression, guideline 4.8 and the lack of Steam networking on mobile.
3. **Age band in the account model.** Neutral age prompt at sign-up. Bands: under 13, 13 to 15, 16 and over, 18 and over. Gates chat, voice, analytics and purchases. Covers GDPR Art. 8 (Finland at 13), COPPA mixed-audience rules and the UK codes.
4. **Chat moderation hooks.** Message IDs, report, block, mute, moderation queue with a response target, and log retention limits. Text chat first. Voice is deferred or disabled for under-16s.
5. **Privacy-by-default analytics.** No ad or tracking SDKs in v1. Pseudonymous IDs, a minimal event schema, EU hosting, and analytics off for under-13s.
6. **Store-agnostic entitlements.** One product catalogue. The server validates Apple, Google, Steam and web-store purchases. No randomised paid items in v1.
7. **Transport abstraction.** WSS for all clients, including browsers. Native UDP can be added later. Server-authoritative simulation.
8. **Renderer.** Compatibility renderer on every target for v1, since the web build and the iOS simulator support only it [P].
9. **Web build constraints.** Single-threaded export. No COOP/COEP. Each file under 200 MB and at most 1,000 files for itch.io. Initial download at most 20 MB for CrazyGames' mobile homepage and under 50 MB in general. Gameplay reached within 20 s.
10. **Asset streaming and budgets.** Lazy-load ship and structure models. Procedural generation keeps the initial payload small.
11. **Controller-first UI.** Focus navigation, glyph system per active input, on-screen keyboard for text, minimum text size of 9 px (12 px target) at 1280x800, and 30 fps at 800p as the default Deck configuration.
12. **Input classes in matchmaking.** Queue key includes input class. Party rule defined. Assist tuned per class.
13. **Save data.** Godot `user://` locally. Steam Cloud files split by change frequency. Progression is server-authoritative, and local saves act as cache. Wrap storage access in try/catch (Poki guidance). Confirm web persistence [U].
14. **Build pipeline.** macOS runner for iOS with Xcode 26 or later. Android AAB targeting API 36 with arm64-v8a. Steam depots. Single-threaded web export.
15. **Naming and IP.** Clearance search on the working title. No Triplane code or assets. Clean-room rule for design inspiration.
16. **Accessibility baseline.** Colour-blind-safe team colours with shape cues, scalable text, subtitles, remappable controls, WCAG 2.1 AA on web store pages.

## 8. Unresolved items to check before launch

- Poki's initial-size target: 8 MB in secondary sources, not on Poki's page [U].
- Steam Datagram Relay cost and eligibility [U].
- Google Play base-module limit: 500 MB on the current page versus 200 MB in older docs [U].
- Google billing rates outside the US, UK and EEA [U].
- Steam revenue split: official table not retrieved [U].
- CrazyGames and Newgrounds revenue terms [U].
- Apple guideline 4.8 wording: summary only, not re-read verbatim [S].
- Finnish section 5 text: not retrieved from Finlex [S].
- Dutch and Spanish loot box status, Digital Fairness Act timing [U].
- UK under-16 proposals: not law [S].
- Trademark status of "Triplane Turmoil" and "Planewar" [U].
- Godot iOS template minimum version and privacy manifest [U].
- Google Play Data safety form details and IARC content rating [K].
- Whether GodotSteam or another GDExtension is needed for Steam Cloud and Steam Input [K].

## 9. Source list

- Apple: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/); [5.1.1 account deletion help](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion); [upcoming requirements](https://developer.apple.com/news/upcoming-requirements/); [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
- Google: [target API requirements](https://developer.android.com/google/play/requirements/target-sdk); [account deletion](https://support.google.com/googleplay/android-developer/answer/13327111); [expanded billing and fees](https://developer.android.com/blog/posts/expanded-billing-choice-and-lower-fees-on-google-play); [size limits](https://support.google.com/googleplay/android-developer/answer/9859372); [64-bit](https://developer.android.com/google/play/requirements/64-bit)
- Steam: [Steam Direct fee](https://partner.steamgames.com/doc/gettingstarted/appfee); [Steam Deck compatibility](https://partner.steamgames.com/doc/steamdeck/compat); [Steam Cloud](https://partner.steamgames.com/doc/features/cloud); [Steam Datagram Relay](https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay); [revenue share, third-party](https://fungies.io/steam-revenue-share-explained.md)
- Godot: [web export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html); [iOS export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html); [high-level multiplayer](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html)
- Portals: [itch.io HTML5](https://itch.io/docs/creators/html5); [itch.io payments](https://itch.io/docs/creators/payments); [Poki requirements](https://developers.poki.com/guide/requirements-quality); [CrazyGames technical](https://docs.crazygames.com/requirements/technical)
- Legal: [FTC COPPA FAQ](https://www.ftc.gov/tips-advice/business-center/guidance/complying-coppa-frequently-asked-questions); [DSA Art. 19 summary](https://www.springlex.eu/en/packages/dsa/dsa-regulation/article-19/); [EAA and games, Taylor Wessing](https://www.taylorwessing.com/en/insights-and-events/insights/2025/03/accessibility-in-the-gaming-industry); [Finnish parliamentary document EDK 2023 AK 14399](https://www.eduskunta.fi/valtiopaivaasiakirjat/EDK-2023-AK-14399); [Digital Fairness Act consultation summary](https://www.lewissilkin.com/insights/2026/01/14/european-commission-issues-responses-to-digital-fairness-consultation-102m1s7); [Netherlands and Spain loot boxes, Fieldfisher](https://www.fieldfisher.com/en/insights/update-netherlands-and-spain-propose-tighter-regulation-on-loot-boxes); [Ofcom gaming guidance, Lewis Silkin](https://www.lewissilkin.com/insights/2025/10/24/ofcom-issues-guidance-about-online-safety-act-in-video-gaming-context-102lr5v); [Triplane Turmoil, Wikipedia](https://en.wikipedia.org/wiki/Triplane_Turmoil)
- Cross-play: [Fortnite input-based matchmaking](https://fortnitenews.com/season-6-introduces-input-based-matchmaking-to-fortnite); [Rainbow Six Siege native M and K on consoles](https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/35zOD6cqVS4JlQJePp0vmt/native-mouse-keyboard-support-on-consoles)
