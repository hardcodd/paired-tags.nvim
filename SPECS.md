# Paired Tags Specification

## Purpose and scope

`paired-tags.nvim` provides automatic markup closing, synchronized paired-tag
renaming, and an HTML Enter action. It extracts the behavior currently used by
Alex's Neovim configuration without depending on that configuration's Lua
modules. The public plugin must be usable through `require("paired_tags").setup()`
and through a `lazy.nvim` plugin specification.

The first release supports `html`, `htmldjango`, `xml`, `javascriptreact`,
`typescriptreact`, `vue`, `svelte`, and embedded markup in `markdown`. A working
Tree-sitter parser for the current language is required for tag completion and
rename. No parser installation or external Lua dependency is performed by the
plugin. PHP is out of scope for this release.

## Behavior

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
- In `html` and `htmldjango`, one Enter between adjacent matching tags such as
  `<div>|</div>` creates an indented content line and places the closer at the
  opening tag's indent. Use the buffer's effective indentation options,
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
- `setup()` registers the required callbacks and default Insert mappings for
  `>` and `<CR>`. Repeating `setup()` must not stack paste wrappers, duplicate
  autocommands, or change the plugin's observable behavior. It must not depend
  on `functions.*` modules or this user's configuration. Keep both mappings
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
- Maintain a roadmap that explicitly includes PHP support and **paired-tag
  highlighting**. Do not describe roadmap features as implemented.

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
