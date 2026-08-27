---
name: word-proofreading
description: Proofread multilingual text or Microsoft Word (.docx) documents for research, academic, business, and general use with paragraph-level language and locale detection, minimal meaning-preserving edits, Light/Standard/Deep modes, detailed Japanese and English guidance, and Word tracked-change safeguards. Use for proofreading or copyediting; do not use for translation or substantive changes to facts, scientific claims, or argument conclusions.
---

# Word Proofreading

Proofread single-language or multilingual material while preserving the
author's meaning and technical intent. Prefer the smallest edit that clearly
improves correctness or readability.

## Select the mode

Use the mode named by the user. If none is specified, use `Standard` and say so
briefly in the result.

- `Light`: Correct typos, grammar, punctuation, and only clearly awkward
  phrasing. Do not make optional stylistic rewrites.
- `Standard`: Apply Light corrections plus improvements to clarity,
  concision, natural phrasing, and terminology consistency. This is the
  default.
- `Deep`: Apply Standard corrections and also review logical connections,
  ambiguity, paragraph organization, academic style, and likely reader
  misunderstandings. Treat issues that require a change in meaning,
  reasoning, evidence, or structure as comments rather than edits.

## Detect language and conventions

- Detect the language of each paragraph or list item independently. In a mixed
  paragraph, treat each sentence or phrase according to its language while
  preserving intentional code-switching.
- Apply the grammar, orthography, punctuation, register, script, and regional
  convention of the detected language. Do not translate material into another
  language unless the user separately requests translation.
- Preserve the original Japanese register (`です・ます` or `である`) and make
  it internally consistent unless the user requests a different register.
- Preserve American or British English according to the document's dominant
  existing convention. When there is no clear signal, avoid changing words
  solely to impose one variety.
- For other languages, preserve the document's dominant regional variety and
  formality level rather than imposing a default variety.
- Preserve the document's established terminology and discipline-specific
  style unless it is demonstrably inconsistent.
- If language or locale detection is uncertain, or reliable proofreading in a
  detected language cannot be assured, leave the affected text unchanged and
  identify the limitation instead of guessing.

## Protect meaning and document anchors

Do not silently change any of the following:

- meaning, claim strength, conclusions, causal or correlational relationships,
  scope, certainty, or scientific interpretation;
- numbers, signs, units, ranges, statistical notation, equations, variable
  names, chemical formulas, or code;
- quotations, citations, URLs, identifiers, figure/table/equation references,
  footnotes, endnotes, bibliography entries, or reference ordering;
- proper nouns, product names, organization names, abbreviations, or technical
  terms, except to fix an unmistakable typo or an unambiguous inconsistency;
- existing comments, tracked revisions, or review decisions.

Before editing, identify protected spans and the document's conventions. After
editing, compare protected content against the source. If a correction could
change meaning or requires subject-matter judgment, leave the text unchanged
and add a comment or issue note.

## Japanese review

Correct, as allowed by the selected mode:

- 誤字脱字、助詞、係り受け、主語述語の対応、句読点;
- 表記ゆれ、冗長表現、重複、曖昧または不自然な論理接続;
- 不自然な直訳調、機械的な定型句、過度に均質なAI調の表現。

Keep specialized writing appropriately technical. Do not over-simplify
research, academic, legal, or professional language merely to make it sound
more conversational.

## English review

Correct, as allowed by the selected mode:

- grammar, syntax, articles, prepositions, tense, subject-verb agreement,
  number agreement, and punctuation;
- word choice, collocation, concision, academic tone, and terminology
  consistency;
- unnecessary nominalization, redundancy, and awkward phrasing when the
  improvement is clear and meaning-preserving.

Avoid strong paraphrases that could alter scientific meaning, emphasis,
modality, or claim strength.

## Other-language review

For languages other than Japanese and English:

- correct language-specific grammar, agreement, inflection, word order,
  spelling, diacritics, punctuation, collocation, redundancy, and register as
  allowed by the selected mode;
- preserve the original script, regional variety, technical vocabulary, and
  established style;
- avoid calquing Japanese or English preferences onto the language;
- use the same meaning, claim-strength, citation, number, and terminology
  protections defined above.

## Handle comments and uncertain issues

- Do not edit factual, scientific, methodological, or logical concerns into
  the author's prose.
- Anchor each comment to a specific passage or location. State the concern
  briefly and distinguish a definite language error from a possible content
  issue.
- In `Deep` mode, comment on ambiguous references, unsupported transitions,
  paragraph-order concerns, and plausible reader misinterpretations without
  inventing facts or evidence.
- Do not create a comment for every minor edit. Reserve comments for decisions
  the author should review.

## Produce the result

For pasted text or plain-text files:

1. Return the corrected text first, preserving paragraph and list structure.
2. Add a concise `Comments / 指摘` section only when author decisions or
   content concerns remain.
3. Show a detailed change list or side-by-side comparison only if the user asks
   for it.

For `.docx` or Word documents, read
[references/word-docx.md](references/word-docx.md) before editing. Use a safe
tracked-change and comment workflow when available, preserve the original, and
follow the installed document-artifact instructions for rendering and
verification.

At delivery, state the mode used and any unresolved limitations. For Word
documents, also state whether revisions are genuine Word Track Changes, which
editing route was used, and whether existing revisions and comments were
preserved.
