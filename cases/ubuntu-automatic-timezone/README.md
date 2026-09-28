# Ubuntu automatic timezone was not updating

Ubuntu's automatic timezone updates were not working.
Fixed and verified on Ubuntu 24.04 / GNOME 46, on 2026-09-28.
Fixing that exposed a second issue:

1. GeoClue's retired Mozilla provider returned 404 errors, so location detection failed.
   Switching to BeaconDB restored correct Sydney coordinates.
2. GNOME 46 then replaced those coordinates with an IP-based reverse-geocoding result for Brisbane.
   Backporting the coordinate-preservation change from [GNOME !469](https://gitlab.gnome.org/GNOME/gnome-settings-daemon/-/merge_requests/469) fixed timezone selection.

The patched native daemon automatically selected `Australia/Sydney`, with GNOME's automatic timezone and location switches still enabled.
Only the datetime component was rebuilt; no build dependencies were installed or packages upgraded for the build.
Ubuntu's original binary remains untouched, with a user-level service override selecting the replacement.

For another machine, check the provider and actual GeoClue coordinates before assuming the same failures.
The backport fixes coordinate substitution, not location-provider failures; it still relies on reverse geocoding for country detection.
The local binary is specific to GNOME 46 and is not maintained by APT; review it after updates and remove the override before changing GNOME major versions or once an official fix is available.

Read the [investigation and diagnostic evidence](INVESTIGATION.md), [build and install instructions](BUILD.md), or [maintenance and undo notes](INVESTIGATION.md#maintenance-and-undo).
