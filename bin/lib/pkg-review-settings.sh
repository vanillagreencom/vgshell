# shellcheck shell=bash
# Terminal package-review editor. The package owner supplies snapshots and
# retains live and offline persistence; this file only edits choices.
vgs_pkg_review_settings() { # OWNER
    local owner=$1 snapshot choices row value summary plan options presets_text id label state accounts saved directory shown
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
    local -a agents=() presets=() words=() offers=()
    snapshot="$("$owner" review-settings-read)" || return
    choices="$(node -e 'process.stdout.write(JSON.stringify(JSON.parse(process.argv[1]).settings))' "$snapshot")" || return
    options="$("$owner" review-settings-agents)" || return
    while true; do
        saved="$("$owner" review-settings-account "$choices")" || return
        summary="$(node -e '
            const s=JSON.parse(process.argv[1]),[state,shown]=process.argv[3].split("\t");
            const agents=new Map(process.argv[2].split("\n").filter(Boolean).map(line=>{const [id,label,state]=line.split("\t");return [id,{label,state}];}));
            const first=Object.hasOwn(s,"enabled")?(s.enabled?"Review with an agent":"Install without review"):"Automatic (review when an agent is available)";
            const agent=agents.get(s.agent);
            const named=!s.agent?"Automatic (use the first available agent)":agent?agent.label+(agent.state==="found"?"":" (not installed)"):s.agent;
            const account=state==="chosen"?shown:state==="missing"?shown+" (not found)":"Automatic (the agent\u0027s own account)";
            process.stdout.write("Before installing: "+first+"\nAI agent: "+named+"\nAccount: "+account+"\nReview command: "+(s.command?"Custom command":"Use the agent\u0027s command"));
        ' "$choices" "$options" "$saved")" || return
        vgs_tui_clear >&2
        vgs_tui_header "$heading" "$purpose" >&2
        vgs_tui_text "$summary" >&2
        vgs_tui_text "$rules" >&2
        row="$(vgs_pkg_review_choose 'Change package review choices' -- 'Before installing' 'AI agent' 'Account' 'Review command' 'Save' 'Cancel')" || return 130
        case $row in
            'Before installing')
                value="$(vgs_pkg_review_choose 'Before installing or updating a package' -- 'Automatic (review when an agent is available)' 'Review with an agent' 'Install without review' 'Back')" || continue
                [[ $value != Back ]] || continue
                case $value in
                    'Review with an agent') value=true ;;
                    'Install without review') value=false ;;
                    *) value=null ;;
                esac
                choices="$("$owner" review-settings-change "$choices" enabled "$value")" || return
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
                choices="$("$owner" review-settings-change "$choices" agent "$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$value")")" || return
                ;;
            'Account')
                accounts="$("$owner" review-settings-accounts "$choices")" || return
                # gum prints the value after the tab: the folder, or nothing for the agent's own account.
                offers=($'Automatic (the agent\'s own account)\t')
                while IFS=$'\t' read -r directory shown; do
                    [[ -z $directory ]] || offers+=("$shown"$'\t'"$directory")
                done <<< "$accounts"
                offers+=($'Back\tBack')
                value="$(vgs_pkg_review_choose 'Account' --label-delimiter=$'\t' -- "${offers[@]}")" || continue
                [[ $value != Back ]] || continue
                choices="$("$owner" review-settings-change "$choices" account "$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$value")")" || return
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
                choices="$("$owner" review-settings-change "$choices" command "$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$value")")" || return
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
