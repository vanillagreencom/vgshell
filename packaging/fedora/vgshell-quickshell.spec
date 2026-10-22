%global commit 2b4501a282689792b62e94f3fb30d8f512324fe6

Name:           vgshell-quickshell
Version:        0.3.2
Release:        2.2b4501a%{?dist}
Summary:        Quickshell with the VGS lifetime and crash fixes
License:        LGPL-3.0-only
URL:            https://git.outfoxxed.me/quickshell/quickshell
Source0:        %{url}/archive/%{commit}.tar.gz
Patch0:         vgs-989-deletelater.patch
Patch1:         vgs-1109-log-filter-mutex.patch
Patch2:         vgs-1993-managed-process-lifetime.patch
Provides:       quickshell = %{version}
Conflicts:      quickshell
Conflicts:      quickshell-git
Obsoletes:      quickshell < 0.3.3
Obsoletes:      quickshell-git < 0.3.3
BuildRequires:  cmake ninja-build gcc-c++ git cli11-devel cpptrace-devel jemalloc-devel
BuildRequires:  qt6-qtbase-devel >= 6.7
BuildRequires:  qt6-qtbase-private-devel qt6-qtdeclarative-devel qt6-qtsvg-devel qt6-qtwayland-devel qt6-qtshadertools-devel
Requires:       qt6-qtbase >= 6.7
BuildRequires:  wayland-devel wayland-protocols-devel libxcb-devel libdrm-devel mesa-libgbm-devel pipewire-devel pam-devel polkit-devel
BuildRequires:  vulkan-headers spirv-tools libzstd-devel

%description
Pinned upstream Quickshell with the Hyprland request socket lifetime fix and
thread-safe logging filters and shell-owned process cleanup used by VGS.

%prep
%autosetup -n quickshell -p1

%build
%cmake -GNinja -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DDISTRIBUTOR="VGS 2 (package: vgshell-quickshell)" \
    -DGIT_REVISION=%{commit} -DINSTALL_QMLDIR=%{_libdir}/qt6/qml
%cmake_build

%install
%cmake_install

%files
%license LICENSE
%{_bindir}/qs
%{_bindir}/quickshell
%{_libdir}/qt6/qml/Quickshell/
%{_datadir}/applications/org.quickshell.desktop
%{_datadir}/icons/hicolor/*/apps/org.quickshell.*

%changelog
* Wed Oct 21 2026 VanillaGreen <brad@vanillagreen.com> - 0.3.2-2.2b4501a
- End managed children and their descendants when their shell ends.
* Sat Oct 17 2026 VanillaGreen <brad@vanillagreen.com> - 0.3.2-1.2b4501a
- Carry the VGS request socket and logging filter crash fixes.
