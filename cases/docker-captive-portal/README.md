# Docker blocked a Wi-Fi captive portal

An Ubuntu laptop connected to aircraft Wi-Fi but could not open the login page.
A Docker bridge claimed the network containing the portal's address, so Linux sent portal traffic toward Docker instead of the Wi-Fi gateway.

The immediate route workaround was reported successful on 2026-09-24.
The preventive change was to move Docker's default bridge and automatic network allocation into `10.153.0.0/16`, using small `/24` subnets.
The configuration passed `dockerd --validate`; after the user installed it and restarted Docker, the reported default bridge was `10.153.0.0/24`.
A later captive-portal connection and a newly allocated Compose network were not tested in the saved follow-up.

For the same symptom, `ip route get PORTAL_IP` is the decisive check: a Docker bridge instead of the expected Wi-Fi path identifies a routing conflict.
There is no universally collision-free private subnet; choose a range that does not overlap the networks and VPNs you actually use.
Restarting Docker can interrupt containers, and existing user-defined networks keep their old subnets until recreated.

Read the [investigation, repair, and undo notes](INVESTIGATION.md), or inspect the [recorded Docker configuration](daemon.json).
