SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

UBUNTU_REPO ?= https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/resolute
UBUNTU_TAG ?= Ubuntu-7.0.0-43.43
KERNEL_VERSION ?= 7.0.0-999.1
PPA ?= ppa:CHANGE_ME/microvm

export UBUNTU_REPO UBUNTU_TAG KERNEL_VERSION PPA

.PHONY: help prepare config verify build source upload clean distclean

help:
	@printf '%s\n' \
	  'make prepare   Clone and patch the Ubuntu kernel source under work/linux' \
	  'make config    Render .config from Firecracker + fragments and import it' \
	  'make verify    Check the generated .config for required built-ins' \
	  'make build     Build the microvm flavour locally' \
	  'make source    Create a signed source package for the PPA' \
	  'make upload    Upload the source package to PPA=ppa:user/name' \
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

source: config
	./scripts/source-package.sh

upload: source
	./scripts/publish-ppa.sh

clean:
	rm -rf out

distclean: clean
	rm -rf work
