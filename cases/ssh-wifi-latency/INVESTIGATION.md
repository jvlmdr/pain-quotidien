# Investigation: slow SSH turned out to be intermittent Wi-Fi latency

Observed on 2026-09-23, on a remote Linux machine using NetworkManager and a MediaTek `mt7925e` Wi-Fi driver.
The exact operating-system release, kernel version, and firmware version were not established in the material used for this write-up.
The investigation used OpenAI Codex CLI `0.154.0`, model `gpt-5.6-sol`, with `medium` reasoning effort, verified from local session metadata.
This account was reconstructed on 2026-09-29; the remote machine's present connection has not been checked.
Hostnames, profile names, SSIDs, BSSIDs, and local addresses are omitted.

## Was SSH waiting on the machine or the network?

The symptom was slow SSH to a machine on the local network.
The investigation reported healthy CPU and memory availability, unused swap, and no corresponding DNS or SSH-authentication fault.
Cycling swap did not address the network evidence; the machine had roughly 48 GiB of available memory and no active paging.

The useful separation was to measure both the client-to-server path and the server-to-router path.
During a degraded interval, the server's ping to its own router averaged about 249 ms and peaked at 695 ms.
Client-to-server latency averaged about 275 ms.
Router latency this high did not depend on the SSH application, and the traffic sample was only about 8 KB/s.
These observations focused the next tests on the server's Wi-Fi connection rather than bulk transfer load or SSH configuration.

## Why did reports sometimes say everything was healthy?

A diagnostic script captured association state, driver information, kernel events, packet counters, and router/client pings into a timestamped report.
The first report arrived after the severe condition had cleared: router latency averaged 3.4 ms, despite weak signal and continuing retries.
A later healthy report averaged 3.0 ms to the router.
Another direct measurement caught the hundreds-of-milliseconds problem again.

The fault was intermittent on a timescale of minutes.
This mattered because a healthy report did not disprove the preceding failure, and an improvement after a change could otherwise be confused with spontaneous recovery.
Capturing a report while SSH was actually slow was more useful than resetting state immediately.
The inspected kernel report did not show a firmware crash or driver timeout, but that was not proof that every driver or firmware interaction was healthy.

## What did the retry counters establish?

`iw` showed a weak 5 GHz signal, around -71 dBm, and substantial transmit-retry activity.
The counters were cumulative since association, so the investigation compared their changes over measurement windows rather than interpreting lifetime totals as current load.
It also measured the client, which had similar retry activity but a stronger signal and no corresponding severe delay in that sample.

Retries were therefore neither unique to the server nor confined to its degraded intervals.
The `tx retries` counter records retry attempts; dividing it by transmitted packets does not give the fraction of packets that needed a retry or ultimately failed.
One packet can require multiple attempts.
Latency, loss, and ultimately failed transmissions remained the practical outcomes to compare.

An intermittent wireless queue or radio-quality problem, possibly involving the driver and access point, was a hypothesis rather than a demonstrated internal mechanism.
The next useful experiment was to change the server's association while continuing to measure the same paths.

## Switching bands without losing the machine

The access point advertised 2.4 GHz and 5 GHz under the same SSID.
A single network name in a Wi-Fi menu therefore did not mean only one radio was available.
The investigation scanned for the radios and selected the 2.4 GHz BSSID explicitly for the test.
An initial script attempt failed its visibility check before changing the connection; a corrected scan found both radios.

Because the server had no attached keyboard, the experiment used cloned connection profiles with autoconnect disabled, not an immediate persistent edit to the original profile.
One clone selected the 2.4 GHz radio; another selected the known 5 GHz radio for recovery.
A systemd timer scheduled recovery in five minutes before a second unit scheduled the switch in five seconds.
Scheduling the switch server-side let it proceed if the SSH connection dropped.
The user ran the switch and subsequently reported working SSH.

The [NetworkManager wireless settings reference](https://networkmanager.dev/docs/api/latest/settings-802-11-wireless.html) documents `band=bg` for 2.4 GHz and `band=a` for 5 GHz, as well as selecting a BSSID.
BSSID locking can prevent roaming, and driver support varies.
The identifying values and machine-specific switching script are not copied here as a ready-to-run repair for another host.

## What changed in the measurements?

| Metric | Degraded 5 GHz sample | 2.4 GHz test |
| --- | --- | --- |
| Server signal | About -71 dBm | About -63 dBm |
| Server → router average | 249 ms | 2.6 ms |
| Client → server average, short test | 275 ms | 4.1 ms |
| Ping loss | Up to 12.5% in earlier samples | 0% in the test |

These are selected sequential samples, not simultaneous measurements or a long-term controlled benchmark.
The longer 2.4 GHz client-path report averaged 16.4 ms with occasional spikes, while the server's router path stayed good.
The client was still on 5 GHz, so the complete client path was not a pure measurement of the server's changed radio.

Retry activity did not disappear: the 2.4 GHz report recorded 1,438 retry attempts over 3,876 transmitted packets, with no ultimately failed transmissions.
Healthy and degraded 5 GHz samples also had overlapping retry activity.
The stronger 2.4 GHz association delivered good observed latency and loss despite retries; the result supported using it as a workaround, not declaring that retransmissions had been eliminated.
It did not establish exactly why the 5 GHz path sometimes degraded or prove a universal benefit from changing bands.

## The state left behind

Once SSH worked on 2.4 GHz, the user cancelled the recovery timer.
The session subsequently reported no remaining transient units, an active test profile with autoconnect disabled, and an inactive 5 GHz recovery profile.
The original profile still autoconnected and could select either band.

Thus the workaround was working for the current connection, but not cleanly persistent.
The session recommended applying the verified preference to the original profile and removing the temporary profiles, but did not record that work being completed.
No reboot, subsequent reconnect, or long-duration stability test was documented.

## Recognizing a recurrence

The distinguishing observation is large router latency during the SSH problem, not merely a weak signal or a large retry counter.
If router latency remains healthy while SSH is slow, this case does not establish the same failing path.
Even bad router latency can have other causes, so compare association state, load, loss, and more than one sample.
An Ethernet comparison would help isolate Wi-Fi further, but was not recorded as a completed test here.

Discover the interface and gateway rather than copying the original machine's values:

```bash
iw dev
nmcli device status
ip -4 route
```

On the server, replace the example interface below with the relevant Wi-Fi interface and run during the failure:

```bash
wifi_interface=wlp1s0
iw dev "$wifi_interface" link
iw dev "$wifi_interface" station dump
wifi_gateway=$(nmcli -g IP4.GATEWAY device show "$wifi_interface" | head -n 1)
if [ -n "$wifi_gateway" ]; then
    ip route get "$wifi_gateway"
    ping -n -I "$wifi_interface" -c 30 -i 1 -W 2 "$wifi_gateway"
fi
iw dev "$wifi_interface" station dump
```

Compare the before/after packet, retry, and failure counters, accounting for any reassociation that reset them.
Check the selected route and bind the ping to the intended Wi-Fi interface rather than assuming a gateway address cannot be reached through another route.
Run a corresponding ping to the server from the client and record whether each report caught a healthy or degraded interval.
Inspect relevant kernel messages if permitted; association output and kernel logs can expose network identifiers and should be reviewed before sharing.

## Reusing the workaround, and finishing it

Changing an association can drop SSH immediately.
For a remote-only host, arrange console access, a verified recovery connection and timer, or another reliable path before switching.
Confirm the intended access point is visible and that recovery can run independently of the SSH session.
The tested five-minute recovery was a safeguard, not a guarantee that every failure is recoverable.

After a successful test, record which profile is active and what will autoconnect next time.
If making a band restriction persistent, save the original settings first, modify only the intended profile, and test reconnect behavior when losing access is tolerable.
For example, `nmcli connection modify PROFILE_NAME 802-11-wireless.band bg` restricts that profile to 2.4 GHz on supported hardware; this is prospective guidance, not a command verified as completing the saved session's cleanup.
It does not fall back to 5 GHz if the 2.4 GHz network is unavailable.
Changing a saved profile and activating it are separate operations, and an old 5 GHz BSSID lock must not be left in a profile intended for 2.4 GHz.

To undo the experiment, reactivate the original profile using a safe access path and remove only the identified temporary profiles and recovery units once they are no longer needed.
Restore saved band/BSSID settings if a later persistent edit was made; clearing both values blindly could erase preexisting choices.
The recorded rollback cancellation did not itself make the test profile persistent.
