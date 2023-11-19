---
title: Accessing a machine behind NAT
date: 2021-10-31T12:04:50+02:00
---
I have a remote machine that I have to occasionally maintain. There is no easy way to connect to it, since all available ISPs at that place can only offer IPv4 (which nowadays means NAT) and not IPv6.

<!--more-->

For this purpose I chose WireGuard, which is probably the simplest and fastest VPN solution available today. There is a great number of articles on this topic on the web. I mostly followed [this one](https://www.digitalocean.com/community/tutorials/how-to-set-up-wireguard-on-ubuntu-20-04), but used other available sources as well.

# Base setup

Generate private and public keys for each peer using `wg genkey` and `wg pubkey`:

```
wg genkey | tee private.key | wg pubkey > public.key
```

Configure `/etc/wireguard/wg0.conf` on the server. Well, in the WireGuard world all machines are just "peers", however let's call the machine with a public IP a "server" for brevity. I use this as a template:

```
[Interface]
PrivateKey = $PRIVATE_KEY # The server private key
Address = 10.8.0.1
ListenPort = $PORT
SaveConfig = true
```

Configure `/etc/wireguard/wg0.conf` on other peers that connect to our server. I use this as a template:

```
[Interface]
PrivateKey = $PRIVATE_KEY # The current peer private key
Address = 10.8.0.$NUMBER/24

[Peer]
PublicKey = $PUBLIC_KEY # The server public key
AllowedIPs = 10.8.0.0/24
PersistentKeepalive = 25
Endpoint = $ADDRESS:$PORT
```

Note that I set [PersistentKeepalive](https://www.wireguard.com/quickstart/#nat-and-firewall-traversal-persistence), without this settings you might not be able to access machines behind NAT after some time.

Add a new `[Peer]` section to your server config:

```
[Peer]
PublicKey = $PUBLIC_KEY # The public key of the new peer
AllowedIPs = 10.8.0.$NUMBER/32
```

That is it! You can bring up the interface using `wg-quick up wg0` on both ends. You can also use `wg-quick@wg0.service` to start the tunnel automatically using systemd.

# Forwarding

In order to allow the peers to communicate with each other we also need to enable packet forwarding.

Set the following variables in `/etc/sysctl.conf`:

```
net.ipv4.ip_forward = 1
```

Enable forwarding on wg0:

```
iptables -A FORWARD -i wg0 -o wg0 -j ACCEPT
```

# Masquerading (optional)

If you also want to route external traffic through the server, enable packet forwarding and masquerading on the external interface:

```
iptables -A FORWARD -i wg0 -o $INTERFACE -j ACCEPT
iptables -t nat -I POSTROUTING -o $INTERFACE -j MASQUERADE
```

In this case also make sure to update `AllowedIPs` to `0.0.0.0/0` on the peers:

```
[Peer]
PublicKey = $PUBLIC_KEY
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
Endpoint = $ADDRESS:$PORT
```

At this point you should have a working setup that allows peers to send packets to each other and (optionally) even route your external traffic through the server. Have fun using WireGuard!
