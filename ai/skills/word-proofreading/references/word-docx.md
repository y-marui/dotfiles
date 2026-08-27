# Word and DOCX workflow

Use this workflow only for `.docx` or an active Microsoft Word document.

## Choose the safest editing route

Use the first available route that can preserve reviewability:

1. Prefer an official Microsoft Word MCP or an Office.js-backed Word session
   only when it explicitly supports Track Changes, comments, and preservation
   of existing revisions. Do not infer these capabilities merely because a
   Word connection exists.
2. Otherwise, when local DOCX tooling is available, use the installed
   document-artifact workflow and its OOXML tracked-replacement and comment
   helpers. Produce a new sibling `.docx`; this is local file redlining, not a
   live official Microsoft Word connection.
3. If neither route can represent every intended edit safely, do not overwrite
   the source or silently produce an untracked final version. Leave the source
   unchanged, explain the limitation, and provide proposed edits or a review
   report. Create a clean rewritten copy only if the user explicitly asks for
   that fallback.

## Preserve the source and review state

- Work from a copy and keep the original untouched. Unless the user specifies
  another destination, save a sibling file beside the source and name it
  `<stem>-proofread-<mode>-<YYYYMMDDHHMM>.docx`, using the local timestamp at
  creation time. Never overwrite the source.
- Before editing, inventory existing comments, tracked insertions/deletions,
  fields, equations, citations, footnotes/endnotes, content controls,
  hyperlinks, bookmarks, cross-references, protected sections, and embedded
  objects.
- Never accept, reject, resolve, delete, flatten, or rewrite existing comments
  and revisions. Preserve their authorship and metadata.
- Do not reconstruct whole paragraphs when a small tracked replacement is
  sufficient. Preserve styles, run formatting, links, fields, bookmarks, and
  document structure.
- Compute the smallest safe text span for each correction and apply Track
  Changes only to that span. For example, correcting `機動角運動量` to
  `軌道角運動量` must record only `機動` as deleted and `軌道` as inserted;
  it must not mark the entire sentence or paragraph as replaced. When several
  separated corrections occur in one paragraph, keep them as separate minimal
  revisions. If a minimal replacement would cross incompatible runs or a
  protected anchor and cannot be represented safely, leave it unchanged and
  add a comment or issue note instead of expanding the replacement scope.
- Treat complex fields, equations, bibliography objects, content controls, and
  text spanning incompatible runs as protected when a safe tracked edit cannot
  be guaranteed. Add a comment or report the issue instead.

## Record the proofreading

- Record every body-text modification as a real Word revision: tracked
  insertion/deletion through the official interface, or equivalent OOXML
  `<w:ins>` and `<w:del>` markup in the copied file.
- Add author-review issues as anchored Word comments. If a tool requires a
  comment author, use `Codex Proofreading` rather than impersonating the user
  or an existing reviewer.
- Use comments, not untracked body edits, for scientific concerns, claim
  changes, missing evidence, major reordering, and ambiguous interpretations.
- Preserve the selected proofreading mode: `Light` must not accumulate
  optional style edits; `Deep` must not turn content concerns into rewritten
  assertions.

## Verify before delivery

Follow the installed document-artifact render-and-inspect workflow. Also verify
all of the following:

- the output opens and renders without corruption or unexpected layout shifts;
- all new text edits appear as Track Changes and can be accepted or rejected in
  Word's Review interface;
- pre-existing revisions and comments remain present and unchanged;
- new comments are anchored to the intended passages;
- protected numbers, equations, citations, terminology, cross-references, and
  bibliography content match the source;
- the original file has not changed.

If any check cannot be completed, state that specific limitation rather than
claiming full Track Changes compatibility.

## Delivery report

Tell the user:

- the output filename;
- the proofreading mode;
- whether the route was official live Word/Office.js, local DOCX OOXML
  redlining, or review-only fallback;
- whether existing comments and revisions were preserved;
- any passages left unchanged because safe tracked editing was not possible.
