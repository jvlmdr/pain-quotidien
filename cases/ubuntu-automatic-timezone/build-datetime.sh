#!/bin/bash
set -eu

cd "$(dirname "$0")"
source_dir=gnome-settings-daemon-46.0
build_dir=datetime-build
headers="$build_dir/headers/usr"

for interface in SessionManager ScreenSaver Shell; do
    case "$interface" in
        SessionManager) output=gsd-session-manager-glue ;;
        ScreenSaver) output=gsd-screen-saver-glue ;;
        Shell) output=gsd-shell-glue ;;
    esac
    "$headers/bin/gdbus-codegen" \
        --interface-prefix "org.gnome.$interface." \
        --generate-c-code "$output" \
        --c-namespace Gsd \
        --annotate "org.gnome.$interface" org.gtk.GDBus.C.Name "$interface" \
        --output-directory "$build_dir" \
        "$source_dir/gnome-settings-daemon/org.gnome.$interface.xml"
done

"$headers/bin/gdbus-codegen" \
    --interface-prefix org.freedesktop. \
    --generate-c-code "$build_dir/timedated" \
    "$source_dir/plugins/datetime/timedated1-interface.xml"

gcc -O2 -g -Wall -Wextra -Wno-unused-parameter \
    -DGETTEXT_PACKAGE='"gnome-settings-daemon"' \
    -DGNOME_SETTINGS_LOCALEDIR='"/usr/share/locale"' \
    -DGNOMECC_DATA_DIR='"/usr/share/gnome-settings-daemon"' \
    -DPLUGIN_NAME='"datetime"' \
    -DPLUGIN_DBUS_NAME='"org.gnome.SettingsDaemon.Datetime"' \
    -DG_LOG_DOMAIN='"datetime"' \
    -I"$build_dir" \
    -I. \
    -I"$source_dir/gnome-settings-daemon" \
    -I"$source_dir/plugins/common" \
    -I"$headers/include" \
    -I"$headers/include/glib-2.0" \
    -I"$headers/lib/x86_64-linux-gnu/glib-2.0/include" \
    -I"$headers/include/geocode-glib-2.0" \
    -I"$headers/include/libgweather-4.0" \
    -I"$headers/include/libgeoclue-2.0" \
    -I"$headers/include/polkit-1" \
    -I"$headers/include/gdk-pixbuf-2.0" \
    "$source_dir/plugins/datetime/gsd-datetime-manager.c" \
    "$source_dir/plugins/datetime/gsd-timezone-monitor.c" \
    "$source_dir/plugins/datetime/main.c" \
    "$source_dir/plugins/datetime/tz.c" \
    "$source_dir/plugins/datetime/weather-tz.c" \
    "$build_dir/timedated.c" \
    -L/usr/lib/gnome-settings-daemon-46 \
    -Wl,-rpath,/usr/lib/gnome-settings-daemon-46 \
    -lgsd -l:libgeocode-glib-2.so.0 -l:libgweather-4.so.0 \
    -l:libgeoclue-2.so.0 -l:libnotify.so.4 -l:libpolkit-gobject-1.so.0 \
    -l:libgio-2.0.so.0 -l:libgobject-2.0.so.0 -l:libglib-2.0.so.0 -lm \
    -o "$build_dir/gsd-datetime"
