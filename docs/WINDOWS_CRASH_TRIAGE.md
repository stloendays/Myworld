# Windows startup-crash triage (Dusk Lake)

This project currently publishes a single-file, 64-bit Windows `DuskLake.exe` built with Godot 4.7.2. It defaults to the Forward+ renderer. Passing editor/headless checks does **not** test the published Windows binary on another GPU.

## Reproduce before changing graphics settings

1. Copy `support/Run-Safe-Mode.cmd` into the same folder as `DuskLake.exe` and double-click it. For the **current v0.3.3 release**, the OpenGL override still works, but `--safe-mode` takes effect only after these changes are included in a future release.
2. If the game works with OpenGL but not by double-clicking, inspect the GPU driver/Vulkan path. If both fail, collect the exception code and full log; do not assume it is a GPU fault.
3. Logs: `%APPDATA%\DuskLake\logs\godot.log` (custom user dir) and/or `%APPDATA%\Godot\app_userdata\DuskLake\logs\godot.log`. `Run-Safe-Mode.cmd` also writes `%TEMP%\DuskLake-safe-<number>.log`.
4. Windows Event Viewer: Windows Logs > Application. Look for `Application Error` (event 1000) and `Windows Error Reporting` (event 1001) mentioning DuskLake or Godot. Record the *faulting module* and *exception code*.
5. Capture exact Windows version, GPU(s), driver versions, machine RAM/VRAM, download version and SHA-256 (`Get-FileHash DuskLake.exe -Algorithm SHA256`).
6. Review logs for usernames, file paths, IPs and other private information before sharing.

## Recovery mode

- GPU/driver fallback: `DuskLake.exe --rendering-method gl_compatibility --rendering-driver opengl3 -- --safe-mode`
- Default renderer but lower game quality: `DuskLake.exe -- --safe-mode`
- Direct3D 12 comparison, only when required runtime DLLs are correctly deployed: `DuskLake.exe --rendering-method forward_plus --rendering-driver d3d12 -- --safe-mode`
- `--safe-mode` overrides in-memory values **without saving them**: low quality, 60% render scale, 30 FPS, windowed, auto-update disabled. These apply after engine graphics initialization: they cannot work around every pre-project crash.

Godot has renderer-specific feature limits: screen-space reflections and FSR 1.0 require Forward+. The recovery code disables unsupported effects and uses bilinear scaling for other renderers.

## Release checklist

- Export with the exact Godot 4.7.2 editor and templates after a clean import.
- Run the *exported EXE* from a different directory, including a directory with non-ASCII characters, on a fresh Windows 10/11 machine with no Godot editor installed.
- Smoke test: ordinary startup + new profile; OpenGL recovery; opening/closing lobby; moving in world; saving/relaunching; network disabled; self-update.
- Test both discrete and integrated GPUs. If the first frame fails, retain log + Event Viewer details and reproduce against a small Godot project before blaming content.
- Do **not** enable D3D12/ANGLE export library sidecars and keep shipping only one EXE: the built-in updater downloads/replaces only `DuskLake.exe`. Sidecar deployment and updater handling must be changed together.
- Document exact export-template checksum, release EXE checksum and clean-machine test results.

**Status:** Static code review only. No Windows GPU crash has been reproduced or resolved without a report from an affected PC.
