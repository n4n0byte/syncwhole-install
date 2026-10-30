# syncwhole installer

Public installer for [syncwhole](https://github.com/n4n0byte/syncwhole) (private).
On a new machine:

```sh
curl -fsSL https://raw.githubusercontent.com/n4n0byte/syncwhole-install/main/install.sh | sh -s -- --name <node>
```

It asks you to approve a code at github.com/login/device, downloads the agent with that
short-lived token, checks it against SHA256SUMS, and enrolls the machine with its own
deploy key. The token is not stored. This script is a copy of `install/install.sh` in the
syncwhole repo; edit it there.
