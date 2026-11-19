SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

UBUNTU_REPO ?= https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/resolute
UBUNTU_TAG ?= Ubuntu-7.0.0-43.43
UBUNTU_SOURCE_VERSION ?= 7.0.0-43.43
USE_APT_SOURCE ?= 1
KERNEL_VERSION ?= 7.0.0-999.1

export UBUNTU_REPO UBUNTU_TAG UBUNTU_SOURCE_VERSION USE_APT_SOURCE KERNEL_VERSION

.PHONY: help prepare config verify build boot-test clean distclean

help:
	@printf '%s\n' \
	  'make prepare   Clone and patch the Ubuntu kernel source under work/linux' \
	  'make config    Render .config from Firecracker + fragments and import it' \
	  'make verify    Check the generated .config for required built-ins' \
	  'make build     Build the microvm flavour locally' \
	  'make boot-test Boot the built vmlinuz in QEMU/KVM and check guest features' \
	  'make clean     Remove out/ (keeps the kernel source clone)' \
	  'make distclean Remove out/ and work/'

prepare:
	./scripts/prepare-source.sh

config: prepare
	./scripts/render-config.sh

verify: config
	./scripts/verify-config.sh

build: config
	./scripts/build-local.sh

boot-test:
	./scripts/boot-test.sh

clean:
	rm -rf out

distclean: clean
	rm -rf work
