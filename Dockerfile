# I am pulling in my alpine-s6 image as the base here so I can reuse it for the common buildimage and later in the runtime. 
# Initially I used to pull this separately at each stage but that gave errors with docker buildx for the BASE_VERSION argument.
ARG BASE_VERSION=3.13-2.2.0.3
FROM rakheshster/alpine-s6:${BASE_VERSION} AS mybase

################################### COMMON BUILDIMAGE ####################################
# This image is to be a base where all the build dependencies are installed. 
# I can use this in the subsequent stages to build stuff
FROM mybase AS alpinebuild

# I realized that the build process doesn't remove this intermediate image automatically so best to LABEL it here and then prune later
# Thanks to https://stackoverflow.com/a/55082473
LABEL stage="alpinebuild"
LABEL maintainer="Rakhesh Sasidharan"

# Get the build-dependencies for everything I plan on building later
# common stuff: git build-base libtool xz cmake gnupg (to verify)
# knot dns: pkgconf gnutls-dev userspace-rcu-dev libedit-dev libidn2-dev fstrm-dev protobuf-c-dev lmdb-dev linux-headers
RUN apk add --update --no-cache \
    git build-base libtool xz cmake gnupg \
    pkgconf gnutls-dev userspace-rcu-dev libedit-dev libidn2-dev fstrm-dev protobuf-c-dev lmdb-dev linux-headers
RUN rm -rf /var/cache/apk/*

################################## BUILD KNOT DNS ####################################
# This image is to only build Knot DNS
FROM alpinebuild AS alpineknot

ENV KNOTDNS_VERSION 3.0.4

LABEL stage="alpineknot"
LABEL maintainer="Rakhesh Sasidharan"

# Download the source & build it
ADD https://secure.nic.cz/files/knot-dns/knot-${KNOTDNS_VERSION}.tar.xz /tmp/
ADD https://secure.nic.cz/files/knot-dns/knot-${KNOTDNS_VERSION}.tar.xz.asc /tmp/
# Import the PGP key used by cz.nic (https://www.knot-dns.cz/download/)
# As above, the import fails on Debian if I download from the default keys.openpgp.org server so use keyserver.ubuntu.com instead
RUN gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys 0x10BB7AF6FEBBD6AB
# Verify the download (exit if it fails)
RUN gpg --status-fd 1 --verify /tmp/knot-${KNOTDNS_VERSION}.tar.xz.asc /tmp/knot-${KNOTDNS_VERSION}.tar.xz 2>/dev/null | grep -q "GOODSIG 10BB7AF6FEBBD6AB" \
    || exit 1

WORKDIR /src
RUN tar xf /tmp/knot-${KNOTDNS_VERSION}.tar.xz -C ./
WORKDIR /src/knot-${KNOTDNS_VERSION}
# Configure knot to expect everything in / (--prefix=/) but when installing put everything into /usr/local (via DESTDIR=) (I copy the contents of this to / in the final image)
RUN ./configure --prefix=/ --enable-dnstap --disable-systemd
RUN make && DESTDIR=/usr/local make install

################################### RUNTIME ENVIRONMENT FOR KEA & KNOT ####################################
# This image has all the runtime dependencies, the built files from the previous stage, and I also create the groups and assign folder permissions etc. 
# I got to create the folder after copying the stuff from previous stage so the permissions don't get overwritten
FROM mybase AS alpineruntime

# Get the runtimes deps for all
# Knot: libuv luajit lmdb gnutls userspace-rcu libedit libidn2
RUN apk add --update --no-cache ca-certificates tzdata \
    drill \
    libuv luajit lmdb gnutls userspace-rcu libedit libidn2 fstrm protobuf-c \
    nano
RUN rm -rf /var/cache/apk/*

# /usr/local/bin -> /bin etc.
COPY --from=alpineknot /usr/local/ /

RUN addgroup -S knot && adduser -D -S knot -G knot
RUN mkdir -p /var/lib/knot && chown knot:knot /var/lib/knot
RUN mkdir -p /var/run/knot && chown knot:knot /var/run/knot

################################### FINALIZE ####################################
# This pulls in the previous stage, adds S6. This is my final stage. 
FROM alpineruntime

LABEL maintainer="Rakhesh Sasidharan"
LABEL org.opencontainers.image.source=https://github.com/rakheshster/docker-knot

# Copy the config files & s6 service files to the correct location
COPY root/ /

# NOTE: s6 overlay doesn't support running as a different user. However, Knot is configured to run as a non-root user in its config. Kea needs to run as root. 

EXPOSE 53/udp 53/tcp
# Knot DNS runs on 53. 

HEALTHCHECK --interval=5s --timeout=3s --start-period=5s \
    CMD drill @127.0.0.1 -p 53 ${TESTZONE} || exit 1

ENTRYPOINT ["/init"]
