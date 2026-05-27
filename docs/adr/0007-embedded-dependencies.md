# ADR-007: Embedded Dependencies Over Runtime Installation

**Status:** Accepted
**Date:** 2025-12-10
**Deciders:** Platform architect

## Context

LessVolatile and OneDriveStandaloneUpdaterr both depend on external tools (Volatility 3, Python 3.9, KAPE, PsExec, Hayabusa, Eric Zimmerman tools). Two approaches were considered:

1. **Runtime installation:** Require the user to install dependencies before running the tool. Document prerequisites.
2. **Embedded dependencies:** Compile all dependencies into the Rust binary via `include_bytes!` (LessVolatile) or `rust-embed` (OneDriveStandaloneUpdaterr). Extract on first run.

## Decision

Embedded dependencies were selected for both tools.

## Rationale

- **Air-gap compatibility:** Incident response frequently occurs in environments without internet access. Runtime installation (`pip install volatility3`, downloading KAPE) is impossible.
- **Determinism:** A specific version of each dependency is pinned at compile time. Runtime installation may pull different versions, producing different outputs — violating the reproducibility principle.
- **Deployment simplicity:** A single file can be carried on a USB drive and run on any target. This matters operationally when responding to incidents across multiple isolated networks.
- **Avoidance of detection:** Runtime installation of forensic tools triggers antivirus and EDR signatures. A single signed or benign-metadata-carrying binary generates less telemetry.

## Consequences

- Binary size is large (~129 MB for LessVolatile, ~324 MB for OneDriveStandaloneUpdaterr). This is a trade-off accepted for operational simplicity.
- Dependencies are frozen at compile time. Updating Volatility 3 plugins or KAPE targets requires rebuilding the binary.
- `rust-embed` increases compile time. Assets are compressed with zstd to reduce binary size.
