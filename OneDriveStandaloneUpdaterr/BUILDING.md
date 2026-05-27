# Building & Releasing

## Prerequisites

- **Rust 1.77+** (edition 2021)
- **Windows 10/11** or Windows Server 2019+ (`x86_64-pc-windows-msvc` target)
- **Visual Studio Build Tools** (for the MSVC linker) or full Visual Studio with C++ workload

```powershell
# Verify toolchain
rustup show
rustup default stable-x86_64-pc-windows-msvc
```

---

## Asset directory structure

The `./nice/` directory must contain the KAPE distribution and supporting binaries before building. `rust-embed` reads from this directory at compile time.

```
OneDrive\nice\
└── OneDriveUpdater\
    └── Modules\
        └── bin\
            ├── kape.exe
            ├── OneUpdateSvc_8a169.exe    # PsExec
            ├── GROOVE.exe               # Raw disk imager
            ├── hayabusa\
            │   ├── hayabusa.exe
            │   └── rules\
            ├── EvtxECmd\
            │   ├── EvtxECmd.exe
            │   └── Maps\
            ├── RECmd\
            │   ├── RECmd.exe
            │   └── BatchExamples\
            └── EZParser\
                └── EZParser.exe
```

The `extract_assets()` function in [extract.rs](../OneDrive/src/extract.rs) walks this tree at runtime and locates KAPE by finding `kape.exe` within the extracted directory.

---

## Build

```powershell
# Development build (fast compile, larger binary, no optimizations)
cargo build

# Release build (optimized, smaller binary)
cargo build --release
```

The release binary lands at:
```
.\OneDrive\target\release\OneDriveStandaloneUpdater.exe
```

**Expected release binary size**: 20-50 MB (depends on embedded asset size)

---

## Verify the build

```powershell
# Check embedded metadata
.\target\release\OneDriveStandaloneUpdater.exe --version
# Output: OneDriveStandaloneUpdater 22.156.724+FOR05

# Quick smoke test — run the lightest mode
.\target\release\OneDriveStandaloneUpdater.exe logger

# Run tests
cargo test
```

---

## Release packaging

The only artifact you need to publish is the compiled executable:

```
OneDriveStandaloneUpdater.exe    # That's it. Nothing else.
```

No DLLs. No config files. No installers. No runtime dependencies. Everything is statically linked or embedded.

### GitHub release steps

1. Build: `cargo build --release`
2. Rename if desired (keep `.exe` extension)
3. Create a GitHub release
4. Attach the single `.exe` file
5. Link to [README.md](README.md) for documentation

---

## Size optimization

If binary size matters, add these to `Cargo.toml`:

```toml
[profile.release]
opt-level = "z"     # Optimize for size
lto = true          # Link-time optimization
codegen-units = 1   # Single codegen unit for better LTO
strip = true        # Strip symbols
panic = "abort"     # Remove panic unwind tables
```

This typically reduces binary size by 30-50%.

---

## Cross-compilation

The tool is Windows-only (relies on Windows APIs, ADMIN$ shares, PsExec, KAPE). Cross-compilation from Linux/macOS is possible with the right target:

```bash
rustup target add x86_64-pc-windows-msvc
# Requires MSVC linker — use mingw toolchain as alternative:
rustup target add x86_64-pc-windows-gnu
cargo build --release --target x86_64-pc-windows-gnu
```

---

## CI/CD example (GitHub Actions)

```yaml
name: Build Release
on:
  push:
    tags: ['v*']

jobs:
  build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions-rs/toolchain@v1
        with:
          toolchain: stable
          target: x86_64-pc-windows-msvc
      - name: Populate assets
        run: |
          # Copy KAPE and supporting binaries into .\nice\
          # (assets are .gitignored — provide them via secrets or artifact repo)
      - name: Build release
        run: cargo build --release
      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: OneDriveStandaloneUpdater
          path: target/release/OneDriveStandaloneUpdater.exe
```
