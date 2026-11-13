# shellcheck shell=bash
# Terminal package-review editor. The package owner supplies snapshots and
# retains live and offline persistence; this file only edits choices.
vgs_pkg_review_settings() { # OWNER
    local owner=$1 snapshot choices row value summary plan options presets_text id label state
    # gum 2.0.2 input cuts each header line at the terminal's last column and
    # does not wrap it. Each line fits an 80-column terminal after the
    # 3-column edge.
    local command_header='Review command
Separate the command and each option with a space.
Quotes and symbols are passed as typed.
The command starts in the folder of its own review.
A command whose first word is claude starts in one fixed folder.
Neither folder holds an update or another review,
so an agent with its own sandbox cannot change them.
A claude command asks you before it reads its review files
or writes its verdict, unless your options allow or deny that.
VGS does not limit a command that has no sandbox.'
    local heading='Set agent review before a package installs or updates'
    local purpose='Choose whether to review packages, which AI agent to use, and an optional command.'
    local rules='Review with an agent uses the agent and command below without asking again.
Automatic asks before AUR installs and updates.
Install without review also skips the paru review questions.
A custom AUR command that cannot run the review asks before continuing.'
    local -a agents=() presets=() words=()
    snapshot="$("$owner" review-settings-read)" || return
    choices="$(node -e 'process.stdout.write(JSON.stringify(JSON.parse(process.argv[1]).settings))' "$snapshot")" || return
    options="$("$owner" review-settings-agents)" || return
    while true; do
        summary="$(node -e '
            const s=JSON.parse(process.argv[1]);
            const agents=new Map(process.argv[2].split("\n").filter(Boolean).map(line=>{const [id,label,state]=line.split("\t");return [id,{label,state}];}));
            const first=Object.hasOwn(s,"enabled")?(s.enabled?"Review with an agent":"Install without review"):"Automatic (review when an agent is available)";
            const agent=agents.get(s.agent);
            const named=!s.agent?"Automatic (use the first available agent)":agent?agent.label+(agent.state==="found"?"":" (not installed)"):s.agent;
            process.stdout.write("Before installing: "+first+"\nAI agent: "+named+"\nReview command: "+(s.command?"Custom command":"Use the agent\u0027s command"));
        ' "$choices" "$options")" || return
        vgs_tui_clear >&2
        vgs_tui_header "$heading" "$purpose" >&2
        vgs_tui_text "$summary" >&2
        vgs_tui_text "$rules" >&2
        row="$(vgs_pkg_review_choose 'Change package review choices' -- 'Before installing' 'AI agent' 'Review command' 'Save' 'Cancel')" || return 130
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
                    value="$(vgs_tui_input --no-show-help --header "$command_header"$'\n\n'"$(vgs_pkg_review_help 'Enter confirms • Esc returns')" --value "$value")" || continue
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
                vgs_pkg_review_choose 'Keep your choices' -- 'Return to editor' >/dev/null || return 130
                ;;
            *) return 130 ;;
        esac
    done
}
