# Model Abstraction Layer

## Design

The WindOH enrichment pipeline uses an LLM provider abstraction to support multiple inference backends through a single interface. The abstraction follows the Adapter pattern, with each backend implementing a common `LLMProvider` interface.

## Interface

```typescript
// providers/types.ts
interface LLMProvider {
  /** Human-readable name for logging and health checks */
  readonly name: string;

  /** Health check — returns latency and model info */
  health(): Promise<{
    available: boolean;
    latencyMs: number;
    modelName: string;
    contextLength: number;
  }>;

  /** Primary inference method */
  complete(request: EnrichmentRequest): Promise<EnrichmentResponse>;

  /** Streaming variant for real-time token display */
  completeStream(
    request: EnrichmentRequest,
    onToken: (token: string) => void
  ): Promise<EnrichmentResponse>;
}

interface EnrichmentRequest {
  systemPrompt: string;
  eventData: EventFields;
  examples: EnrichmentExample[];
  maxTokens: number;
  temperature: number;
}

interface EnrichmentResponse {
  description: string;
  mitreTechniques: Array<{ id: string; name: string; confidence: number }>;
  riskAssessment: { level: 'low' | 'medium' | 'high' | 'critical'; rationale: string };
  flags: BehaviorFlags;
  investigationSteps: string[];
  rawPrompt: string;
  rawResponse: string;
  modelName: string;
  tokensUsed: { prompt: number; completion: number };
  latencyMs: number;
}
```

## Provider Implementations

### OpenAI-Compatible Provider

The primary provider. Supports any OpenAI-compatible chat completions API.

```typescript
// providers/openai-compatible.ts
class OpenAICompatibleProvider implements LLMProvider {
  readonly name = 'openai-compatible';

  constructor(private config: {
    endpoint: string;        // http://192.168.0.133:31337/v1
    apiKey?: string;         // Optional — local LLMs often skip auth
    modelName: string;       // e.g., "llama-3-8b-instruct"
    contextLength: number;   // e.g., 8192
    timeoutMs: number;       // e.g., 60000
  }) {}

  async health(): Promise<HealthResponse> {
    const start = Date.now();
    const res = await fetch(`${this.config.endpoint}/models`, {
      headers: this.config.apiKey
        ? { Authorization: `Bearer ${this.config.apiKey}` }
        : {},
      signal: AbortSignal.timeout(5000),
    });
    return {
      available: res.ok,
      latencyMs: Date.now() - start,
      modelName: this.config.modelName,
      contextLength: this.config.contextLength,
    };
  }

  async complete(request: EnrichmentRequest): Promise<EnrichmentResponse> {
    // Build structured prompt with JSON response format
    // POST to {endpoint}/chat/completions
    // Parse JSON response
    // Return typed EnrichmentResponse with provenance
  }
}
```

### Backends Supported

| Backend | Endpoint Example | Notes |
|---|---|---|
| **llama.cpp** | `http://127.0.0.1:8080/v1` | Fast CPU inference, GGUF models |
| **Ollama** | `http://127.0.0.1:11434/v1` | Easy model management, macOS/Linux |
| **vLLM** | `http://127.0.0.1:8000/v1` | High-throughput GPU inference |
| **text-generation-webui** | `http://127.0.0.1:5000/v1` | oobabooga, broad model support |
| **OpenAI API** | `https://api.openai.com/v1` | Cloud — not default, requires explicit config |
| **Anthropic API** | `https://api.anthropic.com/v1` | Cloud — via OpenAI-compatible proxy |

## Structured Prompt Design

The enrichment prompt uses a constrained JSON response format to ensure parseable, typed output:

```typescript
// prompts/enrichment.ts
function buildEnrichmentPrompt(event: EventFields): EnrichmentRequest {
  const systemPrompt = `You are a security behavioral analyst. Given a Windows process event, produce a structured analysis.

Output MUST be valid JSON matching this schema:
{
  "description": "plain-language description of the behavior (1-3 sentences)",
  "mitre_techniques": [
    {"id": "T1059.001", "name": "PowerShell", "confidence": 0.85}
  ],
  "risk_assessment": {
    "level": "low|medium|high|critical",
    "rationale": "specific reasons for the risk level (1-2 sentences)"
  },
  "flags": {
    "lolbin": true/false,
    "exfiltration": true/false,
    "privilege_escalation": true/false,
    "persistence": true/false,
    "lateral_movement": true/false
  },
  "investigation_steps": ["step 1", "step 2", "step 3"]
}`;

  const userMessage = `---BEGIN EVENT DATA---
Process: ${event.image_path}
Parent Process: ${event.parent_image_path}
Command Line: ${event.command_line}
User: ${event.user_name}
Network Targets: ${event.dest_ip?.join(', ') || 'none'}
File Operations: ${event.file_path_target || 'none'}
Ancestor Chain: ${event.ancestor_chain.join(' → ')}
Behavior Tags: ${event.behavior_tags.join(', ')}
Inter-Event Timing: ${event.inter_event_delta_ms}ms since previous event
---END EVENT DATA---`;

  return {
    systemPrompt,
    eventData: event,
    examples: FEW_SHOT_EXAMPLES,
    maxTokens: 1024,
    temperature: 0.1,  // Low temperature for deterministic enrichment
  };
}
```

## Provider Selection

Configured via environment variables:

```bash
# .env
LLM_PROVIDER=openai-compatible
LLM_ENDPOINT=http://192.168.0.133:31337/v1
LLM_API_KEY=           # Optional
LLM_MODEL_NAME=llama-3-8b-instruct
LLM_CONTEXT_LENGTH=8192
LLM_TIMEOUT_MS=60000
LLM_MAX_CONCURRENCY=4
```

## Fallback and Routing

The current implementation uses a single provider. The architecture supports multi-provider routing via a `RouterProvider` that can:

1. **Health-based routing:** Skip providers that fail health checks.
2. **Capability-based routing:** Route complex prompts to larger models, simple prompts to smaller/faster models.
3. **Cost-based routing:** Prefer local LLMs; fall back to cloud API only if local is unavailable (optional, disabled by default to enforce data sovereignty).

```typescript
// providers/router.ts (planned extension)
class RouterProvider implements LLMProvider {
  constructor(private providers: LLMProvider[]) {}

  async complete(request: EnrichmentRequest): Promise<EnrichmentResponse> {
    for (const provider of this.providers) {
      const health = await provider.health();
      if (health.available) {
        return provider.complete(request);
      }
    }
    throw new Error('No available LLM provider');
  }
}
```
