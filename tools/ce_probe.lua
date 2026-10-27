-- tools/ce_probe.lua  --  Cheat Engine probe for D4BotClau memory research.
--
-- HOW TO RUN
--   1. Launch Diablo IV, be in-game (any zone).
--   2. Cheat Engine -> File -> Open Process -> Diablo IV.exe
--   3. Cheat Engine -> Table -> "Show Cheat Table Lua Script"
--   4. Paste this whole file in, press "Execute script".
--   5. Report is written to tools/ce_report.txt in the repo. Nothing to transcribe.
--
-- During the hunt you can call these from the same Lua console; each call APPENDS
-- to the report, so you never lose the trail:
--   d4dump(0x1A2B3C40)          -- 256-byte hexdump + every plausible interpretation
--   d4dump(0x1A2B3C40, 512)     -- bigger window
--   d4ptr(0x1A2B3C40)           -- follow one pointer, print what it lands on
--   d4chain(0x1A2B3C40, 0x18, 0x2B0, 0x1C)  -- walk a candidate chain, dump the end
--   d4aob("48 8B 05 ?? ?? ?? ?? 48 85 C0")  -- signature scan of all modules
--   d4mark("note text")         -- annotate the report so I know what you were doing

local REPORT = "C:/Users/hwu/Downloads/AI/DS/D4BotClau/tools/ce_report.txt"
local TARGETS = { "Diablo IV.exe", "Diablo IV", "DiabloIV.exe", "D4.exe" }

local out = {}
local function w(s) out[#out + 1] = tostring(s) end
local function wf(f, ...) w(string.format(f, ...)) end
local function flush(mode)
  local f = io.open(REPORT, mode or "w")
  if not f then print("CE probe: cannot write " .. REPORT) return end
  f:write(table.concat(out, "\n"), "\n")
  f:close()
  out = {}
end
local function section(name, fn)
  w("")
  w("=== " .. name .. " ===")
  local ok, err = pcall(fn)
  if not ok then w("!! ERROR: " .. tostring(err)) end
end
local function hex(a) return string.format("0x%X", a) end

-- ---------------------------------------------------------------- hexdump core
local function hexdump_lines(addr, count)
  local bytes = readBytes(addr, count, true)
  if not bytes then return nil end
  local lines = {}
  for i = 1, #bytes, 16 do
    local h, a = {}, {}
    for j = i, math.min(i + 15, #bytes) do
      local b = bytes[j] % 256
      h[#h + 1] = string.format("%02X", b)
      a[#a + 1] = (b >= 32 and b < 127) and string.char(b) or "."
      if #h % 8 == 4 then h[#h + 1] = "" end -- visual gap; formatted below
    end
    lines[#lines + 1] = string.format("%s  %s  |%s|",
      hex(addr + (i - 1)),
      string.format("%-48s", table.concat(h, " "):gsub("%s+$", "")),
      table.concat(a))
  end
  return lines
end

local function try(fn, addr)
  local ok, v = pcall(fn, addr)
  if ok and v ~= nil then return tostring(v) end
  return "-"
end

-- ------------------------------------------------------- interactive helpers
function d4mark(text)
  w("")
  w("----- MARK: " .. tostring(text) .. " -----")
  flush("a")
  print("CE probe: marked -> " .. tostring(text))
end

function d4dump(addr, count)
  count = count or 256
  w("")
  wf("--- d4dump(%s, %d) ---", hex(addr), count)
  wf("int32=%s  int64=%s  float=%s  double=%s  ptr=%s",
    try(readInteger, addr), try(readQword, addr),
    try(readFloat, addr), try(readDouble, addr), try(readPointer, addr))
  local lines = hexdump_lines(addr, count)
  if not lines then
    w("UNREADABLE at " .. hex(addr))
  else
    for _, l in ipairs(lines) do w(l) end
    -- float lattice: most position/HP fields hide in here
    w("float lattice @ " .. hex(addr) .. " (step 4):")
    for off = 0, math.min(count, 128) - 4, 4 do
      local f = try(readFloat, addr + off)
      local i = try(readInteger, addr + off)
      wf("  +0x%02X  float=%-14s int=%s", off, f, i)
    end
  end
  flush("a")
  print("CE probe: dumped " .. hex(addr))
  return addr
end

function d4ptr(addr)
  local p = tonumber(try(readPointer, addr))
  w("")
  wf("--- d4ptr(%s) -> %s ---", hex(addr), p and hex(p) or "nil")
  if p and p > 0x10000 then
    local lines = hexdump_lines(p, 128)
    if lines then for _, l in ipairs(lines) do w(l) end
    else w("pointer target unreadable") end
    wf("target int32=%s float=%s", try(readInteger, p), try(readFloat, p))
  end
  flush("a")
  print("CE probe: d4ptr done")
  return p
end

function d4chain(base, ...)
  local offs = { ... }
  local p = base
  w("")
  local trail = { hex(base) }
  for _, off in ipairs(offs) do
    p = tonumber(try(readPointer, p))
    if not p or p == 0 then
      w("--- d4chain: DEAD at offset " .. hex(off) .. " after " .. table.concat(trail, " -> "))
      flush("a"); return nil
    end
    p = p + off
    trail[#trail + 1] = "+" .. hex(off)
  end
  w("--- d4chain: " .. table.concat(trail, " -> ") .. " = " .. hex(p))
  flush("a")
  return d4dump(p, 192)
end

function d4aob(pattern)
  w("")
  w("--- d4aob: " .. tostring(pattern) .. " ---")
  local ok, res = pcall(AOBScan, pattern)
  if not ok or not res then w("no matches (or scan failed)"); flush("a"); return nil end
  local n = res.Count or 0
  wf("%d match(es)", n)
  for i = 0, math.min(n, 20) - 1 do
    local a = res[i]
    wf("  [%d] %s", i, hex(a))
  end
  flush("a")
  print(string.format("CE probe: AOB %d match(es)", n))
  return res
end

-- ------------------------------------------------------------ bootstrap report
section("attach", function()
  local pid = getOpenedProcessID and getOpenedProcessID() or 0
  if pid == 0 then
    for _, name in ipairs(TARGETS) do
      local p = getProcessIDFromProcessName(name)
      wf("try '%s' -> pid=%s", name, tostring(p))
      if p and p ~= 0 then
        local ok = openProcess(p)
        wf("openProcess(%d) -> %s", p, tostring(ok))
        if ok then break end
      end
    end
    pid = getOpenedProcessID and getOpenedProcessID() or 0
  end
  wf("opened pid = %s", tostring(pid))
  wf("process = %s", tostring(process))
  wf("is64 = %s", tostring(targetIs64Bit and targetIs64Bit()))
  if pid == 0 then w("!! NO PROCESS OPEN -- attach manually via File > Open Process, then re-run") end
end)

section("probe: can we read module memory at all", function()
  local mods = enumModules()
  if not mods then w("enumModules returned nil"); return end
  local shown = 0
  for i, m in ipairs(mods) do
    if shown >= 12 then break end
    local base = m.Address
    local b4 = readBytes(base, 4, true)
    wf("%-28s base=%s size=0x%X read4=%s",
      tostring(m.Name), hex(base), m.Size or 0, b4 and "OK" or "DENIED/NIL")
    shown = shown + 1
  end
  wf("total modules = %d", #mods)
end)

section("module list (full)", function()
  local mods = enumModules()
  if not mods then return end
  for _, m in ipairs(mods) do
    wf("%-34s %s  size=0x%X  %s",
      tostring(m.Name), hex(m.Address), m.Size or 0,
      (m.Is64BitModule and "x64" or "x86"))
  end
end)

section("memory region map", function()
  local ok, regs = pcall(enumMemoryRegions)
  if not ok or not regs then w("enumMemoryRegions unavailable"); return end
  local count, prot, total = 0, {}, 0
  for _, r in ipairs(regs) do
    count = count + 1
    total = total + (r.MemorySize or 0)
    local k = tostring(r.Protect)
    prot[k] = (prot[k] or 0) + 1
  end
  wf("regions = %d  total = %.1f MB", count, total / 1048576)
  w("protect histogram (1=NOACCESS 2=R 4=RW 8=WRITECOPY 16=X 32=XR 64=XRW):")
  for k, v in pairs(prot) do wf("  protect=%-4s regions=%d", k, v) end
  w("first 30 RW/X regions >= 64KB:")
  local shown = 0
  for _, r in ipairs(regs) do
    if shown >= 30 then break end
    if (r.MemorySize or 0) >= 65536 then
      wf("  %s  size=0x%-8X protect=%-4s type=%s",
        hex(r.BaseAddress), r.MemorySize, tostring(r.Protect), tostring(r.Type))
      shown = shown + 1
    end
  end
end)

section("how to continue", function()
  w("This bootstrap tells me: do we have a working read handle, is the module")
  w("list normal or hidden, and which regions are guarded. Next comes the hunt:")
  w("  d4mark('in town, full HP')")
  w("  ... take damage, scan for the value in the CE GUI, narrow it down ...")
  w("  d4dump(<surviving address>)      -- for every candidate you like")
  w("  d4mark('after death/respawn')     -- so I can see which ones were fake")
  w("Save the .CT table too: File > Save As, into tools/ce_session.CT")
end)

-- ---------------------------------------------------------------- main report
section("header", function()
  wf("D4BotClau CE probe report")
  wf("report path: %s", REPORT)
  wf("CE version : %s", tostring(getCheatEngineVersion and getCheatEngineVersion() or "?"))
  wf("helper funcs defined: d4dump d4ptr d4chain d4aob d4mark")
end)

flush("w")
print("CE probe: wrote " .. REPORT)
print("CE probe: helpers ready -> d4dump(addr) / d4ptr(addr) / d4chain(base,off,...) / d4aob(pattern) / d4mark(text)")
