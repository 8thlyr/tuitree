# Notes for JC: tuitree

- **The README explains the parts that make it feel fast.** It had no "how it works", so the lane/worker model was invisible: one thread per project that takes git tasks one at a time because git locks the repo, different projects in parallel, PRs on their own threads, all results over one mpsc channel tagged with a generation so a late PR answer from an older refresh can't overwrite newer data. That's the thing a reviewer wants to see and it was only in `worker.rs` comments.
- **Every claim in that section was checked against the code, not written from the pitch.** The agent read `main.rs`, `worker.rs`, `app/queue.rs`, `git.rs`, `gh.rs` and `cmd.rs`, and added one detail the brief didn't have: `load_worktrees` fans out to 8 threads per chunk inside a single reload.
- **The demo GIF is unchanged and still the best thing in the repo.** It runs on a throwaway repo with four fake agent worktrees and a fake `gh`, so it shows the parallel-agents story with no real code in it. Nothing about this PR touches it.

**Visibility:** `8thlyr/tuitree` is **public** and it's the only Studio repo with a star. Normal push to main.
