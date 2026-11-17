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

Both pull `ghcr.io/wirenboard/tg-spam:master` (published by `wb-image.yml`); the stack
variable `IMAGE` overrides it. Every build also keeps a `:<sha>` tag, so setting `IMAGE`
to it pins or rolls back one stack.

## What the update channel overrides, and why

The defaults in `docker-compose.portainer.yml` are the support chat profile, so that stack
sets only credentials, volume names and the superuser list. The update channel carries
announcements with comments rather than a conversation, and overrides these - and only
these:

| Variable | Support chat | Update channel | What it changes |
|---|---|---|---|
| `OPENAI_VETO` | `false` | `true` | In veto mode the model only confirms spam another check already flagged; with it off the model flags on its own. The channel leans on the model less and pays for fewer calls |
| `MIN_MSG_LEN` | `40` | `20` | Shorter messages are skipped by the ordinary checks. Comments under a post are short, so the channel still looks at them |
| `SIMILARITY_THRESHOLD` | `0.65` | `0.7` | How close to a known spam sample a message has to be. Higher catches less and misfires less |
| `MAX_EMOJI` | `2` | `3` | |
| `DISABLE_ADMIN_SPAM_FORWARD` | `false` | `true` | The channel reports what it caught but does not copy the spam itself into the admin chat |
| `MIN_PROBABILITY`, `META_*`, `OPENAI_CHECK_SHORT_MESSAGES` | set | unset | The channel runs without the metadata checks (links, mentions, forwards, keyboards) and without the model check for short messages |
| `SERVER_ENABLED` | `true`, published on `:8081` | no web UI | The channel's samples and stop-words can only be changed through the bot itself |
| `SUPER_USER` | staff list | the same list plus one login | Both lists live in the stack environment, never in this public repository |

Three further differences are structural rather than tuning, and they are why the two
stacks still need two compose files:

- **The data volume is mounted at `/srv/var`** and `FILES_DYNAMIC=/srv/var` follows it.
  The application itself defaults to `data` relative to its working directory `/srv`,
  which is what the support chat uses. `/srv/var` is inherited from the stack this one
  replaced; nothing in the code needs it.
- **The container runs as `root`**, because the files in that volume belong to root while
  the image runs as `app` (uid 1000).
- **The stack is not deployed from git.** Its compose was pasted into the Portainer web
  editor with every value hard-coded, instead of coming from the stack environment.

Recreating that stack from `docker-compose.portainer.yml` would remove all three at once,
but its data has to reach `/srv/data` first - either by moving the files inside the volume
or by turning the mount point into a variable. A stack's repository URL cannot be changed
after creation, so moving the stack to this repository needs a recreation regardless.

## What is ours in this repository

Everything outside these paths is upstream [umputun/tg-spam](https://github.com/umputun/tg-spam)
byte for byte, at the release last merged:

- `deploy/wb-compat/` - this README, the update channel's compose file, the build and check
  scripts, our patches and our preset data;
- `docker-compose.portainer.yml` - the support chat's compose file;
- `.github/workflows/wb-*.yml` - our CI. Upstream's workflows are not kept: they build and
  publish umputun/tg-spam.

What we change in the bot itself is applied at build time, never committed into upstream's
files. `prepare-tree.sh` checks the committed tree out into a temporary directory, applies
every patch in `patches/` with `git apply --3way` and appends `data/stop-words.txt` to the
preset dictionary; upstream's own `Dockerfile` then builds that directory
(`build-image.sh`). That is the whole trick: since no upstream file differs, a merge of a
new upstream release cannot conflict. And since a patch goes in as a three-way merge,
upstream edits next to our lines merge on their own; only a change to the very lines we
touch, or to code our patch calls, needs a person.

| Patch | What it does | Why it is not upstream |
|---|---|---|
| `0001-restore-message-after-unban.patch` | `MESSAGE_RESTORE`: when an admin presses unban on a ban report, the bot posts the deleted text back to the chat, addressed to its author and prefixed with that message. Empty disables it; dry and training modes skip it, they never delete | Not proposed upstream yet |

Before adding anything here, check that upstream has no option for it, and prefer sending
the change upstream: every patch is code this fork has to carry through each release.

## Updating from upstream

`.github/workflows/wb-upstream-sync.yml` does it every morning with no one involved: it
merges the newest upstream release into `master`, runs the same checks as a pull request
(rendered stack config, the tests of the patched packages, the image build, and that every
variable the two compose files set is still an option of the new binary), pushes the merge
and starts `wb-image.yml`. Nothing to do while it stays green.

When it fails, nothing has reached `master` or the bots. The run's log says why; if the
merge itself went through, it waits on the branch `sync/upstream-<tag>`. The usual cause is
a patch that no longer applies because upstream changed the lines around it:

1. In a clone of this repository, check the release tag out into a scratch worktree
   (`git worktree add ../scratch <tag>`) and apply the patch there with
   `git apply --3way <path to deploy/wb-compat/patches/the patch>`.
2. Resolve the conflicts, make the package's tests pass
   (`go test -short ./app/...`), commit, and regenerate the file with
   `git format-patch -1 --full-index --stdout`. `--full-index` matters: the full blob ids in
   the patch are what lets the next release apply it three-way.
3. Commit the refreshed patch to `sync/upstream-<tag>`, push, open a pull request into
   `master` and merge it once `wb-image.yml` is green.

When upstream gains the same feature, delete the patch and switch the compose files to
upstream's option. With `patches/` empty, the image is plain upstream plus our preset
stop phrases.

A release can also be merged by hand, or an older one picked: run the workflow from the
Actions tab with a tag. A manual `git merge <tag>` conflicts only under
`.github/workflows`; keep this fork's side there.

GitHub turns off a schedule in a public repository after 60 days without a commit and
warns by mail first. A quiet upstream can get there; the Actions tab turns it back on.

## How an update reaches the bots

Push to `master` (by a merged pull request or by the upstream sync) →
`.github/workflows/wb-image.yml` asserts the rendered production config, tests and builds
the patched image, checks that it still has every option the stacks set, publishes it to
ghcr, and only then calls the Portainer webhooks that redeploy the stacks. A failed check
or build leaves `:master` on the previous image and never reaches a bot.

The webhooks come from two repository secrets, `PORTAINER_WEBHOOK_WIRENBOARD_CHAT` and
`PORTAINER_WEBHOOK_UPDATE_CH` (Portainer: the stack → **GitOps updates** → **Webhook** →
**Copy link**). Without them a new image waits on ghcr until someone redeploys the stack.
**Polling** does not fit here: it redeploys as soon as git changes, before CI has built the
image.

Nothing is built on the deployment host. It is a 2-CPU EC2 instance: the build takes
minutes and dies on the reverse-proxy timeout, which is why builds through the Portainer
UI fail. If CI cannot publish, `deploy/wb-compat/build-image.sh` builds on the host under
the same image name and the stack is then deployed with `PULL_POLICY=never`.

To redeploy by hand: Portainer → the stack → **Pull and redeploy**. Leave Portainer's
"re-pull image" off - `pull_policy: always` in the compose already pulls.

## Rollback

Each version change makes the bot back its database up next to it as
`tg-spam.db.<version>-<timestamp>` inside the data volume (`MAX_BACKUPS=10`). To go back
to a known build, set the stack's image tag to that build's `:<sha>` and redeploy.

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
printf %s 'the password' | go run ./deploy/wb-compat/authhash
```

The password is read from stdin, so it stays out of shell history and the process list.
The root README suggests `htpasswd` or `mkpasswd`; this helper needs nothing but a
checked-out repository.

## Secrets

Tokens and the superuser list live in the stack environment in Portainer (and in
Bitwarden), never in this repository - it is public. The OpenAI key must come from the
shared company account, not a personal one.

`CAS_TOKEN` is the Combot API key for the CAS check (combot.org → Settings → API key,
signed in with Telegram). Since 2026-10-25 api.cas.chat refuses requests without it; the
bot then skips CAS and logs a warning once at startup.
