DOKKU_VERSION = master

SSHCOMMAND_URL ?= https://raw.githubusercontent.com/mainto/sshcommand/armhf/sshcommand
PLUGN_URL ?= https://github.com/mainto/plugn/releases/download/v0.2.1/plugn_0.2.1_linux_armv7l.tgz
SIGIL_URL ?= https://github.com/mainto/sigil/releases/download/v0.4.0/sigil_0.4.0_Linux_armv7l.tgz
STACK_URL ?= https://github.com/mainto/herokuish.git
PREBUILT_STACK_URL ?= mainto/armhf-herokuish:v0.3.8
DOKKU_LIB_ROOT ?= /var/lib/dokku
PLUGINS_PATH ?= ${DOKKU_LIB_ROOT}/plugins
CORE_PLUGINS_PATH ?= ${DOKKU_LIB_ROOT}/core-plugins

# If the first argument is "vagrant-dokku"...
ifeq (vagrant-dokku,$(firstword $(MAKECMDGOALS)))
  # use the rest as arguments for "vagrant-dokku"
  RUN_ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  # ...and turn them into do-nothing targets
  $(eval $(RUN_ARGS):;@:)
endif

ifeq ($(CIRCLECI),true)
	BUILD_STACK_TARGETS = circleci deps build
else
	BUILD_STACK_TARGETS = build-in-docker
endif

.PHONY: all apt-update install version copyfiles man-db plugins dependencies sshcommand plugn docker aufs stack count dokku-installer vagrant-acl-add vagrant-dokku

include tests.mk
include deb.mk
include arch.mk

all:
	# Type "make install" to install.

install: docker_check dependencies version copyfiles plugin-dependencies plugins

release: deb-all package_cloud packer

docker_check:
	test -s /usr/bin/docker || (echo "docker is not installed. please install docker first."; exit 1)

package_cloud:
	package_cloud push dokku/dokku/ubuntu/trusty herokuish*.deb
	package_cloud push dokku/dokku/ubuntu/trusty sshcommand*.deb
	package_cloud push dokku/dokku/ubuntu/trusty plugn*.deb
	package_cloud push dokku/dokku/ubuntu/trusty dokku*.deb

packer:
	packer build contrib/packer.json

copyfiles:
	cp dokku /usr/local/bin/dokku
	test -d ~/.basher || mkdir -p ~/.basher && cp /bin/bash ~/.basher/bash
	mkdir -p ${CORE_PLUGINS_PATH} ${PLUGINS_PATH}
	rm -rf ${CORE_PLUGINS_PATH}/*
	test -d ${CORE_PLUGINS_PATH}/enabled || PLUGIN_PATH=${CORE_PLUGINS_PATH} plugn init
	test -d ${PLUGINS_PATH}/enabled || PLUGIN_PATH=${PLUGINS_PATH} plugn init
	find plugins/ -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | while read plugin; do \
		rm -Rf ${CORE_PLUGINS_PATH}/available/$$plugin && \
		rm -Rf ${PLUGINS_PATH}/available/$$plugin && \
		rm -rf ${CORE_PLUGINS_PATH}/$$plugin && \
		rm -rf ${PLUGINS_PATH}/$$plugin && \
		cp -R plugins/$$plugin ${CORE_PLUGINS_PATH}/available && \
		ln -s ${CORE_PLUGINS_PATH}/available/$$plugin ${PLUGINS_PATH}/available; \
		find /var/lib/dokku/ -xtype l -delete;\
		PLUGIN_PATH=${CORE_PLUGINS_PATH} plugn enable $$plugin ;\
		PLUGIN_PATH=${PLUGINS_PATH} plugn enable $$plugin ;\
		done
	chown dokku:dokku -R ${PLUGINS_PATH} ${CORE_PLUGINS_PATH}

addman:
	mkdir -p /usr/local/share/man/man1
	help2man -Nh help -v version -n "configure and get information from your dokku installation" -o /usr/local/share/man/man1/dokku.1 dokku
	mandb

version:
	git describe --tags > ~dokku/VERSION  2> /dev/null || echo '~${DOKKU_VERSION} ($(shell date -uIminutes))' > ~dokku/VERSION

plugin-dependencies: plugn
	sudo -E dokku plugin:install-dependencies --core

plugins: plugn docker
	test -d /home/dokku/.basher || mkdir /home/dokku/.basher
	test -s /home/dokku/.basher/bash || cp /bin/bash /home/dokku/.basher/bash
	sudo -E dokku plugin:install --core

dependencies: apt-update sshcommand plugn docker help2man man-db sigil
	$(MAKE) -e stack

apt-update:
	apt-get update

help2man:
	apt-get install -qq -y help2man

man-db:
	apt-get install -qq -y man-db

sshcommand:
	wget -qO /usr/local/bin/sshcommand ${SSHCOMMAND_URL}
	chmod +x /usr/local/bin/sshcommand
	sshcommand create dokku /usr/local/bin/dokku

plugn:
	wget -qO /tmp/plugn_latest.tgz ${PLUGN_URL}
	tar xzf /tmp/plugn_latest.tgz -C /usr/local/bin

sigil:
	wget -qO /tmp/sigil_latest.tgz ${SIGIL_URL}
	tar xzf /tmp/sigil_latest.tgz -C /usr/local/bin

docker:
	apt-get install -qq -y syslog-ng
	adduser --system --home /var/log/syslog-ng --gecos 'syslog-ng' --group syslog
	install -d -m0750 -o syslog -g dokku /var/log/syslog-ng
	egrep -i "^docker" /etc/group || groupadd docker
	usermod -aG docker dokku

aufs:
ifndef CI
	lsmod | grep aufs || modprobe aufs || apt-get install -qq -y linux-image-`uname -r` > /dev/null
endif

stack:
	docker images | grep mainto/armhf-herokuish || docker pull ${PREBUILT_STACK_URL}

count:
	@echo "Core lines:"
	@cat dokku bootstrap.sh | sed 's/^$$//g' | wc -l
	@echo "Plugin lines:"
	@find plugins -type f -not -name .DS_Store | xargs cat | sed 's/^$$//g' | wc -l
	@echo "Test lines:"
	@find tests -type f -not -name .DS_Store | xargs cat | sed 's/^$$//g' | wc -l

dokku-installer:
	test -f /var/lib/dokku/.dokku-installer-created || python contrib/dokku-installer.py onboot
	test -f /var/lib/dokku/.dokku-installer-created || service dokku-installer start
	test -f /var/lib/dokku/.dokku-installer-created || service nginx reload
	test -f /var/lib/dokku/.dokku-installer-created || touch /var/lib/dokku/.dokku-installer-created

vagrant-acl-add:
	vagrant ssh -- sudo sshcommand acl-add dokku $(USER)

vagrant-dokku:
	vagrant ssh -- "sudo -H -u root bash -c 'dokku $(RUN_ARGS)'"
