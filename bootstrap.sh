#!/usr/bin/env bash
set -eo pipefail; [[ $TRACE ]] && set -x

# A script to bootstrap dokku.
# It expects to be run on Ubuntu 14.04 via 'sudo'
# If installing a tag higher than 0.3.13, it may install dokku via a package (so long as the package is higher than 0.3.13)
# It checks out the dokku source code from Github into ~/dokku and then runs 'make install' from dokku source.

# We wrap this whole script in functions, so that we won't execute
# until the entire script is downloaded.
# That's good because it prevents our output overlapping with wget's.
# It also means that we can't run a partially downloaded script.

ensure-environment() {
  echo "Preparing to install $DOKKU_TAG from $DOKKU_REPO..."
  if ! command -v apt-get &>/dev/null; then
    echo "This installation script requires apt-get. For manual installation instructions, consult http://dokku.viewdocs.io/dokku/advanced-installation/"
    exit 1
  fi

  hostname -f > /dev/null 2>&1 || {
    echo "This installation script requires that you have a hostname set for the instance. Please set a hostname for 127.0.0.1 in your /etc/hosts"
    exit 1
  }
}

install-requirements() {
  echo "--> Ensuring we have the proper dependencies"
  apt-get update -qq > /dev/null
}

install-dokku() {
  if [[ -n $DOKKU_BRANCH ]]; then
    install-dokku-from-source "origin/$DOKKU_BRANCH"
  elif [[ -n $DOKKU_TAG ]]; then
    install-dokku-from-source "tags/$DOKKU_TAG"
  else
      echo "DOKKU_BRANCH or DOKKU_TAG need to be set"
      exit 1
  fi
}


install-dokku-from-source() {
  local DOKKU_CHECKOUT="$1"
  
  apt-get -qq -y install git make software-properties-common
  cd /root
  if [[ ! -d /root/dokku ]]; then
    git clone "$DOKKU_REPO" /root/dokku
  fi

  cd /root/dokku
  git fetch origin
  [[ -n $DOKKU_CHECKOUT ]] && git checkout "$DOKKU_CHECKOUT"
  make install
  make dokku-installer
}

main() {
  export DEBIAN_FRONTEND=noninteractive
  export DOKKU_REPO=${DOKKU_REPO:-"https://github.com/mainto/dokku.git"}

  ensure-environment
  install-requirements
  install-dokku
}

main "$@"
