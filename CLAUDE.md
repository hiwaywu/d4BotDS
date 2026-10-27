# CLAUDE.md

Diablo IV bot (Python, Windows). The v1 default is screen-vision (capture the game, send mouse/keyboard input). Memory reading, packet inspection, process handles, DLL injection, and driver input are all on the table and are developed as optional layers behind a config flag (`memory.enabled`), off by default.

**At the start of every session, read `HANDOFF.md` first.** Section 0 ("NEXT SESSION AT THE HOME PC - START HERE") is a step-by-step checklist the user asked to be guided through: the user does not know what to do next, so take them through it one step at a time (exact command, what they should see, wait for their result), skipping steps already marked done.

- The user runs everything through `.\run.cmd ...` / `.\setup.cmd` in PowerShell from `C:\AI STUFF\Claude\Diablo4\d4-visual-bot`.
- Tests: `pytest` (no game needed; tests needing local screenshots skip).
- After every change or live result: update `HANDOFF.md` in the same commit and push.
- Botting can get the account banned; the user watches every run and F8 stops it.
