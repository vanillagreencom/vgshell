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
    local rules='VGS asks before each install. The first choice is selected when VGS asks. Automatic selects Review when you set an agent or a command, or when VGS finds an agent.'
    local -a agents=() presets=() words=()
    snapshot="$("$owner" review-settings-read)" || return
    choices="$(node -e 'process.stdout.write(JSON.stringify(JSON.parse(process.argv[1]).settings))' "$snapshot")" || return
    saved=$choices
    options="$("$owner" review-settings-agents)" || return
    if [[ $mode == inline ]]; then
        vgs_tui_step 'Package review settings' >&2
        vgs_tui_text 'These choices apply to package installs and updates.' >&2
        vgs_tui_text "$rules" >&2
    fi
    while true; do
        summary="$(node -e '
            const s=JSON.parse(process.argv[1]);
            const agents=new Map(process.argv[2].split("\n").filter(Boolean).map(line=>{const [id,label,state]=line.split("\t");return [id,{label,state}];}));
            const first=Object.hasOwn(s,"enabled")?(s.enabled?"Review":"Install without review"):"Automatic";
            const agent=agents.get(s.agent);
            const named=!s.agent?"Automatic":agent?agent.label+(agent.state==="found"?"":" (not installed)"):s.agent;
            process.stdout.write("First choice when VGS asks: "+first+"\nAgent: "+named+"\nCommand: "+(s.command?"Custom":"Agent default"));
        ' "$choices" "$options")" || return
        if [[ $mode != inline ]]; then
            vgs_tui_clear >&2
            vgs_tui_header 'Package review settings' 'These choices apply to package installs and updates.' >&2
            vgs_tui_text "$summary" >&2
            vgs_tui_text "$rules" >&2
        elif [[ $summary != "$shown" ]]; then
            vgs_tui_text "$summary" >&2
            shown=$summary
        fi
        row="$(vgs_pkg_review_choose 'Edit package review' -- 'First choice' 'AI agent' 'Review command' 'Save' 'Cancel')" || { _vgs_pkg_review_settings_cancel "$mode" "$saved" "$choices"; return 130; }
        case $row in
            'First choice')
                value="$(vgs_pkg_review_choose 'First choice when VGS asks to review packages' -- 'Automatic' 'Review' 'Install without review' 'Back')" || continue
                [[ $value != Back ]] || continue
                choices="$(node -e 'const s=JSON.parse(process.argv[1]);if(process.argv[2]==="Automatic")delete s.enabled;else s.enabled=process.argv[2]==="Review";process.stdout.write(JSON.stringify(s));' "$choices" "$value")" || return
                ;;
            'AI agent')
                # gum prints the value after the tab: the id, or nothing for Automatic.
                agents=($'Automatic\t')
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
                presets=('Agent default')
                while IFS= read -r value; do [[ -z $value ]] || presets+=("$value"); done <<< "$presets_text"
                presets+=('Custom command' 'Back')
                value="$(vgs_pkg_review_choose 'Review command' -- "${presets[@]}")" || continue
                [[ $value != Back ]] || continue
                if [[ $value == 'Custom command' ]]; then
                    value="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).command||"")' "$choices")" || return
                    printf -v input_help '\033[22m%sEnter confirms • Esc returns\033[0m' "$(vgs_tui_sgr "${GUM_PAGER_HELP_FOREGROUND:-}" 39)"
                    value="$(vgs_tui_input --no-show-help --header "Review command"$'\n''Spaces separate arguments. Quotes and shell operators stay literal.'$'\n\n'"$input_help" --value "$value")" || continue
                elif [[ $value == 'Agent default' ]]; then value=''; fi
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
