# LessToil — Contributing

> How to contribute: adding language support, new features, architectural domains, bug fixes, and setting up a development environment.

---

## Table of Contents

1. [Ways to Contribute](#ways-to-contribute)
2. [Adding Language Support](#adding-language-support)
3. [Adding Architectural Domains](#adding-architectural-domains)
4. [Improving Extraction Quality](#improving-extraction-quality)
5. [New Feature Ideas](#new-feature-ideas)
6. [Bug Fixes](#bug-fixes)
7. [Development Setup](#development-setup)
8. [Testing Your Changes](#testing-your-changes)
9. [Code Style](#code-style)
10. [Pull Request Process](#pull-request-process)
11. [Architecture Decision Records](#architecture-decision-records)

---

## Ways to Contribute

| Contribution Type | Impact | Difficulty |
|-------------------|--------|------------|
| Add language support | High — enables the plugin for more projects | Medium |
| Improve tree-sitter queries | Medium — better symbol extraction for existing languages | Low-Medium |
| Add regex fallback extractors | Medium — enables extraction for languages without tree-sitter | Low-Medium |
| Add new architectural domains | Low-Medium — richer codebase classification | Low |
| Add new intelligence modules | Medium-High — new analysis capabilities | Medium-High |
| Improve existing modules | Medium — better accuracy, performance, or coverage | Varies |
| Bug fixes | High — directly improves reliability for all users | Varies |
| Documentation improvements | Medium — better onboarding and understanding | Low |

---

## Adding Language Support

The most impactful contribution. The plugin already supports 56 languages (41 via tree-sitter AST + 15 via regex fallback). New languages are always welcome.

### Step 1: Register the Language

In `core/indexer.py`, add entries to `EXTENSION_LANGUAGE_MAP`:

```python
EXTENSION_LANGUAGE_MAP = {
    # ... existing entries
    '.my_lang': 'my_lang',
    '.ml': 'my_lang',
}
```

### Step 2: Add Tree-sitter Queries

In `core/symbols.py`, define SCM query patterns for symbol and call extraction:

```python
MY_LANG_QUERY = """
(function_definition
  name: (identifier) @function.name
  parameters: (parameters) @function.params
  body: (block) @function.body
) @function.def

(class_definition
  name: (identifier) @class.name
) @class.def

(call_expression
  function: (identifier) @call.name
) @call.expr
"""

LANGUAGE_QUERIES = {
    # ... existing entries
    'my_lang': MY_LANG_QUERY,
}
```

Captures use `@category.field` naming:
- `@function.name`, `@function.def` — function definitions
- `@class.name`, `@class.def` — class definitions
- `@method.name`, `@method.def` — method definitions
- `@call.name`, `@call.expr` — call expressions
- `@import` — import statements

### Step 3: Register Grammar Packages

In **both** installers — they must stay in sync.

**install.sh:**
```bash
# GRAMMAR_PACKAGES array — add at the end
"tree-sitter-my-lang|tree_sitter_my_lang"
```

**install.ps1:**
```powershell
# $GRAMMAR_PACKAGES array — add at the end
@{pip="tree-sitter-my-lang"; imp="tree_sitter_my_lang"}
```

The format is `pip-package-name|python-import-name`.

### Step 4: Add Regex Fallback Extractor

In `core/symbols.py`, add a regex-based extractor for when the tree-sitter grammar is not installed:

```python
def _extract_my_lang_regex(source: str, file_path: str) -> tuple[list[dict], list[dict]]:
    symbols = []
    calls = []

    # Function definitions
    func_pattern = re.compile(
        r'fn\s+(\w+)\s*\(([^)]*)\)',
        re.MULTILINE
    )
    for match in func_pattern.finditer(source):
        symbols.append({
            'name': match.group(1),
            'kind': 'function',
            'start_line': source[:match.start()].count('\n') + 1,
            'signature': f"fn {match.group(1)}({match.group(2)})",
        })

    # Call expressions
    call_pattern = re.compile(
        r'(?<!fn\s)(\w+)\s*\(',
        re.MULTILINE
    )
    for match in call_pattern.finditer(source):
        name = match.group(1)
        if name not in RESERVED_WORDS:  # Skip keywords used as call-like syntax
            calls.append({
                'callee_name': name,
                'call_line': source[:match.start()].count('\n') + 1,
            })

    return symbols, calls

_REGEX_EXTRACTORS['my_lang'] = _extract_my_lang_regex
```

### Step 5: Register in Supported Languages

In `core/symbols.py`:

```python
SUPPORTED_LANGUAGES = {'python', 'typescript', 'javascript', 'go', 'rust', ..., 'my_lang'}
```

### Step 6: Test

See [Testing Your Changes](#testing-your-changes) for test commands.

---

## Adding Architectural Domains

### Via Configuration (No Code Change)

Add custom domains in `.claude/repo-cognition.settings.local.md`:

```yaml
---
domains:
  custom_domains:
    - name: containerization
      description: Docker, Kubernetes, container orchestration
      path_patterns: [Dockerfile, docker-compose, k8s, kubernetes, helm]
      symbol_patterns: [container, image, deployment, pod, service]
      security_boundary: false
---
```

### Via Code (Permanent Addition)

Add to `DOMAIN_DEFINITIONS` in `core/domains.py`:

```python
DOMAIN_DEFINITIONS['containerization'] = {
    'description': 'Docker, Kubernetes, container orchestration',
    'path_patterns': [
        r'Dockerfile', r'docker-compose', r'k8s', r'kubernetes',
        r'helm', r'pod', r'deployment', r'service\.yaml',
    ],
    'symbol_patterns': [
        r'container', r'image', r'deployment', r'pod', r'service',
    ],
    'security_boundary': False,
}
```

---

## Improving Extraction Quality

### Better Tree-sitter SCM Queries

Capture additional symbol types per language: interfaces, enums, type aliases, structs, traits, constants. Add to the language's query string in `LANGUAGE_QUERIES`.

### Better Regex Fallback Patterns

Handle edge cases in languages without tree-sitter grammars: multi-line signatures, nested generics, decorator/annotation syntax, async patterns. Improve `_REGEX_EXTRACTORS` entries.

### Security-Sensitive Heuristics

Improve detection of auth, crypto, and secrets patterns in `core/symbols.py`. The current heuristics check function names, parameter names, and surrounding context for security keywords. Better patterns increase `security_sensitive = 1` accuracy.

### Side-Effect Detection

Improve I/O, mutation, and network call detection. The current heuristics check for known side-effecting patterns (file operations, network calls, database queries, state mutation). Language-specific patterns can be added.

### Duplicate Detection Normalization

Improve `core/similarity.py` — add language-specific identifier replacement rules so SimHash normalization preserves more structural information while being robust to renaming.

---

## New Feature Ideas

Ideas for standalone contributions:

| Feature | Description | Difficulty |
|---------|-------------|------------|
| **Cyclomatic complexity** | Per-function complexity scoring, integrated with stewardship | Medium |
| **Ownership inference** | `git log --follow` integration to infer code ownership from commit history | Medium |
| **API contract extraction** | Parse OpenAPI/GraphQL/protobuf schemas from source into structured tables | Medium-High |
| **Database schema extraction** | Parse SQL migration files into entity-relationship graphs | Medium |
| **Multi-repo support** | Cross-repository dependency tracking via git submodule or workspace awareness | High |
| **Dependency freshness** | Detect outdated dependencies, version drift across packages | Low-Medium |
| **Layer violation diagrams** | Visualize when code in one architectural layer calls into a forbidden layer | Medium |
| **Hotspot heatmaps** | Temporal + call frequency combined into hotspot severity scoring | Medium |
| **Code review checklist generation** | Auto-generate review checklist based on impacted domains and security boundaries | Low-Medium |
| **Refactoring cost estimation** | Estimate person-hours for common refactoring operations based on impacted scope | Medium |

New intelligence modules follow the existing pattern:
1. Create a `.py` file in `core/`
2. Import and call from `session_start.py` (wrapped in try/except)
3. Use `core.manifest` for database access
4. Follow the existing module conventions (see [Code Style](#code-style))

---

## Bug Fixes

### Good First Issues

- Edge cases in regex extraction producing false matches (e.g., language keywords matched as function names)
- Language detection missing common file extensions
- Exclusion patterns missing common directories
- SQLite query performance optimization for very large repos (100K+ files)
- Dashboard formatting issues on specific terminal widths
- Path handling edge cases on Windows (backslash vs. forward slash)

### Common Bug Patterns

- **Regex extraction false positives**: Keywords like `if`, `while`, `for`, `return` matched as function names. Fix: add a `RESERVED_WORDS` filter in the fallback extractor.
- **Language misdetection**: Extension-only detection misidentifies files. Fix: add content-based detection heuristics (shebangs, keywords).
- **SHA256 mismatch on Windows**: Line ending differences (CRLF vs. LF). Fix: normalize line endings before hashing, or hash the normalized content.
- **SQLite timeout**: Long-running queries on large repos. Fix: add query timeouts, optimize indexes, or add LIMIT clauses.

---

## Development Setup

### Prerequisites

```bash
# Clone the monorepo
git clone https://github.com/LongHorizons/WindOH/LessToil.git
cd claude-code

# Install Python dependencies
pip install tree-sitter tree-sitter-python tree-sitter-typescript \
            tree-sitter-go tree-sitter-rust pyyaml

# Verify the plugin core loads
python3 -c "
import sys
sys.path.insert(0, 'plugins/repo-cognition')
from core.manifest import init_db
init_db()
print('Plugin core loaded successfully')
"
```

### Recommended: Editable Install

For active development, install the plugin and grammar packages in development mode:

```bash
# Install grammar packages from the installer
cd plugins/repo-cognition
python3 -c "
import subprocess, sys
packages = [
    'tree-sitter', 'tree-sitter-python', 'tree-sitter-typescript',
    'tree-sitter-go', 'tree-sitter-rust', 'tree-sitter-java',
    'tree-sitter-c', 'tree-sitter-cpp', 'tree-sitter-c-sharp',
    'tree-sitter-ruby', 'tree-sitter-php', 'tree-sitter-swift',
    'tree-sitter-kotlin', 'tree-sitter-scala', 'tree-sitter-lua',
    'tree-sitter-sql', 'tree-sitter-bash', 'tree-sitter-html',
    'tree-sitter-css', 'tree-sitter-json', 'tree-sitter-yaml',
    'tree-sitter-toml', 'tree-sitter-markdown', 'tree-sitter-dockerfile',
    'tree-sitter-hcl', 'tree-sitter-graphql', 'tree-sitter-haskell',
    'tree-sitter-ocaml', 'tree-sitter-elixir', 'tree-sitter-dart',
    'tree-sitter-zig', 'tree-sitter-solidity', 'tree-sitter-svelte',
    'tree-sitter-make', 'tree-sitter-cmake', 'pyyaml'
]
for pkg in packages:
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', pkg])
"
```

---

## Testing Your Changes

### Test Hooks Locally (Without Claude Code)

```bash
# Test SessionStart (run from a project directory)
echo '{"session_id":"test","cwd":"'$(pwd)'"}' | \
  CLAUDE_PLUGIN_ROOT="$(pwd)/plugins/repo-cognition" \
  CLAUDE_PROJECT_DIR="$(pwd)" \
  python3 plugins/repo-cognition/hooks/session_start.py

# Test PostToolUse (simulates editing a file)
echo '{"tool_name":"Write","tool_input":{"file_path":"src/test.ts","content":"function hello() {}"}}' | \
  CLAUDE_PLUGIN_ROOT="$(pwd)/plugins/repo-cognition" \
  python3 plugins/repo-cognition/hooks/post_tool_use.py

# Test PreToolUse (simulates a change before execution)
echo '{"tool_name":"Write","tool_input":{"file_path":"src/test.ts","content":"function login() {}"}}' | \
  CLAUDE_PLUGIN_ROOT="$(pwd)/plugins/repo-cognition" \
  python3 plugins/repo-cognition/hooks/pre_tool_use.py
```

### Test Core Modules Individually

```bash
# File indexing
python3 -c "
import sys
sys.path.insert(0, 'plugins/repo-cognition')
from core.manifest import init_db, get_stats
from core.indexer import walk_repository
init_db()
files = walk_repository()
print(f'Found {len(files)} files')
stats = get_stats()
print(stats)
"

# Symbol extraction on a specific file
python3 -c "
import sys
sys.path.insert(0, 'plugins/repo-cognition')
from core.symbols import parse_file
symbols, calls = parse_file('src/example.py', 'python')
print(f'Extracted {len(symbols)} symbols, {len(calls)} calls')
for s in symbols[:5]:
    print(f'  {s[\"kind\"]}: {s[\"name\"]} (line {s[\"start_line\"]})')
"

# Call graph queries
python3 -c "
import sys
sys.path.insert(0, 'plugins/repo-cognition')
from core.call_graph import get_callers, search_symbols, get_hotspots
results = search_symbols('main')
for r in results:
    print(f'{r[\"name\"]} ({r[\"kind\"]}) in {r[\"file\"]}:{r[\"line\"]}')
"

# Domain inference
python3 -c "
import sys
sys.path.insert(0, 'plugins/repo-cognition')
from core.domains import classify_all_files, get_all_domains
counts = classify_all_files()
for domain, count in sorted(counts.items(), key=lambda x: x[1], reverse=True):
    print(f'  {domain}: {count} files')
"

# SimHash normalization
python3 -c "
import sys
sys.path.insert(0, 'plugins/repo-cognition')
from core.similarity import normalize_code
code = '''def calculate_total(items):
    \"\"\"Sum the prices.\"\"\"
    return sum(item.price for item in items)'''
normalized = normalize_code(code)
print(f'Original:   {code.strip()}')
print(f'Normalized: {normalized}')
"
```

### Test the Full Installer

```bash
# Test the Bash installer (uses local clone)
cd plugins/repo-cognition
bash install.sh --project-dir /tmp/test-project --reindex

# Test the PowerShell installer
pwsh -File install.ps1 -ProjectDir /tmp/test-project -Reindex
```

---

## Code Style

### Python

- Follow **PEP 8**
- **Type hints** on all function signatures
- **Docstrings** for public functions (single line is sufficient; describe _why_, not _what_)
- **SQL**: Always use parameterized queries (`?` placeholders, tuple parameters). Never use f-strings, `.format()`, or string concatenation in SQL statements.
- **Regex**: Compile patterns at module level (not inside functions or loops)
- **Paths**: Use `os.path` / `pathlib` throughout — the plugin runs on Windows and Unix
- **Error handling**: try/except with specific exception types. Let unexpected exceptions propagate to the hook runner.
- **Imports**: Standard library first, third-party second, local modules third. No unused imports.
- **Constants**: Define in `core/__init__.py` (INDEX_DIR, DB_PATH, etc.). Never hardcode paths.

### Hook Scripts

- Exit code **0** = allow the operation to proceed (advisory warnings)
- Exit code **2** = block the operation (governance violations, dangerous simulation grades)
- Output format: JSON with `"hookSpecificOutput"` and `"additionalContext"` or `"systemMessage"`
- All hooks must have graceful failure — if they can't run, they exit 0 so the session isn't blocked
- SessionStart: injects context via `additionalContext`
- PreToolUse: outputs warnings or blocks via exit code
- PostToolUse: minimal output (avoids flooding the transcript)

### Markdown (Agents, Commands, Skills)

- **Frontmatter** must include required fields:
  - Agents: `name`, `description`
  - Commands: `description`
  - Skills: `description`, `triggers`
- **Agents**: Second person ("You are an expert...")
- **Skills**: Imperative/infinitive ("To query the index, use...")
- Keep files concise — agents < 200 lines, commands < 100 lines, skills < 150 lines
- Follow existing patterns from the repo

### JSON

- `hooks.json` and `plugin.json`: standard JSON (no comments, no trailing commas)
- 2-space indentation
- Validate with `python -c "import json; json.load(open('...'))"` before committing

### Shell / PowerShell (Installers)

- **Both installers must stay in sync** — any dependency or grammar package added to one must be added to the other
- Use the same step numbering and output format
- Use the same variable naming conventions where possible
- **Test both installers** before submitting a PR

---

## Pull Request Process

1. **Fork** the repository at https://github.com/LongHorizons/WindOH/LessToil
2. **Create** a feature branch: `git checkout -b feature/my-feature`
3. **Implement** your changes following the [Code Style](#code-style) guidelines
4. **Test** your changes using the commands in [Testing Your Changes](#testing-your-changes)
5. **Update both installers** if you added dependencies (grammar packages, Python modules)
6. **Update documentation** if your change affects user-facing behavior (README, ARCHITECTURE, FAQ as applicable)
7. **Submit** a pull request with:
   - Clear description of the change
   - Languages and file counts tested on
   - Before/after examples (for extraction improvements)
   - Any new dependencies added
   - Confirmation that both `install.sh` and `install.ps1` were updated if needed
   - Confirmation that documentation was updated if needed

### PR Review Checklist

**Python Code:**
- [ ] Imports are clean (no unused imports)
- [ ] No hardcoded paths (use constants from `core/__init__.py`)
- [ ] Fallback behavior works without tree-sitter installed (try/except ImportError)
- [ ] Regex patterns compiled at module level (not inside loops or functions)
- [ ] SQL queries use parameterized statements (no f-strings, `.format()`, or concatenation)
- [ ] Type hints on function signatures
- [ ] PEP 8 compliant

**Hook Behavior:**
- [ ] Exit codes correct: 0 = allow, 2 = block
- [ ] PreToolUse: impact/duplicate/confidence warnings exit 0 (advisory only)
- [ ] PreToolUse: governance violations with severity "error" exit 2 (block)
- [ ] PreToolUse: dangerous simulation grades exit 2 (block)
- [ ] PostToolUse: runs quickly (< 2 seconds per file)
- [ ] SessionStart: new modules added with import + call wrapped in try/except
- [ ] Hooks fail open — if the module can't run, exit 0 so the session isn't blocked

**Installers:**
- [ ] Both `install.sh` and `install.ps1` updated if dependencies changed
- [ ] Both installers tested (or at minimum, the one for your platform)
- [ ] Grammar package entries use correct format: `pip-package|import-name`

**Documentation:**
- [ ] README.md updated for user-facing changes
- [ ] ARCHITECTURE.md updated for structural changes
- [ ] FAQ.md updated for new common questions
- [ ] GETTING_STARTED.md updated for workflow changes

---

## Architecture Decision Records

### ADR-001: Python for Hooks
**Date**: 2026-05-22
**Decision**: Use Python for all hook implementations.
**Rationale**: tree-sitter, SQLite, and graph algorithms are infeasible in bash.
**Alternatives**: Shell scripts (no AST parsing, no SQLite), Node.js/Bun (tree-sitter Python bindings more mature).

### ADR-002: SQLite as Canonical Store
**Date**: 2026-05-22
**Decision**: Single SQLite database (WAL mode) for all structured index data.
**Rationale**: JOINs, recursive CTEs, and indexes are essential for call graph traversal and impact analysis.
**Alternatives**: JSON files (no query capability, full in-memory graph required), DuckDB (heavier dependency).

### ADR-003: PreToolUse Advisory vs. Blocking
**Date**: 2026-05-22
**Decision**: PreToolUse blocks only on governance errors and dangerous simulations. Impact analysis, duplicate detection, and confidence warnings are advisory (exit 0).
**Rationale**: Structural concerns like duplication are code quality matters — agents should be informed but not prevented from proceeding. Prototyping and exploration should not be blocked.
**Alternatives**: Block on all warnings (too intrusive), never block (governance has no teeth).

### ADR-004: Hybrid Tree-sitter + Regex
**Date**: 2026-05-22
**Decision**: Tree-sitter as primary extraction (41 grammars), regex as automatic fallback (15 additional patterns).
**Rationale**: Maximizes accuracy when grammars are installed while ensuring the plugin works without them.
**Alternatives**: Tree-sitter only (too fragile, dependency-heavy), regex only (misses nested scopes and complex syntax).

### ADR-005: .local.md for Cross-Session Persistence
**Date**: 2026-05-22
**Decision**: Markdown files with YAML frontmatter for persistent architectural knowledge.
**Rationale**: Follows existing plugin patterns. LLM agents can read and write this format. Human-readable and version-control friendly.
**Alternatives**: Additional SQLite tables (harder for agents to write), JSON files (less human-readable).

### ADR-006: Sparse Checkout for Installation
**Date**: 2026-05-23
**Decision**: Both installers use `git sparse-checkout` with `--filter=blob:none` to fetch only `plugins/repo-cognition/`.
**Rationale**: The monorepo is large. Sparse checkout makes installation fast (< 10 seconds) even on slow connections.
**Alternatives**: Download individual files (fragile, 48+ files), submodule (adds complexity), separate repo (co-developed with monorepo).

### ADR-007: PowerShell Installer
**Date**: 2026-05-23
**Decision**: Native PowerShell installer alongside Bash installer.
**Rationale**: Windows developers deserve a first-class installation experience. The PS1 script handles Windows path conventions and Python detection.
**Alternatives**: WSL-only (excludes native Windows users), Git Bash only (not universally installed).

### ADR-008: Weakest-Link Confidence Aggregation
**Date**: 2026-05-24
**Decision**: Aggregate confidence is the minimum of all four axes (parser, type, runtime, purpose).
**Rationale**: A symbol with excellent parser extraction but zero type information is genuinely low-confidence. The weakest link determines practical reliability.
**Tradeoff**: Can be overly conservative for dynamic languages. Mitigated by the feedback loop gradually improving scores as runtime data is collected.

### ADR-009: Background Indexing with Graceful Degradation
**Date**: 2026-05-24
**Decision**: Fast file walk in foreground (120s budget), symbol extraction time-budgeted (30s), remainder deferred to incremental reindexing. All advanced modules wrapped in try/except.
**Rationale**: Users should never wait for indexing. The dashboard and basic structural data are available immediately. Symbol extraction catches up incrementally. Module failures never block the session.
**Alternatives**: Full blocking index (bad UX for large repos), fully async (no symbols on first session), persistent daemon (complexity, cross-platform issues).

---

## Questions?

Open an issue at https://github.com/LongHorizons/WindOH/LessToil or start a discussion. Contributors of all experience levels are welcome.
