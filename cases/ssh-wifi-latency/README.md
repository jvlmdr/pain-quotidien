# Slow SSH turned out to be intermittent Wi-Fi latency

SSH to a Linux machine became painfully slow even though CPU, memory, and swap did not explain the delay.
Pinging the machine's own router reproduced the latency, moving the investigation below SSH to its Wi-Fi path.

On 2026-09-23, a temporary switch from the weaker 5 GHz association to 2.4 GHz improved router latency from about 249 ms during a degraded sample to 2.6 ms, with no loss in the 2.4 GHz test.
The test used an automatic rollback because the machine had no local keyboard and changing Wi-Fi could sever SSH.

This was a successful short-term workaround, not a completed persistent repair.
The rollback was cancelled, but the active test profile had autoconnect disabled and the original profile could still choose 5 GHz after reconnection or reboot.
The underlying radio/driver/access-point mechanism was not established.

For a similar issue, measure router latency during the failure before assuming SSH or swap is responsible.
Retry counters alone are not proof of a broken link: this connection remained healthy on 2.4 GHz despite substantial retries.
Do not change the only remote access path without a recovery plan, and do not assume 2.4 GHz is universally better.

Read the [investigation, measurements, and reuse notes](INVESTIGATION.md).
