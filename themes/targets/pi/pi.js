import { readFileSync } from "node:fs";
import { join } from "node:path";
import { getAgentDir, Theme } from "@earendil-works/pi-coding-agent";

/** @param {import("@earendil-works/pi-coding-agent").ExtensionAPI} pi */
export default function (pi) {
  // Pi merges project settings over account settings before session_start.
  // A Theme instance selects our account file even if a project defines vgs.
  // Pi's public Theme constructor and ctx.ui.setTheme own parsing and display.
  pi.on("session_start", (_event, ctx) => {
    if (!ctx.hasUI) return;
    const { colors } = JSON.parse(readFileSync(join(getAgentDir(), "themes", "vgs.json"), "utf8"));
    const result = ctx.ui.setTheme(new Theme(colors, colors, ctx.ui.theme.getColorMode(), { name: "vgs" }));
    if (!result.success) throw new Error(result.error);
  });
}
