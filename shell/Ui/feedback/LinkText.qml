import QtQuick
import QtQuick.Templates as T
import qs.Commons
import qs.Ui

// Text with one cited substring as a link. The text property is plain
// text; every occurrence of `link` is drawn as a link and activates the
// component. `lineCount` is the wrapped label's line count, for owners that
// measure whether the message stayed on one line. Use it where a consumer
// surface cites a file that the core can open through `vgshell edit`.
// The focus ring goes round the first occurrence's words, `linkBox`, not
// the whole text, so a ring on a line of prose shows which words act.
// The box runs on to the spaces around the occurrence, so punctuation
// against it sits inside the ring, and the ring reaches sideways no
// further than one space less a pixel, so it touches no neighbouring word.
T.Control {
