{
  description = "VGS, a desktop shell for Hyprland on Quickshell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # Only required packages enter the runtime PATH. The shared recipe
      # check holds this closure to the manifests and runtime libraries.
      runtimePackages = pkgs: [
        pkgs.bash
        pkgs.bubblewrap
        pkgs.chromium
        pkgs.coreutils
        pkgs.curl
        pkgs.dbus
        pkgs.fd
        pkgs.ffmpeg
        pkgs.file
        pkgs.fontconfig
        pkgs.fzf
        pkgs.gawk
        pkgs.git
        pkgs.glib
        pkgs.gpu-screen-recorder
        pkgs.grim
        pkgs.gum
        pkgs.hyprland
        pkgs.hyprpicker
        pkgs.imagemagick
        pkgs.iproute2
        pkgs.less
        pkgs.libnotify
        pkgs.libsecret
        pkgs.libxkbcommon
        pkgs.mise
        pkgs.networkmanager
        pkgs.nodejs
        pkgs.pipewire
        pkgs.playerctl
        pkgs.power-profiles-daemon
        pkgs.pulseaudio
        pkgs.python3
        pkgs.qrencode
        pkgs.quickshell
        pkgs.gnused
        pkgs.slurp
        pkgs.systemd
        pkgs.tesseract
        pkgs.util-linux
        pkgs.uv
        pkgs.wireplumber
        pkgs.wl-clipboard
        pkgs.wlrctl
        pkgs.wtype
        pkgs.xdg-terminal-exec
        pkgs.xdg-utils
        pkgs.xkeyboard_config
      ];
      # The session supplies its own hyprctl. Keep Hyprland in the closure
      # without overriding the compositor's client on PATH.
      runtimePath = pkgs: lib.makeBinPath (builtins.filter (package: package != pkgs.hyprland) (runtimePackages pkgs));
    in
    {
      packages = forAllSystems (pkgs: {
        default = pkgs.stdenvNoCC.mkDerivation {
          pname = "vgshell";
          version = lib.fileContents ./VERSION;
          src = self;

          nativeBuildInputs = [ pkgs.python3 ];
          # The interpreters fixup writes into the runtime tree's
          # `#!/usr/bin/env` and `#!/bin/bash` lines.
          buildInputs = [ pkgs.bash pkgs.nodejs pkgs.python3 pkgs.libxkbcommon pkgs.xkeyboard_config ];

          dontConfigure = true;
          dontBuild = true;

          # The shared installer writes the same tree every channel ships, and
          # $out/bin/vgshell stays its plain link. Hyprland's exec and a
          # single-instance terminal start vgshell and vgshell-tui without the
          # caller's environment, so each bash entry point under bin/ sets the
          # runtime PATH itself: one line after its leading comment block,
          # which the usage text is read from. The line prefixes the runtime
          # path as one unit, and leaves a PATH that already holds it alone.
          installPhase = ''
            runHook preInstall
            DESTDIR= PREFIX=$out bash packaging/install-system.sh
            substituteInPlace $out/share/vgshell/bin/lib/xkb-keys.py \
              --replace-fail 'SYSTEM_XKB_ROOT = "/usr/share/X11/xkb"' 'SYSTEM_XKB_ROOT = "${pkgs.xkeyboard_config}/share/X11/xkb"' \
              --replace-fail 'SYSTEM_XKB_LIBRARY = "libxkbcommon.so.0"' 'SYSTEM_XKB_LIBRARY = "${pkgs.libxkbcommon}/lib/libxkbcommon.so.0"'
            substituteInPlace $out/share/vgshell/shell/plugins/vgs.keyboard/Service.qml \
              --replace-fail '"/usr/share/X11/xkb/rules/evdev.xml"' '"${pkgs.xkeyboard_config}/share/X11/xkb/rules/evdev.xml"'
            line='case :$PATH: in *:${runtimePath pkgs}:*) ;; *) PATH=${runtimePath pkgs}''${PATH:+:$PATH} ;; esac; export PATH # vgs-nix-path'
            for entry in $out/share/vgshell/bin/*; do
              [[ -f $entry && ! -L $entry ]] || continue
              case "$(head -n 1 "$entry")" in
                '#!/usr/bin/env bash' | '#!/bin/bash') ;;
                *) continue ;;
              esac
              awk -v line="$line" 'NR > 1 && !done && !/^#/ { print line; done = 1 } { print } END { if (!done) print line }' "$entry" >"$entry.nix-path"
              cat "$entry.nix-path" >"$entry"
              rm "$entry.nix-path"
            done
            for entry in vgshell vgshell-tui; do
              grep -qF '# vgs-nix-path' "$out/share/vgshell/bin/$entry" || {
                echo "flake: refused: nix-path=missing path=$out/share/vgshell/bin/$entry" >&2
                exit 1
              }
            done
            bash scripts/check-install-tree.sh "" "$out"
            runHook postInstall
          '';

          meta = {
            description = "Desktop shell for Hyprland on Quickshell";
            homepage = "https://github.com/vanillagreencom/vgshell";
            license = with lib.licenses; [ mit ofl isc asl20 cc-by-sa-40 ];
            platforms = systems;
            mainProgram = "vgshell";
          };
        };
      });

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.default;
          meta.description = "Run the vgshell command";
        };
      });
    };
}
