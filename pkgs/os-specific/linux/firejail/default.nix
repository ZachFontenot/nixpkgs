{ lib
, stdenv
, fetchFromGitHub
, fetchpatch
, pkg-config
, libapparmor
, which
, xdg-dbus-proxy
, nixosTests
}:

stdenv.mkDerivation rec {
  pname = "firejail";
  version = "0.9.68";

  src = fetchFromGitHub {
    owner = "netblue30";
    repo = "firejail";
    rev = version;
    sha256 = "18yy1mykx7h78yj7sz729i3dlsrgi25m17m5x9gbrvsx7f87rw7j";
  };

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = [
    libapparmor
    which
  ];

  configureFlags = [
    "--enable-apparmor"
  ];

  patches = [
    # Adds the /nix directory when using an overlay.
    # Required to run any programs under this mode.
    ./mount-nix-dir-on-overlay.patch

    # By default fbuilder hardcodes the firejail binary to the install path.
    # On NixOS the firejail binary is a setuid wrapper available in $PATH.
    ./fbuilder-call-firejail-on-path.patch

    # NixOS specific whitelist to resolve binary paths in user environment
    # Fixes https://github.com/NixOS/nixpkgs/issues/170784
    # Upstream fix https://github.com/netblue30/firejail/pull/5131
    # Upstream hopefully fixed in later versions > 0.9.68
   ./whitelist-nix-profile.patch

    # Fix OpenGL support for various applications including Firefox
    # Issue: https://github.com/NixOS/nixpkgs/issues/55191
    # Upstream fix: https://github.com/netblue30/firejail/pull/5132
    # Hopefully fixed upstream in version > 0.9.68
    ./fix-opengl-support.patch

    # Fix CVE-2022-31214 by patching in 4 commits from upstream
    # https://seclists.org/oss-sec/2022/q2/188
    (fetchpatch {
      name = "CVE-2022-31214-patch1"; # "fixing CVE-2022-31214"
      url  = "https://github.com/netblue30/firejail/commit/27cde3d7d1e4e16d4190932347c7151dc2a84c50.patch";
      sha256 = "sha256-XXmnYCn4TPUvU43HifZDk4tEZQvOho9/7ehU6889nN4=";
    })
    (fetchpatch {
      name = "CVE-2022-31214-patch2"; # "shutdown testing"
      url  = "https://github.com/netblue30/firejail/commit/04ff0edf74395ddcbbcec955279c74ed9a6c0f86.patch";
      sha256 = "sha256-PV73hRlvYEQihuljSCQMNO34KJ0hDVFexhirpHcTK1I=";
    })
    (fetchpatch {
      name = "CVE-2022-31214-patch3"; # "CVE-2022-31214: fixing the fix"
      url  = "https://github.com/netblue30/firejail/commit/dab835e7a0eb287822016f5ae4e87f46e1d363e7.patch";
      sha256 = "sha256-6plBIliW/nLKR7TdGeB88eQ65JHEasnaRsP3HPXAFyA=";
    })
    (fetchpatch {
      name = "CVE-2022-31214-patch4"; # "CVE-2022-31214: fixing the fix, one more time "
      url  = "https://github.com/netblue30/firejail/commit/1884ea22a90d225950d81c804f1771b42ae55f54.patch";
      sha256 = "sha256-inkpcdC5rl5w+CTAwwQVBOELlHTXb8UGlpU+8kMY95s=";
    })
  ];

  prePatch = ''
    # Fix the path to 'xdg-dbus-proxy' hardcoded in the 'common.h' file
    substituteInPlace src/include/common.h \
      --replace '/usr/bin/xdg-dbus-proxy' '${xdg-dbus-proxy}/bin/xdg-dbus-proxy'
  '';

  preConfigure = ''
    sed -e 's@/bin/bash@${stdenv.shell}@g' -i $( grep -lr /bin/bash .)
    sed -e "s@/bin/cp@$(which cp)@g" -i $( grep -lr /bin/cp .)
  '';

  preBuild = ''
    sed -e "s@/etc/@$out/etc/@g" -e "/chmod u+s/d" -i Makefile
  '';

  # The profile files provided with the firejail distribution include `.local`
  # profile files using relative paths. The way firejail works when it comes to
  # handling includes is by looking target files up in `~/.config/firejail`
  # first, and then trying `SYSCONFDIR`. The latter normally points to
  # `/etc/filejail`, but in the case of nixos points to the nix store. This
  # makes it effectively impossible to place any profile files in
  # `/etc/firejail`.
  #
  # The workaround applied below is by creating a set of `.local` files which
  # only contain respective includes to `/etc/firejail`. This way
  # `~/.config/firejail` still takes precedence, but `/etc/firejail` will also
  # be searched in second order. This replicates the behaviour from
  # non-nixos platforms.
  #
  # See https://github.com/netblue30/firejail/blob/e4cb6b42743ad18bd11d07fd32b51e8576239318/src/firejail/profile.c#L68-L83
  # for the profile file lookup implementation.
  postInstall = ''
    for local in $(grep -Eh '^include.*local$' $out/etc/firejail/*{.inc,.profile} | awk '{print $2}' | sort | uniq)
    do
      echo "include /etc/firejail/$local" >$out/etc/firejail/$local
    done
  '';

  # At high parallelism, the build sometimes fails with:
  # bash: src/fsec-optimize/fsec-optimize: No such file or directory
  enableParallelBuilding = false;

  passthru.tests = nixosTests.firejail;

  meta = {
    description = "Namespace-based sandboxing tool for Linux";
    license = lib.licenses.gpl2Plus;
    maintainers = [ lib.maintainers.raskin ];
    platforms = lib.platforms.linux;
    homepage = "https://firejail.wordpress.com/";
  };
}
