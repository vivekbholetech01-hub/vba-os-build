# ---------------------------------------------------------------------------
# Vivek OS ship launcher (Christopher OS's, for this copy) -- the "Start button"
# of a sealed, source-free copy of the REAL app. Shipped inside every distributable by ship.mjs, next to
# Start.bat, and covered by integrity.json like everything else in the folder.
#
# This is the real-app sibling of build/ship-assets/launcher.ps1 (the demo's).
# The shape is deliberately the same -- node present? -> port -> loopback pin ->
# per-copy lock -> PREFLIGHT the gate -> start -> poll -> browser -> reap. What
# differs is what it starts and what it must NOT do, and both differences are
# about the real app being far more dangerous than the demo.
#
# WHY THIS FILE EXISTS AT ALL. Before it, a shipped copy had no launch path of
# its own: whoever received it ran `node server\index.js` by hand. That is not a
# missing convenience, it is a missing control. The real server is
#
#     const HOST = process.env.COS_HOST || '0.0.0.0'      (server/index.js:245)
#
# so every hand-started copy binds EVERY interface, and the server's own comment
# beside that line says what that means: it "can spawn claude with
# bypassPermissions (chat) and inject input into live terminals (orchestrator),
# and it has NO authentication -- anyone who can reach this port has that
# power." /ws/terminal is not behind requireLoopback (nothing in the upgrade
# handler checks the peer). So on a shipped copy started any other way, a
# node-pty shell on the recipient's machine is reachable from the office LAN.
# The single line `$env:COS_HOST = '127.0.0.1'` in section 3 is currently the
# only thing standing between a distributable and that. See the honesty note
# under it for exactly how far it reaches, which is not as far as it sounds.
#
# EVERYTHING DEV-ONLY IS GONE, and each one for a reason, not for tidiness:
#
#  * No `npm install`. A ship has no package-lock, no dependency manifest worth
#    resolving, and node_modules\node-pty was copied in verbatim and is COVERED
#    BY THE MANIFEST -- an install would rewrite it and the next boot would
#    refuse the copy it just "fixed".
#  * No `npm run build -w frontend`, no Vite, no dist marker. There is no
#    frontend source in a ship. frontend\dist is prebuilt, sealed, and served by
#    the server itself on one port; a hot-reload server would have nothing to
#    reload and would be a second unsigned process serving the same UI.
#  * No `git rev-parse`. There is no .git in a ship. The dev launcher used HEAD
#    only to decide whether to rebuild, and there is no rebuild here.
#  * No Excalidraw canvas. Its Vite + API pair is a development surface; ship.mjs
#    does not ship it, so starting it would fail on a missing folder.
#  * No Chrome flags, no --remote-debugging-port, no ChromeDebug profile. Opening
#    a remote-debugging port on someone else's laptop is a liability, and it is a
#    developer's convenience being paid for by the recipient.
#  * NO KILLING OF STALE NODE PROCESSES, and this is the one worth stopping on.
#    The dev launcher's pre-flight kills any `node` LISTENING on its ports. A
#    ship defaults to MDV2_PORT=4740 -- the DEV copy's port. Shipping that
#    pre-flight means a recipient (or the developer, testing a ship on their own
#    machine) double-clicks Start.bat and it silently kills the running dev
#    server, with live terminal sessions in it. A launcher for someone else's
#    machine gets to manage the processes IT started and nothing else. If the
#    port is taken, the server says so and section 9 shows that message.
#
# HONEST NOTE, up front, because the whole point of the seal is not to promise
# more than it does. THIS FILE IS PLAIN TEXT, ANYONE CAN EDIT IT, AND NOTHING
# VERIFIES IT BEFORE IT RUNS. Concretely, and none of these is fixable here:
#
#  * The preflight in section 7 is a CONVENIENCE, not the lock. The lock is that
#    server\index.js verifies the signed manifest itself on every boot, so
#    deleting section 7 buys nothing -- the server still refuses a modified
#    tree. (If the copy in your hands predates that gate, section 7 says so
#    plainly and refuses rather than pretending.)
#  * This file runs FIRST and runs UNVERIFIED. The server's self-verify only
#    catches an edit here if the edited launcher still starts the real server.
#    Rewrite it to start something else and the gate is never reached.
#  * THE PROCESS ENVIRONMENT IS NOT HASHED AND CANNOT BE.
#    NODE_OPTIONS=--import file:///C:/patch.mjs injects a module that runs
#    BEFORE any verifier in the bundle and can neuter it -- patch process.exit,
#    fs.readFileSync, crypto.verify -- without changing one covered byte. A
#    node.exe placed earlier on PATH does the same thing more simply, because
#    section 2 resolves `node` from PATH and has no way to know it got the real
#    one. NO LAUNCHER CAN FIX EITHER FROM INSIDE THE PROCESS: anything this
#    script did to scrub the environment is itself a line in this script, and
#    the same person deletes it. Closing these needs a signed native launcher
#    that pins an absolute node path and an external trust anchor (OS code
#    signing, TPM, remote attestation).
#  * `node server\index.js` skips this file entirely, and with it the loopback
#    pin. That is gap-shaped, not fixable here, and the fix is in the CODE: the
#    HOST default at server/index.js:245 moving to '127.0.0.1' so the safe value
#    is covered by the signature and survives every launch path. ship.mjs
#    already prints that as a required change.
#
# So: deterrence and tamper-EVIDENCE, not security.
#
# ASCII ONLY, deliberately. Windows PowerShell 5.1 reads a .ps1 with no BOM as
# ANSI, not UTF-8, so an em dash or a curly quote here arrives mangled on a
# machine with a different code page -- and because this file is covered by the
# manifest, "fixing" the encoding after sealing trips the gate.
# ---------------------------------------------------------------------------

# 'Continue', not 'Stop': several probes below (Get-Process on a PID that has
# gone, a health poll before the server is listening, Get-Content on a label
# file that may not exist) are EXPECTED to fail and are handled inline. 'Stop'
# would turn each into a crash that leaves the lock and the child process
# behind.
#
# 'Continue' is not a licence for sloppy calls. It PRINTS the error and carries
# on, so a cmdlet that fails loudly -- a parameter-binding error, which
# -ErrorAction cannot suppress because binding happens before the cmdlet runs --
# dumps a paragraph of PowerShell noise into the window directly ABOVE the one
# line the person is here to read. Every probe below is therefore written so it
# cannot fail LOUDLY, not merely so it cannot crash. That is what makes the
# REFUSE message in section 7 the first thing a human sees.
$ErrorActionPreference = 'Continue'

# EXIT CODES from this script. Start.bat pauses either way, but a shortcut, a
# wrapper or a scheduled task can read them:
#   0  the app ran and stopped normally
#   1  it could not start: no node, the gate refused, or the server died
#   2  another launcher already owns THIS copy (a different copy is unaffected)
# These are the LAUNCHER's codes. The integrity gate's own codes belong to
# `node server\index.js --verify-only` and are listed in section 7.

# --- 1. Where this shipped copy lives. --------------------------------------
#
# $PSScriptRoot is the folder holding THIS file, which after ship.mjs is the
# ship root: Start.bat, ship-launcher.ps1, .env, integrity.json, server\ and
# frontend\ all sit here. It is NOT derived from the working directory -- and
# Start.bat uses %~dp0 for the same reason -- so a double-click from Explorer, a
# shortcut with a different "Start in", or a call from another drive all resolve
# to the same place.
$root = $PSScriptRoot
$serverEntry = Join-Path $root 'server\index.js'

Write-Host ""
Write-Host "  Vivek OS"
Write-Host "  $root"
Write-Host ""

# The one check that has to happen before anything else: is this actually a
# ship? A launcher copied out of the folder, or a half-extracted zip, otherwise
# fails three sections later inside Start-Process with a Windows error about a
# file the reader did not name and cannot place.
if (-not (Test-Path $serverEntry)) {
  Write-Host "  This folder is not a Vivek OS release." -ForegroundColor Red
  Write-Host "  Expected: $serverEntry"
  Write-Host "  Keep Start.bat and ship-launcher.ps1 inside the release folder."
  Write-Host ""
  exit 1
}

# --- 2. Node must exist. -----------------------------------------------------
#
# Get-Command rather than running `node --version` and catching: a missing
# executable raises CommandNotFoundException, which is terminating and would
# have to be caught, and a node that exists but is broken behaves differently
# again. Get-Command answers the only question that matters -- is there a node
# on PATH -- without spawning anything. The version is then printed for the
# support case where someone is on an old Node and the server dies for reasons
# that have nothing to do with the seal. The app is built and tested on v24.
#
# "on PATH" is doing real work in that sentence, and not in a good way:
# whichever node.exe PATH resolves to is the runtime that will execute the
# verified bundle, and this script cannot know it is the real one. See the
# header. This is stated, not defended against, because it cannot be defended
# against from here.
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Host "  Node.js is required (v24.x). Install it, then run again." -ForegroundColor Red
  Write-Host "  Download: https://nodejs.org/"
  Write-Host ""
  exit 1
}
$nodeVersion = (& node --version)
Write-Host "  node $nodeVersion"

# --- 3. Which port, and THE LOOPBACK PIN. ------------------------------------
#
# The port comes from THIS copy's .env, parsed by hand with the same rules as
# ports.mjs -- including the trailing-comment strip. That strip is not cosmetic:
# without it `MDV2_PORT=4740  # the api` parses as NaN, ports.mjs falls back to
# its default, and the launcher and the server then disagree about which port to
# poll. The browser opens on a dead page and nothing on screen says why.
#
# 4660 is the default because that is the DEFAULT_PORTS.api ship.mjs compiles
# into this ship's ports.mjs (SHIP_PORTS), and what it writes into the shipped
# .env -- the dev copy of Vivek OS is on 4760, beside it. If those ever diverge,
# the .env wins here -- which is the correct precedence, since it is the file the
# server reads too.
#
# .env is deliberately EXCLUDED from the signed manifest: moving the port is a
# supported thing to do with a deployed copy, and re-sealing per deployment is
# not a workflow anyone would follow. Editing it cannot break the seal.
#
# Sir's CRM rides in the same file, with ports.mjs's keys and defaults: vba-fe's
# Next dev server (what the CRM pane frames), vba-be's API, and the folder that
# holds both checkouts -- the one this ship sits in, unless SIRS_CRM_DIR says.
#
# A SHIP SHOWS THE LIVE CRM: CRM_FE_URL / CRM_BE_URL, the deployed vba-fe and
# vba-be (ports.mjs's DEFAULT_CRM_URLS, which build\ship.mjs compiles in with
# these same two values). Then nothing of the CRM is started or looked for on
# this PC. `CRM_FE_URL=` (nothing) in .env is the way back to the local dev
# servers below, for a ship run beside the checkouts.
$crmFeUrl = 'https://crm.vba.net.in'
$crmBeUrl = 'https://vbcrm.bhole.co'
$port = 4660
$crmFePort = 4005
$crmBePort = 8008
$crmDir = Split-Path -Parent $root
if (-not (Test-Path -LiteralPath (Join-Path $crmDir 'vba-fe'))) { $crmDir = Join-Path $crmDir "Sir's CRM" }
$envFile = Join-Path $root '.env'
if (Test-Path $envFile) {
  foreach ($line in (Get-Content $envFile)) {
    $t = $line.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    $eq = $t.IndexOf('=')
    if ($eq -lt 1) { continue }
    $k = $t.Substring(0, $eq).Trim()
    $v = $t.Substring($eq + 1)
    $hash = [regex]::Match($v, '\s#')
    if ($hash.Success) { $v = $v.Substring(0, $hash.Index) }
    $v = $v.Trim().Trim('"').Trim("'")
    # The one path and the two addresses this file reads; everything else is a port.
    if ($k -eq 'SIRS_CRM_DIR') { if ($v) { $crmDir = $v }; continue }
    # Written but empty is meaningful here: the local dev servers.
    if ($k -eq 'CRM_FE_URL') { $crmFeUrl = $v; continue }
    if ($k -eq 'CRM_BE_URL') { $crmBeUrl = $v; continue }
    $n = 0
    # A typo'd port falls back to the default rather than binding something
    # absurd or failing later somewhere harder to read.
    if (-not [int]::TryParse($v, [ref]$n)) { continue }
    if ($n -le 0 -or $n -ge 65536) { continue }
    switch ($k) {
      'MDV2_PORT'   { $port = $n }
      'CRM_FE_PORT' { $crmFePort = $n }
      'CRM_BE_PORT' { $crmBePort = $n }
    }
  }
}

# A CLEAN ENVIRONMENT FOR THIS COPY. Started from a terminal inside another
# Christopher or Vivek OS (a chat running Start.bat, say), the environment
# carries that copy's identity -- its session key, its launcher's PID, its
# Claude config dir, its data folder and ports. ports.mjs lets a real
# environment variable beat its own defaults, so an inherited COS_DATA_PARENT
# would put this ship in the dev copy's data room (whose lock then refuses one
# of the two). Each one is dropped, so this copy's .env and its compiled
# defaults decide; the values below are set from this copy's .env.
foreach ($name in 'COS_SESSION_KEY','COS_PROJECT_ID','COS_USAGE_DIR','COS_BUILD_ID',
                  'COS_SUBSCRIPTION_KEY','COS_LAUNCHER_PID','CLAUDE_CONFIG_DIR','CLAUDE_CODE_OAUTH_TOKEN',
                  'COS_DATA_PARENT','COS_CHAT_PARENT','COS_WEB_PORT','COS_CANVAS_API','COS_CANVAS_WEB',
                  'CRM_DAV_LETTER') {
  Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
}
$env:MDV2_PORT    = "$port"
$env:CRM_FE_PORT  = "$crmFePort"
$env:CRM_BE_PORT  = "$crmBePort"
$env:SIRS_CRM_DIR = $crmDir
# The server reads these from .env as well; set here so the two cannot differ
# when .env is missing (and so an inherited value cannot win).
$env:CRM_FE_URL   = $crmFeUrl
$env:CRM_BE_URL   = $crmBeUrl
$crmLive = [bool]$crmFeUrl

# THE LOOPBACK PIN. This is the security-relevant line in the file, and it is
# why the file exists. Read the second half before quoting the first.
#
# It is set as a REAL environment variable -- process.env, not a line in .env.
# That matters twice over. Nothing in the app loads .env into process.env
# (ports.mjs parses port numbers out of it and nothing else), so a COS_HOST line
# in .env is INERT; ship.mjs says so in the shipped .env's own comments rather
# than writing a line that would look like a control and do nothing. And a real
# env var beats the server's code default of '0.0.0.0', which is the value that
# makes an unpinned copy LAN-reachable.
#
# Set BEFORE the preflight in section 7, not just before section 8. If a build
# is ever handed a server that does not understand --verify-only, that preflight
# starts a real server for as long as the timeout allows; it should not spend
# those seconds bound to every interface.
#
# THE LIMIT, plainly: an env var set here only covers people who start the app
# WITH this launcher. `set COS_HOST=0.0.0.0 && node server\index.js` binds every
# interface, and a boot self-verify still passes, because the environment is not
# part of the signed manifest and cannot be. This line is belt-and-braces. The
# fix is the loopback default moving into the CODE at server/index.js:245, where
# the signature covers it, plus requireLoopback on the /ws/terminal upgrade --
# which today has no peer check at all.
$env:COS_HOST = '127.0.0.1'

# The server stops when THIS process does. The watchdog below reaps the tree
# when this script exits, but a watchdog is as mortal as what it watches -
# and closing the console ORPHANS this script rather than ending it, which
# left the port listening with no window attached. Verified both ways: killing
# the console left 4740 up indefinitely; killing this script freed it in five
# seconds. So the server is told who its launcher is and checks for itself.
# See the COS_LAUNCHER_PID block in server/index.js.
$env:COS_LAUNCHER_PID = "$PID"

# NODE_OPTIONS IS DELIBERATELY NOT SCRUBBED HERE, and that is a decision, not an
# omission. Clearing it would look like a hardening step and would not be one:
# whoever can set NODE_OPTIONS before this script runs can also delete the line
# that clears it, since this file is plain text and unverified. Removing it
# would also break the legitimate case (a machine-wide NODE_OPTIONS a support
# engineer set on purpose) while stopping nobody. See the header: the
# environment is outside what any in-process launcher can vouch for.

# --- 4. One instance only, PER COPY. -----------------------------------------
#
# The lock and the logs live in LOCALAPPDATA, OUTSIDE the shipped folder, for
# two reasons:
#
#  (a) A ship can be deployed read-only, which is a sensible thing to do with a
#      folder nobody is supposed to edit. A lock file written into $root would
#      make the launcher fail on exactly the deployment we most want to work.
#  (b) Every byte inside $root except .env and server\data is covered by the
#      manifest. A .launcher.pid appearing beside ship-launcher.ps1 would be a
#      new, unsigned file. Today's verifier checks the files the manifest lists,
#      so it would pass -- but the day anyone tightens that to "no unknown
#      files", the app's own lock file is the first thing it rejects.
#
# PER COPY, not per machine. The state directory is namespaced by a hash of
# $root, so two shipped copies in two folders on two ports run side by side --
# and, just as importantly, do not share one server.log and clobber each other's
# diagnostics. The hash is over the LOWERCASED path, because Windows paths are
# case-insensitive and Explorer will hand us either C:\Ship or c:\ship.
$rootKey = $root.TrimEnd('\').ToLowerInvariant()
$sha = [System.Security.Cryptography.SHA256]::Create()
try {
  $tag = ([BitConverter]::ToString(
    $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($rootKey))
  )).Replace('-', '').Substring(0, 12)
} finally {
  $sha.Dispose()
}

$stateDir = Join-Path $env:LOCALAPPDATA "ChristopherOS\Ship\$tag"
if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
# Twelve hex characters are not a folder name anyone can act on. This one-line
# file is how someone looking at three of these folders works out which copy
# each belongs to before deleting one.
Set-Content -Path (Join-Path $stateDir 'ship-root.txt') -Value $root -Encoding UTF8

# THE LOCK IS A NAMED MUTEX. The .pid file beside it is only a label.
#
# A hand-rolled file lock (Test-Path, then write our PID) has both classic
# failure modes, and both were seen:
#
#  * TOCTOU. Two double-clicks in the same second both pass Test-Path and both
#    write. The loser's server dies on EADDRINUSE, its launcher takes the
#    "exited during startup" path and releases the lock -- which now matches,
#    because it overwrote the file -- deleting the LIVE instance's lock.
#  * Staleness. A pid file outlives the process that wrote it, so it has to be
#    second-guessed, and guessing by ProcessName narrows the recycled-PID window
#    without closing it. Getting it wrong wedges the app shut behind a message
#    that names no file to delete.
#
# A kernel mutex has neither problem. Acquisition is atomic, and the OS releases
# it when the owning process dies for any reason -- crash, kill, reboot,
# Explorer X. There is nothing left behind, so there is nothing to go stale.
#
# Scope is "Local\" (this logon session), not "Global\": LOCALAPPDATA is
# per-user anyway, and creating Global\ objects needs a privilege a locked-down
# account may not have. The honest consequence is that two logon sessions can
# each start this same copy, and the second loses the PORT rather than the lock
# -- it gets the server's own "address in use" failure in section 9 instead of
# the friendly message here. Correct outcome, worse wording.
$lockName = "Local\ChristopherOSShip-$tag"
$lockFile = Join-Path $stateDir 'launcher.pid'

# Identity, not just a PID: PID + which copy + this process's exact start time.
# StartTime.Ticks is what makes a recycled PID distinguishable from ours, and it
# is why Release-Lock can never delete a label belonging to a different launcher
# that started after us.
$startTicks = 0
try { $startTicks = (Get-Process -Id $PID).StartTime.Ticks } catch { }
$identity = "$PID|$rootKey|$startTicks"

$lockMutex = New-Object System.Threading.Mutex -ArgumentList $false, $lockName
$haveLock = $false
try {
  $haveLock = $lockMutex.WaitOne(0)
} catch [System.Threading.AbandonedMutexException] {
  # The previous owner died without releasing. WaitOne throws AND hands us
  # ownership, so this is success, not failure -- the self-healing path a pid
  # file never had.
  $haveLock = $true
}

if (-not $haveLock) {
  # The mutex already told us a live launcher owns this copy. The label is read
  # only to make the message useful, so every read below is written so it cannot
  # fail loudly if the file is missing, empty or corrupt.
  $whoText = 'not named - the label file is stale or unreadable, but the lock is held'
  $held = (Get-Content $lockFile -Raw -ErrorAction SilentlyContinue)
  if ($held) {
    $parts = $held.Trim() -split '\|'
    $heldPid = 0
    # [int]::TryParse BEFORE Get-Process, always. `Get-Process -Id 'not-a-pid'`
    # is a PARAMETER BINDING failure, and -ErrorAction SilentlyContinue cannot
    # suppress it -- binding happens before the cmdlet's ErrorAction applies. A
    # corrupt one-line file would otherwise dump twenty lines of
    # ParameterBindingException into the window, which is exactly the noise this
    # script spends its effort removing.
    if ([int]::TryParse($parts[0].Trim(), [ref]$heldPid)) {
      $holder = Get-Process -Id $heldPid -ErrorAction SilentlyContinue
      if ($holder) {
        $whoText = "PID $heldPid"
      } else {
        # Only one thing produces this: a launcher took the lock moments ago and
        # has not written its label yet. Do not print the dead PID as if it were
        # the answer.
        $whoText = "a launcher that started seconds ago (the label still says PID $heldPid, which has gone)"
      }
    }
  }
  Write-Host ""
  Write-Host "  Already running - this exact copy is open in another window."
  Write-Host "  Holder: $whoText"
  Write-Host "  Use that window, or close it first."
  Write-Host "    http://127.0.0.1:$port/"
  Write-Host ""
  # Worth saying, because the old message left people hunting for a file to
  # delete: there is no stale lock to clear. The lock is held by a running
  # process and disappears with it. A DIFFERENT copy of this app, in a different
  # folder, is unaffected and can be started right now.
  Write-Host "  (Nothing to clean up - the lock is held by that process, not by a file."
  Write-Host "   Logs for this copy: $stateDir)"
  Write-Host ""
  exit 2
}

# The label file. Written AFTER the mutex is ours, so it can never be the thing
# two launchers race over.
Set-Content -Path $lockFile -Value $identity -NoNewline -Encoding UTF8

# Remove the label ONLY if it still names this exact process. An unconditional
# Remove-Item is wrong and has bitten this codebase before: a launcher exiting
# deleted the lock belonging to a DIFFERENT launcher that had started in the
# meantime. The mutex makes that harmless now rather than fatal, but a label
# naming the wrong process is still a lie told to whoever reads it next.
function Release-Lock {
  param([string]$Path, [string]$Identity)
  if (-not (Test-Path $Path)) { return }
  $held = (Get-Content $Path -Raw -ErrorAction SilentlyContinue)
  if ($null -ne $held -and $held.Trim() -eq $Identity) {
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  }
}

# --- 5. Pull the gate's verdict out of whatever else Node printed. -----------
#
# This is not tidiness. It is the difference between someone seeing
#
#     REFUSE: MODIFIED FILE: server/index.js
#
# and seeing it buried under a paragraph that looks like the error itself. The
# real server writes plenty to stderr around startup -- node-pty warnings from
# worker threads (server/index.js:247 exists because of them), Node deprecation
# notices, ExperimentalWarning lines -- and printed verbatim in red they read as
# the failure. The gate's messages are the contract: they always start REFUSE:
# or OK:. Match those and drop everything else; fall back to the last non-empty
# line only when nothing matched, so an unexpected failure still says something.
#
# @() everywhere: a single-match Where-Object returns a bare string, and
# indexing [-1] into a string yields its last CHARACTER, not its last line.
function Get-GateMessage {
  param([string]$Text)
  if (-not $Text) { return '' }
  $lines = @($Text -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
  $named = @($lines | Where-Object { $_ -match '^\s*(REFUSE|OK):' })
  if ($named.Count -gt 0) { return (($named | ForEach-Object { $_.Trim() }) -join '  ') }
  if ($lines.Count -gt 0) { return $lines[-1].Trim() }
  return ''
}

# --- 6. Where node runs from, for BOTH child processes. ----------------------
#
# THE WORKING DIRECTORY IS NOT COSMETIC IN THIS APP. server/index.js seeds a new
# workflow project's directory list with process.cwd() (line 629) -- and the
# agents in those projects get terminal access. Launch from inside the ship and
# every new workflow project defaults to standing in the folder holding the
# sealed bundle, the signed manifest and the MCP shim. USERPROFILE is neutral,
# writable, and outside the ship; it also means any relative path a future
# change introduces lands somewhere boring instead of writing an unsigned file
# into the sealed tree and tripping the gate on the next boot. The real fix is a
# deliberate default at that call site rather than "whatever cwd happens to be";
# this only removes the worst possible answer.
#
# Computed HERE, above the preflight, and used for the verifier too. A verifier
# has no business caring about cwd -- but a build that does not recognise
# --verify-only starts the whole app instead (see section 7), and those seconds
# should not be spent with cwd pointing anywhere worse.
$workDir = $env:USERPROFILE
if (-not $workDir -or -not (Test-Path $workDir)) { $workDir = $stateDir }

# --- 7. PREFLIGHT: the integrity gate, run for its message. ------------------
#
# `node server\index.js --verify-only` checks the Ed25519 signature over the
# SHA-256 manifest and every covered file's hash, prints one line and exits:
#   0 ok | 3 manifest missing | 4 signature invalid | 5 file missing
#   6 file MODIFIED (the message names it) | 7 foreign signing key
#
# It runs here ONLY so a refusal is a single clean red line instead of a
# half-started server writing a stack trace into a log file someone has to go
# and find. It is NOT the protection: the same check runs inside the server on
# every boot, so deleting this section leaves a server that still refuses a
# modified tree.
#
# THE TIMEOUT IS LOAD-BEARING, not defensive padding. A server build that does
# not implement --verify-only ignores the argument and STARTS THE WHOLE APP:
# express listening, node-pty ready, MCP registration running. Without a timeout
# this launcher would block here for ever on a process it believed was a
# verifier. With one, an unrecognised flag costs 90 seconds and then gets a
# plain refusal that says what is actually wrong -- which is the truthful
# outcome, because a copy whose server cannot verify itself is exactly the copy
# this launcher should not start. 90s and not 10s because the first run on a
# cold machine hashes every shipped byte (tens of MB, node-pty included) while
# Defender inspects the same files.
#
# Start-Process with redirects, not `& node ... 2>&1`: PowerShell 5.1 wraps a
# native command's stderr in ErrorRecords when merged (NativeCommandError),
# printing CategoryInfo noise around the REFUSE line and flipping $? to $false
# even on exit 0. Two separate log files, because PS 5.1 hard-errors with
# "RedirectStandardOutput and RedirectStandardError are same" if you point both
# at one path.
$verifyOut = Join-Path $stateDir 'verify.out.log'
$verifyErr = Join-Path $stateDir 'verify.err.log'
Write-Host "  Verifying this copy..."
$pf = Start-Process node `
  -ArgumentList "`"$serverEntry`"", '--verify-only' `
  -NoNewWindow -PassThru `
  -WorkingDirectory $workDir `
  -RedirectStandardOutput $verifyOut -RedirectStandardError $verifyErr

# Touch .Handle while the child is alive. In PS 5.1 a Process object from
# Start-Process -PassThru WITHOUT -Wait has no cached handle, so .ExitCode reads
# back empty once the child dies -- on the one path where that number is the
# thing you wanted. In a try/catch because this only improves a diagnostic and
# must never become the thing that goes wrong.
try { $null = $pf.Handle } catch { }

$verifyExited = $false
try { $verifyExited = $pf.WaitForExit(90000) } catch { $verifyExited = $false }

if (-not $verifyExited) {
  # taskkill /T, not Stop-Process: if this really is a full server it has
  # children (a pty conhost, the claude CLI), and killing only the root orphans
  # them holding the port.
  cmd /c "taskkill /F /T /PID $($pf.Id) >nul 2>&1"
  Write-Host ""
  Write-Host "  REFUSE: this copy's server did not answer --verify-only within 90s." -ForegroundColor Red
  Write-Host "  It has no boot integrity gate, so nothing here can tell a sealed copy" -ForegroundColor Red
  Write-Host "  from an edited one. Not starting it." -ForegroundColor Red
  Write-Host ""
  Write-Host "  This is a BUILD problem, not something to fix on this machine:"
  Write-Host "  the release was produced before the gate was added to server/index.js."
  Write-Host "  Ask whoever sent you this folder for a newer release. They can also check"
  Write-Host "  this copy from outside with seal.mjs, which ships with their build tools,"
  Write-Host "  not with the release:"
  Write-Host "    node build\seal.mjs --verify `"$root`" <publicKey>"
  Write-Host ""
  Release-Lock -Path $lockFile -Identity $identity
  exit 1
}

$verifyCode = 'unknown'
try { $verifyCode = $pf.ExitCode } catch { }
$verifyText = Get-GateMessage (
  (Get-Content $verifyOut -Raw -ErrorAction SilentlyContinue) +
  "`n" +
  (Get-Content $verifyErr -Raw -ErrorAction SilentlyContinue)
)

if ($verifyCode -ne 0) {
  Write-Host ""
  # The captured line names the exact file, e.g.
  #   REFUSE: MODIFIED FILE: server/index.js
  if ($verifyText) { Write-Host "  $verifyText" -ForegroundColor Red }
  else { Write-Host "  Integrity check failed (exit $verifyCode)." -ForegroundColor Red }
  Write-Host "  This copy has been modified and will not start." -ForegroundColor Red
  Write-Host ""
  Write-Host "  Restore it from the original release folder, or ask for a fresh copy."
  Write-Host "  Full output: $verifyOut"
  Write-Host ""
  Release-Lock -Path $lockFile -Identity $identity
  # Deliberately NO browser here. Opening a tab on a server that will never
  # listen is how the dev launcher used to make a refusal look like a hang.
  exit 1
}
if ($verifyText) { Write-Host "  $verifyText" }

# --- 8. Start the server. ----------------------------------------------------
#
# -NoNewWindow so no console flashes up and the child stays attached to this
# console; its output goes to the log files, which is where to look when
# something goes wrong after startup. $workDir is section 6's neutral cwd, and
# the comment there is the one that matters for this call.
$outLog = Join-Path $stateDir 'server.log'
$errLog = Join-Path $stateDir 'server.err.log'
$server = Start-Process node `
  -ArgumentList "`"$serverEntry`"" `
  -NoNewWindow -PassThru `
  -WorkingDirectory $workDir `
  -RedirectStandardOutput $outLog -RedirectStandardError $errLog
$serverPid = $server.Id

# Same .Handle trick, same reason: without it a server that dies during startup
# reports "(exit )" in the diagnostic below, on the one path where the number is
# the whole point.
try { $null = $server.Handle } catch { }

# --- 9. Wait until it actually answers, then open the browser. ---------------
#
# Polling a real endpoint rather than sleeping a fixed number of seconds. A cold
# first run is genuinely slow -- Defender inspects freshly written files, the
# boot gate hashes every shipped byte again inside the server, node-pty loads --
# and a fixed sleep is either too short there or wasted time everywhere else.
# 120 seconds because that cold path on a laptop is minutes-adjacent, and the
# alternative to waiting is opening a browser on nothing.
#
# WHICH endpoint matters. /api/health (server/index.js:274) returns
# { ok, app, time } and writes nothing -- unlike the demo's /api/status, which
# bumps a counter, so every launch silently consumed one of the numbers the demo
# put on screen as evidence. In this app the equivalent mistake would be a store
# write on every single launch.
#
# Any HTTP status counts as "up", not just 200: a 404 or a 500 still proves a
# listener answered, which is the only question here. PS 5.1 raises a
# WebException for every non-2xx, so the presence of .Response is the signal --
# a refused connection has none.
#
# The HasExited check is what the dev launcher lacked: without it a server that
# dies at startup is polled for the full timeout and then handed a browser tab.
$healthy = $false
for ($i = 0; $i -lt 120; $i++) {
  if ($server.HasExited) { break }
  try {
    $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 "http://127.0.0.1:$port/api/health"
    if ($r.StatusCode) { $healthy = $true; break }
  } catch {
    if ($_.Exception.Response) { $healthy = $true; break }
  }
  Start-Sleep -Seconds 1
}

if ($server.HasExited) {
  # WaitForExit() before reading the code: HasExited can go true a moment before
  # the exit status is retrievable. The $null guard stays regardless, because
  # "(exit )" reads like a bug in the launcher and sends people chasing the
  # wrong thing.
  try { $server.WaitForExit() } catch { }
  $code = $null
  try { $code = $server.ExitCode } catch { }
  if ($null -eq $code) { $code = 'unknown' }

  Write-Host ""
  Write-Host "  The server exited during startup (exit $code)." -ForegroundColor Red
  # The tail, not one filtered line: unlike a gate refusal (a single designed
  # sentence) a startup crash is a stack trace, and the frames ARE the
  # information. -Tail rather than -Raw so a large log cannot flood the window.
  # The commonest cause here is the port already being in use -- by another copy
  # of this app, or by the developer's own dev server, which this launcher
  # deliberately does not kill. That message is in these lines.
  $tail = @(Get-Content $errLog -Tail 10 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() -ne '' })
  foreach ($l in $tail) { Write-Host "  $l" -ForegroundColor Red }
  Write-Host "  Full log: $errLog"
  Write-Host "  (If the port is in use, change MDV2_PORT in .env - editing it cannot break the seal.)"
  Write-Host ""
  Release-Lock -Path $lockFile -Identity $identity
  exit 1
}

# --- 9b. Sir's CRM: vba-be (the API) and vba-fe (the Next dev server the CRM
#         pane frames), from the checkouts in $crmDir -- the dev launcher's
#         block, for the ship.
#
#         HERE, after the server is up and right before the watchdog, so a
#         Ctrl+C during the server's start cannot leave them running hidden
#         with nothing to reap them.
#
#         Started only when not already running -- listening on its port, OR as
#         its dev process in that folder (nodemon between restarts holds no
#         port). One started by the dev copy's launcher or by VS Code's
#         Ctrl+Shift+B is used as it is and NEVER touched on close: it is not
#         this window's. The ones started here are reaped by their own process
#         trees only, never by port. Output goes to $stateDir, outside the
#         sealed tree, like every other log of this copy.
#
#         PORT is cleared first: vba-be reads PORT before its own .env, and a
#         machine-wide PORT would otherwise put it on the wrong port.
$crmProcs = @()
function Get-CrmPartState {
  param([string]$Dir, [int]$Port, [string]$DevMarker)
  if (Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue) {
    return "already running on $Port"
  }
  $inDir = (Join-Path $Dir 'node_modules').Replace('/', '\').ToLowerInvariant()
  $found = Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine.ToLowerInvariant().Contains($inDir) -and $_.CommandLine -match $DevMarker } |
    Select-Object -First 1
  if ($found) { return "already running (PID $($found.ProcessId), not listening yet)" }
  return $null
}
function Start-CrmPart {
  param([string]$Name, [string]$Dir, [int]$Port, [string]$DevArgs, [string]$DevMarker)
  if (-not (Test-Path -LiteralPath (Join-Path $Dir 'package.json'))) {
    Write-Host "  $Name not found at $Dir - skipped (set SIRS_CRM_DIR in .env)." -ForegroundColor Yellow
    return
  }
  $state = Get-CrmPartState -Dir $Dir -Port $Port -DevMarker $DevMarker
  if ($state) {
    Write-Host "  $Name is $state - using it as it is."
    return
  }
  if (-not (Test-Path -LiteralPath (Join-Path $Dir 'node_modules'))) {
    Write-Host "  $Name has no node_modules - install it first (VS Code: 'Install Both')." -ForegroundColor Yellow
    return
  }
  $log = Join-Path $stateDir "$Name.log"
  Write-Host "  Starting $Name on $Port   (log: $log)"
  # -WorkingDirectory, not `cd` inside the command: the folder is "Sir's CRM",
  # and an apostrophe is one quoting layer away from breaking a command line.
  $p = Start-Process cmd -PassThru -WindowStyle Hidden -WorkingDirectory $Dir `
    -ArgumentList '/c', "npm run dev$DevArgs > `"$log`" 2>&1"
  $script:crmProcs += $p
}
if ($crmLive) {
  # The live CRM: nothing on this PC to start.
  Write-Host "  Sir's CRM: $crmFeUrl (live)"
} else {
  $env:PORT = ''
  Write-Host "  Sir's CRM ($crmDir)"
  Start-CrmPart -Name 'vba-be' -Dir (Join-Path $crmDir 'vba-be') -Port $crmBePort -DevArgs '' -DevMarker 'nodemon'
  # -p only when .env moves vba-fe off the port its own dev script pins.
  $feArgs = if ($crmFePort -ne 4005) { " -- -p $crmFePort" } else { '' }
  Start-CrmPart -Name 'vba-fe' -Dir (Join-Path $crmDir 'vba-fe') -Port $crmFePort -DevArgs $feArgs -DevMarker '\bnext\b.*\sdev\b'
}
$crmKillLines = ($crmProcs | ForEach-Object { "cmd /c `"taskkill /F /T /PID $($_.Id) >nul 2>&1`"" }) -join "`r`n"

if ($healthy) {
  # The DEFAULT browser, with no flags and no debug profile. The dev launcher
  # opens Chrome with --remote-debugging-port=9222 against a ChromeDebug
  # user-data-dir; that is a development convenience and, on a recipient's
  # laptop, an open debugging port they did not ask for.
  #
  # 127.0.0.1 and not localhost: localhost can resolve to ::1 first, and the
  # server is pinned to the IPv4 loopback by section 3. Same reason the health
  # poll above uses the literal address.
  Start-Process "http://127.0.0.1:$port/"
} else {
  Write-Host "  Server did not answer within 120s - not opening a browser." -ForegroundColor Yellow
  Write-Host "  It may still come up. Log: $outLog"
}

# --- 10. Detached watchdog: nothing survives this window. ---------------------
#
# The moment THIS launcher process ends -- window closed, Ctrl+C, or crash --
# the watchdog kills the server tree, removes the lock label if it is still
# ours, and frees the port. It runs OUTSIDE this console so it lives long enough
# to do the cleanup, and it does not depend on job objects or console-ctrl
# inheritance, neither of which survives an Explorer window being X'd.
#
# This matters more here than in the demo. The real server spawns node-pty
# terminals and the claude CLI as grandchildren; an orphaned tree is not just a
# held port, it is live shells with bypassPermissions running behind no window.
#
# Written to a FILE and started with -File, not passed as a -Command string.
# Start-Process joins -ArgumentList with spaces without escaping embedded
# quotes, so a multi-line script containing `cmd /c "..."` arrives at
# powershell.exe re-parsed by CommandLineToArgvW and can silently lose or merge
# lines. A file has no quoting to get wrong. (The dev launcher passes its
# watchdog as a string, and its lock-release block is dead code as a result: it
# escapes with a backslash, `\$held`, which PowerShell does not treat as an
# escape, so the here-string interpolates $held to nothing and leaves an
# unparseable line.)
#
# The script lives in $stateDir, outside the sealed tree, for the same two
# reasons as the lock: read-only ships, and no unsigned files inside $root.
#
# Inside the here-string, $PID / $serverPid / $port and the two *Lit values are
# expanded NOW -- this launcher's values, baked in -- while the watchdog's OWN
# variables are escaped with a backtick so they survive to run time. The *Lit
# values are single-quote-doubled first: a ship unzipped under C:\Users\O'Brien
# would otherwise terminate the string literal early and produce a watchdog that
# does not parse, and nothing would notice, because the failure happens in a
# hidden window after the cleanup has already been promised.
$lockFileLit = $lockFile.Replace("'", "''")
$identityLit = $identity.Replace("'", "''")
$watchdogFile = Join-Path $stateDir 'watchdog.ps1'
$watchdog = @"
# Generated by ship-launcher.ps1 - safe to delete when the app is not running.
Wait-Process -Id $PID -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 400
# taskkill /T because node spawns children here as a matter of course: a pty
# conhost per terminal, the claude CLI per chat, the MCP shim. Stop-Process
# alone would orphan every one of them and leave the port held.
cmd /c "taskkill /F /T /PID $serverPid >nul 2>&1"
# The Sir's CRM dev servers THIS launcher started (none when they were already up).
$crmKillLines
if (Test-Path '$lockFileLit') {
  `$held = (Get-Content '$lockFileLit' -Raw -ErrorAction SilentlyContinue)
  if (`$null -ne `$held -and `$held.Trim() -eq '$identityLit') {
    Remove-Item -LiteralPath '$lockFileLit' -Force -ErrorAction SilentlyContinue
  }
}
# Last resort, and scoped tightly ON PURPOSE: only a node process still LISTENING
# on OUR port. Covers the case where the tree root died but a child kept the
# socket. It must never widen into "kill node processes" - on a developer's
# machine the neighbouring node is their own dev server.
Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue |
  Where-Object { (Get-Process -Id `$_.OwningProcess -ErrorAction SilentlyContinue).ProcessName -eq 'node' } |
  Select-Object -ExpandProperty OwningProcess -Unique |
  ForEach-Object { Stop-Process -Id `$_ -Force -ErrorAction SilentlyContinue }
"@
Set-Content -Path $watchdogFile -Value $watchdog -Encoding ASCII

# Check that it actually started, because section 11 makes a PROMISE about it.
# Two ways this fails and neither raises anything we would otherwise see:
# powershell.exe not resolvable (Start-Process errors, $wd stays $null), or a
# MachinePolicy/UserPolicy execution policy, which -ExecutionPolicy Bypass
# CANNOT override -- there powershell.exe starts, refuses the file and exits
# within milliseconds. So: did we get a process, and is it still alive a moment
# later? The watchdog's first statement is a Wait-Process on us, so a healthy
# one is guaranteed to still be running.
$wd = $null
try {
  $wd = Start-Process powershell -WindowStyle Hidden -PassThru -ErrorAction SilentlyContinue -ArgumentList `
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$watchdogFile`""
} catch {
  $wd = $null
}
Start-Sleep -Milliseconds 700
$watchdogOk = $false
if ($wd) { try { $watchdogOk = -not $wd.HasExited } catch { $watchdogOk = $false } }

# --- 11. Hold the window open while the app runs. ----------------------------
Write-Host ""
Write-Host "  VERIFIED BUILD - running on http://127.0.0.1:$port/"
Write-Host "  Loopback only. Nothing on the network can reach this."
if ($crmLive) {
  Write-Host "  Sir's CRM $crmFeUrl (live)   |   Alt+C switches"
} else {
  Write-Host "  Sir's CRM http://localhost:$crmFePort (vba-fe)   |   API $crmBePort (vba-be)   |   Alt+C switches"
}
if (-not $crmLive -and $crmProcs.Count -eq 0) {
  Write-Host "  (Sir's CRM was already running - it is left alone when this window closes.)"
}
if ($watchdogOk) {
  Write-Host "  Close this window to stop the app. Nothing is left running."
} else {
  # Say what is actually true instead of repeating the promise. Without the
  # watchdog, closing this window orphans node -- here, with live terminals
  # under it -- and the next start fails on a held port for a reason the user
  # was told could not happen.
  Write-Host "  Close this window to stop the app -- but the cleanup watchdog did not start," -ForegroundColor Yellow
  Write-Host "  so node (PID $serverPid) would keep running, with its terminals, holding port $port." -ForegroundColor Yellow
  Write-Host "  Stop it with:  taskkill /F /T /PID $serverPid" -ForegroundColor Yellow
}
Write-Host "  Logs: $stateDir"
Write-Host ""

# Blocks until the server stops -- OR until the window this script was launched
# from goes away.
#
# Wait-Process alone was not enough, and the gap is not theoretical: closing the
# console kills the cmd.exe that ran this script, but ORPHANS this PowerShell
# rather than ending it. Measured: the console went, this script kept waiting,
# node kept serving, and the port stayed held with no window anywhere on screen.
# Neither the watchdog (which waits on THIS process) nor the server's own
# launcher check (which watches THIS pid) can fire, because this process is
# alive and well and waiting for a server that is doing fine.
#
# So the wait is polled, and each turn also asks whether the console that
# started us still exists. When it does not, this script exits -- which fires
# the watchdog, which reaps the tree, and independently satisfies the server's
# COS_LAUNCHER_PID check. Two seconds is well inside "I closed it and the port
# was free by the time I looked".
$parentPid = (Get-CimInstance Win32_Process -Filter "ProcessId = $PID").ParentProcessId
while ($true) {
  if (-not (Get-Process -Id $serverPid -ErrorAction SilentlyContinue)) { break }
  if ($parentPid -and -not (Get-Process -Id $parentPid -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host "  Window closed - stopping the app so the port is not left held."
    break
  }
  Start-Sleep -Seconds 2
}

# Reached on a clean server exit; the watchdog handles the window-closed path.
# Only the LABEL is removed -- the mutex is released by the OS when this process
# ends, which is the entire reason it is a mutex and not a file.
Release-Lock -Path $lockFile -Identity $identity
Write-Host ""
Write-Host "  *** Vivek OS stopped. ***"
Write-Host ""
