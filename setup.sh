#!/usr/bin/env bash
set -eo pipefail

# Resolve actual script dir even when sourced via symlink
ACTUAL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script_file="$(readlink -f "$0")"
script_dir="$(dirname "$script_file")"
deps="git rsync"
# declare files and dirs so they can be used during install and remove


install_deps(){
  echo "installing deps: $deps"
  sudo apt install -y "$deps"
}

install(){
  install_deps
  # Use ACTUAL_SCRIPT_DIR for repo-local files
  asd="$ACTUAL_SCRIPT_DIR"

  # ensure repo dir exists and copy .config
  REPO_DIR="${SLOOT_DIR:-$HOME/sloot}"
  if [ ! -d "$REPO_DIR" ]; then
    mkdir -p "$REPO_DIR"
  fi
  if [ -f "$asd/.config" ]; then
    cp -f "$asd/.config" "$REPO_DIR/.config"
  fi

  # explicit excludes to user config dir
  USER_CONFIG_DIR="$HOME/.config/sloot"
  if [ ! -d "$USER_CONFIG_DIR" ]; then
    mkdir -p "$USER_CONFIG_DIR"
  fi
  if [ -f "$asd/explicit_excludes" ]; then
    cp -f "$asd/explicit_excludes" "$USER_CONFIG_DIR/explicit_excludes"
  fi

  # copy binaries to ~/.local/bin
  localbin="$HOME/.local/bin"
  if [ ! -d "$localbin" ]; then
    mkdir -p "$localbin"
  fi
  if [ -f "$asd/sloot" ]; then
    cp -f "$asd/sloot" "$localbin/sloot"
    chmod 755 "$localbin/sloot"
  fi
  if [ -f "$asd/dms" ]; then
    cp -f "$asd/dms" "$localbin/dms"
    chmod 755 "$localbin/dms"
  fi

  # nopasswd entry
  npfile="$ACTUAL_SCRIPT_DIR/files/nopasswd"
  nptext="$USER ALL=(root) NOPASSWD: $HOME/.local/bin/sloot"
  # write sudoers file atomically
  echo "$nptext" | sudo tee "/etc/sudoers.d/50-sloot-$USER" >/dev/null
  sudo chmod 440 "/etc/sudoers.d/50-sloot-$USER" || true

  # install user systemd units
  sysduser="$HOME/.config/systemd/user"
  mkdir -p "$sysduser"
  if [ -f "$asd/files/sloot.service" ]; then
    cp -f "$asd/files/sloot.service" "$sysduser/sloot.service"
  fi
  if [ -f "$asd/files/sloot.timer" ]; then
    cp -f "$asd/files/sloot.timer" "$sysduser/sloot.timer"
  fi

  # reload and enable user units
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload || true
    systemctl --user enable sloot.service || true
    systemctl --user enable sloot.timer --now || true
  fi

  echo "sloot installed for user: $USER"
}


remove(){
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
  cat <<'
  Usage: setup.sh [options]
    -r, --remove        Remove aptpolicyd
    -h, --help          Show this help
  If no arguments provided, the script runs install.
  '
}


# default to install if no args
if [ "$#" -eq 0 ]; then
  install
  exit 0
fi

# Parse command line arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    -r|-remove|--r|--remove|remove)
      remove
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