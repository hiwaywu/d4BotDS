# Memory-read layer (plan + status)

## Why

The vision-only bot's two worst failures share one root cause: **it has pixel
positions but no world positions.**

- **Loot pickup fails** because `brain._loot` clicks the *name-plate text box*
  centre (`brain.py` `label_world`, ~L665), not the item model on the ground
  below it; and `combat.loot_label_radius_px: 650` accepts labels far outside
  pickup range, then the timeout path blacklists the item for
  `loot_ignore_s` — a systematic "click too far -> fail -> permanently ignore"
  loop.
- **The bot gets "lost in town"** because `_run_town` failure only logs
  `FAILED` and the cycle falls through to the farm loop, which roams in town.

Memory reading fixes both: an item's world position converts to the exact
screen point at its feet, gives exact distance (only click in range), and the
item stays in the list after a failed click so it is retried instead of
blacklisted. Town becomes a fixed coordinate table instead of template
matching.

## Terminology (don't conflate these)

- **Reader** — `OpenProcess` + `ReadProcessMemory`, ~50 lines of Python
  `ctypes`. The runtime component. No GUI, no engine, no driver.
- **Cheat Engine** — a third-party GUI product (reader + scanner + debugger +
  pointer scanner + Lua). A *convenience for interactive hunting*, not a
  dependency. Skipped here because it is signatured and higher-signal than our
  own reader.
- **Scanner** — our own `tools/scan.py`: region enumeration (`VirtualQueryEx`)
  + differential scanning + candidate ranking. Replaces CE's GUI hunt.
- **D4Bot.exe** — the packaged deliverable. Contains `memory.py`; no engine.

```
FINDING  (dev, once per patch)          RUNNING  (shipped, daily)
  tools/scan.py  <- replaces CE           D4Bot.exe
       | writes                              +-- capture / vision / brain  (existing)
       v                                     +-- memory.py   (the reader)
  offsets.yaml  --------- ships with app ----+
```

## Access rungs (climb only as far as needed)

| Rung | What | Kernel code? | Time to test |
|---|---|---|---|
| 1 | Userspace, normal rights | none | 30 s |
| 2 | Userspace + `SeDebugPrivilege` (run elevated) | none | 2 min |
| 3 | Self-signed kernel driver + test-signing | yes | 2–3 days build |
| 4 | BYOVD (reuse a signed vulnerable driver) | someone else's | 1–3 days |

**Prefer rung 1 or 2.** The driver rungs stay on the table as a fallback if
the userspace handle is denied — they cost 2–3 days and carry a bigger
footprint, so reach for them only if the item-list gain justifies it. Vision
remains the fallback whenever reads are unavailable.

## The decision gate (30 seconds, done first)

1. Launch D4, get in-game (town is fine).
2. Say "go". Claude runs an `OpenProcess(PROCESS_VM_READ)` + 4-byte read at the
   module base, plus a region enumeration. Read-only, nothing written.
3. Outcomes:
   - **Reads return data** → build `memory.py` + `tools/scan.py`, hunt
     position first, then cinder counter, then the item list.
   - **`GetLastError() == 5` (ACCESS_DENIED)** → retry elevated. If still
     denied → the target strips handle rights; the userspace path is closed,
     and the next options are the driver rungs (rung 3/4, on the table) or
     vision-only.

## Hunt order (once the gate passes)

1. **Player `x,y,z`** (2/10 difficulty) — the anchor every other read is
   relative to. Walk a straight line, find the three floats that change
   smoothly.
2. **Cinder counter** (1/10) — small int that goes up 1–3 on pickup. Also
   replaces the visual `kill_signal`.
3. **Ground item list** (6/10) — position + rarity + type. The actual prize:
   exact loot, exact distance, verified pickup.
4. **Inventory count** (1/10) — exact stash-trip trigger.

What already exists in-repo: `tools/ce_probe.lua` — a Cheat Engine Lua probe
that dumps modules/regions and defines `d4dump/d4ptr/d4chain/d4aob/d4mark`.
Optional; the Python scanner is preferred.

## Vision-only fallbacks (available now, no game needed to write)

- Lower `loot_label_radius_px` (~250).
- Click below the label centre (a `label_to_ground_offset_px` constant).
- On timeout, **walk closer** instead of blacklisting the item.
- Make `_run_town` failure abort the cycle loudly instead of falling through
  to roam.
