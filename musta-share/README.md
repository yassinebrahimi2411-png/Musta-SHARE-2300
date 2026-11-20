# Musta-SHARE | مستشار

Regulatory assistant for Algerian Decree **1275** (27/09/2022) as amended by Decree **008** (23/02/2025) — startup / economic-project / patent graduation pathways. House of AI, Université Badji Mokhtar – Annaba (UBMA).

## Files
| File | Purpose |
|---|---|
| `index.html` | Live demo: trilingual (EN/FR/AR, RTL), light/dark, cited answers, `.txt/.md` upload. |
| `knowledge-base.md` | The 35 passages the assistant answers from (official texts + public sources: NESDA, ASF, CATI, CDE, INAPI, startup.dz). |
| `api/chat.js`, `server.js`, `package.json`, `.env.example` | Live-AI backend (keeps the API key server-side). |
| `schema.sql` | Supabase schema: pgvector, hybrid search, Row Level Security. |

## Keep the live AI after hosting (outside claude.ai)
`index.html` talks to `/api/chat` when claude.ai is not present. That endpoint (`api/chat.js`) holds your Anthropic API key on the server; the key never reaches the browser.

**Vercel (recommended):** upload this folder as a project → Settings → Environment Variables → add `ANTHROPIC_API_KEY` (optional: `MODEL`, `ALLOWED_ORIGIN`, `RATE_LIMIT`) → Deploy. The page shows the green **LIVE AI** badge when the endpoint is reachable.

**Any server / VPS / Render:** `ANTHROPIC_API_KEY=sk-ant-... node server.js` (Node 18+, no dependencies).

Cost and safety: default model is `claude-haiku-5-5` (cheap); each question sends the whole knowledge base (~4k tokens). The endpoint limits request size and rate per IP, and restricts the assistant to the Decree 1275 domain. Set a monthly spend limit on your API key. Without the key, the page still works in keyword-search mode.

## Run the demo anywhere
`index.html` is self-contained. Without an AI backend it answers by keyword retrieval; inside claude.ai it runs in **LIVE AI** mode (the model reads the whole knowledge base, understands typos, dialect and mixed languages, remembers the last turns, cites sources and proposes follow-up questions). Host it on Vercel/Netlify/GitHub Pages by uploading the file.

## Production path (Next.js + Supabase)
1. Create a Supabase project, run `schema.sql` in the SQL editor.
2. Create a private Storage bucket `documents`.
3. Ingest the official PDFs (Decrees 1275/008, CNCSIIU mechanisms, INAPI guide) with PyMuPDF (+ Tesseract for scans): chunk by article/paragraph, embed (1024-dim), insert with `is_official = true` using the service-role key.
4. Next.js route `/api/chat`: embed question → `rpc('match_chunks')` → send top chunks to your LLM with the rules below → return answer + `message_sources`.
5. Deploy to Vercel; set `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, LLM/embedding API keys.

## Guardrail prompt
1. Answer only from retrieved texts. 2. If absent, say the detail is not covered and refer to the incubator / CATI office. 3. Cite decree article, document and page. 4. Reply in the user's language.

## Notes
- The amending decree is numbered **008** in the official PDF (the earlier brief said 003).
- Knowledge entries are summaries: verify against the official texts.
