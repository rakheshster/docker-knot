# NOTE
I don't think anyone need use this as there's an official image available [here](https://hub.docker.com/r/cznic/knot). This `README` is intentionally bare as I don't think anyone would be using this container. 

# What is this? 
[Knot DNS](https://www.knot-dns.cz/) (for authoritative DNS; *not* a resolver). 

This container forked out of my [kea-knot](https://hub.docker.com/r/rakheshster/kea-knot) container. The latter has both ISC Kea (DHCP server) and Knot DNS (Kea can provide load balanced DHCP while Knot supports dynamic updates from Kea DHCP). I used to run that at home but recently (Feb 2021) I simplified things and now only need DNS. I could have just gone with the official Knot DNS container but I had this one around anyways and didn't want to let go. Also, mine is based on Alpine and I am attached to the [kea-knot](https://hub.docker.com/r/rakheshster/kea-knot) container for sentimental reasons (I learnt a lot of Docker concepts building it).

# Systemd (to have the container start automatically always)
Example unit file:

```
[Unit]
Description=Knot Container
Requires=docker.service
After=docker.service

[Service]
Restart=on-abort
ExecStart=/usr/bin/docker start -a $NAME
ExecStop=/usr/bin/docker stop -t 2 $NAME

[Install]
WantedBy=local.target
```

Copy this file to `/etc/systemd/system/`. 

Enable it in systemd via: `sudo systemctl enable <service file name>`.