# Theme attribution

## Community theme imports

Each package's palette and terminal colours come from its source repository, apart from the readability overrides in `docs/architecture/themes.md` § Catalog and the terminal readability lifts below. Wallpapers are credited in `BACKGROUNDS-ATTRIBUTION.md`.

| VGS theme | Source repository | License |
|-----------|-------------------|---------|
| `akane` | https://github.com/Grenish/omarchy-akane-theme | no LICENSE file |
| `amberbyte` | https://github.com/tahfizhabib/omarchy-amberbyte-theme | MIT |
| `arc-blueberry` | https://github.com/vale-c/omarchy-arc-blueberry | MIT |
| `arc-raiders` | https://github.com/rondilley/omarchy-arc_raiders-theme | GPL |
| `archwave` | https://github.com/davidguttman/archwave | no LICENSE file |
| `artzen` | https://github.com/tahfizhabib/omarchy-artzen-theme | no LICENSE file |
| `biscuit-de-mar` | https://github.com/OldJobobo/omarchy-biscuit-de-mar-dark-theme | no LICENSE file |
| `brutalism` | https://github.com/bjornramberg/omarchy-brutalism-theme | GPL |
| `coppernight` | https://github.com/hembramnishant50-glitch/omarchy-coppernight-theme | no LICENSE file |
| `cpunk` | https://github.com/stannorbvb-cmd/cpunk | no LICENSE file |
| `delorean` | https://github.com/jbnunn/omarchy-delorean-theme | MIT |
| `ember-n-ash` | https://github.com/Hydradevx/omarchy-ember-n-ash-theme | no LICENSE file |
| `event-horizon` | https://github.com/OldJobobo/omarchy-event-horizon-theme | no LICENSE file |
| `fireside` | https://github.com/bjarneo/omarchy-fireside-theme | no LICENSE file |
| `frankenstein` | https://github.com/twodogsdave/omarchy-frankenstein-theme | MIT |
| `ghost-pastel` | https://github.com/row-huh/omarchy-ghost-pastel-theme | no LICENSE file |
| `greek-noir` | https://github.com/HANCORE-linux/omarchy-greek-noir-theme | MIT |
| `gruvy-glass` | https://github.com/signaldirective/gruvy-glass | no LICENSE file |
| `harbordark` | https://github.com/HANCORE-linux/omarchy-harbordark-theme | MIT |
| `inkypinky` | https://github.com/HANCORE-linux/omarchy-inkypinky-theme | MIT |
| `kurayami` | https://github.com/bjornramberg/omarchy-kurayami-theme | GPL |
| `lowlight` | https://github.com/atif-1402/omarchy-lowlight-theme | no LICENSE file |
| `lunar` | https://github.com/pdfosborne/omarchy-lunar-theme | no LICENSE file |
| `mechanoonna` | https://github.com/HANCORE-linux/omarchy-mechanoonna-theme | MIT |
| `monokai` | https://github.com/bjarneo/omarchy-monokai-theme | no LICENSE file |
| `moon-orbit` | https://github.com/JJDizz1L/moon-orbit | MIT |
| `nagai-twilight` | https://github.com/mwaltzer/omarchy-nagai-twilight-theme | MIT |
| `nebulite` | https://github.com/atif-1402/omarchy-nebulite-theme | no LICENSE file |
| `oxford` | https://github.com/HANCORE-linux/omarchy-oxford-theme | MIT |
| `pmndrs` | https://github.com/leweyse/omarchy-pmndrs-theme | MIT |
| `reddcs` | https://github.com/mohamedredachakir/LINUX-OMARCHY-REDDCS | no LICENSE file |
| `reverie` | https://github.com/bjarneo/omarchy-reverie-theme | no LICENSE file |
| `roseofdune` | https://github.com/HANCORE-linux/omarchy-roseofdune-theme | MIT |
| `saga` | https://github.com/HANCORE-linux/omarchy-saga-theme | MIT |
| `sapphire` | https://github.com/HANCORE-linux/omarchy-sapphire-theme | MIT |
| `snow` | https://github.com/28bby/Snow-Theme | no LICENSE file |
| `soho` | https://github.com/bjarneo/omarchy-soho-theme | no LICENSE file |
| `synthwave84` | https://github.com/omacom-io/omarchy-synthwave84-theme | no LICENSE file |
| `thegreek` | https://github.com/HANCORE-linux/omarchy-thegreek-theme | MIT |
| `tycho` | https://github.com/leonardobetti/omarchy-tycho | MIT |
| `untitled` | https://github.com/niraletter/omarchy-untitled-theme | MIT |
| `vengeance` | https://github.com/Grey-007/vengeance | no LICENSE file |
| `vice-city` | https://github.com/lavarinimoreira/omarchy-vice-city-theme | no LICENSE file |
| `void` | https://github.com/vyrx-dev/omarchy-void-theme | MIT |
| `vurple` | https://github.com/tahfizhabib/omarchy-vurple-theme | no LICENSE file |
| `x-1632` | https://github.com/OldJobobo/omarchy-x-1632-theme | no LICENSE file |

`synthwave84` takes its palette and terminal colours from the extension under Vendor ports.

## Vendor ports

Each vendor port takes its values from the upstream source named below, apart from the readability overrides in `docs/architecture/themes.md` § Catalog and the terminal readability lifts below. The catalog carries only shell palette values and terminal colours from these sources, and no application files.

| VGS theme | Palette and terminal source | License |
|---|---|---|
| `horizon` | [jolaleye/horizon-theme-vscode, dark globals](https://github.com/jolaleye/horizon-theme-vscode/blob/v2.0.2/src/dark/globals.json) | [MIT, © 2018 Jonathan Olaleye](https://github.com/jolaleye/horizon-theme-vscode/blob/v2.0.2/LICENSE) |
| `horizon-light` | [jolaleye/horizon-theme-vscode, bright globals](https://github.com/jolaleye/horizon-theme-vscode/blob/v2.0.2/src/bright/globals.json) | [MIT, © 2018 Jonathan Olaleye](https://github.com/jolaleye/horizon-theme-vscode/blob/v2.0.2/LICENSE) |
| `synthwave84` | [RobbOwen.synthwave-vscode 0.1.20](https://open-vsx.org/extension/RobbOwen/synthwave-vscode/0.1.20), its `terminal.*` and `terminalCursor.foreground` keys plus the surfaces named below | MIT, © Robb Owen |

For the two Horizon packages, the catalog uses the matching globals file for palette and terminal colours.

For `synthwave84`, twenty colour keys come from the extension. It sets twelve `terminal.ansi*` keys, and those answer `color1` to `color6` and `color9` to `color14`; `foreground` and `cursor` come from `terminal.foreground` and `terminalCursor.foreground`. It sets no black or white ANSI pair and no terminal key for the accent, so the remaining keys take the surfaces it paints them from: `accent` from `activityBarBadge.background`, `color0` from `editor.background`, `color8` from `button.background`, and `color7` and `color15` from the top-level `foreground`. The package's own values are `background`, which the extension answers nowhere, and `selection_background`, whose only upstream value carries an alpha channel.

## Terminal readability lifts

A terminal slot that programs draw text in, `color1` to `color6` and `color9` to `color14`, holds at least 4.5:1 against the package's `palette.background`, the floor `scripts/check-theme-contrast.js` judges. Where the source value falls short, the slot holds `mix(source, toward, amount)`: the source value mixed toward white on a dark theme or black on a light one, by the smallest amount in steps of 0.01 that reaches the floor. The mix keeps the source hue. `color0`, `color7`, `color8` and `color15` keep their source values, because they also fill and dim. Each row reads slot, source value, amount and result.

| VGS theme | Toward | Lifted slots |
|---|---|---|
| `akane` | white | `color1` #d2495b + 0.11 → #d75d6d, `color4` #574f72 + 0.29 → #88829b, `color5` #763c5d + 0.32 → #a27a91, `color6` #9279aa + 0.02 → #947cac, `color12` #9279aa + 0.02 → #947cac, `color14` #c85670 + 0.08 → #cc647b |
| `amberbyte` | white | `color1` #b44a4a + 0.13 → #be6262, `color2` #c05a5a + 0.04 → #c36161 |
| `arc-raiders` | white | `color1` #7a555a + 0.16 → #8f7074, `color2` #357e22 + 0.07 → #438731, `color4` #3f57a1 + 0.19 → #6377b3 |
| `artzen` | white | `color1` #9b584d + 0.18 → #ad766d, `color2` #9f6769 + 0.10 → #a97678 |
| `bauhaus` | white | `color4` #5e738b + 0.09 → #6c8095, `color5` #8d758f + 0.01 → #8e7690, `color12` #6c7c82 + 0.03 → #708086 |
| `biscuit-de-mar` | white | `color4` #756d94 + 0.10 → #837c9f, `color5` #7b3d79 + 0.27 → #9f719d, `color6` #756d94 + 0.10 → #837c9f, `color12` #756d94 + 0.10 → #837c9f, `color13` #7b3d79 + 0.27 → #9f719d, `color14` #756d94 + 0.10 → #837c9f |
| `brutalism` | white | `color1` #450404 + 0.45 → #997575, `color2` #630a0a + 0.42 → #a57171, `color9` #9c0909 + 0.36 → #c06262, `color10` #9f1d1d + 0.31 → #bd6363 |
| `catppuccin-latte` | black | `color2` #40a02b + 0.22 → #327d22, `color3` #df8e1d + 0.32 → #986114, `color4` #1e66f5 + 0.03 → #1d63ee, `color5` #ea76cb + 0.31 → #a1518c, `color6` #179299 + 0.17 → #13797f, `color10` #40a02b + 0.22 → #327d22, `color11` #df8e1d + 0.32 → #986114, `color12` #1e66f5 + 0.03 → #1d63ee, `color13` #ea76cb + 0.31 → #a1518c, `color14` #179299 + 0.17 → #13797f |
| `eldritch` | white | `color4` #9071f4 + 0.04 → #9477f4 |
| `ember-n-ash` | white | `color4` #6c5b4c + 0.23 → #8e8175, `color12` #7f6b5d + 0.14 → #918074 |
| `flexoki-light` | black | `color1` #d14d41 + 0.04 → #c94a3e, `color2` #879a39 + 0.20 → #6c7b2e, `color3` #d0a215 + 0.31 → #90700e, `color5` #ce5d97 + 0.12 → #b55285, `color6` #3aa99f + 0.24 → #2c8079, `color9` #d14d41 + 0.04 → #c94a3e, `color10` #879a39 + 0.20 → #6c7b2e, `color11` #d0a215 + 0.31 → #90700e, `color12` #4385be + 0.09 → #3d79ad, `color13` #ce5d97 + 0.12 → #b55285, `color14` #3aa99f + 0.24 → #2c8079 |
| `greek-noir` | white | `color3` #757864 + 0.07 → #7f816f, `color11` #757864 + 0.07 → #7f816f |
| `harbordark` | white | `color5` #77838a + 0.02 → #7a858c, `color6` #6d6d6d + 0.15 → #838383 |
| `horizon-light` | black | `color2` #1eb980 + 0.32 → #147e57, `color5` #e73665 + 0.12 → #cb3059, `color6` #1d8991 + 0.11 → #1a7a81, `color9` #dc3318 + 0.05 → #d13017, `color10` #07da8c + 0.42 → #047e51, `color11` #f77d26 + 0.30 → #ad571b, `color13` #e84a72 + 0.16 → #c33e60, `color14` #1eaeae + 0.30 → #157a7a |
| `kanagawa` | white | `color1` #c34043 + 0.21 → #d0686a, `color9` #e82424 + 0.20 → #ed5050 |
| `last-horizon` | white | `color3` #6b5e73 + 0.14 → #807587, `color11` #6b5e73 + 0.14 → #807587 |
| `lumon` | white | `color1` #4d86b0 + 0.07 → #598eb6 |
| `matte-black` | white | `color3` #b91c1c + 0.27 → #cc5959, `color9` #c02523 + 0.22 → #ce5553, `color11` #b90a0a + 0.31 → #cf5656, `color13` #b91c1c + 0.27 → #cc5959 |
| `mechanoonna` | white | `color1` #c5564a + 0.09 → #ca655a, `color9` #d94e38 + 0.06 → #db5944 |
| `miasma` | white | `color1` #7e6c57 + 0.18 → #958675, `color2` #5f875f + 0.09 → #6d926d, `color3` #b36d43 + 0.09 → #ba7a54, `color4` #78824b + 0.09 → #848d5b, `color5` #bb7744 + 0.02 → #bc7a48, `color9` #7e6c57 + 0.18 → #958675, `color10` #5f875f + 0.09 → #6d926d, `color11` #b36d43 + 0.09 → #ba7a54, `color12` #78824b + 0.09 → #848d5b, `color13` #bb7744 + 0.02 → #bc7a48 |
| `moon-orbit` | white | `color1` #c0685f + 0.15 → #c97f77, `color2` #5a8151 + 0.21 → #7d9b76, `color4` #7b79a4 + 0.17 → #9190b3, `color5` #987195 + 0.17 → #aa89a7, `color6` #7c79a5 + 0.17 → #9290b4 |
| `nagai-twilight` | white | `color6` #406e82 + 0.19 → #648a9a, `color14` #4c84a0 + 0.06 → #578ba6 |
| `nord` | white | `color1` #bf616a + 0.25 → #cf898f, `color5` #b48ead + 0.02 → #b690af, `color9` #bf616a + 0.25 → #cf898f, `color13` #b48ead + 0.02 → #b690af |
| `oxford` | white | `color1` #dd5544 + 0.16 → #e27062, `color2` #688a61 + 0.14 → #7d9a77 |
| `reddcs` | white | `color1` #c24f57 + 0.08 → #c75d64, `color2` #5c7b55 + 0.08 → #698663, `color4` #684c59 + 0.25 → #8e7983, `color5` #a63650 + 0.23 → #ba6478, `color6` #6b6566 + 0.16 → #837e7e, `color9` #c24f57 + 0.08 → #c75d64, `color10` #5c7b55 + 0.08 → #698663, `color12` #684c59 + 0.25 → #8e7983, `color13` #a63650 + 0.23 → #ba6478, `color14` #6b6566 + 0.16 → #837e7e |
| `retro-82` | white | `color2` #028391 + 0.07 → #148c99, `color10` #028391 + 0.07 → #148c99 |
| `reverie` | white | `color4` #587ea8 + 0.07 → #6487ae |
| `rose-pine` | black | `color1` #b4637a + 0.09 → #a45a6f, `color3` #ea9d34 + 0.35 → #986622, `color4` #56949f + 0.19 → #467881, `color5` #907aa9 + 0.15 → #7a6890, `color6` #d7827e + 0.27 → #9d5f5c, `color9` #b4637a + 0.09 → #a45a6f, `color11` #ea9d34 + 0.35 → #986622, `color12` #56949f + 0.19 → #467881, `color13` #907aa9 + 0.15 → #7a6890, `color14` #d7827e + 0.27 → #9d5f5c |
| `rose-pine-main` | white | `color2` #31748f + 0.15 → #5089a0, `color10` #31748f + 0.15 → #5089a0 |
| `rose-pine-moon` | white | `color2` #3e8fb0 + 0.04 → #4693b3, `color10` #3e8fb0 + 0.04 → #4693b3 |
| `solitude` | white | `color1` #565d60 + 0.21 → #797f81, `color6` #707070 + 0.09 → #7d7d7d, `color10` #343d41 + 0.34 → #797f82, `color12` #5d6367 + 0.17 → #797e81, `color14` #707070 + 0.09 → #7d7d7d |
| `thegreek` | black | `color1` #db0030 + 0.18 → #b40027, `color4` #de6a41 + 0.37 → #8c4329, `color9` #db0030 + 0.18 → #b40027, `color12` #de6a41 + 0.37 → #8c4329 |
| `tycho` | white | `color1` #976870 + 0.14 → #a67d84, `color4` #9b826b + 0.01 → #9c836c, `color6` #706b82 + 0.18 → #8a8699 |
| `vurple` | white | `color1` #9f34f3 + 0.06 → #a540f4 |
| `x-1632` | white | `color1` #a07d7d + 0.16 → #af9292, `color2` #73976b + 0.10 → #81a17a, `color4` #7f8da1 + 0.11 → #8d9aab, `color5` #8383c3 + 0.14 → #9494cb, `color6` #7f99c1 + 0.01 → #809ac2, `color9` #af8d8d + 0.04 → #b29292 |

Two imports restore their source values before any lift. `thegreek` takes `color7` #383835 and `color15` #242424 from its source's white and bright white. `biscuit-de-mar` takes `color6` and `color14` #756d94 from its source's cyan, and `color9` #f07342 from its source's bright red.

## Icon themes

Each package's `targets/icons.theme` names one of the Yaru variants in `themes/targets/icons/`, credited in `themes/targets/icons/YARU-LICENSE.md`. For the packages Omarchy also ships, the name is the one in Omarchy's `themes/<name>/icons.theme` (https://github.com/basecamp/omarchy, MIT), except `vantablack` and `white`, whose Omarchy names match no Yaru variant. Every other package takes the variant whose colour lies nearest its accent's hue.
