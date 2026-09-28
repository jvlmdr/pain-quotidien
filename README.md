# Everyday machine fixes with AI agents

Small, annoying computer problems that became fixable with help from AI agents.
These notes share the working fixes and the reasoning that found them, for curious readers and future troubleshooting.

## Fixes

- [Ubuntu automatic timezone was not updating](cases/ubuntu-automatic-timezone/): repairing a retired location provider exposed a second GNOME bug; a small native backport restored automatic timezone selection.
- [Docker blocked a Wi-Fi captive portal](cases/docker-captive-portal/): a bridge subnet captured portal traffic; a temporary route workaround was followed by a smaller custom Docker address pool.
- [Slow SSH turned out to be intermittent Wi-Fi latency](cases/ssh-wifi-latency/): router pings isolated the slow path, and a protected 2.4 GHz test restored good latency; persistent cleanup remained unfinished.

Each entry starts with the short version, with details and supporting artifacts nearby.
The fixes describe specific machines and versions, not universal prescriptions.
