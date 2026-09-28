# Roadmap

This file tracks proposed work; none of the items below is part of the
current release. Django and Jinja HTML templates and their block pairs are
documented as current behavior in [README.md](README.md).

1. **PHP support.** Define the supported PHP template forms, choose and
   validate the parser(s), and cover boundaries between PHP expressions and
   HTML before enabling `php` filetypes.
2. **Broader language coverage.** Evaluate other template and component
   filetypes against their actual Tree-sitter node shapes and add focused
   regression fixtures before advertising support.
3. **Configuration and compatibility.** Explore opt-in mappings or per-filetype
   controls without changing the safe default behavior or stacking handlers.
4. **Automated performance and compatibility checks.** Add repeatable
   large-document benchmarks to CI and verify supported Neovim and parser
   versions there. Editing performance has already been measured and improved
   on 5,000-line HTML and TSX fixtures locally.
