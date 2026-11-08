# Records docs/demo.gif. Run from the repo root after `cargo build --release`:
#   demo/setup.sh demo/.run && vhs demo/demo.tape
Output docs/demo.gif

Set Shell "bash"
Set FontFamily "JetBrains Mono"
Set FontSize 15
Set Width 1500
Set Height 760
Set Padding 16
Set Theme "Catppuccin Mocha"
Set TypingSpeed 60ms

Hide
Type "cd demo/.run && export HOME=$PWD XDG_CONFIG_HOME=$PWD/config PATH=$PWD/bin:$PWD/../../target/release:$PATH PS1='$ ' && clear"
Enter
Sleep 500ms
Show

Type "tuitree"
Enter
Sleep 2s
Enter
Sleep 1.5s

# Worktrees: one per agent, with ahead/behind, sync state and PR.
Down
Sleep 700ms
Down
Sleep 700ms
Down
Sleep 700ms
Down
Sleep 1.5s

# Open the conflicted worktree to see its files.
Up
Sleep 500ms
Enter
Sleep 2.5s
Escape
Sleep 800ms

# Pull requests tab, then the PR detail view with files and review conversation.
Type "2"
Sleep 1.5s
Enter
Sleep 3s
Type "J"
Sleep 400ms
Type "J"
Sleep 400ms
Type "J"
Sleep 2.5s
Escape
Sleep 800ms
Type "1"
Sleep 1.5s
Type "q"
Sleep 500ms
