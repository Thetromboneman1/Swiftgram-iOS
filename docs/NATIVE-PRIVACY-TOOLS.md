# Native privacy and messaging tools

This document describes the native Swiftgram features added on the `feature/native-privacy-tools` branch. They use typed TelegramCore, Postbox, and TelegramUI seams. They do not include Lead-style runtime injection, MTProto constructor scanning, or global layout hooks.

## Selective Ghost Mode

Swiftgram Settings now provides independent controls for suppressing:

- typing and sticker-selection activity;
- voice and instant-video recording activity;
- file, photo, video, and instant-video upload activity;
- sent and seen emoji-interaction activity;
- account online-presence refreshes.

The first four controls stop the matching typed `messages.setTyping` request before it enters the network. Cancellation requests remain allowed so a previously visible activity can be cleared. Online suppression converts online refreshes to Telegram's typed offline status request.

When any Ghost Mode control is enabled, a message's context menu contains an account-scoped exception for that chat. Exceptions are keyed by the current account peer ID and chat peer ID and are bounded to the 512 most recently changed entries. Telegram presence is an account-wide API, so the online-status control cannot have a truthful per-chat exception; the settings screen states this limitation explicitly.

All Ghost Mode controls default to off. This avoids silently changing Telegram behavior before the owner chooses a privacy policy.

## Sponsored-message filtering

`Hide sponsored Telegram messages` defaults to on. The chat-history advertisement signal filters only messages whose typed `AdMessageAttribute.messageType` is `.sponsored`. Telegram recommendations are preserved. The code does not scan view classes or remove arbitrary layout nodes.

Changing the setting applies to newly opened chat histories. Reopen an already visible chat after changing it.

## Local edit history

Local edit history defaults to on. Immediately before Postbox applies an incoming typed edit operation, Swiftgram records the previous non-empty text when it differs from the new text.

Storage properties:

- account-scoped and message-scoped keys;
- at most 5 revisions per message;
- at most 1,000 messages total;
- 30-day retention;
- duplicate adjacent revisions are ignored;
- text never enters diagnostics or logs;
- explicit and global-ID deletion operations remove matching history, including normal auto-expiration deletion paths.

Messages with history gain `Edit History (N)` in their context menu. The viewer shows locally captured text and timestamps and can clear that message's history. Swiftgram Settings includes `Clear all edit history`.

The first version intentionally stores text revisions only. It does not archive deleted messages, expired messages, media payloads, rich-message InstantPages, access hashes, usernames, or peer metadata.

## Explicit Send as Voice

Selecting exactly one supported audio or video file from Files now presents two explicit choices:

- `Send normally`
- `Extract audio and send as voice`

The voice path uses AVFoundation's Apple M4A export preset, requires a real audio track, writes a temporary local audio file, and constructs a typed `TelegramMediaFile` with `.Audio(isVoice: true, ...)`. It never globally reclassifies audio MIME types. Multi-file selections and normal sends retain upstream behavior.

The first version supports Files selections with these extensions: AAC, FLAC, M4A, MP3, MP4, MOV, MPEG, and WAV. A visible error is shown when the file is unavailable, has no audio track, or cannot be exported.

## Redacted translation diagnostics

Swiftgram Settings now includes `Translation Diagnostics`. The screen can copy a redacted report and clear its in-memory counters. It contains:

- active backend (`Apple TranslationSession (on-device)`);
- the last canonical source-to-target language pair;
- Apple model availability state (`installed`, `supported`, or `unsupported`);
- batch state and queue depth;
- translated and skipped counters;
- failed message identifiers represented by process-local, non-reversible opaque IDs;
- app version, build number, and bundle identifier.

The diagnostics API never accepts message text, usernames, phone numbers, access hashes, tokens, or model output. State is process-memory-only and is cleared on app termination or with `Clear Logs`. The Apple Translation privacy contract remains authoritative in [TRANSLATION-PRIVACY.md](TRANSLATION-PRIVACY.md).

## Deferred designs

The approved build does not enable these later candidates:

- message or story read-receipt suppression, pending unread-count and multi-device correctness testing;
- a file-picker repair without a reproducible file-selection failure;
- story saving, which should be explicit and never automatic.

These are intentionally deferred because they touch synchronization, unread state, storage policy, or speculative failure paths beyond this build's acceptance criteria.

## Verification

The required source checks are:

```bash
scripts/build-local.sh test --test-target //Swiftgram/SGPrivacyTools:SGPrivacyToolsTests
scripts/build-local.sh test --test-target //Swiftgram/BonemanTranslation:BonemanTranslationTests
scripts/check-translation-policy.sh
scripts/build-local.sh simulator --build-number <build>
```

Physical-device acceptance after installation:

1. Toggle each Ghost Mode activity independently and verify the other activity types still appear from a second account/device.
2. Add and remove a chat exception and verify it applies only to that account and chat.
3. Reopen a sponsored channel and verify sponsored entries are absent while recommendations remain available.
4. Edit a normal message several times, view its local history, then delete or auto-expire it and verify history is unavailable.
5. Send one audio file normally and as voice, then extract audio from one video and send it as voice.
6. Run Russian-to-English Apple translation, open Translation Diagnostics, confirm the pair/model/batch state, copy the report, and inspect it for content leakage.
