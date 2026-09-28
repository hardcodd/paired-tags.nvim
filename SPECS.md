# Paired Tags Specification

## Purpose and scope

`paired-tags.nvim` provides automatic markup closing, synchronized paired-tag
renaming, matching-tag highlighting, and an HTML Enter action. It extracts
the behavior currently used by Alex's Neovim configuration without depending
on that configuration's Lua modules. The public plugin must be usable through
`require("paired_tags").setup()`
and through a `lazy.nvim` plugin specification.

The plugin supports `html`, `htmldjango`, `jinja`, `jinja2`, `xml`,
`javascriptreact`, `typescriptreact`, `vue`, `svelte`, and embedded markup in
`markdown`. A working
Tree-sitter parser for the current language is required for tag completion and
rename. No parser installation or external Lua dependency is performed by the
plugin. PHP is out of scope for this release.

## Behavior

### HTML tags in Django and Jinja templates

- Apply automatic HTML tag closing, paired-name renaming, paired-name
  highlighting, and the adjacent-tag Enter action inside Django HTML and
  Jinja HTML templates. Support the `htmldjango`, `jinja`, and `jinja2`
  filetypes. `jinja` and `jinja2` use the Jinja Tree-sitter parser; HTML
  content uses an injected HTML parser. The plugin supplies the required
  injection queries without installing parsers or adding a Lua dependency.
- Treat `{% ... %}`, `{{ ... }}`, `{# ... #}`, Django `{% comment %}` and
  `{% verbatim %}`, and Jinja `{% raw %}` as template syntax. Never create or
  rename an HTML tag inside those regions, including quoted text that looks
  like markup. HTML tags in literal content on either side of template
  directives retain normal editing behavior.
- Pair HTML tags across template directives only when the parser and lexical
  structure identify one unambiguous mate. Branches may render different
  markup; skip a change rather than alter an unrelated branch or ancestor.
  Preserve template expressions in attributes and multiline opening tags.
- Retain existing behavior for all previously supported filetypes and for
  missing or broken parsers. Keep large-buffer refreshes and rename paths
  bounded as specified below.

### Django and Jinja block pairs

- In `htmldjango`, `jinja`, and `jinja2`, recognize block forms represented
  by the installed language parser. This includes Django `if`, `for`, `block`,
  `autoescape`, `filter`, `with`, `verbatim`, `comment`, `spaceless`,
  `ifchanged`, and `blocktrans`/`blocktranslate`, and Jinja `if`, `for`,
  `block`, `macro`, `call`, `filter`, `set` blocks, `with`, `autoescape`,
  `trans`, and `raw`. Unpaired statements such as `include` and `extends`
  remain untouched. Unknown or custom tags are not inferred from text alone.
- Typing the final `}` of a complete new `{% ... %}` block opener inserts the
  corresponding `{% end... %}` and leaves the cursor between them. Preserve
  an existing, parser-confirmed matching closer. Do not consume an ancestor's
  or another branch's closer, duplicate a closer, or complete an opener in a
  comment, string, raw/verbatim body, or incomplete statement. Support
  nesting and Jinja whitespace-control delimiters (`{%-`, `-%}`).
- Renaming either block keyword updates only its explicit mate, preserving
  arguments, optional block labels, whitespace control, branch statements,
  and unrelated nested blocks. If the edited syntax no longer establishes an
  unambiguous pair, leave other text unchanged. Block labels are not
  automatically renamed.
- Highlight the two paired block keywords while the cursor is on either
  delimiter, using the configured opening and closing groups. Clear stale
  marks on cursor or text changes, buffer switches, and parser failure. One
  active HTML or template pair is highlighted at a time.
- When the cursor is on a parser-recognized branch keyword, highlight that
  keyword and the opening keyword of its own block with the existing closing
  and opening groups. This includes Django `elif`/`else`, `for`/`empty`,
  `ifchanged`/`else`, and `blocktrans`/`blocktranslate` with `plural`, and Jinja
  `elif`/`else` in `if` and `else` in `for`. Resolve nested branches to their nearest owning
  block. Do not change block renaming or highlight a malformed or unrelated
  branch.
- In template filetypes, typing `{%`, `{{`, or `{#` produces `{%  %}`,
  `{{  }}`, or `{#  #}` immediately, with the cursor between the two spaces.
  Reuse an existing closer, including a single `}` inserted by a brace-pairing
  plugin, without leaving an extra brace or duplicating the closer. The result
  must be the same with `nvim-autopairs` enabled before or after this plugin.
  Typing a generated closer advances through it rather than duplicating its
  characters. Completion of a `{% ... %}` statement still inserts its matching
  `end...` block where applicable. Direct typing of Jinja `{%- ... -%}`
  remains possible despite the generated spaces. Literal, raw/verbatim,
  special-buffer, unsupported-filetype, and parser-unavailable input retains
  native behavior.
  Nested template constructs must not consume each other's generated closers.
- Enter between adjacent matching block delimiters creates one content line
  at the effective buffer indent and places the closer at the opener's
  indent. Mismatched, incomplete, or nonadjacent delimiters retain native
  Enter. Expression (`{{ ... }}`) and comment (`{# ... #}`) delimiters do not
  create block statements or receive block-keyword highlighting.

- In supported normal editing buffers, typing `>` after a newly completed
  opening tag adds the matching closer and leaves the cursor between tags.
  Typing `>` in other contexts retains the native character. Preserve an
  existing matching closer; do not generate duplicates for self-closing or
  HTML void elements. Respect quoting, JSX expressions, fragments, nested
  elements, raw-text content, comments, code fences, and incomplete parser
  states according to the imported regression suite.
- When an existing opening or closing tag name changes, update only its actual
  mate. Preserve attributes, surrounding text, other elements, case, and UTF-8
  names. Handle multiline, paste, rapid input, temporarily malformed markup,
  HTML optional end tags, and changes on either side of the pair. If pairing is
  ambiguous, avoid modifying another element.
- In `html`, `htmldjango`, `jinja`, and `jinja2`, one Enter between adjacent
  matching tags such as `<div>|</div>` creates an indented content line and
  places the closer at the opening tag's indent. Use effective indentation,
  including EditorConfig overrides. In other contexts, return native Enter.
- Feature handling is inactive in special buffers and in filetypes outside the
  supported set. Missing or broken parsers must not cause unrelated buffer
  changes or errors.
- Paired-name edits may use a saved match without reparsing the buffer when
  every intervening user edit is confined to that name. Any change outside
  the saved name, a buffer reload, or uncertain tracking must use the existing
  parser-checked behavior. This optimization must preserve synchronized edits
  from either tag, safety in comments and embedded languages, and behavior
  when a parser is unavailable.
- Text edits that cannot affect a tag or its saved match may bypass parsing;
  uncertain input, including multiline opening tags, must retain the existing
  parser-checked behavior.
- When the cursor is on either tag of a complete, explicitly paired element,
  highlight both tag names. Match names using the language's case rules and
  require a real Tree-sitter element pair, including injected HTML. Nested
  elements highlight their own pair. Do not highlight unpaired, malformed,
  mismatched, self-closing, void, or merely inferred closing tags, nor apparent
  markup in comments, strings, raw text, or Markdown code. Clear stale marks
  when the cursor moves away, text changes, the buffer is left or wiped, or a
  parser becomes unavailable. Highlighting never changes buffer text.
- `setup({ highlight = { opening = "...", closing = "..." } })` accepts
  nonempty highlight-group names for each side; omitted names default to
  `PairedTagsOpening` and `PairedTagsClosing`, linked by default to
  `MatchParen`, including after a colorscheme change. Invalid option shapes or
  names raise an error before setup.
  Repeated `setup()` preserves the initial configuration and does not stack
  callbacks or marks.
- Highlight refreshes inspect the cursor's local parser range and direct
  element children, without a whole-buffer lexical scan. Keep at most two
  highlight extmarks per active buffer and avoid redundant mark updates when
  the pair and buffer revision have not changed. Large-buffer checks must
  verify bounded work without a machine-dependent timing threshold.
- `setup()` registers the required callbacks and default Insert mappings for
  `>`, `{`, `%`, `#`, `}`, and `<CR>`. Repeating `setup()` must not stack paste wrappers,
  duplicate autocommands, or change behavior. It must not depend
  on `functions.*` modules or this user's configuration. Keep all mappings
  silent and nonrecursive, matching the source configuration.

## Integration and compatibility

- Keep the existing behavior covered by the source configuration's paired
  editing tests and bug reports 1–4. Move relevant tests into this repository
  so the plugin can be verified independently of the source configuration.
- The source Neovim configuration installs this plugin from the public
  `hardcodd/paired-tags.nvim` GitHub repository through `lazy.nvim`, not from a
  local path. Remove the duplicated tag and HTML Enter implementations from
  that configuration, retaining its unrelated editor features.
- Target the currently verified Neovim 0.12.5 environment and avoid adding
  other dependencies. Preserve the current Lazy and Tree-sitter versions in the
  configuration unless their APIs require a separately approved change.
- Keep repository documentation, comments, identifiers, and API documentation
  in English. `README.md` must explain every shipped feature, prerequisites,
  installation, settings, limitations, and testing commands. Use an MIT license.
- Keep non-ASCII XML tag-name coverage with Greek test data.
- Maintain a roadmap that explicitly includes PHP support. Do not describe
  remaining roadmap features as implemented.

## Acceptance criteria

1. Focused standalone tests pass for automatic closing, matching renames,
   HTML Enter, unsupported buffers, parser absence, and repeated setup.
2. The imported bug-report regression suites and relevant existing paired
   editing tests pass against the standalone plugin.
3. The source Neovim configuration loads the published GitHub plugin through
   Lazy and its affected tests pass after the migration.
4. The English README and roadmap accurately describe the tested release and
   known limitations. The source configuration's knowledge base reflects the
   resulting architecture.
5. Focused tests cover the optimized rename path and its invalidation after
   unrelated edits. On a representative 5,000-line HTML buffer, repeated
   tracked renames should avoid the full-buffer Tree-sitter parse that dominates
   the current rename latency. Compare the resulting timings with the existing
   behavior without imposing a machine-dependent test threshold.
6. Focused highlighting tests cover nested and malformed markup, injections,
   parser absence, cursor and edit invalidation, configuration, repeated setup,
   and a representative 5,000-line document. Existing editing suites still pass.
7. Django and Jinja HTML tests cover the three filetypes, injected HTML across
   statements, expressions in attributes, multiline tags, raw/comment bodies,
   branch ambiguity, rename in both directions, highlighting, Enter, and a
   representative 5,000-line template.
8. Block tests cover parser-recognized forms, nested and existing closers,
   multiline openers, whitespace control, editing either keyword, highlighting,
   Enter, missing parsers, and non-pairing of expressions and comments.
9. Branch tests assert exact extmark positions, groups, and ownership for each
   supported branch form, including deep same-name nesting, multiple branches,
   malformed input, and highlight invalidation.
10. Delimiter tests cover typed and existing closers, block completion after a
    generated `%}`, nested expressions and comments, literal/raw contexts,
    multiline input, unsupported buffers, missing parsers, and repeated setup.

## Repository discovery and presentation

- The GitHub repository description and topics should identify the plugin as a
  Neovim tag-closing and paired-renaming tool, using only implemented languages
  and behavior. They must not advertise roadmap features as available.
- The repository's social preview should be legible at link-preview size,
  identify the plugin and its two core editing actions, and make no unsupported
  compatibility or performance claims.
- The English README should open with a concise description of current
  capabilities, use familiar search terms naturally, and keep installation,
  prerequisites, limitations, and language coverage easy to find.
- Acceptance requires checking the rendered README, verifying that its claims
  match the implementation, and confirming the published repository metadata
  and default-branch contents after publication.
