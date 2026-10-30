#!/bin/sh
# syncwhole installer. On a new machine:
#
#   curl -fsSL https://raw.githubusercontent.com/n4n0byte/syncwhole-install/main/install.sh | sh -s -- --name NODE
#
# It asks you to approve a code at github.com/login/device, uses that short-lived token
# to download the agent from the private repo and register this machine's deploy key,
# then forgets it. Nothing else has to be online.
set -eu

# Client ID of the syncwhole GitHub App (public; see docs/design.md, "Enrollment").
DEFAULT_CLIENT_ID=""

REPO="${SYNCWHOLE_REPO:-n4n0byte/syncwhole}"
CLIENT_ID="${SYNCWHOLE_CLIENT_ID:-$DEFAULT_CLIENT_ID}"
WEB="${SYNCWHOLE_GITHUB_WEB:-https://github.com}"
API="${SYNCWHOLE_GITHUB_API:-https://api.github.com}"

die() { echo "syncwhole: $*" >&2; exit 1; }

name=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name) name="${2:-}"; shift 2 ;;
    --name=*) name="${1#*=}"; shift ;;
    *) die "unknown argument $1" ;;
  esac
done
[ -n "$name" ] || name=$(hostname | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')

case "$(uname -s)" in
  Linux) os=linux ;;
  Darwin) os=darwin ;;
  *) die "unsupported OS $(uname -s)" ;;
esac
case "$(uname -m)" in
  x86_64|amd64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) die "unsupported CPU $(uname -m)" ;;
esac
asset="syncwhole-$os-$arch"

str() { sed -n "s/.*\"$1\" *: *\"\([^\"]*\)\".*/\1/p"; }
num() { sed -n "s/.*\"$1\" *: *\([0-9][0-9]*\).*/\1/p"; }

token="${SYNCWHOLE_TOKEN:-}"
if [ -z "$token" ]; then
  [ -n "$CLIENT_ID" ] || die "set SYNCWHOLE_CLIENT_ID to the syncwhole GitHub App's client ID"
  resp=$(curl -fsS -X POST -H 'Accept: application/json' -d "client_id=$CLIENT_ID" "$WEB/login/device/code")
  device_code=$(echo "$resp" | str device_code)
  user_code=$(echo "$resp" | str user_code)
  uri=$(echo "$resp" | str verification_uri)
  interval=$(echo "$resp" | num interval)
  [ -n "$device_code" ] || die "GitHub didn't start a device login: $resp"
  echo "Open $uri and enter $user_code" >&2
  while :; do
    sleep "${interval:-5}"
    resp=$(curl -fsS -X POST -H 'Accept: application/json' \
      -d "client_id=$CLIENT_ID&device_code=$device_code&grant_type=urn:ietf:params:oauth:grant-type:device_code" \
      "$WEB/login/oauth/access_token")
    token=$(echo "$resp" | str access_token)
    [ -n "$token" ] && break
    case "$(echo "$resp" | str error)" in
      authorization_pending) ;;
      slow_down) interval=$(( ${interval:-5} + 5 )) ;;
      *) die "device login failed: $resp" ;;
    esac
  done
fi

# The token goes to curl on stdin (printf is a shell builtin), never in argv where
# other users could see it in the process list.
fetch() {
  printf 'Authorization: Bearer %s\n' "$token" |
    curl -fsSL -H @- -H 'Accept: application/vnd.github.raw' \
      "$API/repos/$REPO/contents/$1?ref=dist" -o "$2"
}

dir="$HOME/.local/bin/syncwhole"
mkdir -p "$dir"
tmp="$dir/.syncwhole.download"
trap 'rm -f "$tmp" "$tmp.sums"' EXIT
fetch "$asset" "$tmp" || die "couldn't download $asset from $REPO's dist branch"
fetch SHA256SUMS "$tmp.sums" || die "couldn't download SHA256SUMS"
want=$(awk -v a="$asset" '$2 == a || $2 == "*" a { print $1 }' "$tmp.sums")
if command -v sha256sum >/dev/null 2>&1; then
  got=$(sha256sum "$tmp" | awk '{print $1}')
else
  got=$(shasum -a 256 "$tmp" | awk '{print $1}')
fi
[ -n "$want" ] && [ "$want" = "$got" ] || die "$asset does not match SHA256SUMS"
chmod 755 "$tmp"
mv "$tmp" "$dir/syncwhole"
rm -f "$tmp.sums"

SYNCWHOLE_BOOTSTRAP_TOKEN="$token" exec "$dir/syncwhole" join --name "$name" --repo "$REPO"
