# Workspace Lifecycle Reliability

Date: 2026-08-13

## Goal

Fix the reviewed software-Workspace wake path, Agent launch races, lost launch
errors, and stale switcher documentation without changing the two-system-modal
architecture, Touch Bar placement, or mirror transition timing.

## Scope

### Software Workspace lifecycle

- Starting and resuming on a Mac without a usable physical Touch Bar must never
  call `TouchBarCapture.start()` or `TouchBarCapture.restart()`.
- Sleep and lock notifications may temporarily leave the software Workspace,
  but the corresponding resume notification must restore its interactive
  Workspace scene rather than starting a display-stream retry loop.
- Hardware mode keeps the existing capture restart and physical switcher path.
- The hardware/software decision remains based only on private-API capability,
  never CPU architecture.

### Agent launch session ownership

- Each Workspace entry has a monotonically increasing session generation.
- Agent launch work and delayed auto-collapse belong to the generation in which
  they were created.
- Closing Workspace, stopping the controller, or beginning a newer launch
  cancels obsolete work.
- Completion, failure, and auto-collapse update UI only when their generation is
  still current and Workspace is still open.
- Closing Workspace must not claim that an uncancelled launch has completed by
  merely clearing a Boolean flag.

### Process completion semantics

- Direct application launcher commands such as Codex/Cursor retain a short
  launch grace: surviving the grace period counts as successfully handed off.
- Terminal adapter helpers (`otty-cli` and `osascript`) are short-lived control
  commands and must be awaited to termination so nonzero exits propagate to the
  Workspace failure UI.
- Cancellation terminates only a still-running helper process created by the
  current launch operation; it does not terminate an opened Agent application.

### Custom App errors

- Opening a pinned custom App becomes asynchronous and throwing.
- Both the saved-path attempt and bundle-identifier fallback propagate the
  `NSWorkspace` completion error.
- A missing saved path may use the bundle-identifier fallback. A launch failure
  at an existing path is reported rather than silently ignored.
- The existing Workspace context and Agent buttons remain usable after failure.

### Documentation

- User and developer documentation describe only the current switcher choices:
  physical Touch Bar or independent floating window.
- Documentation continues to state that the mirror window is click-through and
  positioned through Settings, not dragged.

## Design

Pure policy helpers will isolate hardware resume behavior and generation checks
so the smoke test can exercise them without creating windows or touching private
APIs. `TouchBarWindowController` will own the Agent launch and auto-collapse
task handles, cancel them at lifecycle boundaries, and guard every asynchronous
UI write with the captured generation.

`AgentLauncher` will use two explicit completion paths: launch-grace for direct
Agent commands and termination-waiting for terminal helper commands. Process
termination will use a cancellation-aware continuation. Custom App opening will
wrap `NSWorkspace.openApplication` in a checked throwing continuation.

No changes are made to `SwitcherTouchBarController`,
`WorkspaceTouchBarController`, placement `0/1`, `PresentationModeGlobal`
policy, the 1010-point Workspace cap, or the 221ms transition settle.

## Verification

- Add failing smoke assertions for software/hardware resume policy and Workspace
  generation ownership before implementation.
- Add an asynchronous process regression using a delayed nonzero helper process
  so the previous 300ms false-success behavior is observable.
- Add an injected custom-App opener regression proving completion errors reach
  the caller.
- Run `Scripts/run-regression.sh`, shell syntax checks, and `git diff --check`.
- Physical Touch Bar modal behavior remains a required real-hardware manual
  check because the smoke path does not present private system modals.

