#!/usr/bin/env bash
set -eo pipefail

# Resolve actual script dir even when sourced via symlink
ACTUAL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script_file="$(readlink -f "$0")"
script_dir="$(dirname "$script_file")"
deps="git rsync curl"
# declare files and dirs so they can be used during install and remove

GH_URL="https://raw.githubusercontent.com/scottmonster/sloot/refs/heads/master"
INSTALL_DIR="/usr/bin"
LOCAL_BIN="$HOME/.local/bin"
HELPER="domysloot"
USER_CONFIG_DIR="$HOME/.config/sloot"
REPO_DIR="${SLOOT_DIR:-$HOME/sloot}"

export HELPER_PATH="$LOCAL_BIN/$HELPER"


install_deps(){
  echo "installing deps: $deps"
  sudo apt install -y $deps
}

do_install(){
  install_deps
  # Use ACTUAL_SCRIPT_DIR for repo-local files
  asd="$ACTUAL_SCRIPT_DIR"


  # ENSURE REPO DIR
  if [ ! -d "$REPO_DIR" ]; then
    mkdir -p "$REPO_DIR"
  fi

  # ENSURE CONFIG IN REPO DIR
  if [ -f "$asd/.config" ]; then
    cp -f "$asd/.config" "$REPO_DIR/.config"
  elif [ ! -f "$asd/.config" ]; then
    echo "Downloading .config file..."
    curl -fsSL "$GH_URL/.config" -o "$REPO_DIR/.config"
  fi

  # EXPLICIT EXCLUDES TO USER CONFIG DIR
  if [ ! -d "$USER_CONFIG_DIR" ]; then
    mkdir -p "$USER_CONFIG_DIR"
  fi
  if [ -f "$asd/explicit_excludes" ]; then
    cp -f "$asd/explicit_excludes" "$USER_CONFIG_DIR/explicit_excludes"
  elif [ ! -f "$asd/explicit_excludes" ]; then
    echo "Downloading explicit_excludes file..."
    curl -fsSL "$GH_URL/explicit_excludes" -o "$USER_CONFIG_DIR/explicit_excludes"
  fi

  # INSTALL SLOOT
  if [ ! -d "$INSTALL_DIR" ]; then
    mkdir -p "$INSTALL_DIR"
  fi
  if [ -f "$asd/sloot" ]; then
    cp -f "$asd/sloot" "$INSTALL_DIR/sloot"
  elif [ ! -f "$asd/sloot" ]; then
    echo "Downloading sloot binary..."
    sudo curl -fsSL "$GH_URL/sloot" -o "$INSTALL_DIR/sloot"
  fi
  chmod 755 "$INSTALL_DIR/sloot"

  # HELPER
  if [ ! -d "$LOCAL_BIN" ]; then
    mkdir -p "$LOCAL_BIN"
  fi
  if [ -f "$asd/$HELPER" ]; then
    cp -f "$asd/$HELPER" "$LOCAL_BIN/$HELPER"
  elif [ ! -f "$asd/$HELPER" ]; then
    echo "Downloading $HELPER helper..."
    curl -fsSL "$GH_URL/$HELPER" -o "$LOCAL_BIN/$HELPER"
  fi
  chmod 755 "$LOCAL_BIN/$HELPER"


  # nopasswd entry
  # npfile="$ACTUAL_SCRIPT_DIR/files/nopasswd"
  nptext="$USER ALL=(root) NOPASSWD: $INSTALL_DIR/sloot"
  # write sudoers file atomically
  echo "$nptext" | sudo tee "/etc/sudoers.d/50-sloot-$USER" >/dev/null
  sudo chmod 440 "/etc/sudoers.d/50-sloot-$USER" || true

  # install user systemd units
  sysduser="$HOME/.config/systemd/user"
  mkdir -p "$sysduser"
  

  # SLOOT.SERVICE
  if [ -f "$asd/files/sloot.service" ]; then
    text="$(cat "$asd/files/sloot.service")"
  elif [ ! -f "$asd/files/sloot.service" ]; then
    echo "Downloading sloot.service file..."
    text="$(curl -fsSL "$GH_URL/files/sloot.service" )"
  fi
  expanded="$(envsubst <<<"$text")"
  echo "$expanded" > "$sysduser/sloot.service"

  # SLOOT.TIMER
  if [ -f "$asd/files/sloot.timer" ]; then
    text="$(cat "$asd/files/sloot.timer")"
  elif [ ! -f "$asd/files/sloot.timer" ]; then
    echo "Downloading sloot.timer file..."
    text="$(curl -fsSL "$GH_URL/files/sloot.timer")"
  fi
  expanded="$(envsubst <<<"$text")"
  echo "$expanded" > "$sysduser/sloot.timer"

  # reload and enable user units
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload || true
    systemctl --user enable sloot.service || true
    systemctl --user enable sloot.timer --now || true
  fi

  echo "sloot installed for user: $USER"
}


do_remove(){
  echo "Removing user-installed sloot files"

  asd="$ACTUAL_SCRIPT_DIR"
  localbin="$HOME/.local/bin"
  sysduser="$HOME/.config/systemd/user"

  # disable and remove user units
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user stop sloot.timer sloot.service || true
    systemctl --user disable sloot.timer sloot.service || true
    systemctl --user daemon-reload || true
  fi
  rm -f "$sysduser/sloot.service" "$sysduser/sloot.timer" || true

  # remove binaries
  rm -f "$localbin/sloot" "$localbin/dms" || true

  # remove user config files we installed (do not remove whole dirs)
  rm -f "$USER_CONFIG_DIR/explicit_excludes" || true
  rm -f "$REPO_DIR/.config" || true

  # remove sudoers entry
  sudo rm -f "/etc/sudoers.d/50-sloot-$USER" || true

  echo "sloot removed for user: $USER"
}


usage(){
  echo '
  Usage: setup.sh [options]
    -r, --remove        Remove aptpolicyd
    -h, --help          Show this help
  If no arguments provided, the script runs install.
  '
}


# default to install if no args
if [ "$#" -eq 0 ]; then
  do_install
  exit 0
fi

# Parse command line arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    -r|-remove|--r|--remove|remove)
      do_remove
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done