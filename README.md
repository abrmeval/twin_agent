# Twin Agent

An AI-powered **digital twin** that represents a real person on their personal website. Visitors (recruiters, potential clients, collaborators) chat with the twin to learn about the person's career, background, skills, and experience. The twin answers only from the owner's LinkedIn profile and a short summary, stays in character, and can capture leads by pushing notifications when someone wants to get in touch.

## Table of Contents
- [Overview](#overview)
- [How It Works](#how-it-works)
- [Features](#features)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Environment Variables](#environment-variables)
- [Running Locally](#running-locally)
- [Running with Docker](#running-with-docker)
- [Deployment](#deployment)
- [Customizing the Twin](#customizing-the-twin)
- [References](#references)

## Overview

Twin Agent is a conversational AI web app that acts as a digital representative of a professional. It is grounded strictly in two sources of truth about the person it represents:

1. A LinkedIn profile exported as a PDF (`info/profile.pdf`)
2. A short text summary (`info/summary.txt`)

The twin never invents answers outside that context, always discloses that it is an AI digital twin, and routes interested visitors to a lead-capture tool that sends a push notification to the owner.

## How It Works

```
Visitor message
      │
      ▼
 Gradio chat loop  ────────────────────────────────────────────
      │
      ▼
 Digital Twin agent (Groq · gpt-oss-120b)
   ├─ calls tools?  ─── yes ──► AiTools.record_user_details / record_unknown_question
      │                               │
      │                               └─► Pushover notification to owner
      │
      └─ no tools ──► UserMessageValidator (Groq)
                        │
                        └─ recruiter-style question?
                              yes ──► TwinResponseReviewer (Azure Foundry · gpt-5-nano)
                                        │
                                        ├─ is_ok: true  ──► return response
                                        └─ is_ok: false ──► feed suggestions back, re-prompt
```

The twin is grounded by a system prompt built at startup from the PDF profile and text summary. Two auxiliary agents guard quality:

- **User Message Validator** — Decides whether a message is recruiter-relevant before spending tokens on a full review.
- **Twin Response Reviewer** — Scores the twin's reply against persona rules (discloses it is a twin, shows interest, states knowledge limits) and returns `{ "is_ok": bool, "suggestions": "..." }`. If `is_ok` is false, the suggestions are fed back to the twin for a corrected response.

## Features

- Persona-grounded chat strictly limited to the owner's profile and summary
- Automatic disclosure that the twin is an AI representative
- Lead capture: records visitor email/name/notes and pushes a Pushover notification
- Unanswered-question logging for follow-up insight
- Dual-agent quality review pipeline (validator + response reviewer)
- Multi-provider credentials via the OpenAI SDK (Groq, OpenRouter, Azure Foundry)
- Custom Gradio dark/light theme with gold/blue/purple accent palette
- Example prompts and auto-focus input for a polished UX
- Containerized with Docker; CI builds to GHCR and deploys to Render

## Tech Stack

| Layer        | Technology                                             |
|--------------|--------------------------------------------------------|
| Language     | Python 3.12                                            |
| Web UI       | Gradio                                                 |
| LLM access   | OpenAI SDK (OpenAI-compatible endpoints)               |
| Providers    | Groq (`gpt-oss-120b`), Azure Foundry (`gpt-5-nano`), OpenRouter |
| Profile input| PyPDF (reads `info/profile.pdf`)                       |
| Notifications| Requests + Pushover API                                |
| Config       | python-dotenv                                          |
| Packaging    | `pyproject.toml` + `requirements.txt`                  |
| Container    | Docker (python:3.12-slim)                              |
| CI/CD        | GitHub Actions -> GHCR -> Render deploy hook           |

## Project Structure

```
twin_agent/
├── .github/
│   └── workflows/
│       └── dev.yml            # Build/push to GHCR + Render deploy
├── info/
│   ├── profile.pdf            # LinkedIn export (grounding source #1)
│   └── summary.txt            # Short bio (grounding source #2)
├── src/
│   ├── agentic/
│   │   ├── agents.py          # TwinResponseReviewer, UserMessageValidator
│   │   └── context.py         # Reviewer/validator system prompts
│   ├── context.py             # Builds system prompt from profile + summary
│   ├── digital_twin.py        # Core persona agent (Groq)
│   ├── main.py                # Gradio app + chat orchestration loop
│   ├── notifications.py       # Pushover notification client
│   ├── providers.py            # Multi-provider credential router
│   ├── requirements.txt
│   ├── styles.py              # Gradio theme CSS, JS, example prompts
│   └── tools.py                # Function tools (lead capture, question log)
├── .env.example
├── .gitignore
├── Dockerfile
└── README.md
```

## Prerequisites

- Python >= 3.12
- A Groq account with an API key (primary twin + message validator)
- An Azure Foundry endpoint and key for the response reviewer model (`gpt-5-nano`)
- A Pushover account (user + token) to receive lead and unanswered-question notifications
- (Optional) An OpenRouter API key if you want to use that provider
- Docker (for containerized runs)

## Getting Started

1. Clone the repository:

   ```bash
   git clone https://github.com/<owner>/twin_agent.git
   cd twin_agent
   ```

2. Copy the environment template and fill in your secrets:

   ```bash
   cp .env.example .env
   ```

   Then edit `.env` with your provider keys and Pushover credentials.

3. Install dependencies (from the `src/` directory):

   ```bash
   cd src
   pip install -r requirements.txt
   ```

## Environment Variables

All variables are defined in `.env.example`:

| Variable                  | Description                                       | Required for            |
|---------------------------|---------------------------------------------------|-------------------------|
| `GROQ_ENDPOINT`           | Groq OpenAI-compatible endpoint                   | Twin + validator        |
| `GROQ_API_KEY`            | Groq API key                                      | Twin + validator        |
| `AZURE_FOUNDRY_ENDPOINT`  | Azure Foundry endpoint                            | Response reviewer       |
| `AZURE_FOUNDRY_API_KEY`   | Azure Foundry API key                             | Response reviewer       |
| `OPENROUTER_ENDPOINT`     | OpenRouter endpoint (optional alternative)        | Optional                |
| `OPENROUTER_API_KEY`      | OpenRouter API key (optional alternative)         | Optional                |
| `PUSHOVER_USER`           | Pushover user key                                 | Lead notifications      |
| `PUSHOVER_TOKEN`          | Pushover app token                                | Lead notifications      |

> The Pushover user key should start with `u` and the token with `a`; the app logs a validation hint on startup.

## Running Locally

From the `src/` directory:

```bash
python main.py
```

The Gradio web UI launches at `http://localhost:7860` with the title **Digital Twin** and the description *"Talk to my AI twin about my career"*.

## Running with Docker

Build and run the image (matching the Render deployment configuration):

```bash
docker build -t twin-agent .
docker run --env-file .env -p 7860:7860 twin-agent
```

The container binds `0.0.0.0:7860` (via `GRADIO_SERVER_NAME=0.0.0.0` in the Dockerfile) so the port can be discovered by Render's dynamic `$PORT`.

## Deployment

Deployment is automated through `.github/workflows/dev.yml`:

1. On push to `main`, GitHub Actions builds the Docker image and pushes it to GHCR (`ghcr.io/<owner>/digital-twin:latest` and a commit-SHA tag).
2. The workflow syncs environment variables to the Render service via the Render API.
3. A deploy hook is triggered to pull the new image and restart the Render web service.

Required GitHub repository secrets for the workflow:

- `RENDER_SERVICE_ID`, `RENDER_API_KEY`, `RENDER_DEPLOY_HOOK`
- The same provider/Pushover variables listed in [Environment Variables](#environment-variables)

## Customizing the Twin

The twin's persona is driven by the contents of the `info/` directory, so no code changes are required to make it represent a different person:

- **Replace** `info/profile.pdf` with that person's LinkedIn export PDF.
- **Edit** `info/summary.txt` to describe the person in a few lines.
- The system prompt in `src/context.py` (`get_system_prompt`) is automatically rebuilt from these two sources the next time the app starts.

To change the visual identity, edit the palette constants (`GOLD`, `BLUE`, `PURPLE`) and the CSS variables in `src/styles.py`. To change the example prompts shown in the UI, edit the `EXAMPLES` list in the same file.

## References

- [Gradio documentation](https://www.gradio.app/docs)
- [OpenAI Python SDK](https://github.com/openai/openai-python)
- [Groq API](https://console.groq.com/docs)
- [Azure AI Foundry](https://learn.microsoft.com/azure/ai-foundry/)
- [PyPDF](https://pypdf.readthedocs.io/)
- [Pushover API](https://pushover.net/api)
- [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [Render deploy hooks](https://render.com/docs/deploy-hooks)

*Last Updated: 12 Aug 2026*