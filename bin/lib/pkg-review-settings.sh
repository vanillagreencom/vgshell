# shellcheck shell=bash
# Shared inline package-review editor. The package owner supplies snapshots
# and retains both live and offline persistence; this file only edits choices.
# The editor shows each agent by its label and stores its id. On its own it
# draws each view on a cleared screen. Inline, inside a package review, it
# never clears the review's screen: it draws its heading and rules once,
# then the summary of the choices each time they read differently.
# Inline, a cancelled editor says when it drops choices that differ from
# the saved ones; on its own screen the cancel closes the view.
_vgs_pkg_review_settings_cancel() { # MODE SAVED CHOICES
    if [[ $1 == inline ]] && ! node -e '
        const sorted=o=>JSON.stringify(Object.keys(o).sort().map(k=>[k,o[k]]));
        process.exit(sorted(JSON.parse(process.argv[1]))===sorted(JSON.parse(process.argv[2]))?0:1);
    ' "$2" "$3"; then
        vgs_tui_text 'Your changes are not saved.' >&2
    fi
}
vgs_pkg_review_settings() { # OWNER [inline]
    local owner=$1 mode=${2:-} snapshot saved choices row value summary shown="" plan options presets_text input_help id label state
    local heading='Set agent review before a package installs or updates'
    local purpose='Choose whether to review packages, which AI agent to use, and an optional command.'
    local rules='VGS asks each time. Your saved choice is selected; you still confirm each install or update.
Review with an agent
  Selects review with the agent and command below.
Install without review
  Selects installation without an agent review.
Automatic (review when an agent is available)
  Selects review when you choose an agent or command, or VGS finds an agent.'
    local -a agents=() presets=() words=()
    snapshot="$("$owner" review-settings-read)" || return
    choices="$(node -e 'process.stdout.write(JSON.stringify(JSON.parse(process.argv[1]).settings))' "$snapshot")" || return
    saved=$choices
    options="$("$owner" review-settings-agents)" || return
    if [[ $mode == inline ]]; then
        vgs_tui_step "$heading" >&2
        vgs_tui_text "$purpose" >&2
        vgs_tui_text "$rules" >&2
    fi
    while true; do
        summary="$(node -e '
            const s=JSON.parse(process.argv[1]);
            const agents=new Map(process.argv[2].split("\n").filter(Boolean).map(line=>{const [id,label,state]=line.split("\t");return [id,{label,state}];}));
            const first=Object.hasOwn(s,"enabled")?(s.enabled?"Review with an agent":"Install without review"):"Automatic (review when an agent is available)";
            const agent=agents.get(s.agent);
            const named=!s.agent?"Automatic (use the first available agent)":agent?agent.label+(agent.state==="found"?"":" (not installed)"):s.agent;
            process.stdout.write("Before installing: "+first+"\nAI agent: "+named+"\nReview command: "+(s.command?"Custom command":"Use the agent\u0027s command"));
        ' "$choices" "$options")" || return
        if [[ $mode != inline ]]; then
            vgs_tui_clear >&2
            vgs_tui_header "$heading" "$purpose" >&2
            vgs_tui_text "$summary" >&2
            vgs_tui_text "$rules" >&2
        elif [[ $summary != "$shown" ]]; then
            vgs_tui_text "$summary" >&2
            shown=$summary
        fi
        row="$(vgs_pkg_review_choose 'Change package review choices' -- 'Before installing' 'AI agent' 'Review command' 'Save' 'Cancel')" || { _vgs_pkg_review_settings_cancel "$mode" "$saved" "$choices"; return 130; }
        case $row in
            'Before installing')
                value="$(vgs_pkg_review_choose 'Before installing or updating a package' -- 'Automatic (review when an agent is available)' 'Review with an agent' 'Install without review' 'Back')" || continue
                [[ $value != Back ]] || continue
                choices="$(node -e 'const s=JSON.parse(process.argv[1]);if(process.argv[2]==="Automatic (review when an agent is available)")delete s.enabled;else s.enabled=process.argv[2]==="Review with an agent";process.stdout.write(JSON.stringify(s));' "$choices" "$value")" || return
                ;;
            'AI agent')
                # gum prints the value after the tab: the id, or nothing for automatic selection.
                agents=($'Automatic (use the first available agent)\t')
                while IFS=$'\t' read -r id label state; do
                    [[ $state != found ]] || agents+=("$label"$'\t'"$id")
                done <<< "$options"
                agents+=($'Back\tBack')
                value="$(vgs_pkg_review_choose 'AI agent' --label-delimiter=$'\t' -- "${agents[@]}")" || continue
                [[ $value != Back ]] || continue
                choices="$(node -e 'const s=JSON.parse(process.argv[1]);s.agent=process.argv[2];process.stdout.write(JSON.stringify(s));' "$choices" "$value")" || return
                ;;
            'Review command')
                presets_text="$("$owner" review-settings-presets)" || return
                presets=("Use the agent's command")
                while IFS= read -r value; do [[ -z $value ]] || presets+=("$value"); done <<< "$presets_text"
                presets+=('Custom command' 'Back')
                value="$(vgs_pkg_review_choose 'Review command (optional)' -- "${presets[@]}")" || continue
                [[ $value != Back ]] || continue
                if [[ $value == 'Custom command' ]]; then
                    value="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).command||"")' "$choices")" || return
                    printf -v input_help '\033[22m%sEnter confirms • Esc returns\033[0m' "$(vgs_tui_sgr "${GUM_PAGER_HELP_FOREGROUND:-}" 39)"
                    value="$(vgs_tui_input --no-show-help --header "Review command"$'\n''Separate the command and each option with a space. Quotes and symbols are passed as typed.'$'\n\n'"$input_help" --value "$value")" || continue
                elif [[ $value == "Use the agent's command" ]]; then value=''; fi
                choices="$(node -e 'const s=JSON.parse(process.argv[1]);s.command=process.argv[2];process.stdout.write(JSON.stringify(s));' "$choices" "$value")" || return
                ;;
            Save)
                plan="$("$owner" review-settings-plan "$choices")" || { vgs_tui_error 'VGS could not read the selected review command.'; continue; }
                if [[ -n $plan ]]; then
                    mapfile -t words <<< "$plan"
                    vgs_pkg_review_command 'Review command' "${words[@]}"
                fi
                if "$owner" review-settings-write "$snapshot" "$choices" >/dev/null 2>&1; then
                    vgs_tui_success 'Package review settings saved.' >&2
                    return 0
                fi
                vgs_tui_error 'VGS could not save the settings. Your choices are still open.'
                vgs_tui_text 'The settings file may have changed. Cancel and reopen this editor to read it again.' >&2
                vgs_pkg_review_choose 'Keep your choices' -- 'Return to editor' >/dev/null || { _vgs_pkg_review_settings_cancel "$mode" "$saved" "$choices"; return 130; }
                ;;
            *) _vgs_pkg_review_settings_cancel "$mode" "$saved" "$choices"; return 130 ;;
        esac
    done
}
