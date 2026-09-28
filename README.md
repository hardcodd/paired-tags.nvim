# paired-tags.nvim: auto-close, rename, and highlight tags in Neovim

[Русская версия](README.ru.md)

Automatically close markup tags, keep matching names in sync, and highlight
the pair under the cursor while editing in Neovim. The plugin uses Tree-sitter
for HTML, Django and Jinja HTML templates, XML, JSX/TSX, Vue, Svelte, and HTML
embedded in Markdown. It also pairs Django and Jinja block statements and
provides an Enter mapping between adjacent pairs.

![paired-tags.nvim preview with a matching JSX tag pair](assets/social-preview.png)

## Features

| Action | Result |
| --- | --- |
| Type `<section>` | Inserts `</section>` and keeps the cursor between the tags. |
| Rename either name in `<section>...</section>` | Updates its matching name, including when the opening tag has attributes or spans lines. |
| Place the cursor on either tag in `<section>...</section>` | Highlights both tag names. |
| Press Enter at `<section>\|</section>` in HTML | Opens an indented content line and keeps the closing tag at the opener's indent. |
| Type `{%if active%}` in a Django or Jinja HTML template | Produces `{% if active %}{% endif %}`. |
| Rename either keyword in `{% if %}...{% endif %}` | Updates its matching block keyword. |
| Place the cursor on `{% else %}` | Highlights `else` and the `if` or `for` that owns it. |
| Type `{%`, `{{`, or `{#` in a template | Produces `{%  %}`, `{{  }}`, or `{#  #}` with the cursor between the spaces. |

The plugin supports `html`, `htmldjango`, `jinja`, `jinja2`, `xml`,
`javascriptreact`, `typescriptreact`, `vue`, `svelte`, and HTML embedded in
`markdown`. It uses Tree-sitter to identify tags and template blocks; it does
not install parsers. HTML Enter works in `html`, `htmldjango`, `jinja`, and
`jinja2`.

### Automatic tag closing

- Creates a closer after a completed opening tag, including nested tags,
  custom HTML elements, JSX/TSX components, member and namespaced component
  names, and JSX fragments (`<>...</>`).
- Preserves an existing closer. It does not generate one for self-closing tags
  or HTML void elements such as `<br>` and `<img>`. JSX/TSX PascalCase
  components such as `<Input>` remain paired rather than being treated as
  lowercase HTML void elements.
- Handles `>` inside quoted attributes, JSX expressions and generic component
  type arguments without treating it as the end of an opening tag.
- Avoids inserting tags in comparisons, strings, comments, Markdown code, and
  other non-markup text. It leaves an ambiguous parser state unchanged instead
  of consuming a parent's or sibling's existing closer.

### Rename matching tags

- Keeps the matching opener and closer in sync when either name is edited,
  including normal-mode edits, Insert edits, and paste.
- Changes only tag names. Attributes, nested content, neighboring elements,
  and unrelated closing tags stay in place. This covers incomplete edits,
  same-name descendants, temporarily invalid markup, HTML optional end tags,
  raw-text elements, and multiline attributes.
- Preserves JSX component spelling and XML case and UTF-8 names.

### Highlight matching tags

When the cursor is on either tag of an explicitly paired element, the plugin
highlights both names. Nested elements show their own pair. Highlights update
after text changes and clear when the cursor leaves the tag or buffer. The
plugin skips incomplete or mismatched pairs, self-closing and void tags, and
apparent tags in comments, strings, raw text, and Markdown code. Highlighting
does not change buffer text. It uses a local parser update and at most two
extmarks in the active buffer, including in large documents.

### Enter between HTML tags

With the cursor between adjacent matching tags, one `<CR>` creates a content
line and puts the closer at the opening tag's indentation. The content line
uses the buffer's effective `shiftwidth`, `expandtab`, and `tabstop`, so a
project's EditorConfig settings can govern it. A mismatched pair, completion
popup, special buffer, or other filetype keeps normal Enter behavior.

### Django and Jinja HTML templates

HTML tag closing, renaming, highlighting, and Enter work in `htmldjango`,
`jinja`, and `jinja2`. Template statements, expressions, comments, and raw or
verbatim bodies are excluded from HTML edits. If tags cross different template
branches, the plugin avoids treating them as a safe pair.

The same template filetypes support block completion after the final `}`,
paired keyword renaming and highlighting, and Enter indentation between
adjacent matching block delimiters. Supported Django blocks include `if`,
`for`, `block`, `comment`, `verbatim`, `autoescape`, `filter`, `with`,
`spaceless`, `ifchanged`, and `blocktrans`/`blocktranslate`. Supported Jinja
blocks include `if`, `for`, `block`, `macro`, `call`, `filter`, block-form
`set`, `with`, `autoescape`, `trans`, and `raw`. Jinja whitespace-control
delimiters are supported. Unpaired statements such as `include` stay unchanged.
When the cursor is on a branch keyword, the plugin highlights it with its
owning opener: Django `elif`/`else`, `for`/`empty`, `ifchanged`/`else`, and
`blocktrans` or `blocktranslate` with `plural`; Jinja `if`/`elif`/`else` and `for`/`else`. Nested
branches highlight their nearest owner. Renaming remains limited to the
opening and closing block keywords.

Typing `{%`, `{{`, or `{#` inserts the matching delimiter with one space on
each side of the cursor; type the content without adding those spaces. Typing
the generated closing characters advances through them. An existing closer
at the insertion point is preserved. If
`nvim-autopairs` has already inserted a `}`, the plugin replaces that brace
instead of leaving an extra one. Expression and comment
delimiters do not create block statements. Template delimiters typed inside
strings, comments, and raw or verbatim bodies remain literal.

## Requirements

- Neovim 0.12.5 is the tested version. Older versions have not been verified.
- Template tests used `htmldjango` grammar revision `a1031889` and `jinja` /
  `jinja_inline` revision `c213d374`. Other grammar revisions have not been
  verified against these node shapes.
- A working Tree-sitter parser for each language where tag closing or renaming
  is needed: `html`; `htmldjango` and `html` for Django templates; `jinja`,
  `jinja_inline`, and `html` for Jinja templates; `xml`; `javascript` for
  `javascriptreact`, `tsx` for `typescriptreact`, `vue`, `svelte`, and
  `markdown` and `html` for HTML embedded in Markdown. Parser installation is
  managed by your Neovim
  configuration; `nvim-treesitter` may be used for that purpose but is not a
  runtime dependency of this plugin.

When a parser is unavailable, parser-dependent closing, renaming, delimiter
completion, and highlighting leave the buffer alone. HTML Enter does not
require a parser; template block Enter requires one.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "hardcodd/paired-tags.nvim",
  main = "paired_tags",
  opts = {},
  lazy = false,
}
```

With another plugin manager, add the repository to Neovim's runtime path and
call:

```lua
require("paired_tags").setup()
```

`setup()` installs Insert-mode `>`, `{`, `%`, `#`, `-`, `}`, and `<CR>` mappings,
text-change and cursor callbacks, and a paste wrapper used to distinguish
streamed paste from typing.
Calling it again in the same session is harmless. If another plugin also maps
`<CR>`, configure that plugin not to replace this mapping; for example,
`nvim-autopairs` can use `map_cr = false`. The `{` and `}` mappings work with
`nvim-autopairs` loaded before or after this plugin; ordinary brace pairing
continues through its original mappings.

By default, the two highlight groups are `PairedTagsOpening` and
`PairedTagsClosing`; both link to `MatchParen` unless your colorscheme defines
them. To use other existing highlight groups, pass their names on the first
`setup()` call:

```lua
require("paired_tags").setup({
  highlight = { opening = "Search", closing = "Search" },
})
```

Each name can be set independently. Later `setup()` calls preserve the initial
configuration. Invalid option names or empty group names raise an error.

## Limits and roadmap

PHP templates are not supported in this release. Remaining proposed work is
listed in [ROADMAP.md](ROADMAP.md).

The plugin intentionally skips edits when the parser is absent or a pair
cannot be identified safely. It does not auto-install parsers, format a whole
document, or add general punctuation pairing for quotes and brackets.

## Verification

The repository includes standalone tests for setup, highlighting and its
configuration, HTML Enter, paired editing, 56 language scenarios, and three
bug-report suites (35, 62, and 188 cases), plus Django and Jinja
template editing. Run from the repository
root with an installed set of the parsers listed above. `tests/bootstrap.lua`
uses the parsers in Neovim's standard data directory; set
`PAIRED_TAGS_PARSER_RTP` to another complete parser and query runtime path if
necessary. If Jinja parsers are installed separately, append their directory
to `runtimepath` after `tests/bootstrap.lua`.

```sh
nvim --headless -u NONE -i NONE -n \
  '+luafile tests/bootstrap.lua' \
  '+lua local ok, err = pcall(dofile, "tests/setup_spec.lua"); if not ok then print(err); vim.cmd("cquit") end' \
  +qa!

nvim --headless -u NONE -i NONE -n \
  '+luafile tests/bootstrap.lua' \
  '+luafile tests/tag_bug_report_4_spec.lua'

nvim --headless -u NONE -i NONE -n \
  '+lua local ok, err = pcall(dofile, "tests/highlight_config_spec.lua"); if not ok then print(err); vim.cmd("cquit") end' \
  +qa!
```

Replace the test path with `template_html_spec.lua`,
`template_blocks_spec.lua`, `template_branches_spec.lua`,
`template_delimiters_spec.lua`, `html_enter_spec.lua`,
`highlight_spec.lua`, `paired_editing_spec.lua`, `rename_fast_path_spec.lua`,
`tag_scenarios_spec.lua`,
`tag_bug_report_2_spec.lua`, or
`tag_bug_report_3_spec.lua` to run the other suites. Synchronous tests need
the `pcall`/`cquit` wrapper shown above; regression runners exit on their own.
The highlight configuration suite runs without `tests/bootstrap.lua` so it
can call `setup()` with custom options before defaults are registered.
To run the delimiter integration suite in both load orders, replace the path
below with an installed `nvim-autopairs` checkout:

```sh
PAIRED_TAGS_AUTOPAIRS_RTP=/path/to/nvim-autopairs \
  nvim --headless -u NONE -i NONE -n \
  '+luafile tests/bootstrap.lua' \
  '+lua local ok, err = pcall(dofile, "tests/template_delimiter_autopairs_spec.lua"); if not ok then print(err); vim.cmd("cquit") end' \
  +qa!

PAIRED_TAGS_AUTOPAIRS_RTP=/path/to/nvim-autopairs \
  nvim --headless -u NONE -i NONE -n \
  '+lua vim.opt.rtp:append(vim.env.PAIRED_TAGS_AUTOPAIRS_RTP); require("nvim-autopairs").setup({ map_cr = false })' \
  '+luafile tests/bootstrap.lua' \
  '+lua local ok, err = pcall(dofile, "tests/template_delimiter_autopairs_spec.lua"); if not ok then print(err); vim.cmd("cquit") end' \
  +qa!
```

The integration suite was run with `nvim-autopairs` 0.10.0 at `23320e7`.
The contract and acceptance criteria are in [SPECS.md](SPECS.md).

## License

[MIT](LICENSE).
