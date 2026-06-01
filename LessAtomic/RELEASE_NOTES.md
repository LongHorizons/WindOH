# LessAtomic -- Release Notes

## v0.1.0 -- Initial Release (2026-06-01)

**Binary**: `LessAtomic.exe` (168 MB, static, zero runtime deps)  
**Platform**: Windows 10/11 x86_64  

---

## What It Is

LessAtomic is a single self-contained executable that embeds the entire Windows Atomic Red Team™ test library and executes it against the host system with multi-threading, progress reporting, and automatic dependency resolution.

## Embedded Contents

| Component | Count |
|-----------|-------|
| Windows technique YAML files | 265 |
| Total atomic tests | 752 |
| PowerShell tests | 434 |
| Command Prompt tests | 310 |
| Manual tests | 8 |
| Source/bin asset files | 570 (171 MB) |

## System Requirements

- Windows 10 build 1809+ or Windows 11
- x86_64 architecture
- 512 MB RAM minimum
- 200 MB free disk (for temp extraction)
- **No other dependencies**

## Quick Test

```powershell
LessAtomic.exe --version
LessAtomic.exe --dry-run
LessAtomic.exe -t T1059.001 --danger-accept -v
```

## Known Limitations

- `sh`/`bash` executors skipped on native Windows (future WSL support)
- No inter-test isolation (use `-c 1` for sequential execution)
- Many tests trigger AV/EDR alerts
- ~250 tests require admin elevation

## Credits

Built on **Atomic Red Team™** by [Red Canary](https://redcanary.com).  
Technique taxonomy: **MITRE ATT&CK®**.
