# Documentation Index

## Architecture

- [DATA_FLOW.md](architecture/DATA_FLOW.md) — System-level data flow, agent event processing pipeline, WindOH application data flow, design constraints
- [QUEUE_ARCHITECTURE.md](architecture/QUEUE_ARCHITECTURE.md) — BullMQ queue topology, retry semantics, event-driven workflows, monitoring
- [MODEL_ABSTRACTION.md](architecture/MODEL_ABSTRACTION.md) — LLM provider abstraction, structured prompt design, provider selection
- [PERSISTENCE.md](architecture/PERSISTENCE.md) — Storage landscape, agent SQLite design, MongoDB collections, cache strategy, backups
- [TENANCY_RBAC.md](architecture/TENANCY_RBAC.md) — Multi-tenancy model, RBAC roles, permission matrix, audit logging (roadmap)

## Operations

- [FAILURE_HANDLING.md](operations/FAILURE_HANDLING.md) — Failure mode inventory for all components, health check endpoints
- [RUNBOOKS.md](operations/RUNBOOKS.md) — Step-by-step recovery procedures for common failure scenarios

## Security

- [THREAT_MODEL.md](security/THREAT_MODEL.md) — Trust boundaries, threat catalog, risk matrix
- [SECURITY_MODEL.md](security/SECURITY_MODEL.md) — Key management, encryption at rest/in transit, authentication, data minimization

## Deployment

- [DEPLOYMENT.md](deployment/DEPLOYMENT.md) — Docker Compose, Kubernetes manifests, Terraform outline, deployment checklist

## Design Decisions

- [ADR-001: Cryptographic Behavioral Identity](adr/0001-cryptographic-behavioral-identity.md)
- [ADR-002: Count-Min Sketch Baselining](adr/0002-count-min-sketch-baselining.md)
- [ADR-003: 8-Way Sharded Pipeline Concurrency](adr/0003-sharded-pipeline-concurrency.md)
- [ADR-004: Local LLM Inference](adr/0004-local-llm-inference.md)
- [ADR-005: Elasticsearch as Transport Layer](adr/0005-elasticsearch-transport-layer.md)
- [ADR-006: Markov Chains for Sequence Prediction](adr/0006-markov-chains-over-deep-learning.md)
- [ADR-007: Embedded Dependencies](adr/0007-embedded-dependencies.md)

## Project-Level

- [ENGINEERING_PRINCIPLES.md](../ENGINEERING_PRINCIPLES.md) — Design principles and decision framework
- [README.md](../README.md) — Platform overview with architecture diagrams
