# interface-state — Mutating Commands (require root)

Open this when you need the exact command to add, remove, or change an address,
link, route, or neighbor entry. The non-persistence warning in SKILL.md
§ Mutating Commands applies to every command here.

## Addresses

```bash
sudo ip addr add 10.0.0.5/24 dev eth0        # assign an address
sudo ip addr add 10.0.0.5/24 dev eth0 label eth0:1   # labeled alias
sudo ip addr del 10.0.0.5/24 dev eth0        # remove an address
sudo ip addr flush dev eth0                  # remove ALL addresses on eth0
```

## Links

```bash
sudo ip link set eth0 up                     # bring interface up
sudo ip link set eth0 down                   # bring interface down
sudo ip link set eth0 mtu 9000               # set MTU (jumbo frames)
sudo ip link set eth0 address 02:11:22:33:44:55   # override MAC
sudo ip link add veth0 type veth peer name veth1  # create a veth pair
sudo ip link delete veth0                    # delete an interface
```

## Routes

```bash
sudo ip route add 192.168.5.0/24 via 10.0.0.1        # add a route
sudo ip route add default via 10.0.0.1 dev eth0      # set default gateway
sudo ip route add 10.1.0.0/16 dev eth0 metric 100    # metric-weighted route
sudo ip route del 192.168.5.0/24                     # remove a route
sudo ip route replace default via 10.0.0.254         # atomically swap default
```

## Neighbors

```bash
sudo ip neigh add 10.0.0.9 lladdr 00:11:22:33:44:55 dev eth0 nud permanent  # static ARP
sudo ip neigh del 10.0.0.9 dev eth0          # drop a neighbor entry
sudo ip neigh flush dev eth0                 # clear the cache on eth0
```
