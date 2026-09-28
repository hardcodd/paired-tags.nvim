local tags = require("paired_tags")
local api = vim.api
local highlight_ns = api.nvim_get_namespaces().PairedTagHighlight

local function feed(keys)
  api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true),
    "xt", false)
  vim.wait(30)
end

local function buffer(filetype, source)
  local buf = api.nvim_create_buf(true, false)
  api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = filetype
  api.nvim_buf_set_lines(buf, 0, -1, false,
    vim.split(source, "\n", { plain = true }))
  return buf
end

local function current(buf)
  return api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function typed(filetype, before, col, input, expected, label)
  local buf = buffer(filetype, before)
  api.nvim_win_set_cursor(0, { 1, col })
  feed("i" .. input .. "<Esc>")
  assert(current(buf)[1] == expected,
    label .. ": expected " .. vim.inspect(expected) .. ", got "
      .. vim.inspect(current(buf)[1]))
end

local function rename(filetype, before, source, new_name, expected, label)
  local buf = buffer(filetype, before)
  local first = assert(before:find(source, 1, true), label)
  local name_col = first - 1 + #"{% "
  if source:sub(1, 3) == "{%-" then name_col = first - 1 + #"{%- " end
  local old_name = source:match("^{%%%-?%s*([%a_]+)")
  assert(old_name, label .. " source keyword")
  api.nvim_win_set_cursor(0, { 1, name_col + 1 })
  tags.capture_pair({ buf = buf })
  api.nvim_buf_set_text(buf, 0, name_col, 0, name_col + #old_name,
    { new_name })
  tags.edit(buf, 0, name_col + #new_name, false)
  assert(current(buf)[1] == expected,
    label .. ": expected " .. vim.inspect(expected) .. ", got "
      .. vim.inspect(current(buf)[1]))
end

local function rename_keys(filetype, before, source, keys, expected, label)
  local buf = buffer(filetype, before)
  local first = assert(before:find(source, 1, true), label)
  api.nvim_win_set_cursor(0, { 1, first - 1 + #"{% " })
  feed(keys)
  assert(current(buf)[1] == expected,
    label .. ": expected " .. vim.inspect(expected) .. ", got "
      .. vim.inspect(current(buf)[1]))
end

local function marks(filetype, source, needle, expected, label)
  local buf = buffer(filetype, source)
  local first = assert(source:find(needle, 1, true), label)
  api.nvim_win_set_cursor(0, { 1, first })
  tags.refresh_highlight({ buf = buf })
  local found = api.nvim_buf_get_extmarks(buf, highlight_ns, 0, -1, {})
  assert(#found == expected,
    label .. ": expected " .. expected .. " marks, got " .. #found)
end

for _, filetype in ipairs({ "htmldjango", "jinja", "jinja2" }) do
  typed(filetype, "", 0, "{% if active %}",
    "{% if active %}{% endif %}", filetype .. " closes if")
  typed(filetype, "{% if outer %}{% endif %}", #"{% if outer %}",
    "{% if inner %}",
    "{% if outer %}{% if inner %}{% endif %}{% endif %}",
    filetype .. " preserves outer if closer")
  typed(filetype, "{% if active %}{% endif %}", 0,
    "", "{% if active %}{% endif %}",
    filetype .. " does not duplicate an existing closer")
  typed(filetype, "{% endif %}", 0, "{% if active %}",
    "{% if active %}{% endif %}",
    filetype .. " reuses a matching closer")
  typed(filetype, "{% if outer %}{% else %}{% endif %}",
    #"{% if outer %}", "{% if inner %}",
    "{% if outer %}{% if inner %}{% endif %}{% else %}{% endif %}",
    filetype .. " preserves a closer across branches")
  typed(filetype, "{{ \"\" }}", #"{{ \"", "{% if active %}",
    '{{ "{% if active %}" }}',
    filetype .. " leaves a statement inside an expression string literal")
  marks(filetype, "{% if active %}<em>x</em>{% endif %}",
    "{% if", 2, filetype .. " highlights a block pair")
  marks(filetype, "{% if active %}<em>x</em>{% endif %}",
    "{% endif", 2, filetype .. " highlights from the closer")
  marks(filetype, "{% if active %}<em>x</em>",
    "{% if", 0, filetype .. " skips an incomplete block")
  marks(filetype, "{% if active %}{% if nested %}x{% endif %}{% endif %}",
    "{% if nested", 2, filetype .. " highlights an inner block")

  local enter = buffer(filetype, "{% if active %}{% endif %}")
  vim.bo[enter].shiftwidth = 2
  vim.bo[enter].expandtab = true
  api.nvim_win_set_cursor(0, { 1, #"{% if active %}" })
  feed("i<CR>content<Esc>")
  assert(vim.deep_equal(current(enter),
    { "{% if active %}", "  content", "{% endif %}" }),
    filetype .. " Enter must indent adjacent block delimiters")

  local multiline = buffer(filetype, "{% if\nactive %")
  api.nvim_win_set_cursor(0, { 2, #"active %" })
  feed("A}<Esc>")
  assert(vim.deep_equal(current(multiline),
    { "{% if", "active %}{% endif %}" }),
    filetype .. " closes a multiline block opener: "
      .. vim.inspect(current(multiline)))
end

rename("htmldjango", "{% if active %}x{% endif %}",
  "{% endif %}", "endfor", "{% for active %}x{% endfor %}",
  "Django closer rename updates its opener")
rename("jinja", "{% if active %}x{% endif %}",
  "{% endif %}", "endfor", "{% for active %}x{% endfor %}",
  "Jinja closer rename updates its opener")
rename("htmldjango", "{% if outer %}{% if inner %}x{% endif %}{% endif %}",
  "{% if inner %}", "for",
  "{% if outer %}{% for inner %}x{% endfor %}{% endif %}",
  "Django nested rename touches only its mate")
rename("jinja", "{% if outer %}{% if inner %}x{% endif %}{% endif %}",
  "{% if inner %}", "for",
  "{% if outer %}{% for inner %}x{% endfor %}{% endif %}",
  "Jinja nested rename touches only its mate")

marks("htmldjango", "{% comment %}\ntext\n{% endcomment %}",
  "{% comment", 2, "Django multiline comment highlights its pair")
marks("jinja", "{% raw %}text{% endraw %}",
  "{% raw", 2, "Jinja raw highlights its pair")
marks("jinja", "{%- if active -%}x{%- endif -%}",
  "{%- if", 2, "Jinja whitespace-control blocks highlight their pair")

typed("htmldjango", "{% comment %} {% endcomment %}",
  #"{% comment %} ", "{% if active %}",
  "{% comment %} {% if active %}{% endcomment %}",
  "Django comment keeps a nested statement literal")
typed("htmldjango", "{% verbatim %} {% endverbatim %}",
  #"{% verbatim %} ", "{% if active %}",
  "{% verbatim %} {% if active %}{% endverbatim %}",
  "Django verbatim keeps a nested statement literal")
typed("jinja", "{% raw %} {% endraw %}",
  #"{% raw %} ", "{% if active %}",
  "{% raw %} {% if active %}{% endraw %}",
  "Jinja raw keeps a nested statement literal")
typed("jinja", "{#  #}", #"{# ", "{% if active %}",
  "{# {% if active %} #}",
  "Jinja comment keeps a statement literal")
typed("htmldjango", "", 0, "{% if %}", "{% if %}",
  "Django incomplete if is not closed")
typed("jinja", "", 0, "{% if %}", "{% if %}",
  "Jinja incomplete if is not closed")
typed("jinja", "", 0, '{% if text == "{% hi %}" %}',
  '{% if text == "{% hi %}" %}{% endif %}',
  "Jinja quoted delimiters in a condition remain literal")
typed("jinja", "", 0, "{{ value }}", "{{ value }}",
  "Jinja expressions remain unchanged")
typed("htmldjango", "", 0, "{# note #}", "{# note #}",
  "Django comment delimiters remain unchanged")

rename_keys("htmldjango", "{% if active %}x{% endif %}",
  "{% if", "ciwfor<Esc>", "{% for active %}x{% endfor %}",
  "Django normal-mode keyword replacement")
rename_keys("jinja", "{% if active %}x{% endif %}",
  "{% endif", "ciwendfor<Esc>", "{% for active %}x{% endfor %}",
  "Jinja normal-mode closer replacement")

local stale = buffer("jinja", "{% if active %}x{% endif %}")
api.nvim_win_set_cursor(0, { 1, #"{% i" })
tags.capture_pair({ buf = stale })
api.nvim_buf_set_text(stale, 0, #"{% if active %}",
  0, #"{% if active %}x", { "changed" })
api.nvim_buf_set_text(stale, 0, #"{% ", 0, #"{% if", { "for" })
tags.edit(stale, 0, #"{% for", false)
assert(current(stale)[1] == "{% for active %}changed{% endif %}",
  "An unrelated edit invalidates a saved template pair")

local parserless = buffer("jinja", "{% if active %")
local get_parser = vim.treesitter.get_parser
vim.treesitter.get_parser = function(buf, ...)
  if buf == parserless then error("parser unavailable") end
  return get_parser(buf, ...)
end
feed("A}<Esc>")
tags.refresh_highlight({ buf = parserless })
vim.treesitter.get_parser = get_parser
assert(current(parserless)[1] == "{% if active %}",
  "Missing Jinja parser must leave the block unchanged")

for _, case in ipairs({
  { "htmldjango", "{% for item in items %}", "{% endfor %}" },
  { "htmldjango", "{% block content %}", "{% endblock %}" },
  { "htmldjango", "{% comment %}", "{% endcomment %}" },
  { "htmldjango", "{% verbatim %}", "{% endverbatim %}" },
  { "htmldjango", "{% blocktrans %}", "{% endblocktrans %}" },
  { "jinja", "{% for item in items %}", "{% endfor %}" },
  { "jinja", "{% block content %}", "{% endblock %}" },
  { "jinja", "{% macro card() %}", "{% endmacro %}" },
  { "jinja", "{% raw %}", "{% endraw %}" },
  { "jinja", "{% set content %}", "{% endset %}" },
  { "jinja", "{%- if active -%}", "{% endif %}" },
}) do
  typed(case[1], "", 0, case[2], case[2] .. case[3],
    case[1] .. " closes " .. case[2])
end

typed("jinja", "", 0, "{% set value = 1 %}",
  "{% set value = 1 %}", "Jinja assignment is not a paired block")
typed("jinja", "", 0, "{% include 'card.html' %}",
  "{% include 'card.html' %}", "Jinja include is not a paired block")
typed("htmldjango", "", 0, "{% include 'card.html' %}",
  "{% include 'card.html' %}", "Django include is not a paired block")
typed("htmldjango", "", 0, "{% customtag value %}",
  "{% customtag value %}", "Unknown Django tags stay unchanged")
typed("html", "", 0, "}", "}",
  "The brace mapping leaves ordinary HTML input alone")

rename("htmldjango", "{% blocktrans %}x{% endblocktrans %}",
  "{% blocktrans %}", "blocktranslate",
  "{% blocktranslate %}x{% endblocktranslate %}",
  "Django opener rename updates only its paired keyword")
rename("jinja", "{% block card %}x{% endblock %}",
  "{% block card %}", "macro",
  "{% macro card %}x{% endmacro %}",
  "Jinja opener rename updates the closing keyword")

print("Template block editing passed")
