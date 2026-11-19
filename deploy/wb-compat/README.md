# Running the WB antispam bots

Two bots run from this repository, one per chat. They share the same image and the same
update path; everything that differs between them lives in the stack environment in
Portainer, not in the code.

| | support chat | update channel |
|---|---|---|
| Portainer stack | `tg-spam-wirenboard-chat` | `tg-antispam-update_ch` |
| Telegram chat | `t.me/wirenboard`, `-1001443452450` | `-1002273392360` |
| Admin chat | `-1002485520426` | same |
| Compose file | `docker-compose.portainer.yml` | `deploy/wb-compat/docker-compose.update-channel.yml` |
| Container | `tg-spam-wb` | `tg-aspam` |
| Data volume | `tg-spam-wirenboard-chat_tg-spam-wb_data` → `/srv/data` | `tg-antispam-update_ch_data-tg-spam` → `/srv/var` |
| Log volume | `tg-spam-wirenboard-chat_tg-spam-wb_log` | `tg-antispam-update_ch_log-tg-spam` |
| Web UI | `:8081` | none |
| Ban mode | soft ban (restrict) | same |

## Updating a bot

A bot is updated in Portainer and nowhere else: the stack → **Pull and redeploy**. Both
stacks pull `ghcr.io/wirenboard/tg-spam:master`, which is always the newest upstream
release built with our patch, so a redeploy brings the bot to it. Leave Portainer's
"re-pull image" off - `pull_policy: always` in the compose already pulls.

To hold a stack on a release, or to roll it back, set its `IMAGE` variable to that release
and redeploy, e.g. `IMAGE=ghcr.io/wirenboard/tg-spam:v1.29.1`. Remove the variable to follow
the newest again. Each version change makes the bot back its database up next to it as
`tg-spam.db.<version>-<timestamp>` inside the data volume (`MAX_BACKUPS=10`).

What changed in a release: [umputun/tg-spam releases](https://github.com/umputun/tg-spam/releases).
Its image appears in ghcr within a day: `.github/workflows/wb-image.yml` looks for a new
release every morning, builds it and moves `:master` to it. Nothing here ever touches the
stacks.

## What the update channel overrides, and why

The defaults in `docker-compose.portainer.yml` are the support chat profile, so that stack
sets only credentials, volume names and the superuser list. The update channel carries
announcements with comments rather than a conversation, and overrides these - and only
these:

| Variable | Support chat | Update channel | What it changes |
|---|---|---|---|
| `MIN_MSG_LEN` | `40` | `20` | Shorter messages are skipped by the ordinary checks. Comments under a post are short, so the channel still looks at them |
| `SIMILARITY_THRESHOLD` | `0.65` | `0.7` | How close to a known spam sample a message has to be. Higher catches less and misfires less |
| `MAX_EMOJI` | `2` | `3` | |
| `DISABLE_ADMIN_SPAM_FORWARD` | `false` | `true` | The channel reports what it caught but does not copy the spam itself into the admin chat |
| `MIN_PROBABILITY`, `META_*`, `OPENAI_CHECK_SHORT_MESSAGES` | set | unset | The channel runs without the metadata checks (links, mentions, forwards, keyboards) and without the model check for short messages |
| `SERVER_ENABLED` | `true`, published on `:8081` | no web UI | The channel's samples and stop-words can only be changed through the bot itself |
| `SUPER_USER` | staff list | the same list plus one login | Both lists live in the stack environment, never in this public repository |

Two further differences are structural rather than tuning, and they are why the two
stacks still need two compose files:

- **The data volume is mounted at `/srv/var`** and `FILES_DYNAMIC=/srv/var` follows it.
  The application itself defaults to `data` relative to its working directory `/srv`,
  which is what the support chat uses. `/srv/var` is inherited from the stack this one
  replaced; nothing in the code needs it.
- **The container runs as `root`**, because the files in that volume belong to root while
  the image runs as `app` (uid 1000).

The update channel's stack is deployed from this repository: Portainer reads
`deploy/wb-compat/docker-compose.update-channel.yml`, and the values come from the stack
environment. Moving it onto `docker-compose.portainer.yml` would remove both differences,
but its data has to reach `/srv/data` first - either by moving the files inside the volume
or by turning the mount point into a variable.

## How the image is built

This repository carries no tg-spam code, only what is ours:

- `docker-compose.portainer.yml` - the support chat's compose file;
- `deploy/wb-compat/` - this README, the update channel's compose file, the build and check
  scripts, our patches and our preset data;
- `.github/workflows/wb-image.yml` - the build.

`build-image.sh` takes an upstream release as it is: `prepare-tree.sh` checks the release
out into a temporary directory, applies every patch in `patches/` with `git apply --3way`
and appends `data/stop-words.txt` to the preset dictionary, and upstream's own `Dockerfile`
builds the result. A new upstream release therefore needs nothing done here. And since a
patch goes in as a three-way merge, upstream edits next to our lines merge on their own;
only a change to the very lines we touch, or to code our patch calls, needs a person.

| Patch | What it does | Why it is not upstream |
|---|---|---|
| `0001-restore-message-after-unban.patch` | `MESSAGE_RESTORE`: when an admin presses unban on a ban report, the bot posts the deleted text back to the chat, addressed to its author and prefixed with that message. Empty disables it; dry and training modes skip it, they never delete | Not proposed upstream yet |

Before adding anything here, check that upstream has no option for it, and prefer sending
the change upstream: every patch is code we have to carry through each release.

Every build is checked before it is published: the rendered stack config, the tests of the
packages our patches touch, and that every variable the two compose files set is still an
option of the new binary. Tags in `ghcr.io/wirenboard/tg-spam`:

| Tag | What it is |
|---|---|
| `:v1.29.1` | the latest build of that upstream release |
| `:v1.29.1-<sha7>` | one build, never moves; `<sha7>` is this repository's commit |
| `:master`, `:latest` | the newest upstream release |

A push to `master` rebuilds the newest release with what was pushed; a push to another
branch, a pull request's included, only checks and builds. Actions → **wb-image** → **Run
workflow** builds a given release. The workflow keeps its own schedule alive: GitHub turns
a schedule off after 60 days without a commit.

## When a build fails

Nothing is published then: `:master` stays on the last good build, and redeploys keep
getting it. The usual cause is a patch that no longer applies because upstream changed the
very lines around it:

1. Clone umputun/tg-spam, check the new release out, and apply the patch there with
   `git apply --3way <path to deploy/wb-compat/patches/the patch>`.
2. Resolve the conflicts, make the package's tests pass (`go test -short ./app/...`),
   commit, and regenerate the file with `git format-patch -1 --full-index --stdout`.
   `--full-index` matters: the full blob ids in the patch are what lets the next release
   apply it three-way.
3. Replace the patch here through a pull request; merging it builds the release.

When upstream gains the same feature, delete the patch and switch the compose files to
upstream's option. With `patches/` empty, the image is plain upstream plus our preset stop
phrases.

Nothing is built on the deployment host. It is a 2-CPU EC2 instance: the build takes
minutes and dies on the reverse-proxy timeout, which is why builds through the Portainer
UI fail. If CI cannot publish, `deploy/wb-compat/build-image.sh` builds on the host under
the same image name and the stack is then deployed with `PULL_POLICY=never`.

## Things that have already broken

- **One bot token, one process.** Telegram gives updates to a single long-polling
  consumer; a second container on the same token makes both flap on 409. Stop the old
  stack before starting a replacement.
- **Volume names are explicit and mandatory** (`${DATA_VOLUME_NAME:?}`). Compose's
  implicit names are project-prefixed, so renaming a stack silently creates empty
  volumes - that is how the learned database was lost on 2026-04-16. A deploy without
  the names fails loudly instead.
- **A database file does not mean the samples are in it.** Versions before 2026 kept
  samples in text files, and a volume they wrote has a `tg-spam.db` with an empty samples
  store: the bot then exits with "no pesistent spam or ham samples found in the store" and
  upstream's `entrypoint.sh` does not reseed it, since it only fills a volume with no db.
  Both live volumes were migrated in 2026. Should such a volume ever come back from an old
  backup, copy `spam-samples.txt` and `ham-samples.txt` from the image's `/srv/preset` into
  it before the start; the bot imports them and renames them to `.txt.loaded`.
- **Importing a dictionary replaces the whole table**, unlike samples, whose import only
  clears preset-origin rows. Never seed `stop-words.txt` into a live volume: phrases added
  through the web UI would be dropped.
- **Log volumes are per bot.** The update channel runs as root, the support chat as the
  image's `app` user; pointing both at one log volume gives the app user a root-owned file
  and "can't write to log ... permission denied".

## Web UI password

Without `SERVER_AUTH_HASH` the bot generates a random password on every start and prints
it to the log. To pin one, generate a bcrypt hash and put it in the stack environment:

```sh
docker run --rm -it httpd:2.4-alpine htpasswd -nBC 10 tg-spam
```

It asks for the password twice, showing nothing while you type, so the password stays out
of shell history and the process list, and prints `tg-spam:<hash>`: the hash is everything
after the colon.

## Secrets

Tokens and the superuser list live in the stack environment in Portainer (and in
Bitwarden), never in this repository - it is public. The OpenAI key must come from the
shared company account, not a personal one.

`CAS_TOKEN` is the Combot API key for the CAS check (combot.org → Settings → API key,
signed in with Telegram). Since 2026-10-25 api.cas.chat refuses requests without it; the
bot then skips CAS and logs a warning once at startup.
