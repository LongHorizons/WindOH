# ADR-004: Local LLM Inference Over Cloud API

**Status:** Accepted
**Date:** 2025-11-15
**Deciders:** Platform architect

## Context

The WindOH application enriches behavioral tokens with AI-generated descriptions, MITRE ATT&CK mappings, and risk assessments. Two approaches were considered:

1. **Cloud API (OpenAI, Anthropic, etc.):** Send structured prompts to a remote LLM service with an API key.
2. **Local inference:** Run an LLM on-premises via llama.cpp, Ollama, vLLM, or any OpenAI-compatible endpoint.

## Decision

Local inference was selected, with the OpenAI-compatible API protocol as the abstraction layer.

## Rationale

- **Data sovereignty:** Behavioral telemetry includes process command lines, network targets, and user identities — the most sensitive data in a security environment. Routing this through a third-party API creates an exfiltration surface and a compliance liability.
- **Air-gap compatibility:** Many security environments are physically disconnected. Local inference works without internet access.
- **Cost predictability:** Cloud API costs scale with token count and are unbounded. Local inference has a fixed hardware cost.
- **Latency:** Local inference eliminates network round-trip (~50-200ms). For the enrichment pipeline (which runs once per novel behavior, not once per event), this is acceptable either way, but local is faster.
- **Protocol abstraction:** Using the OpenAI-compatible chat completions API as the interface means the LLM backend can be swapped (llama.cpp → Ollama → vLLM → text-generation-webui) with a config change.

## Consequences

- Enrichment quality depends on the local model's capability. A 7B model provides adequate behavioral descriptions; larger models improve MITRE mapping accuracy.
- The operator must provision and maintain LLM infrastructure. This is an operational cost not present with cloud APIs.
- No fallback to cloud is implemented. If the local LLM is unavailable, enrichment pauses. This is by design — no data transits the network boundary for enrichment.
