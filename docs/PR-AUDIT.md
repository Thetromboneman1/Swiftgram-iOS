# Pull request audit

Snapshot: 2026-08-20

- Swiftgram base: `cf8b23beaaac4126a396337ac2d5be13f9f76b66`
- Telegram comparison: `6ad963e5b62d354da79040f388ae2b9132fb17b8`
- Swiftgram was six commits ahead of Telegram at the snapshot.
- Swiftgram had 25 open pull requests. All 25 had zero check runs and zero reviews.
- Swiftgram's only workflow was manual-only and had no historical runs. A clean merge state is not test evidence.

Each included change was taken as an isolated commit or reconstructed patch. No contributor branch was merged wholesale.

## Swiftgram open pull requests

| PR | Title | Author | Date | Status | Purpose | Upstream equivalent | Risks and conflicts | Decision | Rationale and local reference |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [#188](https://github.com/Swiftgram/Telegram-iOS/pull/188) | Hide Premium badge | mvsrcdst | 2026-08-07 | Open, clean, no CI/review | Add a local setting to hide Premium and emoji badges | None found | Touches 28 files and several hot UI paths | DEFER | Cosmetic benefit does not justify the upstream maintenance surface. Candidate `cefd43c87b5d`. |
| [#187](https://github.com/Swiftgram/Telegram-iOS/pull/187) | Hidden folder tabs | mvsrcdst | 2026-07-28 | Open, clean, no CI/review | Hide folders while retaining local access and unread state | None found | Complex ChatList state, persistence, and scrolling behavior | DEFER | Useful but needs focused state and performance tests first. Candidate `63c2357baa1a`. |
| [#186](https://github.com/Swiftgram/Telegram-iOS/pull/186) | Hide AI Rewrite | mvsrcdst | 2026-07-24 | Open, clean, no CI/review | Add a local toggle for Swiftgram's AI rewrite button | None found | Small composer UI coupling | INCLUDE | Small, local-only, and useful for keeping unrelated AI UI out of this build. Source `62d962e25e5e`; local `4302e62f04`. |
| [#185](https://github.com/Swiftgram/Telegram-iOS/pull/185) | QR login | mvsrcdst | 2026-07-23 | Open, clean, no CI/review | Add QR token export, refresh, DC migration, and password retry | None found | Authentication tokens, 2FA retry, background work, and account security | DEFER | Needs a threat model and physical-device authentication tests. Candidate `35b25a1ab24`. |
| [#183](https://github.com/Swiftgram/Telegram-iOS/pull/183) | Hide story ring | mvsrcdst | 2026-07-18 | Open, clean, no CI/review | Add a story-ring visibility setting | None found | Adds setting subscriptions in avatar rendering paths | DEFER | Cosmetic change with avoidable scrolling and memory risk. Candidate `2ca817602e27`. |
| [#181](https://github.com/Swiftgram/Telegram-iOS/pull/181) | SOCKS pre-auth timeout | mvsrcdst | 2026-07-16 | Open, clean, no CI/review | Bound SOCKS and FakeTLS pre-auth reads to 15 seconds | None found | Very slow proxies may time out | INCLUDE | Prevents an indefinite connection hang without changing normal MTProto reads. Source `693b6574664e`; local `9c74ff3fa1`. |
| [#180](https://github.com/Swiftgram/Telegram-iOS/pull/180) | Unauthorized proxy reactivity | mvsrcdst | 2026-07-16 | Open, clean, no CI/review | Apply proxy changes to unauthorized accounts | None found | Reconnect behavior before login | INCLUDE | Mirrors the established authorized-account subscription and disposes it correctly. Source `89f5fb075d5c`; local `1639c6af48`. |
| [#179](https://github.com/Swiftgram/Telegram-iOS/pull/179) | SOCKS IPv6 address | mvsrcdst | 2026-07-16 | Open, clean, no CI/review | Encode IPv4, IPv6, and domain SOCKS addresses safely | Telegram [#735](https://github.com/TelegramMessenger/Telegram-iOS/pull/735) fixes the same bug with weaker validation | Socket address encoding | INCLUDE WITH MODIFICATIONS | Used the bounded Swiftgram commit instead of the weaker official variant. Source `1c5b548cd94e`; local `9aac8ba9bc`. |
| [#178](https://github.com/Swiftgram/Telegram-iOS/pull/178) | Video-circle transcription | mvsrcdst | 2026-07-13 | Open, clean, no CI/review | Extend transcription to video circles | None found | Can allow Apple network speech for unsupported locales and includes forced debug gates | REJECT | It is not reliably on-device and conflicts with the project's privacy requirement. |
| [#177](https://github.com/Swiftgram/Telegram-iOS/pull/177) | 0.5x video circles | levochkaa | 2026-07-04 | Open, clean, no CI/review | Add ultra-wide capture behavior | None found | Camera selection, zoom handoff, low-power behavior, and battery | DEFER | Requires physical camera testing. Candidate `e58b1399cb29`. |
| [#176](https://github.com/Swiftgram/Telegram-iOS/pull/176) | Bottom folder menu placement | levochkaa | 2026-06-23 | Open, clean, no CI/review | Correct context-menu anchoring for bottom folders | None found | Small layout dependency | INCLUDE | Narrow Swiftgram-specific layout correction. Source `30d213cb1f96`; local `832e0e6519`. |
| [#175](https://github.com/Swiftgram/Telegram-iOS/pull/175) | Settings stack navigation | levochkaa | 2026-06-22 | Open, clean, no CI/review | Preserve the Settings stack when opening nested screens | None found | Navigation-stack behavior | INCLUDE | Three focused call-site changes restore expected back navigation. Source `28277057099c`; local `004c99214e`. |
| [#172](https://github.com/Swiftgram/Telegram-iOS/pull/172) | Hidden bot access panel | levochkaa | 2026-06-20 | Open, clean, no CI/review | Adjust business-bot header and pinned layout | None found | 45 files, unrelated localization changes, mixed scope | DEFER | Scope is too broad for the described fix. Candidate `779cf9147b2d`. |
| [#168](https://github.com/Swiftgram/Telegram-iOS/pull/168) | FakeTLS Chrome mimicry | Lawliet2012 | 2026-06-05 | Open, conflicting, no CI/review | Change FakeTLS fingerprinting | None found | 1,009-file polluted branch, fingerprint freshness, ECH mismatch | DEFER | Never merge the branch. Reconstruct only after current packet-capture and device validation. Feature `111292eba07c`. |
| [#166](https://github.com/Swiftgram/Telegram-iOS/pull/166) | Repeat message | itsLuuke | 2026-05-03 | Open, conflicting, no CI/review | Re-send selected content | None found | 1,008-file stale branch and accidental duplicate-send risk | DEFER | Product behavior is not required for this fork. Feature `1c7816572b07`. |
| [#165](https://github.com/Swiftgram/Telegram-iOS/pull/165) | Hide empty-chat sticker | itsLuuke | 2026-04-25 | Open, conflicting, no CI/review | Add an empty-chat sticker setting | None found | Stale branch and sticker lifecycle changes | DEFER | Cosmetic benefit does not justify the layout risk. Feature `f46d4e36d831`. |
| [#164](https://github.com/Swiftgram/Telegram-iOS/pull/164) | More mute options | itsLuuke | 2026-04-25 | Open, conflicting, no CI/review | Add custom mute timers | None found | Duplicated notification logic and high drift | DEFER | Needs a current, minimal implementation. Feature `b4f9cae24d7f`. |
| [#159](https://github.com/Swiftgram/Telegram-iOS/pull/159) | Crowdin updates | Kylmakalle | 2026-04-12 | Open, conflicting, no CI/review | Update localizations | None found | 1,007-file branch mixed with release history | DEFER | Accept only a clean Crowdin export. Branch `77e4385c2515`. |
| [#158](https://github.com/Swiftgram/Telegram-iOS/pull/158) | Wide glass composer | levochkaa | 2026-04-12 | Open, clean, no CI/review | Change composer geometry and controls | None found | 41 files and direct conflict with outgoing translation UI | DEFER | Revisit after translation UI is stable. Candidate `86b3f7d04486`. |
| [#157](https://github.com/Swiftgram/Telegram-iOS/pull/157) | Hide selection buttons | levochkaa | 2026-04-10 | Open, clean, no CI/review | Add selection-button visibility flags | None found | 37 generated localizations for a cosmetic option | DEFER | Not needed for this build. |
| [#156](https://github.com/Swiftgram/Telegram-iOS/pull/156) | Hide submenu | levochkaa | 2026-04-10 | Open, clean, no CI/review | Hide Swiftgram submenu and Edit actions | None found | Mixed scope and thin testing | REJECT | The submitted change combines unrelated settings. |
| [#155](https://github.com/Swiftgram/Telegram-iOS/pull/155) | Profile context menus | levochkaa | 2026-04-10 | Open, clean, no CI/review | Replace profile long-press behavior | None found | 42 files, gesture and accessibility risk | DEFER | No direct benefit to the translation fork. Candidate `2f0d6f169385`. |
| [#154](https://github.com/Swiftgram/Telegram-iOS/pull/154) | Video controls footer | levochkaa | 2026-04-09 | Open, clean, no CI/review | Move playback, PiP, and fullscreen controls | None found | Media and layout regressions | DEFER | Requires focused media and PiP testing. Candidate `5b664046fd79`. |
| [#149](https://github.com/Swiftgram/Telegram-iOS/pull/149) | PT-BR localization | luizpassaroni | 2026-02-07 | Open, conflicting, no CI/review | Add Brazilian Portuguese | Superseded by #159 | Also changes four Bazel-rule submodule pointers | OBSOLETE / ALREADY UPSTREAM | Superseded and carries unnecessary supply-chain changes. |
| [#141](https://github.com/Swiftgram/Telegram-iOS/pull/141) | Center level badge | pokryshkindaniil | 2025-10-18 | Open, conflicting, no CI/review | Center a level badge when the subtitle is empty | None found | Contributor branch contains 969 changed files | INCLUDE WITH MODIFICATIONS | Cherry-picked only the isolated one-file feature commit. Source `f4e4f769fbfa`; local `4bf695010b`. |

Totals: 5 INCLUDE, 2 INCLUDE WITH MODIFICATIONS, 15 DEFER, 2 REJECT, 1 OBSOLETE / ALREADY UPSTREAM.

## Targeted Telegram pull requests

Telegram had 72 open pull requests. This was a targeted review for security, crashes, iOS SDK compatibility, build failures, media, networking, notifications, performance, and translation. It was not a bulk-import exercise. No open official pull request implemented Apple's Translation framework or specifically addressed iOS 26 compatibility.

| PR | Area | Decision | Rationale and local reference |
| --- | --- | --- | --- |
| [#1740](https://github.com/TelegramMessenger/Telegram-iOS/pull/1740) | DNS memory safety | INCLUDE | Adds the missing packet-length check before `memcpy`. Source `b73021a720f3`; local `0e6058f3af`. |
| [#2217](https://github.com/TelegramMessenger/Telegram-iOS/pull/2217) | Drawing allocation failure | INCLUDE | Prevents a null image buffer from reaching `memset`. Source `ffbe9ed4187a`; local `6be4499059`. |
| [#2218](https://github.com/TelegramMessenger/Telegram-iOS/pull/2218) | Localization decode safety | INCLUDE WITH MODIFICATIONS | Bounds-checks persisted length-prefixed data and rejects negative counts. Source `342a8b34b4d5`; local `ad15bb3c72`. Full malformed-input coverage remains a follow-up. |
| [#2220](https://github.com/TelegramMessenger/Telegram-iOS/pull/2220) | Animation cache memory safety | INCLUDE WITH MODIFICATIONS | Re-derives `Data` pointers inside `withUnsafeBytes` instead of caching a dangling pointer. Source `77de8a26c434`; local `b5c1d83b07`. |
| [#2221](https://github.com/TelegramMessenger/Telegram-iOS/pull/2221) | Animation cache ownership | INCLUDE WITH MODIFICATIONS | Removes the failed-initializer double free and is carried with #2220. Source `33e25d757d99`; local `8d91e94390`. |
| [#2197](https://github.com/TelegramMessenger/Telegram-iOS/pull/2197) | MTProto salt recovery | DEFER | Plausible fix, but it changes authenticated protocol state transitions and needs reconnect regression tests. |
| [#2263](https://github.com/TelegramMessenger/Telegram-iOS/pull/2263) | Hermetic CMake build | DEFER | Apply only if host `ccache` reproduces the build failure. This Mac does not have `ccache`. |
| [#2223](https://github.com/TelegramMessenger/Telegram-iOS/pull/2223) | Share extension authorization | DEFER | Useful logged-out behavior fix, but outside the primary feature and needs extension testing. |
| [#2267](https://github.com/TelegramMessenger/Telegram-iOS/pull/2267) | Composer during recording | DEFER | Relevant composer fix, but it needs recording and keyboard tests before combining with translation changes. |
| [#2109](https://github.com/TelegramMessenger/Telegram-iOS/pull/2109) | AirPlay | DEFER | Requires route, call, and recording regression tests. |
| [#2186](https://github.com/TelegramMessenger/Telegram-iOS/pull/2186) | Save to Photos | DEFER | Error signaling remains incomplete in the proposed patch. |
| [#2207](https://github.com/TelegramMessenger/Telegram-iOS/pull/2207) | Playback resume | DEFER | Can preserve a stale resume point after an intentional seek. |
| [#2029](https://github.com/TelegramMessenger/Telegram-iOS/pull/2029) | USB-C microphone | DEFER | Hardware-specific and not validated on the target setup. |
| [#1692](https://github.com/TelegramMessenger/Telegram-iOS/pull/1692) | Inline prediction | DEFER | Stale and incomplete for captions. Reconstruct only if outgoing translation reproduces the bug. |
| [#1401](https://github.com/TelegramMessenger/Telegram-iOS/pull/1401) | Audio-session timing | DEFER | Too stale for a direct integration. |
| [#2248](https://github.com/TelegramMessenger/Telegram-iOS/pull/2248) | Watch stickers | REJECT | Eager, highest-priority downloads create network, storage, and battery cost. |
| [#924](https://github.com/TelegramMessenger/Telegram-iOS/pull/924) | Native DNS | OBSOLETE / ALREADY UPSTREAM | Swiftgram already has an opt-in native-DNS path. |
| [#1608](https://github.com/TelegramMessenger/Telegram-iOS/pull/1608) | Dependabot versions | OBSOLETE / ALREADY UPSTREAM | Dependency versions are stale and unrelated to the current pinned build. |
| [#1521](https://github.com/TelegramMessenger/Telegram-iOS/pull/1521) | Release workflow | REJECT | The fork uses its own least-privilege workflow and local signing path. |
| [#1887](https://github.com/TelegramMessenger/Telegram-iOS/pull/1887) | rsync workaround | DEFER | Keep as troubleshooting reference, not a source patch. |

## Validation rule

An included PR is not considered release-ready because it cherry-picked cleanly. The release gate is the final repository integrity check, targeted tests, full simulator/device compilation, signature verification, and physical-device smoke test documented in the release record.
