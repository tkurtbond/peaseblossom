# The Oberon-2 reports

Moved here from `AGENTS.md` on 2026-09-27, which keeps a summary: the four
texts of the Oberon-2 report kept locally, how they differ, and why
`Oberon2.pdf` is the one Peaseblossom follows.

Two copies of the Oberon-2 report by H. Mössenböck and N. Wirth are kept
locally under `~/Reference/Computer/Languages/Oberon/`, along with
`pdftotext` extracts (`-layout` preserves columns/tables; `-no-layout` is
plain reading order):

- `Oberon2-Report.pdf` / `Oberon2-Report-{layout,no-layout}.text` — the
  original ETH tech report, dated October 1993 in the body text. Typeset by
  the Oberon system itself; the PDF is a frozen 2015 Ghostscript conversion
  (creation date == mod date, never touched again).
- `Oberon2.pdf` / `Oberon2-{layout,no-layout}.text` — a later revision.
  Authored in WriteNow, first exported to PDF in 2007, and saved again in
  2022 without changing its text (see `Oberon2-norayr.pdf` below).
  Content-wise it refines the 1993 text in several places, all in
  one direction (never reversed):
  - Pointers are stated to initialize to NIL by default (§6.4).
  - Forward declaration / redefinition parameter lists must be "identical",
    not just "match" (§10, §10.2) — a stricter, clearer rule.
  - The `Trees` example module's `Init*(t: Tree)` (initializes a tree the
    caller already allocated; 1993's Appendix D4 browser output
    inconsistently shows it as `Init(VAR t: Tree)`) is replaced by
    `NewTree*(): Tree` (allocating function) — an API redesign, updated
    consistently in both the main example and the D4 browser-output example.
  - The array-compatibility rule (Appendix A) is tightened: `ARRAY OF CHAR`
    parameter matching a string requires the formal to be a **value**
    parameter.
  - `ASSERT` is removed: the 1993 §10.3 table has `ASSERT(x)`,
    `ASSERT(x, n)` and `HALT(n)` (though `ASSERT` is missing from its §4
    list of predeclared identifiers); `Oberon2.pdf` has only `HALT(x)`.
  - The FOR statement (§9.8) is redefined: the equivalence evaluates the
    start value first (`v := low; temp := high`, where 1993 has
    `temp := end; v := beg`), and 1993's "temp has the same type as v"
    becomes: low assignment compatible with v, high expression compatible
    with v, step a nonzero constant "of an integer type".
  - Assorted prose smoothing (e.g. "must be left via a return statement"
    instead of "require the presence of a return statement").

A third text, Appendix A of Mössenböck's *Object-Oriented Programming in
Oberon-2*, 2nd ed. (`oop_in_oberon-2_book.pdf`, book pp. 221-254 = PDF pp.
231-264; OCR'd, so its `oop_in_oberon-2_book-{layout,nolayout}.text`
extracts have character errors), is an intermediate state between the two.
It already has the value-parameter array rule, `HALT(x)`, "must be left
via" and "for a fixed number of times"; it still has 1993's FOR
equivalence, "match" for parameter lists, `Init`, and no NIL-initialization
sentence; and it alone lists `ASSERT` among the predeclared identifiers.
It is background only, like `Oberon2-Report.pdf`.

A fourth copy, `Oberon2-norayr.pdf` / `Oberon2-norayr-{layout,no-layout}.text`,
added on 2026-10-05, is the 2007 export of the same revision, before the
2022 save:

- **Its text is identical to `Oberon2.pdf`'s.** Both `pdftotext` extracts
  match `Oberon2.pdf`'s byte for byte, so everything said above about
  `Oberon2.pdf` against the 1993 report holds for it too.
- **`Oberon2.pdf` is this file with an update appended.** Its first 88296
  bytes, the whole of `Oberon2-norayr.pdf`, are identical. macOS 12.4's
  Quartz PDFContext ("AppendMode 1.1") then added an incremental update on
  2022-07-05. That update rewrites only the 26 page dictionaries, adding a
  `CropBox` and `Rotate 0` to each, and the document information
  dictionary, with the author's name re-encoded and a new producer and
  modification date. It replaces no content stream, so no page's text or
  drawing changed: it is what opening and saving the file in Preview
  produces.
- `pdfinfo` tells them apart: `Oberon2-norayr.pdf` has the producer
  "Acrobat Distiller 8.1.0 (Windows)" and the modification date
  2007-09-18, one minute after its creation date.

It adds no rule and settles no question, so it needs no place of its own
in Peaseblossom's decisions: it confirms that `Oberon2.pdf`'s text is the
2007 revision as published, not something edited in 2022.

**`Oberon2.pdf` is the authoritative spec for Peaseblossom.** Use
`Oberon2-Report.pdf` only as historical background or when explicitly
comparing the two. Neither file carries a printed revision number, so when
in doubt about a specific rule, treat `Oberon2.pdf`'s wording as
controlling and check the PDF metadata (`pdfinfo`) if provenance matters
again.
