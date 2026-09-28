local api = vim.api
local autopairs_rtp = assert(vim.env.PAIRED_TAGS_AUTOPAIRS_RTP,
  "Set PAIRED_TAGS_AUTOPAIRS_RTP to the installed nvim-autopairs checkout")
vim.opt.rtp:append(autopairs_rtp)
if not package.loaded["nvim-autopairs"] then
  require("nvim-autopairs").setup({ map_cr = false })
end

local delimiter_ns = assert(api.nvim_get_namespaces().PairedTagDelimiter)

local function feed(keys)
  api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true),
    "xt", false)
  vim.wait(30)
end

local function buffer(filetype, source, cursor)
  local buf = api.nvim_create_buf(true, false)
  api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = filetype
  api.nvim_buf_set_lines(buf, 0, -1, false,
    vim.split(source, "\n", { plain = true }))
  api.nvim_win_set_cursor(0, cursor or { 1, 0 })
  return buf
end

local function expect(buf, expected, label)
  local actual = api.nvim_buf_get_lines(buf, 0, -1, false)
  assert(vim.deep_equal(actual, expected),
    label .. ": expected " .. vim.inspect(expected) .. ", got "
      .. vim.inspect(actual))
end

for _, filetype in ipairs({ "htmldjango", "jinja", "jinja2" }) do
  for _, pair in ipairs({
    { "{%", "%}" }, { "{{", "}}" }, { "{#", "#}" },
  }) do
    local opener, closer = unpack(pair)
    local buf = buffer(filetype, "")
    feed("i" .. opener .. "<Esc>")
    expect(buf, { opener .. "  " .. closer },
      filetype .. " opening " .. opener .. " with nvim-autopairs")
    local inserted = buffer(filetype, "")
    feed("i" .. opener .. "X<Esc>")
    expect(inserted, { opener .. " X " .. closer },
      filetype .. " cursor remains between delimiter spaces " .. opener)
    local completed = buffer(filetype, "")
    feed("i" .. opener .. "value" .. closer .. "<Esc>")
    expect(completed, { opener .. " value " .. closer },
      filetype .. " completed " .. opener .. " with nvim-autopairs")
    assert(#api.nvim_buf_get_extmarks(completed, delimiter_ns, 0, -1, {}) == 0,
      filetype .. " completed delimiter must release its tracking marks")

    local existing = buffer(filetype, closer)
    feed("i" .. opener .. "value" .. closer .. "<Esc>")
    expect(existing, { opener .. " value " .. closer },
      filetype .. " existing closer with nvim-autopairs " .. opener)
  end

  local statement = buffer(filetype, "")
  feed("i{%if outer%}{{item}}{#note#}<Esc>")
  expect(statement,
    { "{% if outer %}{{ item }}{# note #}{% endif %}" },
    filetype .. " nested block, expression, and comment with nvim-autopairs")

  local prefix = "{% if outer %}{% for item in items %}{% if item %}"
  local suffix = "{% endif %}{% endfor %}{% endif %}"
  local nested = buffer(filetype, prefix .. "X" .. suffix, { 1, #prefix })
  feed("i{{item}}{#note#}<Esc>")
  expect(nested, { prefix .. "{{ item }}{# note #}X" .. suffix },
    filetype .. " expression and comment keep their closers in three nested blocks")

  local dictionary = buffer(filetype, "")
  feed("i{{{'a': '}}', 'b': {'c': 2}}}<Esc>")
  expect(dictionary, { "{{ {'a': '}}', 'b': {'c': 2}} }}" },
    filetype .. " nested dictionary and quoted closer stay inside expression")

  local braces = buffer(filetype, "")
  feed("i{x<Esc>")
  expect(braces, { "{x}" },
    filetype .. " ordinary braces keep nvim-autopairs behavior")

  local literal = filetype == "htmldjango"
    and "{% verbatim %} {% endverbatim %}"
    or "{% raw %} {% endraw %}"
  local literal_cursor = filetype == "htmldjango"
    and #"{% verbatim %} " or #"{% raw %} "
  local raw = buffer(filetype, literal, { 1, literal_cursor })
  feed("i{{literal}}<Esc>")
  expect(raw, { filetype == "htmldjango"
    and "{% verbatim %} {{literal}}{% endverbatim %}"
    or "{% raw %} {{literal}}{% endraw %}" },
    filetype .. " raw or verbatim body remains literal")

  if filetype ~= "htmldjango" then
    local controlled = buffer(filetype, "")
    feed("i{%-if active-%}<Esc>")
    expect(controlled, { "{%- if active -%}{% endif %}" },
      filetype .. " Jinja whitespace-control statement with nvim-autopairs")
  end
end

local unsupported = buffer("html", "")
feed("i{%<Esc>")
expect(unsupported, { "{%}" },
  "Unsupported filetype keeps nvim-autopairs' native brace pair")

local parserless = buffer("jinja", "")
local get_parser = vim.treesitter.get_parser
vim.treesitter.get_parser = function(target, ...)
  if target == parserless then error("parser unavailable") end
  return get_parser(target, ...)
end
feed("i{%<Esc>")
vim.treesitter.get_parser = get_parser
expect(parserless, { "{%}" },
  "Missing parser keeps nvim-autopairs' native brace pair")

print("Template delimiter nvim-autopairs integration passed")
