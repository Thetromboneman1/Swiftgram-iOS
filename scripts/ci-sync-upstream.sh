#!/usr/bin/env bash

set -euo pipefail

target_branch="${TARGET_BRANCH:-boneman/main}"
tracking_branch="${TRACKING_BRANCH:-upstream/swiftgram}"
upstream_branch="${UPSTREAM_BRANCH:-master}"
upstream_url="${UPSTREAM_URL:-https://github.com/Swiftgram/Telegram-iOS.git}"
dry_run="${CI_SYNC_DRY_RUN:-false}"
use_filter="${CI_SYNC_USE_FILTER:-false}"
sync_phase="${CI_SYNC_PHASE:-full}"
validation_override="${CI_SYNC_VALIDATION_RESULT:-}"
validated_commit="${CI_SYNC_VALIDATED_COMMIT:-}"
expected_pr_number="${CI_SYNC_EXPECTED_PR_NUMBER:-}"
validation_timeout_seconds="${CI_SYNC_VALIDATION_TIMEOUT_SECONDS:-7200}"
validation_poll_seconds="${CI_SYNC_VALIDATION_POLL_SECONDS:-20}"
repository="${GITHUB_REPOSITORY:-}"
automation_tip="$(git rev-parse HEAD)"

expected_checks=(
    "Repository and translation policy"
    "Run Boneman translation tests"
)

case "${sync_phase}" in
    full|prepare|finalize)
        ;;
    *)
        echo "upstream-sync: CI_SYNC_PHASE must be full, prepare, or finalize" >&2
        exit 2
        ;;
esac
case "${dry_run}" in
    true|false)
        ;;
    *)
        echo "upstream-sync: CI_SYNC_DRY_RUN must be true or false" >&2
        exit 2
        ;;
esac
case "${use_filter}" in
    true|false)
        ;;
    *)
        echo "upstream-sync: CI_SYNC_USE_FILTER must be true or false" >&2
        exit 2
        ;;
esac
if [[ "${dry_run}" == true && "${sync_phase}" != full ]]; then
    echo "upstream-sync: dry-run mode supports only CI_SYNC_PHASE=full" >&2
    exit 2
fi
if [[ "${sync_phase}" == prepare && -n "${validation_override}" ]]; then
    echo "upstream-sync: prepare phase must not receive a validation result" >&2
    exit 2
fi
if [[ "${sync_phase}" == full && "${dry_run}" != true && -n "${validation_override}" ]]; then
    echo "upstream-sync: full phase cannot accept a synthetic validation result outside dry-run mode" >&2
    exit 2
fi
if [[ "${sync_phase}" == finalize ]]; then
    [[ "${validated_commit}" =~ ^[0-9a-f]{40}$ ]] || {
        echo "upstream-sync: finalize phase requires CI_SYNC_VALIDATED_COMMIT as a full lowercase SHA" >&2
        exit 2
    }
    case "${validation_override}" in
        PASS|FAIL|TIMEOUT|PENDING)
            ;;
        *)
            echo "upstream-sync: finalize phase requires an explicit CI_SYNC_VALIDATION_RESULT" >&2
            exit 2
            ;;
    esac
fi

if [[ "${dry_run}" != true && -z "${repository}" ]]; then
    echo "upstream-sync: GITHUB_REPOSITORY is required outside dry-run mode" >&2
    exit 2
fi
[[ "${validation_timeout_seconds}" =~ ^[1-9][0-9]*$ ]] || {
    echo "upstream-sync: CI_SYNC_VALIDATION_TIMEOUT_SECONDS must be a positive integer" >&2
    exit 2
}
[[ "${validation_poll_seconds}" =~ ^[1-9][0-9]*$ ]] || {
    echo "upstream-sync: CI_SYNC_VALIDATION_POLL_SECONDS must be a positive integer" >&2
    exit 2
}

set_output() {
    local key="$1"
    local value="$2"
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        printf '%s=%s\n' "${key}" "${value}" >> "${GITHUB_OUTPUT}"
    fi
}

append_summary() {
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        printf '%s\n' "$*" >> "${GITHUB_STEP_SUMMARY}"
    else
        printf '%s\n' "$*"
    fi
}

remote_branch_exists() {
    git show-ref --verify --quiet "refs/remotes/origin/$1"
}

find_open_pr() {
    local repository_owner="${repository%%/*}"
    gh pr list \
        --repo "${repository}" \
        --state open \
        --base "${target_branch}" \
        --head "${repository_owner}:${tracking_branch}" \
        --json number \
        --jq '.[0].number // empty'
}

resolve_pr_merge() {
    local pr_number="$1"
    local expected_head_sha="$2"
    local expected_base_sha="$3"
    local pr_state
    local merge_state
    local merge_sha
    local parent_shas

    pr_state="$(gh api "repos/${repository}/pulls/${pr_number}")" || return 1
    jq -e \
        --argjson number "${pr_number}" \
        --arg repository "${repository}" \
        --arg head_ref "${tracking_branch}" \
        --arg base_ref "${target_branch}" \
        --arg head_sha "${expected_head_sha}" \
        --arg base_sha "${expected_base_sha}" '
            (.number == $number) and
            (.state == "open") and
            (.head.repo.full_name == $repository) and
            (.head.ref == $head_ref) and
            (.head.sha == $head_sha) and
            (.base.repo.full_name == $repository) and
            (.base.ref == $base_ref) and
            (.base.sha == $base_sha) and
            (.merge_commit_sha | type == "string" and test("^[0-9a-f]{40}$"))
        ' <<< "${pr_state}" >/dev/null || return 1

    merge_sha="$(jq -r '.merge_commit_sha' <<< "${pr_state}")"
    merge_state="$(gh api "repos/${repository}/git/commits/${merge_sha}")" || return 1
    parent_shas="$(jq -r '[.parents[].sha] | join(" ")' <<< "${merge_state}")"
    [[ "${parent_shas}" == "${expected_base_sha} ${expected_head_sha}" ]] || return 1
    printf '%s\n' "${merge_sha}"
}

wait_for_commit_validation() {
    local commit_sha="$1"

    if [[ "${sync_phase}" == finalize && "${validated_commit}" != "${commit_sha}" ]]; then
        echo "upstream-sync: validated commit ${validated_commit} no longer matches ${commit_sha}" >&2
        return 2
    fi

    case "${validation_override}" in
        PASS)
            return 0
            ;;
        FAIL)
            return 1
            ;;
        TIMEOUT|PENDING)
            return 2
            ;;
        "")
            ;;
        *)
            echo "upstream-sync: invalid CI_SYNC_VALIDATION_RESULT=${validation_override}" >&2
            return 2
            ;;
    esac

    if [[ "${dry_run}" == true ]]; then
        return 2
    fi

    local deadline=$((SECONDS + validation_timeout_seconds))
    while (( SECONDS < deadline )); do
        local response
        if ! response="$(gh api "repos/${repository}/commits/${commit_sha}/check-runs?per_page=100")"; then
            echo "upstream-sync: could not read validation checks for ${commit_sha}" >&2
            return 2
        fi

        local all_success=true
        local has_failure=false
        local check_name
        for check_name in "${expected_checks[@]}"; do
            local check_state
            check_state="$(jq -r --arg name "${check_name}" '
                [.check_runs[] | select(.name == $name)]
                | sort_by(.id)
                | last
                | if . == null then "missing"
                  elif .status != "completed" then "pending"
                  elif .conclusion == "success" then "success"
                  else "failure:" + (.conclusion // "unknown")
                  end
            ' <<< "${response}")"
            case "${check_state}" in
                success)
                    ;;
                failure:*)
                    all_success=false
                    has_failure=true
                    echo "upstream-sync: ${check_name} ${check_state}" >&2
                    ;;
                *)
                    all_success=false
                    ;;
            esac
        done

        if [[ "${all_success}" == true ]]; then
            return 0
        fi
        if [[ "${has_failure}" == true ]]; then
            return 1
        fi
        sleep "${validation_poll_seconds}"
    done

    echo "upstream-sync: validation did not finish within ${validation_timeout_seconds} seconds" >&2
    return 2
}

if git remote get-url swiftgram >/dev/null 2>&1; then
    git remote set-url swiftgram "${upstream_url}"
else
    git remote add swiftgram "${upstream_url}"
fi

fetch_options=(--no-tags)
if [[ "${use_filter}" == true ]]; then
    fetch_options+=(--filter=blob:none)
fi
git fetch "${fetch_options[@]}" origin "+refs/heads/${target_branch}:refs/remotes/origin/${target_branch}"
git fetch "${fetch_options[@]}" origin "+refs/heads/${tracking_branch}:refs/remotes/origin/${tracking_branch}" 2>/dev/null || true
git fetch "${fetch_options[@]}" swiftgram "+refs/heads/${upstream_branch}:refs/remotes/swiftgram/${upstream_branch}"

target_tip="$(git rev-parse "refs/remotes/origin/${target_branch}")"
upstream_tip="$(git rev-parse "refs/remotes/swiftgram/${upstream_branch}")"
target_parent="$(git rev-parse "${target_tip}^1" 2>/dev/null || printf '%s' "${target_tip}")"
tracking_tip=""
if remote_branch_exists "${tracking_branch}"; then
    tracking_tip="$(git rev-parse "refs/remotes/origin/${tracking_branch}")"
fi

set_output upstream_tip "${upstream_tip}"
set_output target_tip "${target_tip}"
set_output automation_tip "${automation_tip}"
set_output previous_tracking_tip "${tracking_tip}"

if [[ "${dry_run}" != true && "${automation_tip}" != "${target_tip}" ]]; then
    set_output drift_status YELLOW
    append_summary "## YELLOW - Maintained automation changed during sync"
    append_summary ""
    append_summary "The trusted checkout was \`${automation_tip}\`, but \`${target_branch}\` is now \`${target_tip}\`. No tracking branch or PR was changed; rerun against the new maintained tip."
    exit 1
fi

if [[ -n "${tracking_tip}" && "${tracking_tip}" != "${upstream_tip}" ]] \
    && ! git merge-base --is-ancestor "${tracking_tip}" "${upstream_tip}"; then
    set_output drift_status RED
    append_summary "## RED - Swiftgram tracking history changed"
    append_summary ""
    append_summary "The clean tracking branch was not rewritten. Swiftgram \`${upstream_branch}\` is no longer a fast-forward from \`${tracking_branch}\`; manual review is required."
    if [[ "${dry_run}" != true ]]; then
        open_pr="$(find_open_pr)"
        if [[ -n "${open_pr}" ]]; then
            gh pr comment "${open_pr}" --repo "${repository}" \
                --body "RED: Swiftgram ${upstream_branch} is no longer a fast-forward from ${tracking_branch}. The workflow left the tracking branch unchanged."
        fi
    fi
    exit 1
fi

tracking_changed=false
if [[ "${tracking_tip}" != "${upstream_tip}" ]]; then
    tracking_changed=true
    if [[ "${dry_run}" == true ]]; then
        git update-ref "refs/remotes/origin/${tracking_branch}" "${upstream_tip}"
    elif [[ -n "${tracking_tip}" ]]; then
        gh api --method PATCH "repos/${repository}/git/refs/heads/${tracking_branch}" \
            -f "sha=${upstream_tip}" \
            -F force=false >/dev/null
    else
        gh api --method POST "repos/${repository}/git/refs" \
            -f "ref=refs/heads/${tracking_branch}" \
            -f "sha=${upstream_tip}" >/dev/null
    fi
fi
set_output tracking_changed "${tracking_changed}"

if git merge-base --is-ancestor "${upstream_tip}" "${target_tip}"; then
    set_output validation_commit "${target_tip}"
    set_output validation_base "${target_parent}"
    if [[ "${sync_phase}" == prepare ]]; then
        set_output drift_status YELLOW
        append_summary "## YELLOW - Swiftgram is already integrated"
        append_summary ""
        append_summary "Tracking tip: \`${upstream_tip}\`; maintained-branch validation is pending for \`${target_tip}\`."
        exit 0
    fi
    validation_status=0
    wait_for_commit_validation "${target_tip}" || validation_status=$?
    if [[ "${validation_status}" -eq 0 ]]; then
        drift_status=GREEN
        validation_result=PASS
    elif [[ "${validation_status}" -eq 1 ]]; then
        drift_status=YELLOW
        validation_result=FAIL
    else
        drift_status=YELLOW
        validation_result="NOT CONFIRMED"
    fi
    set_output drift_status "${drift_status}"
    append_summary "## ${drift_status} - Swiftgram is already integrated"
    append_summary ""
    append_summary "Tracking tip: \`${upstream_tip}\`; maintained-branch validation: ${validation_result}."
    if [[ "${dry_run}" != true ]]; then
        open_pr="$(find_open_pr)"
        if [[ -n "${open_pr}" ]]; then
            gh pr close "${open_pr}" --repo "${repository}" \
                --comment "Swiftgram ${upstream_tip} is now contained in ${target_branch}; closing the completed sync PR. Maintained-branch validation: ${validation_result}."
        fi
    fi
    [[ "${drift_status}" == GREEN ]]
    exit
fi

merge_clean=true
merge_output="$(git merge-tree --write-tree --name-only --no-messages "${target_tip}" "${upstream_tip}")" \
    || merge_clean=false
conflict_files=""
if [[ "${merge_clean}" != true ]]; then
    conflict_count="$(printf '%s\n' "${merge_output}" | sed -n '2,$p' | wc -l | tr -d ' ')"
    echo "upstream-sync: merge conflict paths (${conflict_count})" >&2
    printf '%s\n' "${merge_output}" | sed -n '2,$p' >&2
    conflict_files="$(printf '%s\n' "${merge_output}" | sed -n '2,101p' | sed 's/^/- `/' | sed 's/$/`/')"
    if (( conflict_count > 100 )); then
        conflict_files+=$'\n'"- ... $((conflict_count - 100)) more conflicting paths in the workflow log"
    fi
fi

pr_body="$(mktemp)"
cleanup() {
    local exit_status=$?
    trap - EXIT
    set +e
    /bin/rm -f -- "${pr_body}"
    exit "${exit_status}"
}
trap cleanup EXIT

drift_status=RED
validation_result="NOT RUN"
if [[ "${merge_clean}" == true ]]; then
    drift_status=YELLOW
    validation_result=PENDING
fi
short_tip="${upstream_tip:0:12}"

write_pr_body() {
    {
        echo "<!-- boneman-upstream-sync -->"
        echo "# ${drift_status} - Swiftgram upstream sync"
        echo
        echo "| Field | Value |"
        echo "| --- | --- |"
        echo "| Swiftgram source | \`${upstream_tip}\` |"
        echo "| Maintained base | \`${target_tip}\` |"
        echo "| Tracking branch | \`${tracking_branch}\` |"
        echo "| Merge simulation | $([[ "${merge_clean}" == true ]] && echo PASS || echo CONFLICT) |"
        echo "| Repository policy and translation tests | ${validation_result} |"
        echo
        case "${drift_status}" in
            GREEN)
                echo "The upstream tip merges cleanly. The repository policy checks and Boneman translation tests passed on the PR merge commit. Signed archive, device installation, and offline behavior remain local release gates."
                ;;
            YELLOW)
                echo "The upstream tip merges cleanly, but automated validation is pending or failed. Review the attached checks before integrating."
                ;;
            RED)
                echo "The upstream tip conflicts with the maintained branch. No customization branch was rewritten. Resolve this on a separate integration branch."
                if [[ -n "${conflict_files}" ]]; then
                    echo
                    echo "## Conflicting paths"
                    echo
                    printf '%s\n' "${conflict_files}"
                fi
                ;;
        esac
        echo
        echo "This PR is maintained by the daily [Upstream Sync](https://github.com/${repository}/actions/workflows/sync-upstream.yml) workflow."
    } > "${pr_body}"
}

write_pr_body
title="[${drift_status}] Sync Swiftgram ${short_tip}"

if [[ "${dry_run}" == true ]]; then
    if [[ "${merge_clean}" == true ]]; then
        validation_status=0
        wait_for_commit_validation "${upstream_tip}" || validation_status=$?
        if [[ "${validation_status}" -eq 0 ]]; then
            drift_status=GREEN
            validation_result=PASS
        elif [[ "${validation_status}" -eq 1 ]]; then
            drift_status=YELLOW
            validation_result=FAIL
        else
            drift_status=YELLOW
            validation_result="NOT CONFIRMED"
        fi
        write_pr_body
    fi
    cat "${pr_body}"
else
    if [[ "${sync_phase}" == finalize ]]; then
        [[ "${expected_pr_number}" =~ ^[1-9][0-9]*$ ]] || {
            echo "upstream-sync: finalize phase requires CI_SYNC_EXPECTED_PR_NUMBER for an open sync PR" >&2
            exit 2
        }
        open_pr="${expected_pr_number}"
    else
        open_pr="$(find_open_pr)"
    fi
    if [[ -z "${open_pr}" ]]; then
        pr_url="$(gh pr create \
            --repo "${repository}" \
            --base "${target_branch}" \
            --head "${tracking_branch}" \
            --title "${title}" \
            --body-file "${pr_body}")"
        printf '%s\n' "${pr_url}"
        open_pr="${pr_url##*/}"
        if [[ ! "${open_pr}" =~ ^[0-9]+$ ]]; then
            open_pr="$(find_open_pr)"
        fi
        [[ -n "${open_pr}" ]] || {
            echo "upstream-sync: pull request was created but its number could not be resolved" >&2
            exit 1
        }
    fi
    set_output pr_number "${open_pr}"

    if [[ "${merge_clean}" == true ]]; then
        merge_commit_sha=""
        if ! merge_commit_sha="$(resolve_pr_merge "${open_pr}" "${upstream_tip}" "${target_tip}")"; then
            drift_status=YELLOW
            validation_result="PR IDENTITY OR MERGE CHANGED"
        else
            set_output validation_base "${target_tip}"
            set_output validation_commit "${merge_commit_sha}"
            if [[ "${sync_phase}" == prepare ]]; then
                drift_status=YELLOW
                validation_result=PENDING
            else
                validation_status=0
                wait_for_commit_validation "${merge_commit_sha}" || validation_status=$?
                if [[ "${validation_status}" -eq 0 ]]; then
                    drift_status=GREEN
                    validation_result=PASS
                elif [[ "${validation_status}" -eq 1 ]]; then
                    drift_status=YELLOW
                    validation_result=FAIL
                else
                    drift_status=YELLOW
                    validation_result="NOT CONFIRMED"
                fi
                if [[ "${drift_status}" == GREEN ]]; then
                    confirmed_merge_commit=""
                    if ! confirmed_merge_commit="$(resolve_pr_merge "${open_pr}" "${upstream_tip}" "${target_tip}")" \
                        || [[ "${confirmed_merge_commit}" != "${merge_commit_sha}" ]]; then
                        drift_status=YELLOW
                        validation_result="PR CHANGED AFTER VALIDATION"
                    fi
                fi
            fi
        fi
        write_pr_body
        title="[${drift_status}] Sync Swiftgram ${short_tip}"
        gh pr edit "${open_pr}" --repo "${repository}" --title "${title}" --body-file "${pr_body}"
    fi
fi

set_output drift_status "${drift_status}"
append_summary "## ${drift_status} - Swiftgram upstream ${short_tip}"
append_summary ""
append_summary "Tracking branch update: ${tracking_changed}; merge simulation: $([[ "${merge_clean}" == true ]] && echo PASS || echo CONFLICT); validation: ${validation_result}."

if [[ "${sync_phase}" == prepare && "${merge_clean}" == true && "${validation_result}" == PENDING && "${merge_commit_sha:-}" =~ ^[0-9a-f]{40}$ ]]; then
    exit 0
fi
if [[ "${drift_status}" != GREEN ]]; then
    exit 1
fi
