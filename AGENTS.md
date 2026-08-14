# AGENTS.md

Repo-specific guidance for OpenCode agents working in `twin_agent`.
Keep this short and high-signal; see the README for full project background.

## Working directory

- The app runs from `src/`, **not the repo root**. `src/main.py` uses bare top-level imports (`import context as context`, `from digital_twin import DigitalTwin`, `from providers import AiProvider`) that only resolve when `src/` is on `sys.path` (i.e. CWD = `src/`).
- `src/context.py` resolves `info/profile.pdf` and `info/summary.txt` relative to `__file__` (`../info/`), so those load correctly regardless of CWD — but everything else still requires CWD = `src/`.

## Toolchain

- This is a **uv** project, despite the README mentioning only pip. `src/` contains `pyproject.toml`, `uv.lock`, `.python-version` (`3.12`), and a local `.venv`.
- Install: `cd src; uv sync` (preferred). `pip install -r requirements.txt` also works as a fallback.
- Run: `cd src; uv run python main.py` (or `python main.py` inside an activated `src/.venv`). Gradio starts on `http://localhost:7860`.
- Containerized: `docker build -t twin-agent . && docker run --env-file .env -p 7860:7860 twin-agent` (run from repo root; the Dockerfile copies `src/` to `/app` and `info/` to `/info/`).

## Verification

- There is **no test suite, lint config, typecheck, or formatter** in this repo. Do not invent `pytest`/`ruff`/`mypy` commands. If asked to "run tests", say there are none unless you add them.
- The only end-to-end check is launching the Gradio app and chatting through the UI; it requires real Groq + Azure Foundry + Pushover credentials in `.env`.

## Environment

- `.env` lives at the **repo root** and is gitignored. Copy from `.env.example`.
- `load_dotenv(override=True)` is called separately in `src/providers.py` and `src/notifications.py` (not centralized). `python-dotenv` walks up from CWD, so running from `src/` finds the repo-root `.env`.
- **Dependency gotcha:** `requirements.txt` and `pyproject.toml` declare `dotenv>=0.9.9`, but the code imports `from dotenv import load_dotenv`, which is the API of `python-dotenv` (a different package). `uv.lock` is the authoritative resolution; if dependencies are re-pinned, the correct package name is `python-dotenv`, not `dotenv`.
- `OPENCOODE_API_KEY` in `.env.example` (note the typo) is **not referenced anywhere in code**. Treat it as vestigial; do not wire it into `providers.py` without confirming intent.

## Architecture (multi-agent flow)

Three agents are constructed in `src/main.py` at startup and share a single `AiProvider` (`src/providers.py`) that routes credentials by string key:

| Agent | File | Provider key | Model |
|---|---|---|---|
| `DigitalTwin` (persona) | `src/digital_twin.py` | `"groq"` | `openai/gpt-oss-120b` |
| `UserMessageValidator` | `src/agentic/agents.py` | `"groq"` | `openai/gpt-oss-120b` |
| `TwinResponseReviewer` | `src/agentic/agents.py` | `"foundry"` | `gpt-5-nano` |

- Model names are **hardcoded in each class** (`digital_twin.py:17`, `agents.py:18`, `agents.py:40`), not env-driven. Changing a model = a code edit.
- OpenRouter is registered in `providers.py` but **no agent uses it** today.
- `AiProvider.get_provider_credentials(name)` returns `(False, "", "")` when a provider's endpoint or key is missing — agents raise `Exception("Provider not found")` on init, so missing creds crash the app at startup, not lazily.

## Chat loop and known issues

- `src/main.py` `chat()` loop: twin is called → if `finish_reason == "tool_calls"`, tools run (`tools.py`) and the loop continues; otherwise the validator decides whether the message is recruiter-relevant, and if so the response reviewer scores it. `is_ok == false` feeds `suggestions` back and re-prompts.
- **Reviewer/validator output must be valid JSON.** Both parse the model's `message.content` with `json.loads` (`agents.py:23`, `agents.py:44`) into specific fields (`is_ok`/`suggestions`, `review_twin_response`). Any non-JSON or missing-field output will throw. If you touch prompts in `src/agentic/context.py`, preserve the JSON contract and keyed examples.
- **Known bug in the feedback path:** `main.py:58-66` appends a *list* (`[{...}]`) to `messages` instead of a single message dict. The OpenAI SDK expects each `messages` entry to be a dict, so a failed review that triggers re-prompt will break the next `prompt_agent` call. Fix this when editing the loop rather than preserving it.

## Persona / grounding

- The twin is grounded only by `info/profile.pdf` and `info/summary.txt`, assembled into the system prompt in `src/context.py:get_system_prompt`. To repoint the persona to a different person, replace those two files — no code change needed.
- Styles/example prompts/accents live in `src/styles.py` (`GOLD`, `BLUE`, `PURPLE`, `CSS`, `JS`, `EXAMPLES`).

## CI / deployment

- Pushing to `main` triggers `.github/workflows/dev.yml`: build Docker image → push to `ghcr.io/<owner>/digital-twin:latest` (+ commit SHA tag) → PUT env vars to Render via Render API → POST deploy hook.
- There is no PR-gating, no matrix, no test step in CI. Branch/PR conventions beyond "push to main deploys" are not defined in the repo.
- Gradio must bind `0.0.0.0` for Render's dynamic `$PORT` — handled by `GRADIO_SERVER_NAME=0.0.0.0` in the Dockerfile; don't rebind to `127.0.0.1` in code or the deploy will fail health checks.