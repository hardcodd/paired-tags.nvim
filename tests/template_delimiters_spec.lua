local api = vim.api
local delimiter_ns = assert(api.nvim_get_namespaces().PairedTagDelimiter)

local function feed(keys)
  api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true),
    "xt", false)
  vim.wait(30)
end

local function buffer(filetype, source, buftype)
  local buf = api.nvim_create_buf(true, false)
  api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = filetype
  if buftype then vim.bo[buf].buftype = buftype end
  api.nvim_buf_set_lines(buf, 0, -1, false,
    vim.split(source, "\n", { plain = true }))
  return buf
end

local function lines(buf)
  return api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function typed(filetype, source, cursor, keys, expected, label, buftype)
  local buf = buffer(filetype, source, buftype)
  api.nvim_win_set_cursor(0, cursor)
  feed("i" .. keys .. "<Esc>")
  assert(vim.deep_equal(lines(buf), expected),
    label .. ": expected " .. vim.inspect(expected) .. ", got "
      .. vim.inspect(lines(buf)))
  return buf
end

for _, filetype in ipairs({ "htmldjango", "jinja", "jinja2" }) do
  for _, pair in ipairs({
    { "{%", "%}" },
    { "{{", "}}" },
    { "{#", "#}" },
  }) do
    typed(filetype, "", { 1, 0 }, pair[1] .. "X",
      { pair[1] .. " X " .. pair[2] },
      filetype .. " inserts the closer and leaves the cursor inside "
        .. pair[1])
    local completed = typed(filetype, "", { 1, 0 },
      pair[1] .. "value" .. pair[2],
      { pair[1] .. " value " .. pair[2] },
      filetype .. " typed closer must advance through " .. pair[2])
    assert(#api.nvim_buf_get_extmarks(completed, delimiter_ns, 0, -1, {}) == 0,
      filetype .. " completed delimiter must release its tracking marks")
    typed(filetype, pair[2], { 1, 0 }, pair[1],
      { pair[1] .. "  " .. pair[2] },
      filetype .. " existing closer must not duplicate " .. pair[2])
    typed(filetype, pair[2], { 1, 0 }, pair[1] .. "value" .. pair[2],
      { pair[1] .. " value " .. pair[2] },
      filetype .. " typed existing closer must not duplicate " .. pair[2])
  end

  typed(filetype, "", { 1, 0 }, "{%if ready%}",
    { "{% if ready %}{% endif %}" },
    filetype .. " generated statement closer still completes its block")
  typed(filetype, "{% if outer %}{% endif %}",
    { 1, #"{% if outer %}" }, "{%if inner%}",
    { "{% if outer %}{% if inner %}{% endif %}{% endif %}" },
    filetype .. " nested generated closer preserves outer block")
  typed(filetype, "", { 1, 0 }, "{%if ready%}{{value}}{#note#}",
    { "{% if ready %}{{ value }}{# note #}{% endif %}" },
    filetype .. " mixed nested delimiters keep their own closers")
  typed(filetype, "", { 1, 0 }, "{{{'a': {'b': 1}}}}",
    { "{{ {'a': {'b': 1}} }}" },
    filetype .. " nested dictionary braces do not consume expression closer")
  typed(filetype, "", { 1, 0 }, '{%if text == "{% hi %}"%}',
    { '{% if text == "{% hi %}" %}{% endif %}' },
    filetype .. " quoted statement delimiters do not consume the outer closer")
  typed(filetype, "", { 1, 0 }, "{{{'a': '}}', 'b': {'c': 2}}}",
    { "{{ {'a': '}}', 'b': {'c': 2}} }}" },
    filetype .. " quoted expression closers and nested dictionaries stay literal")
  typed(filetype, "", { 1, 0 }, "{#literal {{ value }}#}",
    { "{# literal {{ value }} #}" },
    filetype .. " nested-looking delimiters in comments stay literal")
  typed(filetype, "", { 1, 0 }, "{{<CR>value<CR>}}",
    { "{{ ", "value", "}}" },
    filetype .. " generated expression closer survives multiline content")
  typed(filetype, "{% if\nready %}", { 1, 0 }, "{#note#}",
    { "{# note #}{% if", "ready %}" },
    filetype .. " delimiter insertion preserves multiline neighbors")
  typed(filetype, "{# note #}", { 1, #"{# " }, "{{ ignored }}",
    { "{# {{ ignored }}note #}" },
    filetype .. " expression opener inside a comment stays literal")
end

typed("htmldjango", "{% verbatim %} {% endverbatim %}",
  { 1, #"{% verbatim %} " }, "{{ literal }}",
  { "{% verbatim %} {{ literal }}{% endverbatim %}" },
  "Django verbatim body stays literal")
typed("jinja", "{% raw %} {% endraw %}",
  { 1, #"{% raw %} " }, "{{ literal }}",
  { "{% raw %} {{ literal }}{% endraw %}" },
  "Jinja raw body stays literal")
typed("jinja", "{{ 'value' }}", { 1, #"{{ '" }, "{# literal #}",
  { "{{ '{# literal #}value' }}" },
  "Delimiter opener inside a template string stays literal")

for _, filetype in ipairs({ "htmldjango", "jinja" }) do
  local long = buffer(filetype, "")
  feed("i{{<Esc>")
  local replacement = { "" }
  for _ = 1, 130 do replacement[#replacement + 1] = "value" end
  replacement[#replacement + 1] = ""
  api.nvim_buf_set_text(long, 0, 3, 0, 3, replacement)
  local last_row = api.nvim_buf_line_count(long)
  api.nvim_win_set_cursor(0, { last_row, 0 })
  feed("i}}<Esc>")
  assert(lines(long)[last_row] == " }}",
    filetype .. " generated closer must survive more than 128 content lines: "
      .. vim.inspect(lines(long)[last_row]))
end

local removed_opener = buffer("jinja", "")
feed("i{{<Esc>")
api.nvim_buf_set_text(removed_opener, 0, 0, 0, 2, { "" })
api.nvim_win_set_cursor(0, { 1, 0 })
feed("i}<Esc>")
assert(lines(removed_opener)[1] == "}  }}",
  "Deleting an opener must invalidate its generated closer marker: "
    .. vim.inspect(lines(removed_opener)[1]))

local changed_filetype = buffer("jinja", "")
feed("i{{<Esc>")
vim.bo[changed_filetype].filetype = "html"
api.nvim_win_set_cursor(0, { 1, 2 })
feed("i}<Esc>")
assert(lines(changed_filetype)[1] == "{{}  }}",
  "A filetype change must restore native closer input: "
    .. vim.inspect(lines(changed_filetype)[1]))

typed("html", "", { 1, 0 }, "{{", { "{{" },
  "HTML buffer keeps native braces")
typed("lua", "", { 1, 0 }, "{#", { "{#" },
  "Unsupported filetype keeps native delimiters")
typed("jinja", "", { 1, 0 }, "{%", { "{%" },
  "Special buffer keeps native delimiters", "nofile")

local parserless = buffer("jinja", "")
local get_parser = vim.treesitter.get_parser
vim.treesitter.get_parser = function(target, ...)
  if target == parserless then error("parser unavailable") end
  return get_parser(target, ...)
end
feed("i{{<Esc>")
vim.treesitter.get_parser = get_parser
assert(lines(parserless)[1] == "{{",
  "Missing parser must leave typed delimiter unchanged")

print("Template delimiter completion passed")
