# Investigation: Docker blocked a Wi-Fi captive portal

Recorded on 2026-09-24, on an Ubuntu laptop running Linux Docker Engine.
The exact Ubuntu and Docker versions were not established in the material used for this write-up.
The immediate repair was described in a pasted ChatGPT conversation; its model was not recorded.
The follow-up used Claude Code `2.1.281`, model `claude-opus-5-5`, verified from the saved transcript metadata.
This account was reconstructed on 2026-09-29, not retested against the aircraft network.
Hostnames, Wi-Fi identifiers, and bridge IDs are omitted; the private address ranges are retained because they explain the route selection.

## Why could Wi-Fi connect but the login page fail?

The laptop had a Wi-Fi address and DNS server, but ordinary HTTP requests failed before reaching the login page.
DNS resolved the requested HTTP sites to the captive portal at `172.19.1.1`.
Curl then reported a connection attempt from `172.19.0.1` ending in `No route to host`.
That source address belonged to a Docker bridge, not the Wi-Fi interface.

Meanwhile, a request to another private address returned an HTTP 307 redirect to the login site.
This showed that at least part of the aircraft network was reachable and narrowed the problem beyond a simple failure to associate with Wi-Fi.
Failed pings to a public address before portal login were not sufficient to diagnose the fault.

The route table supplied the explanation:

| Route | Does it contain portal address `172.19.1.1`? |
| --- | --- |
| `172.19.0.0/16` on a Docker bridge | Yes. |
| `172.19.206.0/23` on Wi-Fi | No. |
| Default route through the Wi-Fi gateway | Matches every IPv4 destination, but is less specific than the Docker route. |

The portal lay outside the directly connected Wi-Fi subnet, even though it was part of the wider network accessible through the Wi-Fi gateway.
The Docker `/16` was a more specific match than the default route and captured that destination.
The apparent portal failure was therefore a local routing conflict, not evidence that the portal itself was down.

ChatGPT suggested deleting the exact conflicting route as a temporary workaround.
The user opened the Claude follow-up by saying that ChatGPT had solved the Wi-Fi problem.
The pasted material contains the before-state and suggested workaround, but not an after-state capture of the portal loading.
The immediate success is a user-reported result, not an independently repeated test in this write-up.

## Was there something unusual in the Docker setup?

By the follow-up, the offending user-defined bridge had disappeared.
There was no `/etc/docker/daemon.json` or inspected systemd service override supplying a custom address pool.
The remaining default bridge used a different `172.x` subnet.
A running container used host networking, so it did not explain the removed bridge.

Compose projects with implicit default bridge networks were plausible sources, but the exact project that created the offending bridge was not established.
That uncertainty did not prevent identifying the general failure: automatically allocated Docker subnets can conflict with networks a laptop later joins.
Docker's [networking documentation](https://docs.docker.com/engine/network/) explains how automatic subnet allocation uses address pools and why custom pools may be needed to avoid routing conflicts.
An overlap check at creation cannot guarantee compatibility with future networks, and the directly connected Wi-Fi subnet alone did not describe every reachable private destination in this case.

## Preventing another collision

The selected [daemon.json](daemon.json) separates two jobs:

- `bip` assigns `10.153.0.1/24` to the default Docker bridge.
- `default-address-pools` supplies `/24` subnets from `10.153.0.0/16` for new automatically allocated networks.

The [Docker daemon reference](https://docs.docker.com/reference/cli/dockerd/) documents these settings and configuration validation.
The number 153 was a choice, not a reserved or universally safe Docker range.
The follow-up found no current route using the selected block.
That does not prove it will never conflict with a VPN, office LAN, or another network visited later.
Smaller individual subnets limit what each bridge claims, but do not eliminate address collisions.
Explicitly configured networks can also use addresses outside the selected pool.

The configuration passed `dockerd --validate`, and the user was given privileged installation and restart commands.
Afterward, the transcript records `docker0` at `10.153.0.1` with subnet `10.153.0.0/24`.
The default bridge was marked `linkdown`, consistent with no containers being attached to it at that moment.
No new Compose bridge or later aircraft login was tested in the follow-up; their expected behavior should not be mistaken for an observed result.

## Checking another machine

Resolve or obtain the portal address, then inspect the route to that destination, not just the laptop's own Wi-Fi subnet:

```bash
ip -4 route
ip route get 172.19.1.1
docker network ls
```

Replace `172.19.1.1` with that network's actual portal address.
Inspect candidate Docker networks with `docker network inspect NETWORK_NAME` and compare their subnets with the selected route.
The routing commands are read-only; Docker inspection requires access to the Docker daemon.
That access is powerful and should not be granted merely to run this check.

If the portal route already goes through the expected Wi-Fi interface and gateway, the defining evidence here is absent.
Investigate other causes rather than deleting Docker networks reflexively.
VPN routes, custom policy routing, proxies, and DNS behavior can produce different problems with a similar symptom.

## A temporary route workaround

When the destination is demonstrably captured by a Docker route and the affected container connectivity can be interrupted, remove only that exact route to test the diagnosis.
Record the complete original route first, including its interface and attributes, so it can be restored.
The original repair used this shape, with placeholders that must be replaced from the current route table:

```bash
sudo ip route del SUBNET dev DOCKER_BRIDGE_INTERFACE
ip route get PORTAL_IP
```

This changes host routing and may break access to containers on that subnet.
It does not delete the Docker network or prevent Docker from recreating the route.
Verify the portal now uses the expected Wi-Fi path and actually loads; a successful route deletion alone is not a successful login.
Restore the recorded route when needed, and treat the address-pool change below as a separate preventive decision.
If traffic is not taking that exact Docker route, this is not the appropriate test.

## Applying the preventive configuration

These instructions concern a rootful Linux Docker Engine, not Docker Desktop or a rootless daemon with different configuration paths.
Inspect the daemon's startup configuration and the routes present on networks and VPNs used regularly before selecting a pool.
If `/etc/docker/daemon.json` already exists, back it up and merge the relevant keys rather than replacing unrelated configuration with this small example.

From this case's directory, validate the candidate without starting another daemon:

```bash
dockerd --validate --config-file daemon.json
```

For a machine with no existing configuration, the recorded installation shape was:

```bash
sudo install -d -m755 /etc/docker
sudo install -m644 daemon.json /etc/docker/daemon.json
sudo systemctl restart docker
ip -4 route show dev docker0
```

Restarting the daemon can interrupt workloads; schedule it with their owners rather than assuming host networking makes a container immune to a restart.
Existing user-defined networks retain their subnets.
Recreate only the specific conflicting networks when their workloads can tolerate it; blanket pruning is not needed to establish the diagnosis.
Check `ip route get PORTAL_IP` again and verify the actual login page, not only the existence of a new Docker route.

## Maintenance and undo

If another collision occurs, inspect the actual selected route and revise the pool if necessary.
Do not treat all `172.x` addresses as private: the private block is `172.16.0.0/12`, not the whole `172.0.0.0/8`.

To undo, restore the previous daemon configuration, or remove only the added networking keys if other settings now coexist with them.
When the file was created solely for this fix and is still unchanged, removing that specific file restores automatic defaults after a Docker restart.
Networks created under the custom pool do not automatically revert; their recreation remains a separate, potentially disruptive operation.
The old defaults may reintroduce the original conflict.
