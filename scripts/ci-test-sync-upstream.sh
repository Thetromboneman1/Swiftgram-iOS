#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
sync_script="$script_dir/ci-sync-upstream.sh"
temp_base="${TMPDIR:-/tmp}"
[[ "$temp_base" == /* ]] || { echo "sync-self-test: TMPDIR must be absolute" >&2; exit 2; }
temp_base="$(cd -- "${temp_base%/}" && pwd -P)"
fixture_root="$(mktemp -d "$temp_base/swiftgram-sync-test.XXXXXX")"

cleanup() {
    local exit_status=$?
    trap - EXIT
    case "$fixture_root" in
        "$temp_base"/swiftgram-sync-test.*)
            /bin/rm -rf -- "$fixture_root"
            ;;
        *)
            echo "sync-self-test: temporary cleanup guard failed" >&2
            exit_status=1
            ;;
    esac
    exit "$exit_status"
}
trap cleanup EXIT

origin_repo="$fixture_root/origin.git"
swiftgram_repo="$fixture_root/swiftgram.git"
seed_repo="$fixture_root/seed"
runner_repo="$fixture_root/runner"
mock_bin="$fixture_root/bin"
pr_state="$fixture_root/pr.json"
merge_state="$fixture_root/merge.json"

git init --bare --quiet "$origin_repo"
git init --bare --quiet "$swiftgram_repo"
git init --quiet "$seed_repo"
git -C "$seed_repo" config user.name "Sync Fixture"
git -C "$seed_repo" config user.email "sync-fixture@example.invalid"
printf '%s\n' base > "$seed_repo/state.txt"
git -C "$seed_repo" add state.txt
git -C "$seed_repo" commit --quiet -m "base"
target_tip="$(git -C "$seed_repo" rev-parse HEAD)"
git -C "$seed_repo" remote add origin "$origin_repo"
git -C "$seed_repo" push --quiet origin "HEAD:refs/heads/boneman/main" "HEAD:refs/heads/upstream/swiftgram"
printf '%s\n' upstream >> "$seed_repo/state.txt"
git -C "$seed_repo" commit --quiet -am "upstream"
upstream_tip="$(git -C "$seed_repo" rev-parse HEAD)"
git -C "$seed_repo" remote add swiftgram "$swiftgram_repo"
git -C "$seed_repo" push --quiet swiftgram "HEAD:refs/heads/master"

git clone --quiet --branch boneman/main "$origin_repo" "$runner_repo"
git -C "$runner_repo" remote add swiftgram "$swiftgram_repo"
git -C "$runner_repo" fetch --quiet swiftgram master
merge_tree="$(git -C "$runner_repo" merge-tree --write-tree "$target_tip" "$upstream_tip")"
merge_commit="$(printf '%s\n' "synthetic merge" | GIT_AUTHOR_NAME="Sync Fixture" GIT_AUTHOR_EMAIL="sync-fixture@example.invalid" GIT_COMMITTER_NAME="Sync Fixture" GIT_COMMITTER_EMAIL="sync-fixture@example.invalid" git -C "$runner_repo" commit-tree "$merge_tree" -p "$target_tip" -p "$upstream_tip")"

mkdir "$mock_bin"
mock_gh="$mock_bin/gh"
cat > "$mock_gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == pr && "${2:-}" == list ]]; then
    [[ " $* " == *" --head fixture:upstream/swiftgram "* ]] || exit 96
    printf '%s\n' 1
elif [[ "${1:-}" == pr && "${2:-}" == edit ]]; then
    exit 0
elif [[ "${1:-}" == api && "${2:-}" == --method ]]; then
    exit 0
elif [[ "${1:-}" == api && "${2:-}" == repos/fixture/repo/pulls/* ]]; then
    cat "$GH_MOCK_PR_STATE"
elif [[ "${1:-}" == api && "${2:-}" == repos/fixture/repo/git/commits/* ]]; then
    cat "$GH_MOCK_MERGE_STATE"
else
    printf 'unexpected gh invocation:' >&2
    printf ' %q' "$@" >&2
    printf '\n' >&2
    exit 97
fi
MOCK
chmod 700 "$mock_gh"

write_states() {
    local head_repository="$1"
    local merge_parent="$2"
    jq -n \
        --arg repository "$head_repository" \
        --arg head_ref "upstream/swiftgram" \
        --arg head_sha "$upstream_tip" \
        --arg base_sha "$target_tip" \
        --arg merge_sha "$merge_commit" '{
            number: 1,
            state: "open",
            head: {repo: {full_name: $repository}, ref: $head_ref, sha: $head_sha},
            base: {repo: {full_name: "fixture/repo"}, ref: "boneman/main", sha: $base_sha},
            merge_commit_sha: $merge_sha
        }' > "$pr_state"
    jq -n --arg base "$target_tip" --arg head "$merge_parent" \
        '{parents: [{sha: $base}, {sha: $head}]}' > "$merge_state"
}

output_value() {
    local output_file="$1"
    local key="$2"
    awk -F= -v key="$key" '$1 == key { value = $2 } END { print value }' "$output_file"
}

run_sync() {
    local output_file="$1"
    shift
    : > "$output_file"
    (
        cd "$runner_repo"
        env \
            PATH="$mock_bin:$PATH" \
            GH_MOCK_PR_STATE="$pr_state" \
            GH_MOCK_MERGE_STATE="$merge_state" \
            GITHUB_OUTPUT="$output_file" \
            GITHUB_REPOSITORY="fixture/repo" \
            TARGET_BRANCH="boneman/main" \
            TRACKING_BRANCH="upstream/swiftgram" \
            UPSTREAM_BRANCH="master" \
            UPSTREAM_URL="$swiftgram_repo" \
            "$@" \
            "$sync_script"
    )
}

write_states "fixture/repo" "$upstream_tip"
prepare_output="$fixture_root/prepare.outputs"
run_sync "$prepare_output" CI_SYNC_PHASE=prepare >/dev/null
[[ "$(output_value "$prepare_output" validation_commit)" == "$merge_commit" ]]
[[ "$(output_value "$prepare_output" pr_number)" == 1 ]]

finalize_output="$fixture_root/finalize.outputs"
run_sync "$finalize_output" \
    CI_SYNC_PHASE=finalize \
    CI_SYNC_EXPECTED_PR_NUMBER=1 \
    CI_SYNC_VALIDATED_COMMIT="$merge_commit" \
    CI_SYNC_VALIDATION_RESULT=PASS >/dev/null
[[ "$(output_value "$finalize_output" drift_status)" == GREEN ]]

set +e
run_sync "$fixture_root/mismatch.outputs" \
    CI_SYNC_PHASE=finalize \
    CI_SYNC_EXPECTED_PR_NUMBER=1 \
    CI_SYNC_VALIDATED_COMMIT=0000000000000000000000000000000000000000 \
    CI_SYNC_VALIDATION_RESULT=PASS >/dev/null 2>&1
mismatch_status=$?
set -e
[[ "$mismatch_status" -ne 0 ]]
[[ "$(output_value "$fixture_root/mismatch.outputs" drift_status)" == YELLOW ]]

write_states "attacker/fork" "$upstream_tip"
set +e
run_sync "$fixture_root/fork.outputs" CI_SYNC_PHASE=prepare >/dev/null 2>&1
fork_status=$?
set -e
[[ "$fork_status" -ne 0 ]]
[[ -z "$(output_value "$fixture_root/fork.outputs" validation_commit)" ]]

write_states "fixture/repo" "$target_tip"
set +e
run_sync "$fixture_root/parents.outputs" CI_SYNC_PHASE=prepare >/dev/null 2>&1
parents_status=$?
set -e
[[ "$parents_status" -ne 0 ]]
[[ -z "$(output_value "$fixture_root/parents.outputs" validation_commit)" ]]

set +e
run_sync "$fixture_root/full-override.outputs" \
    CI_SYNC_PHASE=full \
    CI_SYNC_VALIDATION_RESULT=PASS >/dev/null 2>&1
override_status=$?
set -e
[[ "$override_status" -eq 2 ]]

dry_run_output="$fixture_root/dry-run.outputs"
set +e
run_sync "$dry_run_output" CI_SYNC_DRY_RUN=true >/dev/null
dry_run_status=$?
set -e
[[ "$dry_run_status" -eq 1 ]]
[[ "$(output_value "$dry_run_output" drift_status)" == YELLOW ]]

dry_run_pass_output="$fixture_root/dry-run-pass.outputs"
run_sync "$dry_run_pass_output" \
    CI_SYNC_DRY_RUN=true \
    CI_SYNC_VALIDATION_RESULT=PASS >/dev/null
[[ "$(output_value "$dry_run_pass_output" drift_status)" == GREEN ]]

echo "sync-self-test: PASS"
