# Build xrdp pulseaudio modules in builder container
# See https://github.com/neutrinolabs/pulseaudio-module-xrdp/wiki/README

ARG REPO_NAME_LC=REPO_NAME_LC
ARG TAG=latest
#ARG API_BACKEND_CONTAINER="api:backend"
#ARG API_STATIC_DIR="/var/www/static"
#FROM  $API_BACKEND_CONTAINER as source
#FROM $REPO_NAME_LC:build-cache as build-cache-source

FROM ubuntu:$TAG as builder

RUN sed -i -E 's/^# deb-src /deb-src /g' /etc/apt/sources.list \
    && apt-get update \
    && DEBIAN_FRONTEND="noninteractive" apt-get install -y --no-install-recommends \
        ccache \
        build-essential \
        dpkg-dev \
        git \
        libpulse-dev \
        pulseaudio \
    && apt-get build-dep -y pulseaudio \
    && apt-get source pulseaudio \
    && rm -rf /var/lib/apt/lists/*

RUN echo 'PATH=/usr/lib/ccache:$PATH ; export PATH' >> /etc/profile && echo 'PATH=/usr/lib/ccache:$PATH ; export PATH' >> /etc/profile.d/ccache.sh \
    && $(cd /usr/local/bin && ln -s /usr/lib/ccache/* . ) \
    && echo '# CCACHE_DIR' >> /etc/ccache.conf \
    && echo 'cache_dir /ccache' >> /etc/ccache.conf \
    && echo 'hard_link false' >> /etc/ccache.conf \
    && echo 'umask 002' >> /etc/ccache.conf \
    && echo 'max_size 2G' >> /etc/ccache.conf \
    && echo 'compression true' >> /etc/ccache.conf \
    && echo 'compression_level 3' >> /etc/ccache.conf \
    && echo '#find $CCACHE_DIR -type d | xargs chmod g+s' >> /etc/ccache.conf \
    && mkdir -p /ccache \
    && find /ccache -type d | xargs chmod g+s

#ARG REPO_NAME_LC=REPO_NAME_LC
# see https://github.com/docker/buildx/blob/master/docs/reference/buildx_build.md#cache-from
# and https://github.com/moby/moby/issues/34482#issuecomment-454716952
FROM $REPO_NAME_LC:build-cache as build-cache-source
FROM scratch
COPY --from=build-cache-source /ccache/ /ccache/

RUN cd /pulseaudio-$(pulseaudio --version | awk '{print $2}') \
    && ./configure

RUN git clone https://github.com/neutrinolabs/pulseaudio-module-xrdp.git /pulseaudio-module-xrdp \
    && cd /pulseaudio-module-xrdp \
    && ./bootstrap \
    && ./configure PULSE_DIR=/pulseaudio-$(pulseaudio --version | awk '{print $2}') \
    && make \
    && make install

#ARG REPO_NAME_LC=REPO_NAME_LC
#build-cache docker-remote-desktop-slim
#ARG TAG=build-cache
#ARG REPO_NAME_LC=REPO_NAME_LC
FROM scratch as build-cache
COPY --from=builder /ccache/ /ccache/

# Build the final image
FROM ubuntu:$TAG

RUN apt-get update \
    && DEBIAN_FRONTEND="noninteractive" apt-get install -y --no-install-recommends \
        dbus-x11 \
        firefox \
        git \
        locales \
        pavucontrol \
        pulseaudio \
        pulseaudio-utils \
        sudo \
        x11-xserver-utils \
        xfce4 \
        xfce4-goodies \
        xfce4-pulseaudio-plugin \
        xorgxrdp \
        xrdp \
        xubuntu-icon-theme \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i -E 's/^; autospawn =.*/autospawn = yes/' /etc/pulse/client.conf \
    && [ -f /etc/pulse/client.conf.d/00-disable-autospawn.conf ] && sed -i -E 's/^(autospawn=.*)/# \1/' /etc/pulse/client.conf.d/00-disable-autospawn.conf || : \
    && locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8

COPY --from=builder /usr/lib/pulse-*/modules/module-xrdp-sink.so /usr/lib/pulse-*/modules/module-xrdp-source.so /var/lib/xrdp-pulseaudio-installer/
COPY entrypoint.sh /usr/bin/entrypoint
EXPOSE 3389/tcp
ENTRYPOINT ["/usr/bin/entrypoint"]
