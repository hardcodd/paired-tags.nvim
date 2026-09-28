local tags = require("paired_tags")
local api = vim.api
local namespace = assert(api.nvim_get_namespaces().PairedTagHighlight)

local function buffer(filetype, source)
  local buf = api.nvim_create_buf(true, false)
  api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = filetype
  api.nvim_buf_set_lines(buf, 0, -1, false, { source })
  return buf
end

local function column(source, needle, occurrence)
  local first = 1
  for _ = 1, occurrence or 1 do
    first = assert(source:find(needle, first, true), needle)
    if _ < (occurrence or 1) then first = first + #needle end
  end
  return first - 1
end

local function marks(buf)
  local found = api.nvim_buf_get_extmarks(buf, namespace, 0, -1,
    { details = true })
  table.sort(found, function(a, b) return a[3] < b[3] end)
  return found
end

local function select(buf, source, needle, occurrence)
  api.nvim_win_set_cursor(0, { 1, column(source, needle, occurrence) + 3 })
  tags.refresh_highlight({ buf = buf })
end

local function expect_branch(filetype, source, branch, branch_occurrence,
    opener, opener_occurrence, label)
  local buf = buffer(filetype, source)
  select(buf, source, branch, branch_occurrence)
  local found = marks(buf)
  assert(#found == 2, label .. ": expected exactly two marks, got " .. #found)
  local open_col = column(source, opener, opener_occurrence) + 3
  local branch_col = column(source, branch, branch_occurrence) + 3
  local opener_name = opener:match("^{%% ([%a_]+)")
  local branch_name = branch:match("^{%% ([%a_]+)")
  assert(found[1][3] == open_col
    and found[1][4].end_col == open_col + #opener_name
    and found[1][4].hl_group == "PairedTagsOpening",
    label .. ": wrong owning opener: " .. vim.inspect(found))
  assert(found[2][3] == branch_col
    and found[2][4].end_col == branch_col + #branch_name
    and found[2][4].hl_group == "PairedTagsClosing",
    label .. ": wrong branch: " .. vim.inspect(found))
  return buf
end

for _, filetype in ipairs({ "htmldjango", "jinja", "jinja2" }) do
  local source = "{% if outer %}{% if inner %}x{% elif other %}y{% else %}z{% endif %}{% else %}q{% endif %}"
  expect_branch(filetype, source, "{% elif", 1, "{% if", 2,
    filetype .. " inner elif belongs to inner if")
  expect_branch(filetype, source, "{% else", 1, "{% if", 2,
    filetype .. " inner else belongs to inner if")
  expect_branch(filetype, source, "{% else", 2, "{% if", 1,
    filetype .. " outer else belongs to outer if")
  expect_branch(filetype,
    "{% if a %}{% elif b %}{% elif c %}{% else %}{% endif %}",
    "{% elif", 2, "{% if", 1,
    filetype .. " second elif belongs to original if")
end

expect_branch("htmldjango", "{% for x in xs %}x{% empty %}y{% endfor %}",
  "{% empty", 1, "{% for", 1, "Django empty belongs to for")
expect_branch("htmldjango", "{% ifchanged value %}x{% else %}y{% endifchanged %}",
  "{% else", 1, "{% ifchanged", 1, "Django else belongs to ifchanged")
expect_branch("htmldjango", "{% blocktrans %}one{% plural %}many{% endblocktrans %}",
  "{% plural", 1, "{% blocktrans", 1, "Django plural belongs to blocktrans")
expect_branch("htmldjango", "{% blocktranslate %}one{% plural %}many{% endblocktranslate %}",
  "{% plural", 1, "{% blocktranslate", 1,
  "Django plural belongs to blocktranslate")
expect_branch("jinja", "{% for x in xs %}x{% else %}y{% endfor %}",
  "{% else", 1, "{% for", 1, "Jinja else belongs to for")
expect_branch("jinja2", "{% for x in xs %}x{% else %}y{% endfor %}",
  "{% else", 1, "{% for", 1, "Jinja2 else belongs to for")
for _, filetype in ipairs({ "htmldjango", "jinja", "jinja2" }) do
  local deeply_nested = table.concat({
    "{% if a %}",
    "{% for item in items %}",
    "{% if b %}",
    "{% if c %}",
    "{% else %}",
    "{% endif %}",
    "{% elif d %}",
    "{% else %}",
    "{% endif %}",
    filetype == "htmldjango" and "{% empty %}" or "{% else %}",
    "{% endfor %}",
    "{% else %}",
    "{% endif %}",
  })
  expect_branch(filetype, deeply_nested, "{% else", 1, "{% if", 3,
    filetype .. " deepest else belongs to the third if")
  expect_branch(filetype, deeply_nested, "{% elif", 1, "{% if", 2,
    filetype .. " elif after a nested if belongs to the second if")
  expect_branch(filetype, deeply_nested, "{% else", 2, "{% if", 2,
    filetype .. " middle else belongs to the second if")
  expect_branch(filetype, deeply_nested,
    filetype == "htmldjango" and "{% empty" or "{% else",
    1 + (filetype == "htmldjango" and 0 or 2), "{% for", 1,
    filetype .. " for branch belongs to for")
  expect_branch(filetype, deeply_nested, "{% else",
    filetype == "htmldjango" and 3 or 4, "{% if", 1,
    filetype .. " final else belongs to outermost if")
end

local source = "{% if a %}{% if b %}x{% else %}y{% endif %}{% else %}z{% endif %}"
local buf = expect_branch("jinja", source, "{% else", 1, "{% if", 2,
  "Nested branch selected")
select(buf, source, "{% endif", 1)
local closer_marks = marks(buf)
assert(#closer_marks == 2 and closer_marks[1][3] == column(source, "{% if", 2) + 3
  and closer_marks[2][3] == column(source, "{% endif", 1) + 3,
  "Moving to end keyword must restore the normal opener/closer pair")
api.nvim_win_set_cursor(0, { 1, column(source, "x") })
tags.refresh_highlight({ buf = buf })
assert(#marks(buf) == 0, "Moving off the branch must clear marks")

local malformed = buffer("jinja", "{% if a %}x{% else %}y")
select(malformed, "{% if a %}x{% else %}y", "{% else", 1)
assert(#marks(malformed) == 0, "An unclosed block must not highlight a branch")
local unrelated = buffer("htmldjango", "{% else %}")
select(unrelated, "{% else %}", "{% else", 1)
assert(#marks(unrelated) == 0, "An orphan branch must not highlight")

local multiline_source = { "{% if outer %}", "  {% if inner %}",
  "    {% else %}", "  {% endif %}", "{% endif %}" }
local multiline = api.nvim_create_buf(true, false)
api.nvim_set_current_buf(multiline)
vim.bo[multiline].filetype = "jinja"
api.nvim_buf_set_lines(multiline, 0, -1, false, multiline_source)
api.nvim_win_set_cursor(0, { 3, 7 })
tags.refresh_highlight({ buf = multiline })
local multiline_marks = marks(multiline)
assert(#multiline_marks == 2
  and multiline_marks[1][2] == 1 and multiline_marks[1][3] == 5
  and multiline_marks[2][2] == 2 and multiline_marks[2][3] == 7,
  "A multiline nested branch must mark the inner opener and branch")

local controlled = buffer("jinja", "{%- if ready -%}x{%- else -%}y{%- endif -%}")
api.nvim_win_set_cursor(0, { 1, #"{%- if ready -%}x{%- " })
tags.refresh_highlight({ buf = controlled })
local controlled_marks = marks(controlled)
assert(#controlled_marks == 2
  and controlled_marks[1][3] == #"{%- "
  and controlled_marks[2][3] == #"{%- if ready -%}x{%- ",
  "Jinja whitespace-control else must resolve to its if")

local edited_source = "{% if ready %}x{% else %}y{% endif %}"
local edited = expect_branch("jinja", edited_source, "{% else", 1,
  "{% if", 1, "Branch before editing")
local else_col = column(edited_source, "{% else") + 3
api.nvim_buf_set_text(edited, 0, else_col, 0, else_col + #"else",
  { "unknown" })
tags.refresh_highlight({ buf = edited })
assert(#marks(edited) == 0, "Invalidated branch must clear stale marks")

for _, filetype in ipairs({ "htmldjango", "jinja" }) do
  local large_lines = { "{% if ready %}" }
  for _ = 1, 2500 do large_lines[#large_lines + 1] = "content" end
  large_lines[#large_lines + 1] = "{% else %}"
  for _ = 1, 2500 do large_lines[#large_lines + 1] = "content" end
  large_lines[#large_lines + 1] = "{% endif %}"
  local large = api.nvim_create_buf(true, false)
  api.nvim_set_current_buf(large)
  vim.bo[large].filetype = filetype
  api.nvim_buf_set_lines(large, 0, -1, false, large_lines)
  api.nvim_win_set_cursor(0, { 2502, 3 })
  tags.refresh_highlight({ buf = large })
  local found = marks(large)
  assert(#found == 2 and found[1][2] == 0 and found[1][3] == 3
    and found[2][2] == 2501 and found[2][3] == 3,
    filetype .. " branch must resolve across 5,000 content lines")
end

local parserless = buffer("jinja", "{% if a %}x{% else %}y{% endif %}")
local get_parser = vim.treesitter.get_parser
vim.treesitter.get_parser = function(target, ...)
  if target == parserless then error("parser unavailable") end
  return get_parser(target, ...)
end
select(parserless, "{% if a %}x{% else %}y{% endif %}", "{% else", 1)
vim.treesitter.get_parser = get_parser
assert(#marks(parserless) == 0, "Missing parser must not highlight a branch")

local lost_parser_source = "{% if a %}x{% else %}y{% endif %}"
local lost_parser = expect_branch("jinja", lost_parser_source,
  "{% else", 1, "{% if", 1, "Branch before parser loss")
vim.treesitter.get_parser = function(target, ...)
  if target == lost_parser then error("parser unavailable") end
  return get_parser(target, ...)
end
tags.refresh_highlight({ buf = lost_parser })
vim.treesitter.get_parser = get_parser
assert(#marks(lost_parser) == 0,
  "Parser loss must clear an already highlighted branch")

print("Template branch highlighting passed")
