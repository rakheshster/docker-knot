# Knot + Docker
![Buildx & Push [Alpine]](https://github.com/rakheshster/docker-knot/workflows/Docker%20Build%20&%20Push/badge.svg)

> **I don't think anyone need use this as there's an official image available [here](https://hub.docker.com/r/cznic/knot).**

# What is this? 
[Knot DNS](https://www.knot-dns.cz/) (for authoritative DNS; *not* a resolver). 

This container forked out of my [kea-knot](https://github.com/rakheshster/docker-knot) container. The latter packaged both ISC Kea (DHCP server) and Knot DNS. Kea can provide load balanced DHCP (as in a pair of Kea servers can provide DHCP to a subnet such that if one goes down the other takes over) while Knot DNS can accept dynamic DNS updates from Kea DHCP (so when Kea hands out an IP address it can create a DNS mapping). I used to run that at home but recently (Feb 2021) I simplified things and now only need DNS. I could have just gone with the official Knot DNS container but I had this one around anyways and didn't want to let go. Also, mine is based on Alpine and I am attached to the [kea-knot](https://github.com/rakheshster/docker-knot) container for sentimental reasons (I learnt a lot of Docker concepts building it).

# Getting this
It is best to target a specific release when pulling this repo. Either switch to the correct tag after downloading, or download a zip of the latest release from the [Releases](https://github.com/rakheshster/docker-knot/releases) page. In the interest of speed however, as mentioned above I'd suggest downloading the built image from Docker Hub at [rakheshster/knot](https://hub.docker.com/repository/docker/rakheshster/knot).

Version numbers are of the format `<knot version>-<patch>`. I will update the `<patch>` number when there's any change introduced by me (e.g. a change to the Dockerfile or the base image).

# s6-overlay
This image contains [s6-overlay](https://github.com/just-containers/s6-overlay). I like their philosophy of a Docker container being “one thing” rather than “one process per container”. 

# Running this
## Data
Knot has 1) its config file at `/etc/knot` and 2) stores its zones database at `/var/lib/knot/zones`. The latter is where we store our zones but these can be dynamically updated by Knot due to Dynamic DNS or DNSSEC, hence the location of `/var/lib` to store them. This is a design decision I went.

I would recommend making Docker volumes for each of these locations and mapping them to the container. You don't need to keep the leases or zone DBs out of the container, but I prefer it that way. The way I run it at home is thus:

```
# name of the container; also used as a prefix for the volumes
NAME="kea-knot"
IMAGE="rakheshster/knot:3.0.4-3"

# create Docker volumes to store data
KNOT_CONFIG=${NAME}_knotconfig && docker volume create $KNOT_CONFIG
KNOT_ZONES=${NAME}_knotzones && docker volume create $KNOT_ZONES

# run the container
docker create --name "$NAME" \
    -p 53:53 \
    --restart=unless-stopped \
    --cap-add=NET_ADMIN \
    -e TZ="Europe/London" \
    -e TESTZONE="raxnet.uk"
    --mount type=volume,source=$KNOT_CONFIG,target=/etc/knot \
    --mount type=volume,source=$KNOT_ZONES,target=/var/lib/knot/zones \
    $IMAGE
```

The `.scripts/createcontainer.sh` script does exactly this. It creates the volumes and container as above and also outputs a systemd service unit file so the container is automatically launched by systemd as a service. The script does not start the container however, you can do that via `docker start <container name>`. 

The timezone variable `TZ` in the `docker run` command is useful so Knot sets timestamps correctly. Also, Knot needs the `NET_ADMIN` capability to bind on port 53. I like to have a macvlan network with a separate IP for this container, but that's just my preference. The `.scripts/createcontainer.sh` lets you specify the IP address and network name and if none is specified it uses the "bridge" network  (as in the above snippet). 

## Knot zone editing
The Knot documentation gives steps on how to edit the zone files safely. To make it easy I include a script called `vizone`. This is copied to the `/sbin` folder of the container. Simply do the following to edit a zone safely and have Knot reload. 

```
docker exec -it <container name> vizone <zone name>
```

This script is a wrapper around the four commands specified in [this section](https://www.knot-dns.cz/docs/2.8/html/operation.html#reading-and-editing-the-zone-file-safely) of the Knot documentation. You can also `docker exec -it <container name> knotc <options>` too. My script is entirely optional. 

## Knot zone behaviour
As said above the Knot zones are stored at `/var/lib/knot/zones` and by default Knot overwrites the zone files with changes. This behaviour is controlled by the `zonefile-sync` configuration parameter (default value is `0` which tells Knot to [update the file as soon as possible](https://www.knot-dns.cz/docs/2.8/singlehtml/index.html#zonefile-sync); it is possible to disable this by setting the value to `-1` (in which case the `knotc zone-flush` command can be used to perform a manual sync or dump the changes to a separate file)). 

The [zone loading](https://www.knot-dns.cz/docs/2.8/singlehtml/index.html#zone-loading), [journal behaviour](https://www.knot-dns.cz/docs/2.8/singlehtml/index.html#journal-behaviour), and [examples](https://www.knot-dns.cz/docs/2.8/singlehtml/index.html#example-1) sections in the Knot documentation are worth a read. The journal is where Knot saves changes to the zone file and is typically used to answer IXFR queries (this too can be changed such that the journal has both the zone and changes in it). By default the journal is [stored in a folder](https://www.knot-dns.cz/docs/2.7/html/reference.html#journal-db) called `journal` under `/var/lib/knot/zones`. 

The default settings for these values are as follows (this is not explicitly stated in the example `knot.conf` file):
```
zonefile-sync: 0
zonefile-load: whole
journal-content: changes
```

If you want to disable the zone file from being overwritten and would prefer all changes be stored in the journal change these to:
```
zonefile-sync: -1
zonefile-load: difference-no-serial
journal-content: changes
```

Do refer to the Knot documentation for more info though. I am no Knot expert and the above is just what I use at home. 

## Reloading
If you want to reload Knot or Kea I provide some useful wrapper scripts. These simply use `s6` to reload the appropriate service. To reload Knot for instance, do:

```
docker exec -it <container name> knot-reload
```

## Systemd (to have the container start automatically always)
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
