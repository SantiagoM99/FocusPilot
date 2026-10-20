# The focuspilot command

`focuspilot` lets the owner, or an agent running in a Herdr pane, add tasks to FocusPilot and read them. It ships inside the app at `FocusPilot.app/Contents/Helpers/focuspilot`. To use it from a shell, link it onto your PATH once:

```sh
ln -s ~/Applications/FocusPilot.app/Contents/Helpers/focuspilot ~/.local/bin/focuspilot
```

## Note for agents

Paste this section into an agent's instructions.

> **FocusPilot tasks.** The owner keeps their task list in FocusPilot. From this Herdr pane you can:
>
> - `focuspilot add "<task> [deadline]"` adds one task to the end of the owner's Next list, in the project linked to this Herdr workspace, marked "from Herdr". Put a deadline at the end if there is one: `focuspilot add "Re-run ablation by fri 23:59"`. If the deadline can't be read, the task is still added without one and a note says why.
> - `focuspilot tasks` shows the owner's current Now task and the open tasks of this workspace's project. Add `--json` to either command for machine-readable output.
>
> You can only add and read. You cannot change the owner's Now task, reorder tasks, change deadlines, or edit or delete any task. The owner decides priorities, and can undo anything you add. Add tasks the owner should know about; do not add your own internal steps. A pane can add at most 20 tasks per minute; past that, adds are refused.

## What each command does

| Command | Result |
| --- | --- |
| `focuspilot add <text>` | Appends a task to the end of Next. The text is split like quick capture: a trailing deadline phrase ("by fri 23:59", "Oct 20", "tomorrow") becomes the deadline. |
| `focuspilot tasks` | Prints Now (title, next action, deadline) and the open tasks of the workspace's linked project, in the owner's order. |
| `--json` | Options go before the task text; `--` ends them, so `focuspilot add -- --json flag docs` adds the text as typed (capture trims dashes at the very start or end of a title). Machine-readable output for either command. `add` reports `status` (`added`, `alreadyAdded` or `queued`), `title`, `project`, `deadline` and `hints`; `tasks` reports `running`, `now`, `project` and `tasks`. |

Exit status: `0` done (or queued), `1` refused or failed, `2` usage error, `3` FocusPilot is not running (`tasks` only).

## Where tasks go

- **In a Herdr pane whose workspace is linked to a project:** that project.
- **In a pane whose workspace has no linked project:** No project, and the command says so.
- **Outside Herdr** (no Herdr environment variables): No project. `tasks` shows only Now.

The workspace is read from the pane's environment (`HERDR_WORKSPACE_ID`, `HERDR_PANE_ID`, `HERDR_SOCKET_PATH`). **This scoping is a privacy convenience, not a security boundary.** Any local process can set those variables and claim another workspace. Every process running as the owner can already reach FocusPilot's data, and the command never offers more than adding a task and reading.

## When FocusPilot is closed

`add` queues the task in an inbox file, and FocusPilot imports it when it next starts. The deadline is read when the command runs, so "tomorrow" keeps its meaning. Each add carries an ID, so a task is never imported twice. `tasks` reports "FocusPilot is not running" and exits with status 3.

## How it works

- **The command never opens FocusPilot's databases.** It sends one request over a Unix socket at `~/Library/Application Support/FocusPilot/CommandLine/cli.sock` to the running app, which writes through its `TaskRepository` in one write per add.
- **Owner-only access:** the folder is `0700` and the socket `0600`, and the app refuses connections from other users.
- **Inbox:** `CommandLine/inbox.jsonl` in the same folder (`0600`).
- **Testing:** set `FOCUSPILOT_DATA_DIR` to another folder to point both the app and the command at different data, so the owner's data is untouched. A short path such as `/tmp/fp-test` is needed, because socket paths are limited to 104 bytes.
