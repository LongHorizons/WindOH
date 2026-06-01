# LessAtomic — Quick Start

## One binary. 752 Windows attack technique tests. Fully self-contained.

---

## 🚀 10 Seconds to Start

```powershell
# 1. Extract LessAtomic-release.zip
# 2. Open a terminal (PowerShell or CMD) in the extracted folder
# 3. Run:

LessAtomic.exe --version
# → LessAtomic 0.1.0

LessAtomic.exe --dry-run
# → Found 752 matching test(s)
```

**That's it.** On first run, LessAtomic extracts its embedded assets (570 files) to `%TEMP%\LessAtomic\atomics\`. Subsequent runs use the cache — instant startup. No external dependencies needed.

---

## 📁 What You Get

```
LessAtomic/
├── LessAtomic.exe        ← The executor (168 MB, fully self-contained)
│                           Embeds 265 YAML definitions + 570 src/bin assets
├── README.md             ← Full docs: architecture, Mermaid diagrams, credits
├── QUICKSTART.md         ← This file
├── RELEASE_NOTES.md      ← Version info, requirements, known issues
└── LICENSE.txt           ← MIT License + ATT&CK/ART attribution
```

**No `atomics/` directory needed.** Everything is inside the binary.

---

## ⚡ Performance

LessAtomic uses **80% of your CPU cores** by default for maximum throughput.

| Machine | Workers | vs Invoke-Atomic (sequential) |
|---------|---------|-------------------------------|
| 4-core laptop | 4 | ~3.5× faster |
| 8-core desktop | 7 | **~6× faster** |
| 16-core workstation | 13 | ~10–12× faster |

**Full ART suite (752 tests), 8-core machine:**
- Invoke-AtomicRedTeam: ~6–12 hours
- LessAtomic: **~40–90 minutes**

Override with `-c N` if you want fewer/more workers.

---

## 📊 What's Embedded

| Asset | Count | Size |
|--------|-------|------|
| Technique YAML files | 265 | ~239 KB |
| Source scripts (src/) | ~350 | ~10 MB |
| Binary tools (bin/) | ~220 | ~161 MB |
| Total atomic tests | **752** | — |

---

## 🏃 Usage

### List tests

```powershell
LessAtomic.exe --dry-run                  # All 752 tests
LessAtomic.exe -t T1003 --dry-run        # Filter by technique
LessAtomic.exe -e powershell --dry-run   # Filter by executor
LessAtomic.exe --name "LSASS" --dry-run  # Filter by name
```

### Run tests

```powershell
LessAtomic.exe -t T1059.001                             # Single technique
LessAtomic.exe -t T1003 --auto-install                  # Auto-install deps
LessAtomic.exe -t T1059.001 -c 4 -v --danger-accept     # 4 threads, verbose
LessAtomic.exe --danger-accept -c 4 -o json --log-dir .\logs\  # Full run
```

### Output options

```powershell
-o text                         # Text summary (default)
-o json                         # Machine-readable JSON
--log-dir .\logs\               # Per-test .log files
```

---

## ⚠ Safety

These are **REAL attack techniques**. Always use a disposable VM.

---

<div align="center">

```
⚛ LessAtomic v0.1.0 — Built on Atomic Red Team™ by Red Canary
```

</div>
