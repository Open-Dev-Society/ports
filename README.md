# ports

A small tool that tells you, in plain terms, which localhost servers are running on your Mac and what they cost you. Working name.

With AI coding agents, people don't know what servers were started for them, and those servers keep holding memory.

## The question it answers

"What's running that I forgot about, and what is it costing me?" Not "what's on this port?", which existing tools already answer.

## What we saw on the first run (Nov 2026, a 16 GB Mac)

`prototype/ports.py` found 11 listeners. Five were dev servers started inside agent copies, about 4.6 GB in total, one of them `next dev` at 3.8 GB after 11 hours. All five were open to the network. The other six were apps and system services (Spotify, ControlCenter on port 5000, rapportd), which is why a raw port list is mostly noise.

## What makes it work

1. **Real memory.** RSS undercounts badly: `next-server` read as 11 MB while really using 3.7 GB, because most of it was swapped out. Use `top`'s mem column or `proc_pid_rusage`'s `phys_footprint`.
2. **Name the owner.** A detached server is reparented to launchd, so the process tree loses its owner. Its working folder and environment (`REX_BLOCK`, `TMUX_PANE`) still show the project and terminal. Note `next-server` rewrites its process title, which hides its environment from `ps`; its parent `next dev` still has it.
3. **Stop the whole server.** Killing the pid on the port can leave `pnpm` or `next dev` to restart it. Signal the process group, TERM then KILL.
4. **Hide system listeners by default.** Dev servers only, unless asked for everything.
5. **Flag servers open to the network.** Listening on `*` means others on the same Wi-Fi may reach them.
6. **Be where people look.** People who don't know servers are running won't run a command. A menu bar count like "5 servers · 4.6 GB", and a nudge for ones untouched for hours.

## Plan

A single command-line tool first, then its output in the menu bar through xbar. Separate from baton: anyone using AI coding tools has this problem.

## Look at first

Checked on GitHub by description and activity only, not used yet.

- [treadiehq/port-kill](https://github.com/treadiehq/port-kill): closest competitor. Try it first to confirm the gap is real.
- [pranshuparmar/witr](https://github.com/pranshuparmar/witr): traces a process or port to what started it.
- [jkfran/killport](https://github.com/jkfran/killport): how to stop processes on a port.
- [matryer/xbar](https://github.com/matryer/xbar): any script's output in the menu bar (last updated 2024).
