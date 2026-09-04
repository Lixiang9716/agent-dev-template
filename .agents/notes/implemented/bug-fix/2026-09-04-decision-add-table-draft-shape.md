# Agent Note: `decision add` table-format draft shape — help and validator now agree (issue #132)

Status: implemented
Related: D40, D32

## Problem

First-hand from radiant's M3 tail batch: `gov decision add --help`
described the draft file as "first line the title, the rest the body",
demoting the table shape to a parenthetical afterthought — while the
validator for `table`-format sources refuses any non-row line
(`table drafts are table rows; this line is not: …`), quoting the line
but showing no valid example. An agent working in a table-format repo
followed the help's primary clause, wrote a title+body draft, and hit a
refusal that gave it nothing to fix the draft WITH. Help and validator
could not both be read as correct; the first attempt of the exact
audience the command was built for (D40's parallel-branch agents) was
the failure mode.

## Decision

- The `--from` help is now format-aware: in a repo whose
  `.gov/decisions.json` configures `table`, `gov decision add --help`
  says "table-row lines ONLY — first cell Dn or '?', one row per
  decision; not title+body"; in sections/dir repos it says "first line
  the title, the rest the body". The help you read is the shape the
  validator enforces for YOUR repo.
- The non-row refusal quotes the offending line (as before) AND now
  shows a minimal valid row modeled on the table's own header, e.g.
  `| ? | <title> | <alternatives> |` — an example that fits THIS
  table's columns, not a generic one.
- An empty table draft fails loud ("wants row lines") instead of
  rewriting the file to append nothing silently (rules 5).

## Alternatives considered

- **Accept title+body for table format and wrap it into a row** —
  rejected: the columns are adopter-defined (the header lives in the
  adopter's file), so auto-wrapping must guess which column the title
  belongs in and must discard the multi-line body; fabricating
  structured rows from unstructured text is silent guessing, against
  rules 5. The honest contract is: the tool says the shape, the draft
  matches it.
- **One static help listing both shapes** — rejected as weaker: the
  reported failure was an agent reading the wrong shape as primary for
  its repo; a static both-shapes string still makes the reader resolve
  which clause applies. Format-aware help removes the resolution step.
  (Cost: `--help` reads `.gov/decisions.json` from cwd — `main()` has
  no git-root anchor before `parse_args`, so help from a subdirectory
  of a table repo can show the sections wording; the refusal, which
  does anchor, remains the authoritative teacher there.)

## Consequences

Refusal messages grow one example line; tests pin the exact-line quote,
the header-derived example, the empty-draft refusal, and both help
wordings. Adopters that scripted against the old refusal text (regex on
`this line is not`) still match — that clause is unchanged; only an
example line was added after it.
