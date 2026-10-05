# The release package of COPR vanillagreen/vgshell. Build its source RPM with
# packaging/fedora/srpm.sh from a checkout at the release tag:
# docs/architecture/distribution-fedora.md. The dependency block is the
# same in vgshell-git.spec; scripts/check-packaging.js holds both to the
# requirement data and the preflight floor.

Name:           vgshell
Version:        0.1.0
Release:        1%{?dist}
Summary:        Desktop shell for Hyprland on Quickshell
License:        MIT AND OFL-1.1 AND ISC AND Apache-2.0
URL:            https://github.com/vanillagreencom/vgshell
Source0:        %{url}/releases/download/v%{version}/vgshell-%{version}.tar.gz
BuildArch:      noarch

BuildRequires:  bash
BuildRequires:  coreutils
BuildRequires:  python3

# begin runtime dependencies
Requires:       quickshell >= 0.3.1
Requires:       hyprland >= 0.56
Requires:       nodejs >= 1:18
Requires:       python3
Requires:       libxkbcommon
Requires:       xkeyboard-config
Requires:       git
Requires:       ImageMagick
Requires:       NetworkManager
Requires:       bash
Requires:       bubblewrap
Requires:       chromium
Requires:       coreutils
Requires:       curl
Requires:       dbus-tools
Requires:       fd-find
Requires:       file
Requires:       fzf
Requires:       glib2
Requires:       grim
Requires:       gum
Requires:       hyprpicker
Requires:       iproute
Requires:       less
Requires:       libnotify
Requires:       libsecret
Requires:       pipewire-utils
Requires:       playerctl
Requires:       pulseaudio-utils
Requires:       qrencode
Requires:       slurp
Requires:       systemd
Requires:       tesseract
Requires:       tesseract-langpack-eng
Requires:       util-linux
Requires:       util-linux-core
Requires:       uv
Requires:       wireplumber
Requires:       wl-clipboard
Requires:       wlrctl
Requires:       wtype
Requires:       xdg-terminal-exec
Requires:       xdg-utils
Recommends:     bluez
Recommends:     brightnessctl
Recommends:     cronie
Recommends:     ddcutil
Recommends:     glibc-common
Recommends:     greetd
Recommends:     polkit
Recommends:     tailscale
Recommends:     xorg-x11-xinit
Recommends:     tmux
Recommends:     ydotool
# end runtime dependencies

%description
VGS is a desktop shell for Hyprland, built on Quickshell. A small fixed core
starts the shell, talks to Hyprland, hosts surfaces and loads plugins; the
bar, its widgets, every panel and every background service are plugins.

%prep
%autosetup -n vgshell-%{version}

%build

%install
DESTDIR=%{buildroot} PREFIX=%{_prefix} SYSCONFDIR=%{_sysconfdir} packaging/install-system.sh

%check
scripts/check-install-tree.sh %{buildroot} %{_prefix} %{_sysconfdir}

%files
%license %{_datadir}/licenses/vgshell/LICENSE
%doc %{_datadir}/doc/vgshell/README.md
%dir %{_datadir}/licenses/vgshell
%dir %{_datadir}/doc/vgshell
%{_bindir}/vgshell
%{_bindir}/vgshell-browser-policy
%attr(0440,root,root) %config(noreplace) %{_sysconfdir}/sudoers.d/vgshell-theme-browser
%config(noreplace) %{_sysconfdir}/xdg/autostart/vgshell.desktop
%{_datadir}/vgshell/

%post
if [ "$1" -eq 1 ]; then
    cat %{_datadir}/vgshell/bin/lib/post-install.txt
fi

%changelog
* Mon Sep 28 2026 Brad <brad@vanillagreen.com> - 0.1.0-1
- First release of VGS as vgshell
