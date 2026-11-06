---
name: rag-on-pgvector
description: Use when building retrieval, embeddings or RAG on Postgres with pgvector, or Claude API tool-use agents that read from Postgres.
---

# RAG on pgvector

1. **Baseline first.** Start with Postgres full-text search. Add vectors only if recall improves on a labelled query set.
2. **Pin the embedding model** and its dimension in a migration. Store `embedding_model` and `embedded_at` on every row.
3. **HNSW tuning.**
   - Set `m` and `ef_construction` explicitly, and `hnsw.ef_search` per query.
   - Measure recall@k against exact search.
4. **Hybrid retrieval.** Combine full-text and vector search with reciprocal-rank fusion. Evaluate that before adding a reranker.
5. **Chunking.** Chunk by document structure, record the chunker version, and keep source IDs for citations.
6. **Tenant isolation** happens in SQL (row filters, RLS), never in the prompt.
7. **Embedding APIs.** Never send raw PAN or PII to one. Run training-data-hygiene on the corpus first.
8. **DB roles.** The agent's DB role is read-only. Migrations go through the normal Go migration tool and review (see postgres-query-review).
9. **Validate outputs.** Check structured outputs against a JSON schema in Go/TS, then retry or fail closed.
10. **Retrieval eval set.** Build 50–200 queries with gold document IDs. Track recall@k and answer faithfulness every release.

Overlaps: postgres-query-review (index and plan review), supabase-postgres-best-practices (pgvector rules); defer to eval-design for the eval set.
