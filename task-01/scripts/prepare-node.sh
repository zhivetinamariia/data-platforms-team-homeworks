#!/usr/bin/env bash
set -Eeuo pipefail

MODE="${1:---check}"
VERSION=3.4.0
HOME_DIR=/home/hadoop
HADOOP_HOME="$HOME_DIR/hadoop-$VERSION"
JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ "$#" -le 1 && ( "$MODE" == --check || "$MODE" == --install ) ]] ||
  fail "Usage: $0 [--check|--install]"

check_installation() {
  echo "===== $(hostname): installation check ====="

  id hadoop
  [[ "$(getent passwd hadoop | cut -d: -f6)" == "$HOME_DIR" ]] ||
    fail "Unexpected home directory for hadoop"

  [[ -x "$JAVA_HOME/bin/java" ]] ||
    fail "Java 11 executable not found"

  [[ -x "$HADOOP_HOME/bin/hadoop" ]] ||
    fail "Hadoop executable not found"

  local version_output
  version_output="$(sudo -n -u hadoop env JAVA_HOME="$JAVA_HOME" \
    "$HADOOP_HOME/bin/hadoop" version)"
  printf '%s\n' "$version_output"

  grep -Fxq "Hadoop $VERSION" <<< "$version_output" ||
    fail "Unexpected Hadoop version"

  echo "PASS: hadoop user, Java and Hadoop $VERSION are present"
}

if [[ "$MODE" == --check ]]; then
  check_installation
  exit 0
fi

[[ "$EUID" == 0 ]] ||
  fail "Installation requires root: sudo bash prepare-node.sh --install"

[[ "$(uname -m)" == x86_64 ]] ||
  fail "This script supports the x86_64 Hadoop archive only"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
  openjdk-11-jdk-headless openssh-server openssh-client \
  curl ca-certificates tar

systemctl enable --now ssh

if ! id hadoop >/dev/null 2>&1; then
  useradd --create-home --home-dir "$HOME_DIR" --shell /bin/bash hadoop
fi

[[ "$(getent passwd hadoop | cut -d: -f6)" == "$HOME_DIR" ]] ||
  fail "Existing hadoop user has an unexpected home directory"

if [[ -e "$HADOOP_HOME" ]]; then
  echo "SKIP: Existing Hadoop directory will not be overwritten"
  check_installation
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

archive="hadoop-$VERSION.tar.gz"
base="https://archive.apache.org/dist/hadoop/common/hadoop-$VERSION"

curl --fail --location --retry 3 \
  "$base/$archive" -o "$work/$archive"

curl --fail --location --retry 3 \
  "$base/$archive.sha512" -o "$work/$archive.sha512"

expected="$(grep -Eo '[[:xdigit:]]{128}' "$work/$archive.sha512")"
[[ "${#expected}" == 128 ]] ||
  fail "Cannot parse the official SHA-512 checksum"

actual="$(sha512sum "$work/$archive" | awk '{print $1}')"
[[ "${actual,,}" == "${expected,,}" ]] ||
  fail "Hadoop archive SHA-512 mismatch"

echo "PASS: Archive SHA-512 verified"

tar -xzf "$work/$archive" -C "$work"
[[ -x "$work/hadoop-$VERSION/bin/hadoop" ]] ||
  fail "Unexpected archive contents"

chown -R hadoop:hadoop "$work/hadoop-$VERSION"
mv "$work/hadoop-$VERSION" "$HADOOP_HOME"

check_installation
