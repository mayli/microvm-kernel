FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

# The Ubuntu kernel build needs the source package build-dependencies.  Install
# them from the resolute archive instead of maintaining a hand-written list.
RUN sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources \
 && apt-get update \
 && apt-get build-dep -y linux \
 && apt-get install -y --no-install-recommends \
      bc bison flex libssl-dev libelf-dev dwarves zstd cpio kmod rsync \
      fakeroot dpkg-dev python3 python3-dev libpython3-dev python3-setuptools \
      ca-certificates curl git \
 && rm -rf /var/lib/apt/lists/*
