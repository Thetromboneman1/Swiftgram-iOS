#!/usr/bin/env bash

set -euo pipefail

translation_root="${TRANSLATION_ROOT:-Swiftgram/BonemanTranslation}"
source_root="${translation_root}/Sources"
test_root="${translation_root}/Tests"

fail() {
    echo "translation-policy: $*" >&2
    exit 1
}

[[ -f "${translation_root}/BUILD" ]] || fail "missing ${translation_root}/BUILD"
[[ -d "${source_root}" ]] || fail "missing ${source_root}"
[[ -d "${test_root}" ]] || fail "missing ${test_root}"

source_count="$(find "${source_root}" -type f -name '*.swift' -print | wc -l | tr -d ' ')"
test_count="$(find "${test_root}" -type f -name '*.swift' -print | wc -l | tr -d ' ')"
(( source_count > 0 )) || fail "no Swift sources found under ${source_root}"
(( test_count > 0 )) || fail "no Swift tests found under ${test_root}"

banned_network_pattern='URLSession|URLRequest|URLProtocol|NSURLConnection|CFNetwork|NWConnection|https?://|SGGTranslate|gtranslate|google[[:space:]_-]*translate|microsoft[[:space:]_-]*translator|DeepL|OpenAI|alternativeTranslateText|messages\.translateText|network\.request'
if rg --line-number --ignore-case --glob '*.swift' "${banned_network_pattern}" "${source_root}"; then
    fail "the Boneman translation boundary references a network or cloud translation surface"
fi

cache_file="${source_root}/TranslationCache.swift"
[[ -f "${cache_file}" ]] || fail "missing in-memory TranslationCache.swift"
if rg --line-number 'FileManager|UserDefaults|SQLite|write\(to:|Data\(contentsOf:' "${cache_file}"; then
    fail "translation cache must remain process-memory-only"
fi

rg --quiet 'name[[:space:]]*=[[:space:]]*"BonemanTranslation"' "${translation_root}/BUILD" \
    || fail "missing BonemanTranslation Bazel library"
rg --quiet 'name[[:space:]]*=[[:space:]]*"BonemanTranslationTests"' "${translation_root}/BUILD" \
    || fail "missing BonemanTranslationTests Bazel target"
rg --quiet 'BonemanTranslationTestRunner' "${translation_root}/BUILD" \
    || fail "missing Boneman translation test runner"
rg --quiet 'effectiveBackend\(rawValue: "default", appleSystemAvailable: true\)' "${test_root}" \
    || fail "tests do not pin Apple translation as the supported default"
rg --quiet 'testCacheIsBoundedAndUsesRecentAccessForEviction' "${test_root}" \
    || fail "tests do not cover bounded cache eviction"

core_file="submodules/TelegramCore/Sources/TelegramEngine/Messages/Translate.swift"
translation_attribute_file="submodules/TelegramCore/Sources/SyncCore/SyncCore_TranslationMessageAttribute.swift"
engine_file="submodules/TelegramCore/Sources/TelegramEngine/Messages/TelegramEngineMessages.swift"
service_file="submodules/TranslateUI/Sources/Translate.swift"
screen_file="submodules/TranslateUI/Sources/TranslateScreen.swift"
chat_file="submodules/TranslateUI/Sources/ChatTranslation.swift"
outgoing_file="submodules/TelegramUI/Sources/Chat/ChatMessageDisplaySendMessageOptions.swift"
message_file="submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift"
controller_file="submodules/TelegramUI/Sources/ChatController.swift"
display_node_file="submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift"
translation_panel_file="submodules/TelegramUI/Components/TranslateHeaderPanelComponent/Sources/ChatTranslationPanelNode.swift"
settings_file="Swiftgram/SGSettingsUI/Sources/SGSettingsController.swift"
simple_settings_file="Swiftgram/SGSimpleSettings/Sources/SimpleSettings.swift"
simple_settings_build="Swiftgram/SGSimpleSettings/BUILD"
core_build="submodules/TelegramCore/BUILD"
translate_ui_build="submodules/TranslateUI/BUILD"

integration_files=(
    "${core_file}"
    "${translation_attribute_file}"
    "${engine_file}"
    "${service_file}"
    "${screen_file}"
    "${chat_file}"
    "${outgoing_file}"
    "${message_file}"
    "${controller_file}"
    "${display_node_file}"
    "${translation_panel_file}"
    "${settings_file}"
    "${simple_settings_file}"
    "${simple_settings_build}"
    "${core_build}"
    "${translate_ui_build}"
)
for path in "${integration_files[@]}"; do
    [[ -f "${path}" ]] || fail "missing translation integration file ${path}"
done

rg --quiet '^import BonemanTranslation$' "${core_file}" \
    || fail "TelegramCore translation does not import BonemanTranslation"
rg --quiet '^import BonemanTranslation$' "${service_file}" \
    || fail "TranslateUI service does not import BonemanTranslation"
rg --quiet '^import BonemanTranslation$' "${simple_settings_file}" \
    || fail "Swiftgram translation settings do not import BonemanTranslation"
for build_file in "${simple_settings_build}" "${core_build}" "${translate_ui_build}"; do
    rg --fixed-strings --quiet '//Swiftgram/BonemanTranslation:BonemanTranslation' "${build_file}" \
        || fail "${build_file} does not depend on BonemanTranslation"
done
rg --quiet 'TranslationSession' "${service_file}" \
    || fail "whole-chat Apple TranslationSession integration is missing"
rg --quiet 'LanguageAvailability' "${service_file}" \
    || fail "Apple language availability handling is missing"
rg --quiet 'prepareTranslation\(\)' "${service_file}" \
    || fail "Apple language-pack preparation is missing"
rg --quiet '@available\(iOS 18\.0' "${service_file}" \
    || fail "iOS 18 whole-chat availability handling is missing"
rg --quiet 'translateTextWithApple' "${service_file}" \
    || fail "single-text Apple TranslationSession entry point is missing"
if rg --line-number 'translationPresentation' "${screen_file}"; then
    fail "individual and outgoing translation must use the audited TranslationSession service, not translationPresentation"
fi
for required_pattern in 'TranslationSession\.Configuration' '\.translationTask\(' 'LanguageAvailability' 'prepareTranslation\(\)' 'session\.translate\('; do
    rg --quiet "${required_pattern}" "${screen_file}" \
        || fail "translation review screen is missing audited Apple TranslationSession behavior: ${required_pattern}"
done
rg --quiet 'replaceText' "${screen_file}" \
    || fail "outgoing translation review screen has no user-approved replacement action"
rg --quiet '@available\(iOS 18\.0' "${screen_file}" \
    || fail "individual/outgoing Apple translation availability handling is missing"
rg --quiet 'localOnly:[[:space:]]*true' "${chat_file}" \
    || fail "whole-chat Apple translation is not explicitly local-only"
rg --quiet 'clearCachedMessageTranslations' "${display_node_file}" \
    || fail "whole-chat disable path does not clear local translated-message state"
rg --quiet 'engineExperimentalInternalTranslationService[[:space:]]*=' "${display_node_file}" \
    || fail "Apple TranslationSession service is not installed into the chat host"
rg --fixed-strings --quiet 'requestedSourceLanguage ?? detectedAppleTranslationLanguage' "${service_file}" \
    || fail "whole-chat Apple translation does not detect a source language per message before model preparation"
rg --quiet 'if isAppleTranslationSelected\(context:[[:space:]]*context\)' "${translation_panel_file}" \
    || fail "translation provider attribution is not conditional on the selected backend"
rg --quiet 'Translations use Apple Translation on device\.' "${translation_panel_file}" \
    || fail "Apple whole-chat translation is missing on-device provider attribution"
rg --quiet 'public var hasRenderableContent' "${translation_attribute_file}" \
    || fail "translation attributes do not distinguish blank failures from renderable results"
for retry_file in "${chat_file}" "submodules/TelegramUI/Sources/ChatHistoryListNode.swift"; do
    rg --quiet 'translation\.hasRenderableContent' "${retry_file}" \
        || fail "${retry_file} lets blank local translation attributes suppress retries"
done
rg --quiet 'case[[:space:]]+system' "${simple_settings_file}" \
    || fail "Swiftgram settings do not expose the Apple system backend"
rg --quiet 'value[[:space:]]*==[[:space:]]*\.system' "${settings_file}" \
    || fail "Swiftgram settings UI does not gate the Apple system backend"

strict_local_files=(
    "${screen_file}"
    "${outgoing_file}"
    "${message_file}"
)
direct_network_pattern='URLSession|URLRequest|URLProtocol|NSURLConnection|CFNetwork|NWConnection|https?://|DeepL|OpenAI'
if rg --line-number --ignore-case "${direct_network_pattern}" "${strict_local_files[@]}"; then
    fail "an Apple translation UI integration file references a network or cloud translation surface"
fi

python3 - \
    "${core_file}" \
    "${engine_file}" \
    "${service_file}" \
    "${chat_file}" \
    "${outgoing_file}" \
    "${message_file}" \
    "${screen_file}" \
    "${controller_file}" \
    "${display_node_file}" <<'PY'
import re
import sys
from pathlib import Path


def load(path: str) -> str:
    return Path(path).read_text(encoding="utf-8")


def section(text: str, start: str, end: str, label: str) -> str:
    start_index = text.find(start)
    if start_index < 0:
        raise SystemExit(f"translation-policy: missing {label} start marker")
    end_index = text.find(end, start_index + len(start))
    if end_index < 0:
        raise SystemExit(f"translation-policy: missing {label} end marker")
    return text[start_index:end_index]


core = load(sys.argv[1])
engine = load(sys.argv[2])
service = load(sys.argv[3])
chat = load(sys.argv[4])
outgoing = load(sys.argv[5])
message = load(sys.argv[6])
screen = load(sys.argv[7])
controller = load(sys.argv[8])
display_node = load(sys.argv[9])

cloud_pattern = re.compile(
    r"URLSession|URLRequest|URLProtocol|NSURLConnection|CFNetwork|NWConnection|"
    r"https?://|SGGTranslate|gtranslate|google\s*translate|microsoft\s*translator|"
    r"DeepL|OpenAI|alternativeTranslateText|messages\.translateText|network\s*\.",
    re.I,
)


def require_local(section_text: str, label: str) -> None:
    match = cloud_pattern.search(section_text)
    if match:
        raise SystemExit(
            f"translation-policy: {label} references cloud/network token {match.group(0)!r}"
        )

peer_function = section(
    core,
    "private func _internal_translateMessagesByPeerId",
    "func _internal_translateMessagesViaText",
    "message translation function",
)
local_branch = section(
    peer_function,
    "if localOnly {",
    "guard let inputPeer",
    "local-only message branch",
)
if "return _internal_translateTextsLocally" not in local_branch:
    raise SystemExit("translation-policy: local-only message branch does not return through the Apple service")
require_local(local_branch, "local-only message branch")
if re.search(r"translateRichMessage|_internal_translate\(", local_branch, re.I):
    raise SystemExit("translation-policy: local-only message branch references a non-local translation route")
if peer_function.find("if localOnly {") > peer_function.find("account.network.request"):
    raise SystemExit("translation-policy: local-only message return occurs after a network call")

via_text_function = section(
    core,
    "func _internal_translateMessagesViaText",
    "func _internal_togglePeerMessagesTranslationHidden",
    "via-text translation function",
)
via_local_branch = section(
    via_text_function,
    "if localOnly {",
    "var listOfSignals",
    "local-only via-text branch",
)
if "return _internal_translateTextsLocally" not in via_local_branch:
    raise SystemExit("translation-policy: local-only via-text branch does not return through the Apple service")
require_local(via_local_branch, "local-only via-text branch")
if re.search(r"_internal_translate\(", via_local_branch, re.I):
    raise SystemExit("translation-policy: local-only via-text branch references a non-local translation route")
if via_text_function.find("if localOnly {") > via_text_function.find("gtranslate"):
    raise SystemExit("translation-policy: local-only via-text return occurs after Google translation")

wrapper_starts = (
    "private func sgWrappedTranslateSingle",
    "private func sgWrappedTranslateMultiple",
)
for index, function_name in enumerate(wrapper_starts):
    if index + 1 < len(wrapper_starts):
        wrapper = section(engine, function_name, wrapper_starts[index + 1], function_name)
    else:
        start_index = engine.find(function_name)
        if start_index < 0:
            raise SystemExit(f"translation-policy: missing {function_name}")
        wrapper = engine[start_index:]
    system_case = section(wrapper, "case .system:", "case .default:", f"{function_name} system case")
    if ".fail(.generic)" not in system_case:
        raise SystemExit(f"translation-policy: {function_name} can fall through from Apple to cloud")
    require_local(system_case, f"{function_name} system case")

local_text_service = section(
    service,
    "public func translateTextWithApple",
    "func alternativeTranslateText",
    "single-text Apple service",
)
for required in ("engineExperimentalInternalTranslationService", ".translate("):
    if required not in local_text_service:
        raise SystemExit(f"translation-policy: single-text Apple service is missing {required}")
require_local(local_text_service, "single-text Apple service")

apple_chat_branch = section(
    chat,
    "if isAppleTranslationSelected(context: context) {",
    "let enableLocalIfPossible = false",
    "Apple whole-chat branch",
)
if "localOnly: true" not in apple_chat_branch:
    raise SystemExit("translation-policy: Apple whole-chat branch is not local-only")
require_local(apple_chat_branch, "Apple whole-chat branch")
if "translateMessagesViaText" in apple_chat_branch:
    raise SystemExit("translation-policy: Apple whole-chat branch references a non-local fallback")

apple_outgoing_branch = section(
    outgoing,
    "if isAppleTranslationSelected(context: selfController.context) {",
    "let _ = (selfController.context.engine.messages.translate",
    "Apple outgoing branch",
)
for required in ("presentTranslateScreen", "replaceText: applyTranslation", "return"):
    if required not in apple_outgoing_branch:
        raise SystemExit(f"translation-policy: Apple outgoing branch is missing {required}")
require_local(apple_outgoing_branch, "Apple outgoing branch")

apple_message_branch = section(
    message,
    "if isAppleTranslationSelected(context: item.context) {",
    "Queue.mainQueue().async",
    "Apple individual-message branch",
)
for required in ("presentTranslateScreen", "return"):
    if required not in apple_message_branch:
        raise SystemExit(f"translation-policy: Apple individual-message branch is missing {required}")
require_local(apple_message_branch, "Apple individual-message branch")

screen_entry = screen[screen.find("public func presentTranslateScreen"):]
for required in (
    "TranslationSession.Configuration",
    ".translationTask(",
    "LanguageAvailability",
    "prepareTranslation()",
    "session.translate(",
    "replaceText",
):
    if required not in screen_entry:
        raise SystemExit(f"translation-policy: Apple review screen is missing {required}")
require_local(screen_entry, "Apple translation review screen")

controller_branch = section(
    controller,
    "if useSystemTranslation {",
    "} else {",
    "chat-panel Apple translation branch",
)
for required in ("presentTranslateScreen", "toggleTranslation(.translated)"):
    if required not in controller_branch:
        raise SystemExit(f"translation-policy: chat-panel Apple branch is missing {required}")
require_local(controller_branch, "chat-panel Apple translation branch")

composer_branch = section(
    display_node,
    "if useSystemTranslation {",
    "} else {",
    "composer Apple translation branch",
)
for required in ("presentTranslateScreen", "replaceText:"):
    if required not in composer_branch:
        raise SystemExit(f"translation-policy: composer Apple branch is missing {required}")
require_local(composer_branch, "composer Apple translation branch")
PY

echo "translation-policy: PASS"
