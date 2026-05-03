# Why UID/GID matters for ai-jail

## The core problem

The container has its own users (`agent`, `root`, `node`, ...). Your Mac has
its own users (`yuryalencar`, ...). **They share the bind-mounted
`/workspace` folder.** When a process inside the container writes a file,
the kernel doesn't record "user agent wrote this" — it records the
**numeric UID** of whoever wrote it. That same number is then interpreted
on the host against your host's user table.

So if the container's `agent` user has UID 1000, and Claude Code writes
`src/foo.ts`, the file on your Mac shows up owned by **whatever host user
has UID 1000** — which is probably nobody (macOS users start at 501) or
some unrelated system account.

Result without UID matching:

- Files written by the agent are owned by `root` or some random UID on your
  host.
- You can't edit them in your editor without `sudo chown` every time.
- Git sees them as owned by someone else.
- The reverse: files *you* create on the host can't be edited by the agent
  inside the jail (permission denied).

## What ai-jail does

At build time, [scripts/build.sh](../scripts/build.sh) reads `id -u` and
`id -g` from your shell and bakes them into the image:

```sh
docker build \
  --build-arg USER_UID="$(id -u)" \
  --build-arg USER_GID="$(id -g)" \
  ...
```

The Dockerfile then makes the in-container `agent` user have **exactly
those numbers**. So `agent` inside ≡ `yuryalencar` outside, as far as the
kernel's permission checks are concerned. Files written by either one are
owned by both.

That's the "no `sudo chown` dance" line in the
[README](../README.md#what-you-get).

## Why the macOS edge case is annoying

On Linux, your UID/GID are usually `1000/1000` — the same numbers the
`node` base image already uses for its `node` user. Renaming `node` →
`agent` is enough.

On macOS, your UID is `501` and your GID is `20` (the `staff` group
everyone is in). The number `20` happens to already be assigned inside
Debian to `dialout` (a system group for serial port access). So you can't
just say "make the agent group GID 20" — there's already a group at GID 20.

The fix in [docker/Dockerfile](../docker/Dockerfile): **if a group already
owns your host GID, rename *that* group to `agent`** instead of trying to
shove `agent` onto a number that's taken. Same logic for the user. The
agent user ends up with `uid=501 gid=20`, exactly matching your host.

## Why it's per-machine

Different developers have different UIDs (one might be 501, another 1001).
That's why the image is built locally with `ai-jail build` instead of
pulled from a registry — a generic image would have wrong numbers for
whoever pulled it.

If you change machines, or your host UID/GID changes for any reason
(unusual, but possible), rerun `ai-jail build` to rebake the numbers.

## TL;DR

UID/GID matching is the bridge between "agent can write files" and "you own
those files on your Mac." Without it, every agent-written file would land
as `root` or a stranger — and the whole "agent works on your project" flow
breaks down on the very first file write.
