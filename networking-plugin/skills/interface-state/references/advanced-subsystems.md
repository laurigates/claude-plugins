# interface-state — Modern Subsystems

Open this when the question involves policy routing, non-main routing tables,
network namespaces, VLAN/bond/bridge/vxlan devices, or the bridge forwarding DB.

## Modern Subsystems net-tools Never Covered

```bash
ip rule                     # policy routing rules (which table applies to what)
ip route show table 100     # a specific non-main routing table
ip netns list               # network namespaces (the base under containers)
ip netns exec <ns> ip -br a # run any command inside a namespace
ip -br link show type vlan   # VLAN interfaces
ip -d link show <dev>        # -d = driver/type detail (bond, bridge, vxlan…)
bridge -c fdb show           # bridge forwarding DB (iproute2 bridge tool)
bridge vlan show             # per-port VLAN membership on a bridge
```
