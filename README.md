# tuitree

[![CI](https://github.com/8thlyr/tuitree/actions/workflows/ci.yml/badge.svg)](https://github.com/8thlyr/tuitree/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/8thlyr/tuitree)](https://github.com/8thlyr/tuitree/releases)

A terminal dashboard for your git worktrees and GitHub pull requests, in the spirit of LazyGit.

![tuitree showing five agent worktrees with ahead/behind, sync and PR columns, then a PR's files and review conversation](docs/demo.gif)

## Why

If you run several coding agents at once, each one usually gets its own worktree and branch.
After an hour you have five of them and no idea which are ahead, which fell behind `main`,
which would conflict on merge, and which already landed as a squash-merged PR. tuitree puts
all of that in one table per repo, next to each branch's PR and its review comments, and
lets you sync or delete the finished ones in a batch.

For each project you add, tuitree shows:

- **Worktrees**: every local worktree with its branch, commits ahead/behind `origin/<default>`,
  whether it can sync with `origin/<default>`, and the files and lines changed since the
  merge-base with `origin/<default>`. Open one to see the per-file `+added -deleted` list.
- **Pull requests**: open PRs from GitHub (number, title, branch, author, draft, files, lines).
  Open one to see its per-file list and its conversation: comments and review summaries
  (approved, requested changes), oldest first.

On start and on refresh it runs `git fetch origin --prune` in the background, so the numbers
match the remote. The UI never waits for git or the network.

## Status and stack

- Early (version 0.1.0). Linux is the main target; it also builds on macOS.
- Rust (edition 2024) with [ratatui](https://ratatui.rs) 0.30, plus anyhow, libc, serde, serde_json and toml.
- Runtime: `git` 2.38 or newer (for `git merge-tree --write-tree`); the GitHub CLI `gh` is optional and only needed for the PR view and the PR column.

## How it works

- **UI loop.** `main` builds the app, then loops: draw, `event::poll` for up to 100ms, send key
  and mouse events to the app state, drain the update channel. It redraws on every tick whether
  or not anything changed, which is what keeps the spinner turning and the "fetched 12s ago"
  text current. Everything is a plain `std::thread`; there is no async runtime and no tokio.
- **Lanes.** Each project gets a *lane*: one thread, started on first use, that takes tasks one
  at a time because git locks the repository. A refresh (fetch and reload) and every queued
  delete or sync go through that lane, so they cannot race each other; lanes of different
  projects run in parallel. Within one reload the per-worktree git commands also run up to eight
  at a time.
- **Messages.** Lanes and PR loaders send `Update` values over one std mpsc channel: project
  path, generation number, and a kind (worktrees, fetch result, activity, PRs, PR detail, job
  started or finished). The loop applies them to the app state between ticks. PR updates carry
  the generation of the reload that asked for them, so a late answer from an older reload is
  ignored instead of overwriting newer data. PR lists and PR details load on their own threads.
- **Nothing blocks the UI.** `git fetch`, the `git merge-tree` conflict check and the single
  `gh api graphql` request behind the PR column all run off the UI thread, and the fetch and that
  request run at the same time. Opening a PR loads its files and conversation on another thread
  again. The UI side only ever waits 100ms, so the table keeps repainting while git works.
- **Child processes.** git and gh are run as child processes rather than linked as libraries, so
  the user's own git config, credential helper and `gh auth login` just work. Children get no
  stdin and their own session, with the prompting variables set, so a git or gh that wants a
  password fails fast instead of grabbing the terminal.
- **Terminal restore.** `ratatui::init()` installs a panic hook that restores the terminal.
  tuitree wraps it in its own hook that turns mouse capture off first, so a panic leaves a usable
  shell behind.

## Install

You need `git` 2.38 or newer. For the PR view and the PR column you also need the
[GitHub CLI](https://cli.github.com), logged in (`gh auth login`).

**Prebuilt binary** (Linux x86_64/aarch64, macOS Apple Silicon/Intel). Pick your target from
the [latest release](https://github.com/8thlyr/tuitree/releases/latest):

```sh
target=x86_64-unknown-linux-gnu   # or aarch64-unknown-linux-gnu, aarch64-apple-darwin, x86_64-apple-darwin
curl -sL https://github.com/8thlyr/tuitree/releases/latest/download/tuitree-v0.1.0-$target.tar.gz | tar xz
install tuitree-v0.1.0-$target/tuitree ~/.local/bin/
```

**Homebrew** (macOS or Linux):

```sh
brew install jonathancostin/tap/tuitree
```

**With cargo** (current stable Rust):

```sh
cargo install --git https://github.com/8thlyr/tuitree --locked
```

Or from a clone: `cargo install --path .`. Both put `tuitree` in `~/.cargo/bin`.

Then run `tuitree` and press `a` to add a repository.

### Try it without your own repos

`demo/setup.sh` builds a throwaway repo with four agent worktrees and a fake `gh`, the same
setup the GIF above was recorded from:

```sh
demo/setup.sh /tmp/tuitree-demo
HOME=/tmp/tuitree-demo XDG_CONFIG_HOME=/tmp/tuitree-demo/config \
  PATH=/tmp/tuitree-demo/bin:$PATH tuitree
```

## Keys

| Key            | Action                                         |
| -------------- | ---------------------------------------------- |
| `j` / `k`, arrows | Move                                        |
| `1` / `2`      | Go to the Worktrees / Pull requests tab        |
| `Tab`          | Switch between Worktrees and Pull requests     |
| `Enter` / `l`  | Open (project, then list, then files)          |
| `Esc` / `h`    | Back                                           |
| `J` / `K`      | Scroll an open PR's comments                   |
| `Space`        | Mark or unmark the selected worktree row       |
| `M`            | Mark every merged worktree (press again to unmark) |
| `s`            | Sync the marked worktrees, or the selected one, with `origin/<default>` (asks first) |
| `x`            | Delete the marked worktrees, or the selected one, with their local branches (asks first) |
| `p`            | Jump to the selected worktree's open PR in the Pull requests tab |
| `Q`            | Show or hide the job queue                     |
| `a`            | Add a project (type a path, `~` works)         |
| `d`            | Remove the selected project (asks first)       |
| `r`            | Refresh: fetch, worktree stats and PRs         |
| `?`            | Help                                           |
| `q`            | Quit (asks first while jobs are running)       |

The mouse works too: click a project, a tab or a row to select it, click a selected row
again (or double click) to open it, click the mark column (left of the branch) to mark a row, click a PR number to jump to it,
click dialog buttons, and use the wheel to scroll the list (or PR comments) under the pointer.

Removing a project only removes it from tuitree. Nothing on disk is touched.

## Sync with origin

The Sync column shows, for each worktree, what `git merge origin/<default>` would do:

- `up to date`: nothing to merge.
- `ready`: merges cleanly. `ready (ff)` means a fast-forward, no merge commit.
- `conflicts N`: N files would conflict. Open the worktree to see which ones.
- `dirty`: uncommitted changes to tracked files, so tuitree won't merge.
- `merged #123` or `merged`: the branch is already merged (see below). Its row is dimmed.

The check runs in the background with `git merge-tree --write-tree` (git 2.38 or newer),
which never touches your branches, index or files. Press `s` to run
`git merge origin/<default>` in the marked (or selected) worktrees. Rows that are not `ready`
are skipped and the dialog says why. It merges and never rebases, so no history is rewritten
and it is safe for pushed branches. If a merge hits conflicts anyway, tuitree runs
`git merge --abort` and reports it.

## Already merged branches

Squash and rebase merges can leave the branch's original commits outside the default branch's
ancestry. tuitree marks a branch as merged when either check matches and shows `↑0` for its
outstanding ahead count:

- **Content**: merging the branch into `origin/<default>` would change nothing
  (`git merge-tree --write-tree` gives the same tree as `origin/<default>`). No gh needed.
  This misses branches whose lines were changed again on the default branch later.
- **Merged PR**: with gh, from the PR list tuitree loads once per refresh (see the PR column
  below). A merged PR whose head branch is the worktree's branch counts, as long as the branch
  has no new commits since that PR's head. This shows `merged #123`.

Merged rows are safe to clean up: `M` marks them all and `x` deletes them. The delete dialog
does not warn that they are unmerged or unpushed.

## PR comments

Opening a pull request loads its files and its conversation with one
`gh pr view <n> --json files,comments,reviews` call. The conversation shows, oldest first:

- Comments, with their author and age. Comments hidden on GitHub show `(hidden on GitHub)`.
- Reviews: `approved`, `requested changes`, `reviewed` or `review dismissed`, with the review's
  summary text. Inline code comments are not shown, and a review that only holds inline
  comments is skipped.

Bodies are shown as raw Markdown, without HTML comments. `J` / `K` or the wheel scroll it.

## PR column

The PR column shows the pull request each worktree's branch belongs to, as `#123 open`
(green), `#123 draft` (grey), `#123 merged` (purple) or `#123 closed` (red). It matches on the
PR's head branch, only for PRs from the repository itself (not forks), and shows the newest
PR when a branch had several. `-` means the branch has no PR; the column stays empty when gh
is not installed, not logged in, or origin is not on GitHub.

The data comes from one GitHub GraphQL request per refresh (`gh api graphql`), which asks for
the PRs of exactly the worktrees' branches, never one call per row. It runs while
`git fetch` runs. Press `p` on a row, or click its PR, to jump to an open PR in the Pull
requests tab.

## Delete worktrees

Press `x` to delete the marked worktrees (or the selected one) with their local branches.
The single confirm dialog lists each one with what you would lose: uncommitted and untracked
files, commits that are not on origin, and a branch that is not merged into
`origin/<default>`. After you confirm, tuitree does not ask again:

- `git worktree remove --force` (with `--force --force` for a locked worktree). This also
  handles untracked and ignored files such as `node_modules` and submodules.
- If the directory is already gone: `git worktree prune`.
- Then `git branch -D <branch>`.

Detached worktrees only lose the worktree. The main worktree and the default branch are never
deleted, and remote branches are never touched. If git still fails (for example the branch is
checked out in another worktree), the queue shows git's full error.

## Background jobs

Deletes and syncs go into a queue and run in the background, so you can keep working, switch
projects and queue more while they run. Jobs of one repository run one at a time (git locks
the repository); different projects run in parallel. Each row shows its queued or running job,
and `Q` shows the queue with every job's state (pending, running, done, failed, skipped) and
the full error of failed ones. A failed job never stops the jobs after it. The worktree list
reloads after each job, and the cursor and marks stay on the same worktrees.

## Config

Projects are stored in `$XDG_CONFIG_HOME/tuitree/config.toml`, or
`~/.config/tuitree/config.toml` when `XDG_CONFIG_HOME` is not set:

```toml
[[projects]]
path = "/home/you/code/my-app"
```

## How the numbers are counted

- **Ahead/behind**: `git rev-list --left-right --count origin/<default>...HEAD`. The default
  branch comes from `refs/remotes/origin/HEAD` and falls back to `main`.
- **Files and lines**: `git diff --numstat <merge-base>` in the worktree. This compares the
  merge-base with the files on disk, so it includes commits, staged and unstaged changes.
- **Untracked files** (not ignored) count as new files: every line is an addition. Binary
  files show `bin` and add no line counts.

## Tests

The tests start the real `tuitree` binary inside `tmux` against throwaway git repos (a local
"origin", a clone with several worktrees, commits ahead and behind, uncommitted edits,
untracked and binary files, branches that merge cleanly or conflict) and a fake `gh`. They
press keys and send mouse clicks, check the rendered screens, and check the repos with git
after syncing and deleting. You need `tmux` installed.

```sh
cargo test
```

Each run saves every captured screen and a pass/fail summary in
`tests/artifacts/<date-time>/`.

There is also a live smoke test against real GitHub repos. It needs network access and a
logged-in `gh`. Point it at a local clone with worktrees and at a local clone of a repo with
open PRs (they can be the same):

```sh
TUITREE_LIVE_WORKTREES=~/code/my-app TUITREE_LIVE_PRS=~/code/other-app \
  cargo test --test e2e -- --ignored
```

It fetches both repos and only reads them otherwise (it never syncs or deletes anything).
Its screens go to `tests/artifacts/<date-time>/live_github_smoke/` and are copied to `smoke/`.

## Layout

- `src/main.rs`: entry point. `src/app.rs` and `src/app/` (`actions.rs`, `mouse.rs`, `queue.rs`): app state, key and mouse handling, job queue.
- `src/git.rs`, `src/gh.rs`, `src/cmd.rs`: git and GitHub CLI calls. `src/worker.rs`: background work.
- `src/config.rs`: project list. `src/model.rs`: data types. `src/ui.rs`: rendering.
- `tests/e2e/`: the tmux-driven end-to-end tests and their fixtures.
- `demo/`: the demo repo script and the vhs tape for `docs/demo.gif`.
- `.github/workflows/`: CI (fmt, clippy, tests) and the tag-triggered release build.

## License

MIT. See [LICENSE](LICENSE).
