# Roadmap

This file tracks proposed work; none of the items below is part of the
current release.

1. **Paired-tag highlighting (required).** Highlight the opener and closer of
   the pair under the cursor, with configurable highlight groups and a bounded
   update path for large files. Test nested, malformed, and injected markup.
2. **PHP support.** Define the supported PHP template forms, choose and
   validate the parser(s), and cover boundaries between PHP expressions and
   HTML before enabling `php` filetypes.
3. **Broader language coverage.** Evaluate other template and component
   filetypes against their actual Tree-sitter node shapes and add focused
   regression fixtures before advertising support.
4. **Configuration and compatibility.** Explore opt-in mappings or per-filetype
   controls without changing the safe default behavior or stacking handlers.
5. **Automated performance and compatibility checks.** Add repeatable
   large-document benchmarks to CI and verify supported Neovim and parser
   versions there. Editing performance has already been measured and improved
   on 5,000-line HTML and TSX fixtures locally.
