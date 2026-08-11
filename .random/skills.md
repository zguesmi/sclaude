# Working principles

## Prefer existing, battle-tested solutions over custom ones

Before writing any non-trivial piece of infrastructure — migration runners,
retry/backoff, connection pooling, config loading, (de)serialization, CLI
parsing, schedulers, caching, etc. — STOP and check whether a standard crate or
tool already solves it, especially one already in the dependency tree.

### The rule

1. **Search first.** For any "plumbing" task, name the 2–3 established
   crates/tools that do it and what they give for free (correctness, edge
   cases, maintenance) before writing code.
2. **Default to what's already in `Cargo.toml`.** This repo already depends on
   `sqlx`, `tokio`, `serde`, `validator`, `config`, `thiserror`, `reqwest`,
   `humantime-serde`. Use their built-in facilities before adding a new dep or
   hand-rolling one.
3. **Challenge requirements that lead to reinvention.** If a request implies
   building custom infra (e.g. "a custom version table for migrations"), push
   back: name the existing tool, say what it already handles, and quantify how
   much is *genuinely* custom (usually a thin wrapper). Build only that delta.
4. **Only hand-roll when justified,** and say why: no suitable crate exists, the
   dependency is disproportionately heavy for the need, or a hard constraint
   rules it out.
5. **Propose before building.** A one-line "crate X already does this; I'd wrap
   it and add only Y — ok?" beats a large custom implementation the user then
   has to unwind.

### What "challenge" looks like

- ❌ Silently implement the literal spec.
- ✅ "You asked for a custom migration version table + confirmation prompt.
  `sqlx::migrate!` already does version tracking, an advisory lock, checksums,
  and transactional apply. The only genuinely custom part is the prompt
  (~20 lines). I'd wrap sqlx and add just that — ok?"

### Why this exists

The first migration runner was hand-rolled: it reimplemented version tracking,
advisory locking, compile-time file discovery, and transaction handling that
`sqlx::migrate!` already provides — with more surface area for bugs (a
duplicate-version gap was found in review) and no migration checksums. It was
avoidable, and `sqlx::migrate!` had already been recommended before it was
built. Don't repeat that.
