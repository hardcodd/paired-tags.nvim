local tags = require("paired_tags")
local api = vim.api
local highlight_ns = api.nvim_get_namespaces().PairedTagHighlight

local function feed(keys)
  api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true),
    "xt", false)
  vim.wait(30)
end

local function buffer(filetype, lines)
  local buf = api.nvim_create_buf(true, false)
  api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = filetype
  api.nvim_buf_set_lines(buf, 0, -1, false,
    type(lines) == "table" and lines or { lines })
  return buf
end

local function line(buf)
  return api.nvim_buf_get_lines(buf, 0, 1, false)[1]
end

local function type_at(filetype, before, column, keys, expected, label)
  local buf = buffer(filetype, before)
  api.nvim_win_set_cursor(0, { 1, column })
  feed("i" .. keys .. "<Esc>")
  assert(line(buf) == expected,
    label .. ": expected " .. vim.inspect(expected) .. ", got "
      .. vim.inspect(line(buf)))
  return buf
end

local function rename(filetype, before, source, replacement, expected, label)
  local buf = buffer(filetype, before)
  local first = assert(before:find(source, 1, true), label)
  local name_start = first - 1 + (source:sub(1, 2) == "</" and 2 or 1)
  local old_name = source:match("^</?([^%s>]+)")
  api.nvim_win_set_cursor(0, { 1, name_start + 1 })
  tags.capture_pair({ buf = buf })
  api.nvim_buf_set_text(buf, 0, name_start, 0, name_start + #old_name,
    { replacement })
  tags.edit(buf, 0, name_start + #replacement, false)
  assert(line(buf) == expected,
    label .. ": expected " .. vim.inspect(expected) .. ", got "
      .. vim.inspect(line(buf)))
end

local function highlights(filetype, source, needle, expected, label)
  local buf = buffer(filetype, source)
  local first = assert(source:find(needle, 1, true), label)
  api.nvim_win_set_cursor(0, { 1, first })
  tags.refresh_highlight({ buf = buf })
  local marks = api.nvim_buf_get_extmarks(buf, highlight_ns, 0, -1, {})
  assert(#marks == expected, label .. ": expected " .. expected
    .. " highlight marks, got " .. #marks)
end

for _, filetype in ipairs({ "htmldjango", "jinja", "jinja2" }) do
  local language = vim.treesitter.language.get_lang(filetype)
  local test_buf = buffer(filetype, "<div></div>")
  local ok, parser = pcall(vim.treesitter.get_parser, test_buf, language)
  assert(ok and parser and pcall(function() parser:parse() end),
    filetype .. " parser is required for the template suite")

  type_at(filetype, "{% if active %}{% endif %}", #"{% if active %}",
    "<strong>", "{% if active %}<strong></strong>{% endif %}",
    filetype .. " closes an HTML tag inside a template block")
  type_at(filetype, "", 0, '<div class="{{ style }}">',
    '<div class="{{ style }}"></div>',
    filetype .. " preserves an interpolated attribute")
  type_at(filetype, "<main></main>", #"<main>", "<main>",
    "<main><main></main></main>",
    filetype .. " closes a same-name nested element")
  rename(filetype, "<section>{% if ok %}<span>x</span>{% endif %}</section>",
    "<section>", "article",
    "<article>{% if ok %}<span>x</span>{% endif %}</article>",
    filetype .. " renames an opener across a template block")
  rename(filetype, "<section>{% if ok %}x{% endif %}</section>",
    "</section>", "article",
    "<article>{% if ok %}x{% endif %}</article>",
    filetype .. " renames a closer across a template block")
  rename(filetype, '<section class="{{ mode }}">x</section>',
    '<section class="{{ mode }}">', "article",
    '<article class="{{ mode }}">x</article>',
    filetype .. " renames a tag with an interpolated attribute")
  highlights(filetype, "<main>{% if ok %}<em>x</em>{% endif %}</main>",
    "<em>", 2, filetype .. " highlights an element in a block")
  highlights(filetype, '{{ "<em>x</em>" }}', "<em>", 0,
    filetype .. " does not highlight expression text")
  highlights(filetype,
    "{% if ok %}<em>{% else %}</em>{% endif %}",
    "<em>", 0, filetype .. " skips tags across template branches")
  rename(filetype,
    "{% if ok %}<em>{% else %}</em>{% endif %}",
    "<em>", "strong",
    "{% if ok %}<strong>{% else %}</em>{% endif %}",
    filetype .. " does not rename a different branch closer")

  local enter = buffer(filetype, "<div></div>")
  vim.bo[enter].shiftwidth = 2
  vim.bo[enter].expandtab = true
  api.nvim_win_set_cursor(0, { 1, 5 })
  feed("i<CR>content<Esc>")
  assert(vim.deep_equal(api.nvim_buf_get_lines(enter, 0, -1, false),
    { "<div>", "  content", "</div>" }),
    filetype .. " Enter must indent adjacent HTML tags")

  local multiline = buffer(filetype,
    { "<section", ' class="{{ mode }}"' })
  api.nvim_win_set_cursor(0, { 2, # ' class="{{ mode }}"' })
  feed("A><Esc>")
  local multiline_lines = api.nvim_buf_get_lines(multiline, 0, -1, false)
  assert(multiline_lines[1] == "<section"
    and vim.trim(multiline_lines[2])
      == 'class="{{ mode }}"></section>',
    filetype .. " closes a multiline tag with an expression: "
      .. vim.inspect(multiline_lines))
end

type_at("htmldjango", "{% if ok %}{% else %}</em>{% endif %}",
  #"{% if ok %}", "<em>",
  "{% if ok %}<em></em>{% else %}</em>{% endif %}",
  "Django does not consume a different branch closer")
type_at("jinja", "{% if ok %}{% else %}</em>{% endif %}",
  #"{% if ok %}", "<em>",
  "{% if ok %}<em></em>{% else %}</em>{% endif %}",
  "Jinja does not consume a different branch closer")
highlights("jinja", "{% if first %}<em>{% elif second %}</em>{% endif %}",
  "<em>", 0, "Jinja elif does not create an HTML pair")

type_at("htmldjango", "{% comment %}{% endcomment %}",
  #"{% comment %}", "<div>",
  "{% comment %}<div>{% endcomment %}",
  "Django comment must keep markup literal")
type_at("htmldjango", "{% verbatim %}{% endverbatim %}",
  #"{% verbatim %}", "<div>",
  "{% verbatim %}<div>{% endverbatim %}",
  "Django verbatim must keep markup literal")
type_at("jinja", "{% raw %}{% endraw %}", #"{% raw %}", "<div>",
  "{% raw %}<div>{% endraw %}",
  "Jinja raw block must keep markup literal")
type_at("jinja", '{% set text = "<span>" %}', #'{% set text = "',
  "<em>", '{% set text = "<em><span>" %}',
  "Jinja quoted statement text must keep markup literal")

local large_lines = { "<main>" }
for index = 2, 4999 do
  if index == 2500 then
    large_lines[index] = "{% if ready %}"
  elseif index == 2501 then
    large_lines[index] = "{% endif %}"
  else
    large_lines[index] = "body"
  end
end
large_lines[5000] = "</main>"
local large = buffer("jinja", large_lines)
api.nvim_win_set_cursor(0, { 1, 2 })
tags.refresh_highlight({ buf = large })
assert(#api.nvim_buf_get_extmarks(large, highlight_ns, 0, -1, {}) == 2,
  "Jinja HTML pair stays discoverable across a large template")

print("Template HTML editing passed")
