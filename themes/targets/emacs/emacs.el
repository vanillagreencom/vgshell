;;; emacs.el --- the vgs theme for Emacs  -*- lexical-binding: t -*-
;; A stable final init line and the apply hook load this generated file.
;; Disable earlier themes so their unassigned faces cannot survive the apply.
(mapc #'disable-theme custom-enabled-themes)
(deftheme vgs "The vgs desktop theme.")
(custom-theme-set-faces
 'vgs
 '(default ((t (:foreground "#@{color.text}" :background "#@{color.background}"))))
 '(cursor ((t (:background "#@{color.accent}"))))
 '(region ((t (:background "#@{listItem.selected}" :extend t :foreground "#@{listItem.selectedForeground}"))))
 '(highlight ((t (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))))
 '(hl-line ((t (:background "#@{color.surfaceRaised}" :extend t))))
 '(fringe ((t (:background "#@{color.background}"))))
 '(vertical-border ((t (:foreground "#@{color.border}"))))
 '(line-number ((t (:foreground "#@{color.textFaint}" :background "#@{color.background}"))))
 '(line-number-current-line ((t (:foreground "#@{color.text}" :background "#@{color.surfaceRaised}"))))
 '(mode-line ((t (:foreground "#@{color.text}" :background "#@{color.surfaceRaised}" :box nil))))
 '(mode-line-inactive ((t (:foreground "#@{color.textMuted}" :background "#@{color.surface}" :box nil))))
 '(minibuffer-prompt ((t (:foreground "#@{color.accent}"))))
 '(link ((t (:foreground "#@{color.info}" :underline t))))
 '(isearch ((t (:foreground "#@{color.onAccent}" :background "#@{color.accent}"))))
 '(lazy-highlight ((t (:background "#@{color.borderStrong}"))))
 '(show-paren-match ((t (:foreground "#@{badge.tone.accent.foreground}" :weight bold :background "#@{badge.tone.accent.background}"))))
 '(shadow ((t (:foreground "#@{color.textFaint}"))))
 '(error ((t (:foreground "#@{color.danger}"))))
 '(warning ((t (:foreground "#@{color.warning}"))))
 '(success ((t (:foreground "#@{color.success}"))))
 '(font-lock-comment-face ((t (:foreground "#@{color.textFaint}" :slant italic))))
 '(font-lock-doc-face ((t (:foreground "#@{color.textMuted}" :slant italic))))
 '(font-lock-string-face ((t (:foreground "#@{terminal.color2}"))))
 '(font-lock-keyword-face ((t (:foreground "#@{terminal.color5}"))))
 '(font-lock-builtin-face ((t (:foreground "#@{terminal.color6}"))))
 '(font-lock-function-name-face ((t (:foreground "#@{terminal.color4}"))))
 '(font-lock-variable-name-face ((t (:foreground "#@{color.text}"))))
 '(font-lock-type-face ((t (:foreground "#@{terminal.color3}"))))
 '(font-lock-constant-face ((t (:foreground "#@{terminal.color6}"))))
 '(font-lock-preprocessor-face ((t (:foreground "#@{terminal.color1}"))))
 '(font-lock-warning-face ((t (:foreground "#@{color.warning}"))))
 '(ansi-color-black ((t (:foreground "#@{terminal.color0}" :background "#@{terminal.color0}"))))
 '(ansi-color-red ((t (:foreground "#@{terminal.color1}" :background "#@{terminal.color1}"))))
 '(ansi-color-green ((t (:foreground "#@{terminal.color2}" :background "#@{terminal.color2}"))))
 '(ansi-color-yellow ((t (:foreground "#@{terminal.color3}" :background "#@{terminal.color3}"))))
 '(ansi-color-blue ((t (:foreground "#@{terminal.color4}" :background "#@{terminal.color4}"))))
 '(ansi-color-magenta ((t (:foreground "#@{terminal.color5}" :background "#@{terminal.color5}"))))
 '(ansi-color-cyan ((t (:foreground "#@{terminal.color6}" :background "#@{terminal.color6}"))))
 '(ansi-color-white ((t (:foreground "#@{terminal.color7}" :background "#@{terminal.color7}"))))
 '(ansi-color-bright-black ((t (:foreground "#@{terminal.color8}" :background "#@{terminal.color8}"))))
 '(ansi-color-bright-red ((t (:foreground "#@{terminal.color9}" :background "#@{terminal.color9}"))))
 '(ansi-color-bright-green ((t (:foreground "#@{terminal.color10}" :background "#@{terminal.color10}"))))
 '(ansi-color-bright-yellow ((t (:foreground "#@{terminal.color11}" :background "#@{terminal.color11}"))))
 '(ansi-color-bright-blue ((t (:foreground "#@{terminal.color12}" :background "#@{terminal.color12}"))))
 '(ansi-color-bright-magenta ((t (:foreground "#@{terminal.color13}" :background "#@{terminal.color13}"))))
 '(ansi-color-bright-cyan ((t (:foreground "#@{terminal.color14}" :background "#@{terminal.color14}"))))
 '(ansi-color-bright-white ((t (:foreground "#@{terminal.color15}" :background "#@{terminal.color15}"))))
;; Emacs 31.1 face-spec-recalc replaces the defface spec when a theme
;; supplies one. Keep native conditions and non-colour attributes here.
 '(bookmark-face
   ((((class grayscale) (background light)) (:foreground "#@{color.text}" :distant-foreground "#@{color.text}"))
    (((class grayscale) (background dark)) (:foreground "#@{color.text}" :distant-foreground "#@{color.text}"))
    (((class color) (background light)) (:foreground "#@{color.text}" :distant-foreground "#@{color.text}"))
    (((class color) (background dark)) (:foreground "#@{color.text}" :distant-foreground "#@{color.text}"))))
 '(breakpoint-disabled
   ((((class color) (min-colors 88)) (:foreground "#@{color.textFaint}"))
    (((class color) (min-colors 8) (background light)) (:foreground "#@{color.textFaint}"))
    (((class color) (min-colors 8) (background dark)) (:foreground "#@{color.textFaint}"))
    (((type tty) (class mono)) (:inverse-video t :foreground "#@{color.textFaint}"))
    (t (:background "gray" :foreground "#@{color.textFaint}"))))
 '(completions-common-part
   ((((class color) (min-colors 16) (background light)) (:foreground "#@{color.text}"))
    (((class color) (min-colors 16) (background dark)) (:foreground "#@{color.text}"))))
 '(confusingly-reordered
   ((((supports :underline (:style wave))) (:underline (:style wave :color "#@{color.border}")))
    (t (:inherit warning))))
 '(cua-global-mark
   ((((min-colors 88) (class color)) (:foreground "#@{color.text}" :background "#@{color.surface}"))
    (((class color)) (:foreground "#@{color.text}" :background "#@{color.surface}"))
    (t (:weight bold :background "#@{color.surface}" :foreground "#@{color.text}"))))
 '(custom-button-mouse
   ((((type x w32 ns haiku pgtk android) (class color) (min-colors 88)) (:box (:line-width 2 :style released-button) :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (((type x w32 ns haiku pgtk android)) (:box (:line-width 2 :style released-button) :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (t (:inverse-video t :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))))
 '(custom-button-pressed-unraised
   ((default (:inherit custom-button-unraised))
    (((class color) (background light)) (:foreground "#@{color.text}"))
    (((class color) (background dark)) (:foreground "#@{color.text}"))))
 '(custom-button-pressed
   ((((type x w32 ns haiku pgtk android) (class color grayscale)) (:box (:line-width 2 :style pressed-button) :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (((type x w32 ns haiku pgtk android)) (:box (:line-width 2 :style pressed-button) :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (t (:inverse-video t :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))))
 '(custom-button
   ((((type x w32 ns haiku pgtk android) (class color) (min-colors 88)) (:box (:line-width 2 :style released-button) :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (((type x w32 ns haiku pgtk android)) (:box (:line-width 2 :style released-button) :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))))
 '(custom-changed
   ((((min-colors 88) (class color)) (:foreground "#@{badge.tone.accent.foreground}" :background "#@{badge.tone.accent.background}"))
    (((class color)) (:foreground "#@{badge.tone.accent.foreground}" :background "#@{badge.tone.accent.background}"))
    (t (:slant italic :background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))))
 '(custom-comment-tag
   ((((class color) (background dark)) (:foreground "#@{color.textFaint}"))
    (((class color) (background light)) (:foreground "#@{color.textFaint}"))
    (((class grayscale) (background light)) (:foreground "#@{color.textFaint}" :weight bold :slant italic))
    (((class grayscale) (background dark)) (:foreground "#@{color.textFaint}" :weight bold :slant italic))
    (t (:weight bold :foreground "#@{color.textFaint}"))))
 '(custom-comment
   ((((type tty)) (:background "#@{color.surface}" :foreground "#@{color.text}"))
    (((class grayscale color) (background light)) (:background "#@{color.surface}" :foreground "#@{color.text}"))
    (((class grayscale color) (background dark)) (:background "#@{color.surface}" :foreground "#@{color.text}"))
    (t (:slant italic :background "#@{color.surface}" :foreground "#@{color.text}"))))
 '(custom-group-tag-1
   ((default (:weight bold :height 1.2 :inherit variable-pitch))
    (((class color) (background dark)) (:foreground "#@{color.textHeading}"))
    (((min-colors 88) (class color) (background light)) (:foreground "#@{color.textHeading}"))
    (((class color) (background light)) (:foreground "#@{color.textHeading}"))))
 '(custom-group-tag
   ((default (:weight bold :height 1.2 :inherit variable-pitch))
    (((class color) (background dark)) (:foreground "#@{color.textHeading}"))
    (((min-colors 88) (class color) (background light)) (:foreground "#@{color.textHeading}"))
    (((class color) (background light)) (:foreground "#@{color.textHeading}"))
    (t (:weight bold :foreground "#@{color.textHeading}"))))
 '(custom-invalid
   ((((class color)) (:foreground "#@{badge.tone.danger.foreground}" :background "#@{badge.tone.danger.background}"))
    (t (:weight bold :slant italic :underline t :background "#@{badge.tone.danger.background}" :foreground "#@{badge.tone.danger.foreground}"))))
 '(custom-modified
   ((((min-colors 88) (class color)) (:foreground "#@{badge.tone.accent.foreground}" :background "#@{badge.tone.accent.background}"))
    (((class color)) (:foreground "#@{badge.tone.accent.foreground}" :background "#@{badge.tone.accent.background}"))
    (t (:slant italic :background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))))
 '(custom-rogue
   ((((class color)) (:foreground "#@{color.text}" :background "#@{color.surface}"))
    (t (:underline t :background "#@{color.surface}" :foreground "#@{color.text}"))))
 '(custom-set
   ((((min-colors 88) (class color)) (:foreground "#@{color.text}" :background "#@{color.surface}"))
    (((class color)) (:foreground "#@{color.text}" :background "#@{color.surface}"))
    (t (:slant italic :background "#@{color.surface}" :foreground "#@{color.text}"))))
 '(custom-state
   ((((class color) (background dark)) (:foreground "#@{color.success}"))
    (((class color) (background light)) (:foreground "#@{color.success}"))))
 '(custom-themed
   ((((min-colors 88) (class color)) (:foreground "#@{badge.tone.accent.foreground}" :background "#@{badge.tone.accent.background}"))
    (((class color)) (:foreground "#@{badge.tone.accent.foreground}" :background "#@{badge.tone.accent.background}"))
    (t (:slant italic :background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))))
 '(custom-variable-obsolete
   ((((class color) (background dark)) (:foreground "#@{color.text}"))
    (((min-colors 88) (class color) (background light)) (:foreground "#@{color.text}"))
    (((class color) (background light)) (:foreground "#@{color.text}"))
    (t (:slant italic :foreground "#@{color.text}"))))
 '(custom-variable-tag
   ((((class color) (background dark)) (:foreground "#@{color.text}" :weight bold))
    (((min-colors 88) (class color) (background light)) (:foreground "#@{color.text}" :weight bold))
    (((class color) (background light)) (:foreground "#@{color.text}" :weight bold))
    (t (:weight bold :foreground "#@{color.text}"))))
 '(diary
   ((((min-colors 88) (class color) (background light)) (:foreground "#@{color.warning}"))
    (((class color) (background light)) (:foreground "#@{color.warning}"))
    (((min-colors 88) (class color) (background dark)) (:foreground "#@{color.warning}"))
    (((class color) (background dark)) (:foreground "#@{color.warning}"))
    (t (:weight bold :foreground "#@{color.warning}"))))
 '(diff-added
   ((default (:inherit diff-changed))
    (((class color) (min-colors 257) (background light)) (:background "#@{badge.tone.success.background}" :extend t :foreground "#@{badge.tone.success.foreground}"))
    (((class color) (min-colors 88) (background light)) (:background "#@{badge.tone.success.background}" :extend t :foreground "#@{badge.tone.success.foreground}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{badge.tone.success.background}" :extend t :foreground "#@{badge.tone.success.foreground}"))
    (((class color)) (:foreground "#@{badge.tone.success.foreground}" :extend t :background "#@{badge.tone.success.background}"))))
 '(diff-changed-unspecified
   ((default (:inherit diff-changed))
    (((class color) (min-colors 88) (background light)) (:background "#@{badge.tone.warning.background}" :extend t :foreground "#@{badge.tone.warning.foreground}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{badge.tone.warning.background}" :extend t :foreground "#@{badge.tone.warning.foreground}"))
    (((class color)) (:foreground "#@{badge.tone.warning.foreground}" :extend t :background "#@{badge.tone.warning.background}"))))
 '(diff-error
   ((((class color)) (:foreground "#@{badge.tone.danger.foreground}" :background "#@{badge.tone.danger.background}" :weight bold))
    (t (:weight bold :background "#@{badge.tone.danger.background}" :foreground "#@{badge.tone.danger.foreground}"))))
 '(diff-file-header
   ((((class color) (min-colors 88) (background light)) (:background "#@{color.surfaceRaised}" :weight bold :extend t :foreground "#@{color.text}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{color.surfaceRaised}" :weight bold :extend t :foreground "#@{color.text}"))
    (((class color)) (:foreground "#@{color.text}" :weight bold :extend t :background "#@{color.surfaceRaised}"))
    (t (:weight bold :extend t :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))))
 '(diff-header
   ((((class color) (min-colors 88) (background light)) (:background "#@{color.surfaceRaised}" :extend t :foreground "#@{color.text}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{color.surfaceRaised}" :extend t :foreground "#@{color.text}"))
    (((class color)) (:foreground "#@{color.text}" :weight bold :extend t :background "#@{color.surfaceRaised}"))
    (t (:weight bold :extend t :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))))
 '(diff-refine-added
   ((default (:inherit diff-refine-changed))
    (((class color) (min-colors 257) (background light)) (:background "#@{color.surface}" :foreground "#@{color.text}"))
    (((class color) (min-colors 88) (background light)) (:background "#@{color.surface}" :foreground "#@{color.text}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{color.surface}" :foreground "#@{color.text}"))))
 '(diff-refine-changed
   ((((class color) (min-colors 88) (background light)) (:background "#@{badge.tone.warning.background}" :foreground "#@{badge.tone.warning.foreground}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{badge.tone.warning.background}" :foreground "#@{badge.tone.warning.foreground}"))
    (t (:inverse-video t :background "#@{badge.tone.warning.background}" :foreground "#@{badge.tone.warning.foreground}"))))
 '(diff-refine-removed
   ((default (:inherit diff-refine-changed))
    (((class color) (min-colors 257) (background light)) (:background "#@{color.surface}" :foreground "#@{color.text}"))
    (((class color) (min-colors 88) (background light)) (:background "#@{color.surface}" :foreground "#@{color.text}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{color.surface}" :foreground "#@{color.text}"))))
 '(diff-removed
   ((default (:inherit diff-changed))
    (((class color) (min-colors 257) (background light)) (:background "#@{badge.tone.danger.background}" :extend t :foreground "#@{badge.tone.danger.foreground}"))
    (((class color) (min-colors 88) (background light)) (:background "#@{badge.tone.danger.background}" :extend t :foreground "#@{badge.tone.danger.foreground}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{badge.tone.danger.background}" :extend t :foreground "#@{badge.tone.danger.foreground}"))
    (((class color)) (:foreground "#@{badge.tone.danger.foreground}" :extend t :background "#@{badge.tone.danger.background}"))))
 '(dired-broken-symlink
   ((((class color)) (:foreground "#@{badge.tone.danger.foreground}" :background "#@{badge.tone.danger.background}" :weight bold))
    (t (:weight bold :slant italic :underline t :background "#@{badge.tone.danger.background}" :foreground "#@{badge.tone.danger.foreground}"))))
 '(ebrowse-member-attribute
   ((((min-colors 88)) (:foreground "#@{terminal.color3}"))
    (t (:foreground "#@{terminal.color3}"))))
 '(ebrowse-progress
   ((((min-colors 88)) (:background "#@{color.surface}" :foreground "#@{color.text}"))
    (t (:background "#@{color.surface}" :foreground "#@{color.text}"))))
 '(ebrowse-root-class
   ((((min-colors 88)) (:weight bold :foreground "#@{terminal.color4}"))
    (t (:weight bold :foreground "#@{terminal.color4}"))))
 '(ebrowse-tree-mark
   ((((min-colors 88)) (:foreground "#@{color.text}"))
    (t (:foreground "#@{color.text}"))))
 '(edebug-disabled-breakpoint
   ((((class color) (min-colors 88) (background light)) (:background "#@{color.surface}" :extend t :foreground "#@{color.text}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{color.surface}" :extend t :foreground "#@{color.text}"))))
 '(ediff-current-diff-A
   ((((class color) (min-colors 88) (background light)) (:background "#@{badge.tone.danger.background}" :extend t :foreground "#@{badge.tone.danger.foreground}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{badge.tone.danger.background}" :extend t :foreground "#@{badge.tone.danger.foreground}"))
    (((class color) (min-colors 16)) (:foreground "#@{badge.tone.danger.foreground}" :background "#@{badge.tone.danger.background}" :extend t))
    (((class color)) (:foreground "#@{badge.tone.danger.foreground}" :background "#@{badge.tone.danger.background}" :extend t))
    (t (:inverse-video t :extend t :background "#@{badge.tone.danger.background}" :foreground "#@{badge.tone.danger.foreground}"))))
 '(ediff-current-diff-Ancestor
   ((((class color) (min-colors 88) (background light)) (:background "#@{badge.tone.info.background}" :extend t :foreground "#@{badge.tone.info.foreground}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{badge.tone.info.background}" :extend t :foreground "#@{badge.tone.info.foreground}"))
    (((class color) (min-colors 16) (background light)) (:background "#@{badge.tone.info.background}" :extend t :foreground "#@{badge.tone.info.foreground}"))
    (((class color) (min-colors 16) (background dark)) (:background "#@{badge.tone.info.background}" :extend t :foreground "#@{badge.tone.info.foreground}"))
    (((class color)) (:foreground "#@{badge.tone.info.foreground}" :background "#@{badge.tone.info.background}" :extend t))
    (t (:inverse-video t :extend t :background "#@{badge.tone.info.background}" :foreground "#@{badge.tone.info.foreground}"))))
 '(ediff-current-diff-B
   ((((class color) (min-colors 88) (background light)) (:background "#@{badge.tone.success.background}" :extend t :foreground "#@{badge.tone.success.foreground}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{badge.tone.success.background}" :extend t :foreground "#@{badge.tone.success.foreground}"))
    (((class color) (min-colors 16)) (:foreground "#@{badge.tone.success.foreground}" :background "#@{badge.tone.success.background}" :extend t))
    (((class color)) (:foreground "#@{badge.tone.success.foreground}" :background "#@{badge.tone.success.background}" :weight bold :extend t))
    (t (:inverse-video t :extend t :background "#@{badge.tone.success.background}" :foreground "#@{badge.tone.success.foreground}"))))
 '(ediff-current-diff-C
   ((((class color) (min-colors 88) (background light)) (:background "#@{badge.tone.warning.background}" :extend t :foreground "#@{badge.tone.warning.foreground}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{badge.tone.warning.background}" :extend t :foreground "#@{badge.tone.warning.foreground}"))
    (((class color) (min-colors 16)) (:foreground "#@{badge.tone.warning.foreground}" :background "#@{badge.tone.warning.background}" :extend t))
    (((class color)) (:foreground "#@{badge.tone.warning.foreground}" :background "#@{badge.tone.warning.background}" :weight bold :extend t))
    (t (:inverse-video t :extend t :background "#@{badge.tone.warning.background}" :foreground "#@{badge.tone.warning.foreground}"))))
 '(ediff-fine-diff-A
   ((((class color) (min-colors 88) (background light)) (:background "#@{badge.tone.danger.background}" :foreground "#@{badge.tone.danger.foreground}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{badge.tone.danger.background}" :foreground "#@{badge.tone.danger.foreground}"))
    (((class color) (min-colors 16)) (:foreground "#@{badge.tone.danger.foreground}" :background "#@{badge.tone.danger.background}"))
    (((class color)) (:foreground "#@{badge.tone.danger.foreground}" :background "#@{badge.tone.danger.background}" :weight bold))
    (t (:underline t :stipple "gray3" :background "#@{badge.tone.danger.background}" :foreground "#@{badge.tone.danger.foreground}"))))
 '(ediff-fine-diff-Ancestor
   ((((class color) (min-colors 88) (background light)) (:background "#@{badge.tone.info.background}" :foreground "#@{badge.tone.info.foreground}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{badge.tone.info.background}" :foreground "#@{badge.tone.info.foreground}"))
    (((class color) (min-colors 16) (background light)) (:background "#@{badge.tone.info.background}" :foreground "#@{badge.tone.info.foreground}"))
    (((class color) (min-colors 16) (background dark)) (:background "#@{badge.tone.info.background}" :foreground "#@{badge.tone.info.foreground}"))
    (((class color)) (:foreground "#@{badge.tone.info.foreground}" :background "#@{badge.tone.info.background}"))
    (t (:underline t :stipple "gray3" :background "#@{badge.tone.info.background}" :foreground "#@{badge.tone.info.foreground}"))))
 '(ediff-fine-diff-B
   ((((class color) (min-colors 88) (background light)) (:background "#@{badge.tone.success.background}" :foreground "#@{badge.tone.success.foreground}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{badge.tone.success.background}" :foreground "#@{badge.tone.success.foreground}"))
    (((class color) (min-colors 16)) (:foreground "#@{badge.tone.success.foreground}" :background "#@{badge.tone.success.background}"))
    (((class color)) (:foreground "#@{badge.tone.success.foreground}" :background "#@{badge.tone.success.background}"))
    (t (:underline t :stipple "gray3" :background "#@{badge.tone.success.background}" :foreground "#@{badge.tone.success.foreground}"))))
 '(ediff-fine-diff-C
   ((((class color) (min-colors 88) (background light)) (:background "#@{badge.tone.warning.background}" :foreground "#@{badge.tone.warning.foreground}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{badge.tone.warning.background}" :foreground "#@{badge.tone.warning.foreground}"))
    (((type pc)) (:foreground "#@{badge.tone.warning.foreground}" :background "#@{badge.tone.warning.background}"))
    (((class color) (min-colors 16)) (:foreground "#@{badge.tone.warning.foreground}" :background "#@{badge.tone.warning.background}"))
    (((class color)) (:foreground "#@{badge.tone.warning.foreground}" :background "#@{badge.tone.warning.background}" :weight bold))
    (t (:underline t :stipple "gray3" :background "#@{badge.tone.warning.background}" :foreground "#@{badge.tone.warning.foreground}"))))
 '(edmacro-label
   ((default (:inherit bold))
    (((class color) (background dark)) (:foreground "#@{color.text}"))
    (((min-colors 88) (class color) (background light)) (:foreground "#@{color.text}"))
    (((class color) (background light)) (:foreground "#@{color.text}"))
    (t (:inherit bold :foreground "#@{color.text}"))))
 '(elisp-major-mode-name
   ((((background light)) (:foreground "#@{color.text}"))
    (((background dark)) (:foreground "#@{color.text}"))))
 '(elisp-rx
   ((((background light)) (:foreground "#@{terminal.color6}"))
    (((background dark)) (:foreground "#@{terminal.color6}"))))
 '(elisp-symbol-at-mouse
   ((((background light)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (((background dark)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))))
 '(elisp-symbol-role-definition
   ((default (:inherit font-lock-function-name-face))
    (((background light)) (:foreground "#@{terminal.color6}"))
    (((background dark)) (:foreground "#@{terminal.color6}"))))
 '(elisp-symbol-role
   ((default (:inherit font-lock-function-call-face))
    (((background light)) (:foreground "#@{terminal.color6}"))
    (((background dark)) (:foreground "#@{terminal.color6}"))))
 '(elisp-unknown-call
   ((default (:inherit elisp-function))
    (((background light)) (:foreground "#@{color.text}"))
    (((background dark)) (:foreground "#@{color.text}"))))
 '(emacs-authors-author
   ((((class color) (min-colors 88) (background light)) (:foreground "#@{color.text}" :weight bold :height 1.05 :inherit variable-pitch))
    (((class color) (min-colors 88) (background dark)) (:foreground "#@{color.text}" :weight bold :height 1.05 :inherit variable-pitch))
    (((supports :weight bold) (supports :height 1.05)) (:weight bold :height 1.05 :inherit variable-pitch :foreground "#@{color.text}"))
    (((supports :weight bold)) (:weight bold :inherit variable-pitch :foreground "#@{color.text}"))
    (t (:inherit variable-pitch :foreground "#@{color.text}"))))
 '(emacs-authors-descriptor
   ((((class color) (min-colors 88) (background light)) (:foreground "#@{color.text}" :inherit variable-pitch))
    (((class color) (min-colors 88) (background dark)) (:foreground "#@{color.text}" :inherit variable-pitch))
    (t (:inherit variable-pitch :foreground "#@{color.text}"))))
 '(epa-mark
   ((default (:weight bold))
    (((class color) (background dark)) (:foreground "#@{color.text}"))
    (((class color) (background light)) (:foreground "#@{color.text}"))))
 '(epa-string
   ((((class color) (background dark)) (:foreground "#@{terminal.color2}"))
    (((class color) (background light)) (:foreground "#@{terminal.color2}"))))
 '(erc-fill-wrap-merge-indicator-face
   ((((min-colors 88) (background light)) (:foreground "#@{color.accent}"))
    (((min-colors 16) (background light)) (:foreground "#@{color.accent}"))
    (((min-colors 16) (background dark)) (:foreground "#@{color.accent}"))
    (t (:inherit shadow :foreground "#@{color.accent}"))))
 '(ert-test-result-expected
   ((((class color) (background light)) (:background "#@{badge.tone.success.background}" :foreground "#@{badge.tone.success.foreground}"))
    (((class color) (background dark)) (:background "#@{badge.tone.success.background}" :foreground "#@{badge.tone.success.foreground}"))))
 '(ert-test-result-unexpected
   ((((class color) (background light)) (:background "#@{badge.tone.danger.background}" :foreground "#@{badge.tone.danger.foreground}"))
    (((class color) (background dark)) (:background "#@{badge.tone.danger.background}" :foreground "#@{badge.tone.danger.foreground}"))))
 '(erts-mode-specification-name
   ((((class color) (background dark)) (:foreground "#@{color.text}"))
    (((class color) (background light)) (:foreground "#@{color.text}"))
    (t (:weight bold :foreground "#@{color.text}"))))
 '(erts-mode-specification-value
   ((((class color) (background dark)) (:foreground "#@{color.text}"))
    (((class color) (background light)) (:foreground "#@{color.text}"))
    (t (:weight bold :foreground "#@{color.text}"))))
 '(escape-glyph
   ((((background dark)) (:foreground "#@{terminal.color6}"))
    (((type pc)) (:foreground "#@{terminal.color6}"))
    (t (:foreground "#@{terminal.color6}"))))
 '(eshell-prompt
   ((default (:weight bold))
    (((class color) (background light)) (:foreground "#@{color.info}"))
    (((class color) (background dark)) (:foreground "#@{color.info}"))))
 '(flymake-error
   ((((supports :underline (:style wave))) (:underline (:style wave :color "#@{color.danger}")))
    (t (:inherit error))))
 '(flymake-note
   ((((supports :underline (:style wave))) (:underline (:style wave :color "#@{color.info}")))
    (t (:inherit warning))))
 '(flymake-warning
   ((((supports :underline (:style wave))) (:underline (:style wave :color "#@{color.warning}")))
    (t (:inherit warning))))
 '(flyspell-duplicate
   ((((supports :underline (:style wave))) (:underline (:style wave :color "#@{color.warning}")))
    (t (:underline t :inherit warning))))
 '(flyspell-incorrect
   ((((supports :underline (:style wave))) (:underline (:style wave :color "#@{color.danger}")))
    (t (:underline t :inherit error))))
 '(gomoku-X
   ((((background light)) (:foreground "#@{color.text}" :weight bold))
    (((class color)) (:foreground "#@{color.text}" :weight bold))))
 '(header-line
   ((default (:inherit mode-line))
    (((type tty)) (:inverse-video nil :underline t :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (((class color grayscale) (background light)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}" :box nil))
    (((class color grayscale) (background dark)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}" :box nil))
    (((class mono) (background light)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}" :inverse-video nil :box nil :underline t))
    (((class mono) (background dark)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}" :inverse-video nil :box nil :underline t))))
 '(help-key-binding
   ((((class color) (min-colors 88) (background light)) (:background "#@{color.surface}" :foreground "#@{color.text}" :box (:line-width (-1 . -1) :color "#@{color.border}") :inherit fixed-pitch))
    (((class color) (min-colors 88) (background dark)) (:background "#@{color.surface}" :foreground "#@{color.text}" :box (:line-width (-1 . -1) :color "#@{color.border}") :inherit fixed-pitch))
    (((class color grayscale) (background light)) (:background "#@{color.surface}" :inherit fixed-pitch :foreground "#@{color.text}"))
    (((class color grayscale) (background dark)) (:background "#@{color.surface}" :inherit fixed-pitch :foreground "#@{color.text}"))
    (t (:background "#@{color.surface}" :inherit fixed-pitch :foreground "#@{color.text}"))))
 '(hexl-ascii-region
   ((((class color grayscale) (background light)) (:background "#@{color.surface}" :foreground "#@{color.text}" :box nil))
    (((class color grayscale) (background dark)) (:background "#@{color.surface}" :foreground "#@{color.text}" :box nil))))
 '(holiday
   ((((class color) (background light)) (:background "#@{badge.tone.warning.background}" :foreground "#@{badge.tone.warning.foreground}"))
    (((class color) (background dark)) (:background "#@{badge.tone.warning.background}" :foreground "#@{badge.tone.warning.foreground}"))
    (t (:inverse-video t :background "#@{badge.tone.warning.background}" :foreground "#@{badge.tone.warning.foreground}"))))
 '(homoglyph
   ((((background dark)) (:foreground "#@{terminal.color6}"))
    (((type pc)) (:foreground "#@{terminal.color6}"))
    (t (:foreground "#@{terminal.color6}"))))
 '(ido-indicator
   ((((min-colors 88) (class color)) (:foreground "#@{badge.tone.accent.foreground}" :background "#@{badge.tone.accent.background}" :width condensed))
    (((class color)) (:foreground "#@{badge.tone.accent.foreground}" :background "#@{badge.tone.accent.background}" :width condensed))
    (t (:inverse-video t :background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))))
 '(ido-only-match
   ((((class color)) (:foreground "#@{color.success}"))
    (t (:slant italic :foreground "#@{color.success}"))))
 '(ido-subdir
   ((((min-colors 88) (class color)) (:foreground "#@{color.text}"))
    (((class color)) (:foreground "#@{color.text}"))
    (t (:underline t :foreground "#@{color.text}"))))
 '(image-dired-thumb-flagged
   ((((class color) (min-colors 88) (background light)) (:background "#@{badge.tone.danger.background}" :foreground "#@{badge.tone.danger.foreground}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{badge.tone.danger.background}" :foreground "#@{badge.tone.danger.foreground}"))
    (((class color) (min-colors 16) (background light)) (:background "#@{badge.tone.danger.background}" :foreground "#@{badge.tone.danger.foreground}"))
    (((class color) (min-colors 16) (background dark)) (:background "#@{badge.tone.danger.background}" :foreground "#@{badge.tone.danger.foreground}"))
    (((class color) (min-colors 8)) (:background "#@{badge.tone.danger.background}" :foreground "#@{badge.tone.danger.foreground}"))
    (t (:inverse-video t :background "#@{badge.tone.danger.background}" :foreground "#@{badge.tone.danger.foreground}"))))
 '(image-dired-thumb-header-file-size
   ((((class color) (min-colors 88)) (:foreground "#@{color.text}"))
    (((class color) (min-colors 16)) (:foreground "#@{color.text}"))
    (default (:inherit header-line))))
 '(image-dired-thumb-mark
   ((((class color) (min-colors 16)) (:background "#@{badge.tone.warning.background}" :foreground "#@{badge.tone.warning.foreground}"))
    (((class color)) (:foreground "#@{badge.tone.warning.foreground}" :background "#@{badge.tone.warning.background}"))
    (default (:inherit header-line))))
 '(info-menu-star
   ((((class color)) (:foreground "#@{color.text}"))
    (t (:underline t :foreground "#@{color.text}"))))
 '(info-node
   ((((class color) (background light)) (:foreground "#@{color.text}" :weight bold :slant italic))
    (((class color) (background dark)) (:foreground "#@{color.text}" :weight bold :slant italic))
    (t (:weight bold :slant italic :foreground "#@{color.text}"))))
 '(info-title-1
   ((((type tty pc) (class color) (background light)) (:foreground "#@{color.textHeading}" :weight bold))
    (((type tty pc) (class color) (background dark)) (:foreground "#@{color.textHeading}" :weight bold))
    (t (:height 1.2 :inherit info-title-2 :foreground "#@{color.textHeading}"))))
 '(info-title-2
   ((((type tty pc) (class color)) (:foreground "#@{color.textHeading}" :weight bold))
    (t (:height 1.2 :inherit info-title-3 :foreground "#@{color.textHeading}"))))
 '(isearch-fail
   ((((class color) (min-colors 88) (background light)) (:background "RosyBrown1" :foreground "#@{color.text}"))
    (((class color) (min-colors 88) (background dark)) (:background "red4" :foreground "#@{color.text}"))
    (((class color) (min-colors 16)) (:background "red" :foreground "#@{color.text}"))
    (((class color) (min-colors 8)) (:background "red" :foreground "#@{color.text}"))
    (((class color grayscale)) (:foreground "#@{color.text}"))
    (t (:inverse-video t :foreground "#@{color.text}"))))
 '(landmark-font-lock-face-O
   ((((class color)) (:foreground "#@{terminal.color1}"))
    (t (:weight bold :foreground "#@{terminal.color1}"))))
 '(landmark-font-lock-face-X
   ((((class color)) (:foreground "#@{terminal.color2}"))
    (t (:weight bold :foreground "#@{terminal.color2}"))))
 '(line-number-major-tick
   ((((class color grayscale) (background light)) (:background "#@{color.surface}" :weight bold :foreground "#@{color.text}"))
    (((class color grayscale) (background dark)) (:background "#@{color.surface}" :weight bold :foreground "#@{color.text}"))
    (t (:inherit line-number :background "#@{color.surface}" :foreground "#@{color.text}"))))
 '(line-number-minor-tick
   ((((class color grayscale) (background light)) (:background "#@{color.surface}" :weight bold :foreground "#@{color.text}"))
    (((class color grayscale) (background dark)) (:background "#@{color.surface}" :weight bold :foreground "#@{color.text}"))
    (t (:inherit line-number :background "#@{color.surface}" :foreground "#@{color.text}"))))
 '(link-visited
   ((default (:inherit link))
    (((class color) (background light)) (:foreground "#@{color.info}"))
    (((class color) (background dark)) (:foreground "#@{color.info}"))))
 '(match
   ((((class color) (min-colors 88) (background light)) (:background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))
    (((class color) (min-colors 8) (background light)) (:background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))
    (((class color) (min-colors 8) (background dark)) (:background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))
    (((type tty) (class mono)) (:inverse-video t :background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))
    (t (:background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))))
 '(message-header-cc
   ((((class color) (background dark)) (:foreground "#@{color.text}" :weight bold))
    (((class color) (background light)) (:foreground "#@{color.text}"))
    (t (:weight bold :foreground "#@{color.text}"))))
 '(message-header-name
   ((((class color) (background dark)) (:foreground "#@{color.text}"))
    (((class color) (background light)) (:foreground "#@{color.text}"))
    (t (:weight bold :foreground "#@{color.text}"))))
 '(message-header-newsgroups
   ((((class color) (background dark)) (:foreground "#@{color.text}" :weight bold :slant italic))
    (((class color) (background light)) (:foreground "#@{color.text}" :weight bold :slant italic))
    (t (:weight bold :slant italic :foreground "#@{color.text}"))))
 '(message-header-other
   ((((class color) (background dark)) (:foreground "#@{color.text}"))
    (((class color) (background light)) (:foreground "#@{color.text}"))
    (t (:weight bold :slant italic :foreground "#@{color.text}"))))
 '(message-header-subject
   ((((class color) (background dark)) (:foreground "#@{color.textHeading}"))
    (((class color) (background light)) (:foreground "#@{color.textHeading}" :weight bold))
    (t (:weight bold :foreground "#@{color.textHeading}"))))
 '(message-header-to
   ((((class color) (background dark)) (:foreground "#@{color.text}" :weight bold))
    (((class color) (background light)) (:foreground "#@{color.text}" :weight bold))
    (t (:weight bold :slant italic :foreground "#@{color.text}"))))
 '(message-header-xheader
   ((((class color) (background dark)) (:foreground "#@{color.text}"))
    (((class color) (background light)) (:foreground "#@{color.text}"))
    (t (:weight bold :foreground "#@{color.text}"))))
 '(message-mml
   ((((class color) (background dark)) (:foreground "#@{terminal.color2}"))
    (((class color) (background light)) (:foreground "#@{terminal.color2}"))
    (t (:weight bold :foreground "#@{terminal.color2}"))))
 '(message-separator
   ((((class color) (background dark)) (:foreground "#@{color.textMuted}"))
    (((class color) (background light)) (:foreground "#@{color.textMuted}"))
    (t (:weight bold :foreground "#@{color.textMuted}"))))
 '(mode-line-highlight
   ((((supports :box t) (class color grayscale) (min-colors 88) (background light)) (:box (:line-width 2 :color "#@{color.border}" :style released-button)))
    (((supports :box t) (class color grayscale) (min-colors 88) (background dark)) (:box (:line-width 2 :color "#@{color.border}" :style released-button)))
    (t (:inherit highlight))))
 '(newsticker-enclosure-face
   ((default (:weight bold))
    (((class color) (background dark)) (:background "#@{color.surface}" :foreground "#@{color.text}"))
    (((class color) (background light)) (:background "#@{color.surface}" :foreground "#@{color.text}"))))
 '(newsticker-extra-face
   ((default (:slant italic :height 0.8))
    (((class color) (background dark)) (:foreground "#@{color.textFaint}"))
    (((class color) (background light)) (:foreground "#@{color.textFaint}"))))
 '(newsticker-feed-face
   ((default (:weight bold :height 1.2))
    (((class color) (background dark)) (:foreground "#@{color.text}"))
    (((class color) (background light)) (:foreground "#@{color.text}"))))
 '(newsticker-immortal-item-face
   ((default (:weight bold :slant italic))
    (((class color) (background dark)) (:foreground "#@{color.warning}"))
    (((class color) (background light)) (:foreground "#@{color.warning}"))))
 '(newsticker-old-item-face
   ((default (:weight bold))
    (((class color) (background dark)) (:foreground "#@{color.text}"))
    (((class color) (background light)) (:foreground "#@{color.text}"))))
 '(newsticker-treeview-face
   ((((class color) (background dark)) (:foreground "#@{color.text}"))
    (((class color) (background light)) (:foreground "#@{color.text}"))))
 '(newsticker-treeview-immortal-face
   ((default (:inherit newsticker-treeview-face :slant italic))
    (((class color) (background dark)) (:foreground "#@{color.warning}"))
    (((class color) (background light)) (:foreground "#@{color.warning}"))))
 '(newsticker-treeview-selection-face
   ((((class color) (background dark)) (:background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))
    (((class color) (background light)) (:background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))))
 '(nobreak-hyphen
   ((((background dark)) (:foreground "#@{terminal.color6}"))
    (((type pc)) (:foreground "#@{terminal.color6}"))
    (t (:foreground "#@{terminal.color6}"))))
 '(nobreak-space
   ((((class color) (min-colors 88)) (:inherit escape-glyph :underline t :background "#@{color.infoSubtle}" :foreground "#@{color.text}"))
    (((class color) (min-colors 8)) (:background "#@{color.infoSubtle}" :foreground "#@{color.text}"))
    (t (:inverse-video t :background "#@{color.infoSubtle}" :foreground "#@{color.text}"))))
 '(org-dispatcher-highlight
   ((default (:weight bold))
    (((class color) (min-colors 88) (background dark)) (:background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))
    (((class color) (min-colors 88) (background light)) (:background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))
    (((class color) (min-colors 16) (background dark)) (:foreground "#@{badge.tone.accent.foreground}" :background "#@{badge.tone.accent.background}"))
    (((class color) (min-colors 16) (background light)) (:foreground "#@{badge.tone.accent.foreground}" :background "#@{badge.tone.accent.background}"))
    (t (:inverse-video t :background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))))
 '(package-mark-delete-line
   ((((class color) (background light)) (:background "#@{badge.tone.danger.background}" :extend t :foreground "#@{badge.tone.danger.foreground}"))
    (((class color) (background dark)) (:background "#@{badge.tone.danger.background}" :extend t :foreground "#@{badge.tone.danger.foreground}"))
    (t (:inherit (highlight) :extend t :background "#@{badge.tone.danger.background}" :foreground "#@{badge.tone.danger.foreground}"))))
 '(package-mark-install-line
   ((((class color) (background light)) (:background "#@{badge.tone.success.background}" :extend t :foreground "#@{badge.tone.success.foreground}"))
    (((class color) (background dark)) (:background "#@{badge.tone.success.background}" :extend t :foreground "#@{badge.tone.success.foreground}"))
    (t (:inherit (highlight) :extend t :background "#@{badge.tone.success.background}" :foreground "#@{badge.tone.success.foreground}"))))
 '(prolog-builtin-face
   ((((class color) (background light)) (:foreground "#@{terminal.color5}"))
    (((class color) (background dark)) (:foreground "#@{terminal.color5}"))
    (((class grayscale) (background light)) (:foreground "#@{terminal.color5}" :weight bold))
    (((class grayscale) (background dark)) (:foreground "#@{terminal.color5}" :weight bold))
    (t (:weight bold :foreground "#@{terminal.color5}"))))
 '(rcirc-bright-nick
   ((((class grayscale) (background light)) (:foreground "#@{terminal.color6}" :weight bold :underline t))
    (((class grayscale) (background dark)) (:foreground "#@{terminal.color6}" :weight bold :underline t))
    (((class color) (min-colors 88) (background light)) (:foreground "#@{terminal.color6}"))
    (((class color) (min-colors 88) (background dark)) (:foreground "#@{terminal.color6}"))
    (((class color) (min-colors 16) (background light)) (:foreground "#@{terminal.color6}"))
    (((class color) (min-colors 16) (background dark)) (:foreground "#@{terminal.color6}"))
    (((class color) (min-colors 8)) (:foreground "#@{terminal.color6}"))
    (t (:weight bold :underline t :foreground "#@{terminal.color6}"))))
 '(rcirc-my-nick
   ((((class color) (min-colors 88) (background light)) (:foreground "#@{color.text}"))
    (((class color) (min-colors 88) (background dark)) (:foreground "#@{color.text}"))
    (((class color) (min-colors 16) (background light)) (:foreground "#@{color.text}"))
    (((class color) (min-colors 16) (background dark)) (:foreground "#@{color.text}"))
    (((class color) (min-colors 8)) (:foreground "#@{color.text}" :weight bold))
    (t (:inverse-video t :weight bold :foreground "#@{color.text}"))))
 '(rcirc-nick-in-message
   ((((class grayscale) (background light)) (:foreground "#@{terminal.color5}" :weight bold))
    (((class grayscale) (background dark)) (:foreground "#@{terminal.color5}" :weight bold))
    (((class color) (min-colors 88) (background light)) (:foreground "#@{terminal.color5}"))
    (((class color) (min-colors 88) (background dark)) (:foreground "#@{terminal.color5}"))
    (((class color) (min-colors 16) (background light)) (:foreground "#@{terminal.color5}"))
    (((class color) (min-colors 16) (background dark)) (:foreground "#@{terminal.color5}"))
    (((class color) (min-colors 8)) (:foreground "#@{terminal.color5}" :weight bold))
    (t (:weight bold :foreground "#@{terminal.color5}"))))
 '(rcirc-other-nick
   ((((class grayscale) (background light)) (:foreground "#@{terminal.color3}" :weight bold :slant italic))
    (((class grayscale) (background dark)) (:foreground "#@{terminal.color3}" :weight bold :slant italic))
    (((class color) (min-colors 88) (background light)) (:foreground "#@{terminal.color3}"))
    (((class color) (min-colors 88) (background dark)) (:foreground "#@{terminal.color3}"))
    (((class color) (min-colors 16) (background light)) (:foreground "#@{terminal.color3}"))
    (((class color) (min-colors 16) (background dark)) (:foreground "#@{terminal.color3}"))
    (((class color) (min-colors 8)) (:foreground "#@{terminal.color3}" :weight light))
    (t (:weight bold :slant italic :foreground "#@{terminal.color3}"))))
 '(rcirc-prompt
   ((((min-colors 88) (background dark)) (:foreground "#@{color.info}"))
    (((background dark)) (:foreground "#@{color.info}"))
    (t (:foreground "#@{color.info}"))))
 '(rcirc-server-prefix
   ((default (:inherit rcirc-server))
    (((class grayscale)) (:foreground "#@{color.danger}"))
    (((class color) (min-colors 16)) (:foreground "#@{color.danger}"))
    (((class color) (min-colors 8) (background light)) (:foreground "#@{color.danger}"))
    (((class color) (min-colors 8) (background dark)) (:foreground "#@{color.danger}"))))
 '(rcirc-server
   ((((class grayscale) (background light)) (:foreground "#@{color.text}" :weight bold :slant italic))
    (((class grayscale) (background dark)) (:foreground "#@{color.text}" :weight bold :slant italic))
    (((class color) (min-colors 88) (background light)) (:foreground "#@{color.text}"))
    (((class color) (min-colors 88) (background dark)) (:foreground "#@{color.text}"))
    (((class color) (min-colors 16) (background light)) (:foreground "#@{color.text}"))
    (((class color) (min-colors 16) (background dark)) (:foreground "#@{color.text}"))
    (((class color) (min-colors 8) (background light)) (:foreground "#@{color.text}"))
    (((class color) (min-colors 8) (background dark)) (:foreground "#@{color.text}"))
    (t (:weight bold :slant italic :foreground "#@{color.text}"))))
 '(reb-match-0
   ((((class color) (background light)) (:background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))
    (((class color) (background dark)) (:background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))
    (t (:inverse-video t :background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))))
 '(reb-match-1
   ((((class color) (background light)) (:background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))
    (((class color) (background dark)) (:background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))
    (t (:inverse-video t :background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))))
 '(reb-match-2
   ((((class color) (background light)) (:background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))
    (((class color) (background dark)) (:background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))
    (t (:inverse-video t :background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))))
 '(reb-match-3
   ((((min-colors 88) (class color) (background light)) (:background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))
    (((class color) (background light)) (:background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))
    (((class color) (background dark)) (:background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))
    (t (:inverse-video t :background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))))
 '(secondary-selection
   ((((class color) (min-colors 88) (background light)) (:background "#@{badge.tone.accent.background}" :extend t :foreground "#@{badge.tone.accent.foreground}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{badge.tone.accent.background}" :extend t :foreground "#@{badge.tone.accent.foreground}"))
    (((class color) (min-colors 16) (background light)) (:background "#@{badge.tone.accent.background}" :extend t :foreground "#@{badge.tone.accent.foreground}"))
    (((class color) (min-colors 16) (background dark)) (:background "#@{badge.tone.accent.background}" :extend t :foreground "#@{badge.tone.accent.foreground}"))
    (((class color) (min-colors 8)) (:background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}" :extend t))
    (t (:inverse-video t :background "#@{badge.tone.accent.background}" :foreground "#@{badge.tone.accent.foreground}"))))
 '(separator-line
   ((((type graphic) (background dark)) (:height 0.1 :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (((type graphic) (background light)) (:height 0.1 :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (t (:foreground "#@{color.text}" :underline t :background "#@{color.surfaceRaised}"))))
 '(smerge-base
   ((((class color) (min-colors 88) (background light)) (:background "#@{badge.tone.warning.background}" :extend t :foreground "#@{badge.tone.warning.foreground}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{badge.tone.warning.background}" :extend t :foreground "#@{badge.tone.warning.foreground}"))
    (((class color)) (:foreground "#@{badge.tone.warning.foreground}" :extend t :background "#@{badge.tone.warning.background}"))))
 '(smerge-lower
   ((((class color) (min-colors 88) (background light)) (:background "#@{badge.tone.success.background}" :extend t :foreground "#@{badge.tone.success.foreground}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{badge.tone.success.background}" :extend t :foreground "#@{badge.tone.success.foreground}"))
    (((class color)) (:foreground "#@{badge.tone.success.foreground}" :extend t :background "#@{badge.tone.success.background}"))))
 '(smerge-refined-added
   ((default (:inherit smerge-refined-change))
    (((class color) (min-colors 88) (background light)) (:background "#@{badge.tone.success.background}" :foreground "#@{badge.tone.success.foreground}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{badge.tone.success.background}" :foreground "#@{badge.tone.success.foreground}"))
    (t (:inverse-video t :background "#@{badge.tone.success.background}" :foreground "#@{badge.tone.success.foreground}"))))
 '(smerge-refined-removed
   ((default (:inherit smerge-refined-change))
    (((class color) (min-colors 88) (background light)) (:background "#@{badge.tone.danger.background}" :foreground "#@{badge.tone.danger.foreground}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{badge.tone.danger.background}" :foreground "#@{badge.tone.danger.foreground}"))
    (t (:inverse-video t :background "#@{badge.tone.danger.background}" :foreground "#@{badge.tone.danger.foreground}"))))
 '(smerge-upper
   ((((class color) (min-colors 88) (background light)) (:background "#@{badge.tone.danger.background}" :extend t :foreground "#@{badge.tone.danger.foreground}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{badge.tone.danger.background}" :extend t :foreground "#@{badge.tone.danger.foreground}"))
    (((class color)) (:foreground "#@{badge.tone.danger.foreground}" :extend t :background "#@{badge.tone.danger.background}"))))
 '(speedbar-button-face
   ((((class color) (background light)) (:foreground "#@{color.text}"))
    (((class color) (background dark)) (:foreground "#@{color.text}"))))
 '(speedbar-directory-face
   ((((class color) (background light)) (:foreground "#@{color.text}"))
    (((class color) (background dark)) (:foreground "#@{color.text}"))))
 '(speedbar-file-face
   ((((class color) (background light)) (:foreground "#@{color.text}"))
    (((class color) (background dark)) (:foreground "#@{color.text}"))
    (t (:weight bold :foreground "#@{color.text}"))))
 '(speedbar-highlight-face
   ((((class color) (background light)) (:background "#@{color.surface}" :foreground "#@{color.text}"))
    (((class color) (background dark)) (:background "#@{color.surface}" :foreground "#@{color.text}"))))
 '(speedbar-selected-face
   ((((class color) (background light)) (:foreground "#@{color.text}" :underline t))
    (((class color) (background dark)) (:foreground "#@{color.text}" :underline t))
    (t (:underline t :foreground "#@{color.text}"))))
 '(speedbar-separator-face
   ((((class color) (background light)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}" :overline "#@{color.border}"))
    (((class color) (background dark)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}" :overline "#@{color.border}"))
    (((class grayscale monochrome) (background light)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}" :overline "#@{color.border}"))
    (((class grayscale monochrome) (background dark)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}" :overline "#@{color.border}"))))
 '(speedbar-tag-face
   ((((class color) (background light)) (:foreground "#@{color.text}"))
    (((class color) (background dark)) (:foreground "#@{color.text}"))))
 '(tab-bar-tab-highlight
   ((((class color) (min-colors 88) (background light)) (:box (:line-width 1 :style released-button) :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (((class color) (min-colors 88) (background dark)) (:box (:line-width 1 :style released-button) :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (t (:inverse-video nil :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))))
 '(tab-bar-tab-inactive
   ((default (:inherit tab-bar-tab))
    (((class color) (min-colors 88) (background light)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (t (:inverse-video t :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))))
 '(tab-bar-tab
   ((default (:inherit tab-bar))
    (((class color) (min-colors 88) (background light)) (:box (:line-width 1 :style released-button) :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (((class color) (min-colors 88) (background dark)) (:box (:line-width 1 :style released-button) :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (t (:inverse-video nil :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))))
 '(tab-bar
   ((((class color) (min-colors 88) (background light)) (:inherit variable-pitch :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (((class color) (min-colors 88) (background dark)) (:inherit variable-pitch :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (((class mono)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (t (:inverse-video t :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))))
 '(tab-line-highlight
   ((((class color) (min-colors 88) (background light)) (:box (:line-width 1 :style released-button) :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (((class color) (min-colors 88) (background dark)) (:box (:line-width 1 :style released-button) :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (t (:inverse-video nil :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))))
 '(tab-line-tab-current
   ((default (:inherit tab-line-tab))
    (((class color) (min-colors 88) (background light)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))))
 '(tab-line-tab-inactive
   ((default (:inherit tab-line-tab))
    (((class color) (min-colors 88) (background light)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (((class color) (min-colors 88) (background dark)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (t (:inverse-video t :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))))
 '(tab-line-tab
   ((default (:inherit tab-line))
    (((class color) (min-colors 88) (background light)) (:box (:line-width 1 :style released-button) :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (((class color) (min-colors 88) (background dark)) (:box (:line-width 1 :style released-button) :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (t (:inverse-video nil :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))))
 '(tab-line
   ((((class color) (min-colors 88) (background light)) (:inherit variable-pitch :height 0.9 :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (((class color) (min-colors 88) (background dark)) (:inherit variable-pitch :height 0.9 :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (((class mono)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (t (:inverse-video t :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))))
 '(table-cell
   ((((min-colors 88) (class color)) (:foreground "#@{color.text}" :background "#@{color.surfaceRaised}"))
    (((class color)) (:foreground "#@{color.text}" :background "#@{color.surfaceRaised}"))
    (t (:weight bold :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))))
 '(todo-category-string
   ((((class grayscale) (background light)) (:foreground "#@{terminal.color2}" :weight bold))
    (((class grayscale) (background dark)) (:foreground "#@{terminal.color2}" :weight bold))
    (((class color) (min-colors 88) (background light)) (:foreground "#@{terminal.color2}"))
    (((class color) (min-colors 88) (background dark)) (:foreground "#@{terminal.color2}"))
    (((class color) (min-colors 16) (background light)) (:foreground "#@{terminal.color2}"))
    (((class color) (min-colors 16) (background dark)) (:foreground "#@{terminal.color2}"))
    (((class color) (min-colors 8)) (:foreground "#@{terminal.color2}"))
    (t (:weight bold :underline t :foreground "#@{terminal.color2}"))))
 '(todo-comment
   ((((class grayscale) (background light)) (:foreground "#@{color.textFaint}" :weight bold :slant italic))
    (((class grayscale) (background dark)) (:foreground "#@{color.textFaint}" :weight bold :slant italic))
    (((class color) (min-colors 88) (background light)) (:foreground "#@{color.textFaint}"))
    (((class color) (min-colors 88) (background dark)) (:foreground "#@{color.textFaint}"))
    (((class color) (min-colors 16) (background light)) (:foreground "#@{color.textFaint}"))
    (((class color) (min-colors 16) (background dark)) (:foreground "#@{color.textFaint}"))
    (((class color) (min-colors 8) (background light)) (:foreground "#@{color.textFaint}"))
    (((class color) (min-colors 8) (background dark)) (:foreground "#@{color.textFaint}"))
    (t (:weight bold :slant italic :foreground "#@{color.textFaint}"))))
 '(todo-diary-expired
   ((default (:weight bold))
    (((class color) (min-colors 88) (background light)) (:foreground "#@{color.warning}"))
    (((class color) (min-colors 88) (background dark)) (:foreground "#@{color.warning}"))
    (((class color) (min-colors 16) (background light)) (:foreground "#@{color.warning}"))
    (((class color) (min-colors 16) (background dark)) (:foreground "#@{color.warning}"))
    (((class color) (min-colors 8)) (:foreground "#@{color.warning}"))
    (t (:inverse-video t :foreground "#@{color.warning}"))))
 '(todo-done-sep
   ((((class grayscale) (background light)) (:foreground "#@{color.success}" :weight bold))
    (((class grayscale) (background dark)) (:foreground "#@{color.success}" :weight bold))
    (((class color) (min-colors 88) (background light)) (:foreground "#@{color.success}"))
    (((class color) (min-colors 88) (background dark)) (:foreground "#@{color.success}"))
    (((class color) (min-colors 16) (background light)) (:foreground "#@{color.success}"))
    (((class color) (min-colors 16) (background dark)) (:foreground "#@{color.success}"))
    (((class color) (min-colors 8)) (:foreground "#@{color.success}" :weight bold))
    (t (:weight bold :foreground "#@{color.success}"))))
 '(todo-done
   ((((class grayscale) (background light)) (:foreground "#@{color.success}" :weight bold))
    (((class grayscale) (background dark)) (:foreground "#@{color.success}" :weight bold))
    (((class color) (min-colors 88) (background light)) (:foreground "#@{color.success}"))
    (((class color) (min-colors 88) (background dark)) (:foreground "#@{color.success}"))
    (((class color) (min-colors 16) (background light)) (:foreground "#@{color.success}"))
    (((class color) (min-colors 16) (background dark)) (:foreground "#@{color.success}"))
    (((class color) (min-colors 8)) (:foreground "#@{color.success}" :weight bold))
    (t (:weight bold :foreground "#@{color.success}"))))
 '(todo-nondiary
   ((((class grayscale) (background light)) (:foreground "#@{color.warning}" :weight bold))
    (((class grayscale) (background dark)) (:foreground "#@{color.warning}" :weight bold))
    (((class color) (min-colors 88) (background light)) (:foreground "#@{color.warning}"))
    (((class color) (min-colors 88) (background dark)) (:foreground "#@{color.warning}"))
    (((class color) (min-colors 16) (background light)) (:foreground "#@{color.warning}"))
    (((class color) (min-colors 16) (background dark)) (:foreground "#@{color.warning}"))
    (((class color) (min-colors 8)) (:foreground "#@{color.warning}"))
    (t (:weight bold :underline t :foreground "#@{color.warning}"))))
 '(todo-top-priority
   ((default (:weight bold))
    (((class grayscale) (background light)) (:foreground "#@{color.danger}" :slant italic))
    (((class grayscale) (background dark)) (:foreground "#@{color.danger}" :slant italic))
    (((class color) (min-colors 88) (background light)) (:foreground "#@{color.danger}"))
    (((class color) (min-colors 88) (background dark)) (:foreground "#@{color.danger}"))
    (((class color) (min-colors 16) (background light)) (:foreground "#@{color.danger}"))
    (((class color) (min-colors 16) (background dark)) (:foreground "#@{color.danger}"))
    (((class color) (min-colors 8) (background light)) (:foreground "#@{color.danger}"))
    (((class color) (min-colors 8) (background dark)) (:foreground "#@{color.danger}"))
    (t (:slant italic :foreground "#@{color.danger}"))))
 '(tool-bar
   ((default (:box (:line-width 1 :style released-button) :foreground "#@{color.text}"))
    (((type haiku)) (:foreground "#@{color.text}" :background "#@{color.surface}"))
    (((type x w32 ns pgtk android) (class color)) (:background "#@{color.surface}" :foreground "#@{color.text}"))
    (((type x) (class mono)) (:background "#@{color.surface}" :foreground "#@{color.text}"))))
 '(tooltip
   ((((class color)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}" :inherit variable-pitch))
    (t (:inherit variable-pitch :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))))
 '(trailing-whitespace
   ((((class color) (background light)) (:background "#@{color.infoSubtle}" :foreground "#@{color.text}"))
    (((class color) (background dark)) (:background "#@{color.infoSubtle}" :foreground "#@{color.text}"))
    (t (:inverse-video t :background "#@{color.infoSubtle}" :foreground "#@{color.text}"))))
 '(transient-key-exit
   ((((class color) (background light)) (:inherit transient-key :foreground "#@{color.danger}"))
    (((class color) (background dark)) (:inherit transient-key :foreground "#@{color.danger}"))))
 '(transient-key-noop
   ((((class color) (background light)) (:inherit transient-key :foreground "#@{color.textFaint}"))
    (((class color) (background dark)) (:inherit transient-key :foreground "#@{color.textFaint}"))))
 '(transient-key-recurse
   ((((class color) (background light)) (:inherit transient-key :foreground "#@{color.info}"))
    (((class color) (background dark)) (:inherit transient-key :foreground "#@{color.info}"))))
 '(transient-key-return
   ((((class color) (background light)) (:inherit transient-key :foreground "#@{color.warning}"))
    (((class color) (background dark)) (:inherit transient-key :foreground "#@{color.warning}"))))
 '(transient-key-stack
   ((((class color) (background light)) (:inherit transient-key :foreground "#@{color.accent}"))
    (((class color) (background dark)) (:inherit transient-key :foreground "#@{color.accent}"))))
 '(transient-key-stay
   ((((class color) (background light)) (:inherit transient-key :foreground "#@{color.success}"))
    (((class color) (background dark)) (:inherit transient-key :foreground "#@{color.success}"))))
 '(tty-menu-disabled-face
   ((((class color) (min-colors 16)) (:foreground "#@{color.text}" :background "#@{color.surface}"))
    (((class color)) (:foreground "#@{color.text}" :background "#@{color.surface}"))
    (t (:inherit shadow :background "#@{color.surface}" :foreground "#@{color.text}"))))
 '(tty-menu-enabled-face
   ((((class color)) (:foreground "#@{color.text}" :background "#@{color.surface}" :weight bold))
    (t (:weight bold :background "#@{color.surface}" :foreground "#@{color.text}"))))
 '(tty-menu-selected-face
   ((((class color)) (:background "#@{color.surface}" :foreground "#@{color.text}"))
    (t (:inverse-video t :background "#@{color.surface}" :foreground "#@{color.text}"))))
 '(vera-font-lock-function
   ((((class color) (background light)) (:foreground "#@{terminal.color4}"))
    (((class color) (background dark)) (:foreground "#@{terminal.color4}"))
    (t (:slant italic :weight bold :foreground "#@{terminal.color4}"))))
 '(vera-font-lock-interface
   ((((class color) (background light)) (:foreground "#@{color.text}"))
    (((class color) (background dark)) (:foreground "#@{color.text}"))
    (t (:slant italic :weight bold :foreground "#@{color.text}"))))
 '(vera-font-lock-number
   ((((class color) (background light)) (:foreground "#@{terminal.color3}"))
    (((class color) (background dark)) (:foreground "#@{terminal.color3}"))
    (t (:slant italic :weight bold :foreground "#@{terminal.color3}"))))
 '(which-func
   ((((class color) (min-colors 88) (background light)) (:inherit font-lock-function-name-face :foreground "#@{terminal.color4}"))
    (((class grayscale mono) (background dark)) (:inherit font-lock-function-name-face :foreground "#@{terminal.color4}"))
    (((class color) (background light)) (:inherit font-lock-function-name-face :foreground "#@{terminal.color4}"))
    (((class color) (min-colors 88) (background dark)) (:foreground "#@{terminal.color4}"))
    (((background dark)) (:foreground "#@{terminal.color4}"))
    (t (:foreground "#@{terminal.color4}"))))
 '(whitespace-hspace
   ((((class color) (background dark)) (:background "#@{color.surface}" :foreground "#@{color.text}"))
    (((class color) (background light)) (:background "#@{color.surface}" :foreground "#@{color.text}"))
    (t (:inverse-video t :background "#@{color.surface}" :foreground "#@{color.text}"))))
 '(whitespace-newline
   ((default (:weight normal))
    (((class color) (background dark)) (:foreground "#@{color.textFaint}"))
    (((class color) (min-colors 88) (background light)) (:foreground "#@{color.textFaint}"))
    (((class color) (background light)) (:foreground "#@{color.textFaint}"))
    (t (:underline t :foreground "#@{color.textFaint}"))))
 '(whitespace-space
   ((((class color) (background dark)) (:background "#@{color.surface}" :foreground "#@{color.text}"))
    (((class color) (background light)) (:background "#@{color.surface}" :foreground "#@{color.text}"))
    (t (:inverse-video t :background "#@{color.surface}" :foreground "#@{color.text}"))))
 '(whitespace-tab
   ((((class color) (background dark)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (((class color) (background light)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (t (:inverse-video t :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))))
 '(widget-field
   ((((type tty)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}" :extend t))
    (((class grayscale color) (background light)) (:background "#@{color.surfaceRaised}" :box (:line-width (1 . -1) :color "#@{color.borderControl}") :extend t :foreground "#@{color.text}"))
    (((class grayscale color) (background dark)) (:background "#@{color.surfaceRaised}" :box (:line-width (1 . -1) :color "#@{color.borderControl}") :extend t :foreground "#@{color.text}"))
    (((background light)) (:background "#@{color.surfaceRaised}" :box (:line-width (1 . -1) :color "#@{color.borderControl}") :extend t :foreground "#@{color.text}"))
    (((background dark)) (:background "#@{color.surfaceRaised}" :box (:line-width (1 . -1) :color "#@{color.borderControl}") :extend t :foreground "#@{color.text}"))
    (t (:slant italic :extend t :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))))
 '(widget-single-line-field
   ((((type tty)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (((class grayscale color) (background light)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (((class grayscale color) (background dark)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (((background light)) (:stipple "gray3" :extend t :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (t (:slant italic :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))))
 '(window-tool-bar-button-checked-hover
   ((default (:inherit tab-line))
    (((class color) (min-colors 88) (supports :box t)) (:box (:line-width -1 :style pressed-button) :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (((class color)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (t (:inverse-video t :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))))
 '(window-tool-bar-button-checked
   ((default (:inherit tab-line))
    (((supports :box t)) (:box (:line-width -1 :style pressed-button) :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (((class color)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (t (:inverse-video t :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))))
 '(window-tool-bar-button-disabled
   ((default (:inherit tab-line))
    (((class color) (min-colors 88)) (:box (:line-width -1 :style released-button) :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (t (:inverse-video t :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))))
 '(window-tool-bar-button-hover
   ((default (:inherit tab-line))
    (((class color) (min-colors 88)) (:box (:line-width -1 :style released-button) :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (t (:inverse-video t :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))))
 '(window-tool-bar-button
   ((default (:inherit tab-line))
    (((class color) (min-colors 88) (supports :box t)) (:box (:line-width -1 :style released-button) :background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (((class color) (min-colors 88)) (:background "#@{color.surfaceRaised}" :foreground "#@{color.text}"))
    (t (:inverse-video t :background "#@{color.surfaceRaised}" :foreground "#@{color.text}")))))
(provide-theme 'vgs)
(enable-theme 'vgs)
