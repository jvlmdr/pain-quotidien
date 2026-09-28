# Build prerequisites

The recorded build targets Ubuntu 24.04 x86-64 with GNOME Settings Daemon 46 and its installed runtime libraries.
It does not install or upgrade packages.
The commands below prepare a new build directory; do not run them over a source tree containing unrelated changes.
Run them from this case's directory.

## Source

Download the original Ubuntu source package and extract it, applying its distribution patches:

```bash
curl -fLO https://archive.ubuntu.com/ubuntu/pool/main/g/gnome-settings-daemon/gnome-settings-daemon_46.0-1ubuntu1.24.04.1.dsc
curl -fLO https://archive.ubuntu.com/ubuntu/pool/main/g/gnome-settings-daemon/gnome-settings-daemon_46.0.orig.tar.xz
curl -fLO https://archive.ubuntu.com/ubuntu/pool/main/g/gnome-settings-daemon/gnome-settings-daemon_46.0-1ubuntu1.24.04.1.debian.tar.xz
dpkg-source -x gnome-settings-daemon_46.0-1ubuntu1.24.04.1.dsc
patch --directory=gnome-settings-daemon-46.0 -p1 < preserve-geoclue-coordinates.patch
```

`dpkg-source` checks the archives against the source manifest.
If its signing key is unavailable, it cannot authenticate the manifest signature; the recorded download relied on Ubuntu's HTTPS archive endpoint.

## Headers and tools

GCC, Python 3, `dpkg-source`, `dpkg-deb`, `patch`, and curl must already be available.
The build also links to the system's installed GNOME 46 `libgsd.so` and datetime runtime dependencies.
Download and extract the development packages rather than installing their dependency trees:

```bash
mkdir -p datetime-build/packages datetime-build/headers
(
    cd datetime-build/packages
    apt-get download libglib2.0-dev libglib2.0-dev-bin \
        libgeoclue-2-dev libgeocode-glib-dev libgweather-4-dev \
        libnotify-dev libpolkit-gobject-1-dev libgdk-pixbuf-2.0-dev
)
for package in datetime-build/packages/*.deb; do
    dpkg-deb -x "$package" datetime-build/headers
done
cp config.h datetime-build/config.h
bash build-datetime.sh > datetime-build/build.log 2>&1
```

The recorded package versions are listed in [header-versions.txt](header-versions.txt).
`apt-get download` selects versions from the local APT indexes, so repeating these unpinned commands later may produce different headers.
Review compatibility before using the resulting executable.

## Install for the current user

Inspect any existing binary or drop-ins at these paths before installing; the recorded machine had none.
These commands overwrite matching local files and need no sudo:

```bash
install -d -m755 "$HOME/.local/libexec" \
    "$HOME/.config/systemd/user/org.gnome.SettingsDaemon.Datetime.service.d"
install -m755 datetime-build/gsd-datetime "$HOME/.local/libexec/gsd-datetime-46"
install -m644 datetime-override.conf \
    "$HOME/.config/systemd/user/org.gnome.SettingsDaemon.Datetime.service.d/50-local-timezone-fix.conf"
systemctl --user daemon-reload
systemctl --user restart org.gnome.SettingsDaemon.Datetime.target
timedatectl show -p Timezone
```

This assumes the GNOME session is running and both automatic timezone detection and location services are enabled.
See the [investigation](INVESTIGATION.md#maintenance-and-undo) for verification and undo instructions.
