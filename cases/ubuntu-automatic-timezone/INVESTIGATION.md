# Investigation: Ubuntu automatic timezone was not updating

Short version: [README.md](README.md).

Last verified: 2026-09-28.
Environment: Ubuntu 24.04 x86-64, GNOME Settings Daemon `46.0-1ubuntu1.24.04.1`, GeoClue `2.7.0-3ubuntu7`, geocode-glib `3.26.3-6build3`.
Recorded status: fixed locally with a working location provider and a GNOME backport.

## Starting problem

Automatic timezone updates were not working.
The laptop was in Sydney and had been in Brisbane the previous day.
The initial question was why automatic detection was not updating, not why a working detector was choosing the wrong city.
Repairing location detection exposed a second problem in how GNOME selected the timezone.

## 1. Could the system obtain a location?

GNOME's Automatic Time Zone and Location Services switches were enabled, but GeoClue's configured Mozilla location provider returned HTTP 404 responses.
An enabled setting was therefore not enough: the service supplying location data was failing.
This established a concrete fault to repair before evaluating timezone selection.

The provider was changed to BeaconDB through [99-beacondb.conf](99-beacondb.conf), and GeoClue was restarted.
Afterward, GeoClue reported coordinates in Sydney.
A later Wi-Fi-based result had an accuracy radius of approximately three kilometers, sufficient to distinguish Sydney from Brisbane.
Location detection was now functioning, but the system timezone remained `Australia/Brisbane`.
That separated the original provider failure from a second failure downstream of location detection.

## 2. Where did the correct coordinates stop being used?

GNOME 46 reverse-geocodes the detected location, then selects a timezone using the coordinates in the returned place.
A direct request to GNOME's reverse-geocoding endpoint with Sydney coordinates returned a place in Brisbane instead.
Requests with synthetic coordinates in another country, and even a request without coordinates, also returned Brisbane.
These results suggested that the endpoint was not using the requested coordinates.

The recent visit to Brisbane made stale location data a plausible hypothesis.
To test the local-cache explanation, the geocoding cache was moved aside and automatic detection refreshed.
A newly fetched response still contained Brisbane.
A separate request with cache-bypass headers and a unique URL returned the same result.
Clearing the local cache therefore did not repair the failure, and the evidence did not support treating yesterday's travel as its cause.

DNS, certificate, proxy, and routing checks did not reveal a local redirection of the endpoint.
That made inspecting the upstream service implementation the next useful step.

## 3. What explained the endpoint's behavior?

The [GNOME service's source](https://gitlab.gnome.org/Infrastructure/openshift-images/nominatim-cache/-/blob/c6ee4866b57e055dc54737f5a44b74302be74d7b/app/main.py) showed that its reverse handler locates the caller's IP using MaxMind and ignores latitude and longitude query parameters.
The [October 2025 change](https://gitlab.gnome.org/Infrastructure/openshift-images/nominatim-cache/-/commit/5dbcf58bfe341064d4ea97164b5305dd8771da57) introduced this IP-only behavior.
This explained why changing the supplied coordinates did not change the response.

BeaconDB's IP lookup returned Sydney, whereas GNOME's MaxMind lookup returned Brisbane for the caller's IP.
The internal reason for MaxMind's Brisbane result was not established.
The important local failure was that GNOME replaced GeoClue's independently obtained Sydney coordinates with this IP-based result.
Better precision from GeoClue could not fix that substitution.

## 4. Was there an upstream fix?

[GNOME issue #925](https://gitlab.gnome.org/GNOME/gnome-settings-daemon/-/issues/925) described incorrect timezone selection despite correct GeoClue coordinates.
It was closed by [merge request !469](https://gitlab.gnome.org/GNOME/gnome-settings-daemon/-/merge_requests/469), which preserves the original coordinates for timezone selection and uses reverse geocoding only for country detection.
This addressed the mechanism observed on the laptop.
The installed Ubuntu package did not include the change.

The coordinate-preservation portion was backported to Ubuntu's GNOME 46 source in [preserve-geoclue-coordinates.patch](preserve-geoclue-coordinates.patch).
An initial suggestion to install the full settings-daemon build dependencies would have pulled in many unrelated packages.
The user's objection prompted a smaller build of only the datetime executable.
Eight development-header/tool packages were downloaded and extracted locally, totaling approximately 2.2 MB; no packages were installed or upgraded for this build.
[BUILD.md](BUILD.md) records the prerequisites, build procedure, and user-only installation.

## 5. Did the automatic path now work?

The replacement executable was installed at `~/.local/libexec/gsd-datetime-46` and selected by a user-level systemd [override](datetime-override.conf).
Ubuntu's original executable was left untouched.
The datetime target was restarted because the service itself refuses manual start and stop.

The patched daemon received Sydney coordinates, resolved the country to Australia, selected `Australia/Sydney`, and logged a successful timezone change.
`timedatectl show -p Timezone` independently confirmed the result.
The user confirmed the visible result.
GNOME's Automatic Time Zone and Location Services switches remained enabled, and the service stayed active after temporary debug logging was removed and the target restarted.
This tested automatic detection rather than merely setting the timezone manually.

The separate geocode-glib `g_ascii_strtod` warning persisted.
[Upstream issue #35](https://gitlab.gnome.org/GNOME/geocode-glib/-/issues/35) documents a related parsing defect, but the backport no longer uses the returned coordinates for timezone selection.
The successful timezone change showed that this warning did not prevent the repaired path from working in this test.
Travel across timezones and behavior after a distribution upgrade were not tested.

## Recognizing the same problem on another machine

An unchanged or incorrect timezone is only the symptom.
These observations distinguish the failures found here from other causes:

| Observation | What it establishes | Next step |
| --- | --- | --- |
| Automatic timezone or location services disabled | The tested automatic path is not enabled. | Resolve the setting before assuming a provider or coordinate-selection bug. |
| Configured Mozilla provider returns 404 and no fresh location is obtained | The location-provider failure matches the first fault. | Repair the provider and obtain a fresh location. |
| Fresh GeoClue coordinates are correct, reverse response substitutes another location, and installed daemon selects using that response | The coordinate-substitution mechanism matches the second fault. | Check for an official fix or an applicable backport. |
| GeoClue itself reports incorrect coordinates | This does not establish the downstream substitution failure. | Investigate the location source first. |

Begin with read-only checks:

```bash
timedatectl show -p Timezone
dpkg-query -W gnome-settings-daemon geoclue-2.0 libgeocode-glib-2-0
gsettings get org.gnome.desktop.datetime automatic-timezone
gsettings get org.gnome.system.location enabled
systemctl --user show org.gnome.SettingsDaemon.Datetime.service -p ExecStart -p ActiveState -p DropInPaths
journalctl --user -u org.gnome.SettingsDaemon.Datetime.service -n 50 --no-pager
journalctl -u geoclue.service -n 50 --no-pager
```

Inspect the active GeoClue provider and obtain an actual location result if needed.
Normal logging may omit coordinates, so their absence from the journal is not evidence that location detection failed.
Journal access may also be restricted.
Obtain appropriate consent before collecting or sharing precise location or Wi-Fi identifiers.
Compare against an independently known physical location, not only another IP lookup.
Prefer a current official package fix when available; do not assume the recorded package state still applies.
The build and override are specific to the tested GNOME 46 environment.

### Obtaining the decisive evidence

The successful location test used the datetime daemon's debug messages.
In a running GNOME session, a temporary runtime drop-in can enable those messages without changing which executable runs:

```bash
systemctl --user edit --runtime --drop-in=90-location-debug.conf org.gnome.SettingsDaemon.Datetime.service
```

Add the following in the editor, using a different drop-in name if that name already contains unrelated configuration:

```ini
[Service]
Environment=G_MESSAGES_DEBUG=datetime
```

Then restart the target and read the fresh messages, allowing time for GeoClue to produce a result:

```bash
systemctl --user restart org.gnome.SettingsDaemon.Datetime.target
journalctl --user -u org.gnome.SettingsDaemon.Datetime.service --since '5 minutes ago' --no-pager
```

The repaired daemon produced these messages during the recorded test, with precise coordinates redacted here:

```text
Got location [latitude redacted],[longitude redacted]
Geocode lookup resolved country to 'Australia'
Found updated timezone 'Australia/Sydney' for country 'AU'
Successfully changed timezone to 'Australia/Sydney'
```

Compare the reported coordinates with the known physical location.
These messages can reveal precise location, so avoid sharing the unredacted journal unnecessarily.
After testing, remove only the named temporary drop-in shown by `systemctl --user cat org.gnome.SettingsDaemon.Datetime.service`, reload with `systemctl --user daemon-reload`, and restart the target again.
Do not revert the entire service: that could also remove the installed fix or unrelated overrides.

To test whether the reverse endpoint respects its inputs, the investigation compared synthetic city coordinates and a request without coordinates:

```bash
curl -fsS 'https://nominatim.gnome.org/reverse?format=jsonv2&lat=-33.8688&lon=151.209&zoom=10&addressdetails=1'
curl -fsS 'https://nominatim.gnome.org/reverse?format=jsonv2&lat=35.6762&lon=139.6503&zoom=10&addressdetails=1'
curl -fsS 'https://nominatim.gnome.org/reverse?format=jsonv2'
```

These requests disclose the caller's public IP even though the coordinates are synthetic.
All three returned the same Brisbane place in the recorded investigation; the pinned upstream source then confirmed why.
Identical responses alone would not prove the implementation, and differing responses on another date or network would require reevaluating this part of the diagnosis.

## Maintenance and undo

APT does not maintain the replacement executable; official updates to the original datetime daemon do not update this copy.
Review the override after relevant package updates and remove it before changing GNOME major versions or once the official package fixes the issue.
The backport still depends on reverse geocoding for country detection, so a wrong country result or network failure remains a limitation.

Restore Ubuntu's executable for the current user with:

```bash
rm "$HOME/.config/systemd/user/org.gnome.SettingsDaemon.Datetime.service.d/50-local-timezone-fix.conf"
systemctl --user daemon-reload
systemctl --user restart org.gnome.SettingsDaemon.Datetime.target
```

This retains the compiled replacement and the independent BeaconDB configuration.
To revert the provider too, inspect and remove only `/etc/geoclue/conf.d/99-beacondb.conf` with administrator privileges, then restart `geoclue.service`.
On the tested package version, that may restore the original unavailable provider.
