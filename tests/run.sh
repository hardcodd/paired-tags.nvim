#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
: "${PAIRED_TAGS_AUTOPAIRS_RTP:?Set PAIRED_TAGS_AUTOPAIRS_RTP to the nvim-autopairs checkout}"

synchronous_suites=(
  setup_spec
  highlight_config_spec
  html_enter_spec
  paired_editing_spec
  rename_fast_path_spec
  highlight_spec
  tag_scenarios_spec
  template_html_spec
  template_blocks_spec
  template_branches_spec
  template_delimiters_spec
)
regression_suites=(
  tag_bug_regressions_spec
  tag_bug_report_2_spec
  tag_bug_report_3_spec
  tag_bug_report_4_spec
)

for suite in "${synchronous_suites[@]}"; do
  printf 'Running %s\n' "$suite"
  if [[ "$suite" == highlight_config_spec ]]; then
    nvim --headless -u NONE -i NONE -n \
      "+lua local ok, err = pcall(dofile, 'tests/$suite.lua'); if not ok then print(err); vim.cmd('cquit') end" \
      +qa!
  else
    nvim --headless -u NONE -i NONE -n \
      '+luafile tests/bootstrap.lua' \
      "+lua local ok, err = pcall(dofile, 'tests/$suite.lua'); if not ok then print(err); vim.cmd('cquit') end" \
      +qa!
  fi
done

for suite in "${regression_suites[@]}"; do
  printf 'Running %s\n' "$suite"
  nvim --headless -u NONE -i NONE -n \
    '+luafile tests/bootstrap.lua' \
    "+luafile tests/$suite.lua"
done

printf 'Running template_delimiter_autopairs_spec (plugin first)\n'
nvim --headless -u NONE -i NONE -n \
  '+luafile tests/bootstrap.lua' \
  '+lua local ok, err = pcall(dofile, "tests/template_delimiter_autopairs_spec.lua"); if not ok then print(err); vim.cmd("cquit") end' \
  +qa!

printf 'Running template_delimiter_autopairs_spec (autopairs first)\n'
nvim --headless -u NONE -i NONE -n \
  '+lua vim.opt.rtp:append(vim.env.PAIRED_TAGS_AUTOPAIRS_RTP); require("nvim-autopairs").setup({ map_cr = false })' \
  '+luafile tests/bootstrap.lua' \
  '+lua local ok, err = pcall(dofile, "tests/template_delimiter_autopairs_spec.lua"); if not ok then print(err); vim.cmd("cquit") end' \
  +qa!
