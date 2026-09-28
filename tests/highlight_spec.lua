local tags = require("paired_tags")
local api = vim.api
local namespace = assert(api.nvim_get_namespaces().PairedTagHighlight)
assert(api.nvim_get_hl(0, { name = "PairedTagsOpening" }).link == "MatchParen")
assert(api.nvim_get_hl(0, { name = "PairedTagsClosing" }).link == "MatchParen")
vim.cmd.colorscheme("habamax")
assert(api.nvim_get_hl(0, { name = "PairedTagsOpening" }).link == "MatchParen")
assert(api.nvim_get_hl(0, { name = "PairedTagsClosing" }).link == "MatchParen")

local function buffer(filetype, lines)
  local buf = api.nvim_create_buf(true, false)
  api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = filetype
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

local function marks(buf)
  local result = api.nvim_buf_get_extmarks(buf, namespace, 0, -1,
    { details = true })
  table.sort(result, function(a, b)
    return a[2] < b[2] or a[2] == b[2] and a[3] < b[3]
  end)
  return result
end

local function select_tag(buf, row, needle, offset)
  local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  local first = assert(line:find(needle, 1, true), needle)
  api.nvim_win_set_cursor(0, { row + 1, first - 1 + (offset or 1) })
  tags.refresh_highlight({ buf = buf })
end

local function expect_pair(buf, opener_row, opener_col, opening_name,
    closer_row, closer_col, closing_name)
  local found = marks(buf)
  assert(#found == 2, "expected two marks, got " .. #found)
  assert(found[1][2] == opener_row and found[1][3] == opener_col
    and found[1][4].end_col == opener_col + #opening_name
    and found[1][4].hl_group == "PairedTagsOpening", "wrong opener mark")
  assert(found[2][2] == closer_row and found[2][3] == closer_col
    and found[2][4].end_col == closer_col + #closing_name
    and found[2][4].hl_group == "PairedTagsClosing",
    ("wrong closer mark: expected %d:%d-%d, got %d:%d-%d")
      :format(closer_row, closer_col, closer_col + #closing_name,
        found[2][2], found[2][3], found[2][4].end_col))
end

local function expect_none(buf)
  assert(#marks(buf) == 0,
    "stale or unsafe highlight at " .. vim.inspect(api.nvim_win_get_cursor(0)))
end

local nested = buffer("html", { "<main><section>text</section></main>" })
local unchanged_tick = api.nvim_buf_get_changedtick(nested)
select_tag(nested, 0, "<section>")
expect_pair(nested, 0, 7, "section", 0, 21, "section")
assert(api.nvim_buf_get_changedtick(nested) == unchanged_tick,
  "highlighting changed buffer text")
local original = marks(nested)
tags.refresh_highlight({ buf = nested })
local repeated = marks(nested)
assert(original[1][1] == repeated[1][1]
  and original[2][1] == repeated[2][1], "unchanged pair recreated marks")
select_tag(nested, 0, "</section>")
expect_pair(nested, 0, 7, "section", 0, 21, "section")
api.nvim_win_set_cursor(0, { 1, 15 })
tags.refresh_highlight({ buf = nested })
expect_none(nested)
select_tag(nested, 0, "<main>")
expect_pair(nested, 0, 1, "main", 0, 31, "main")
local background = api.nvim_create_buf(true, false)
vim.bo[background].filetype = "html"
tags.refresh_highlight({ buf = background })
expect_pair(nested, 0, 1, "main", 0, 31, "main")
api.nvim_win_set_cursor(0, { 1, 16 })
tags.refresh_highlight({ buf = nested })
expect_none(nested)
local repeated_names = buffer("html", { "<div><div>x</div></div>" })
select_tag(repeated_names, 0, "<div>", 7)
expect_pair(repeated_names, 0, 6, "div", 0, 13, "div")
select_tag(repeated_names, 0, "<div>")
expect_pair(repeated_names, 0, 1, "div", 0, 19, "div")

local malformed = buffer("html", { "<div><span>text</div>" })
select_tag(malformed, 0, "<span>")
expect_none(malformed)
select_tag(malformed, 0, "<div>")
expect_pair(malformed, 0, 1, "div", 0, 17, "div")
local mismatch = buffer("xml", { "<Box></box>" })
select_tag(mismatch, 0, "<Box>")
expect_none(mismatch)
local complete = buffer("xml", { "<Box></Box>" })
select_tag(complete, 0, "<Box>")
expect_pair(complete, 0, 1, "Box", 0, 7, "Box")
local greek = buffer("xml", { "<δοκιμή>ok</δοκιμή>" })
select_tag(greek, 0, "<δοκιμή>")
expect_pair(greek, 0, 1, "δοκιμή", 0, 18, "δοκιμή")
local html_case = buffer("html", { "<DIV>ok</div>" })
select_tag(html_case, 0, "<DIV>")
expect_pair(html_case, 0, 1, "DIV", 0, 9, "div")
local optional = buffer("html", { "<ul><li>one<li>two</ul>" })
select_tag(optional, 0, "<li>")
expect_none(optional)
local multiline = buffer("html", {
  "<section", "  class='box'>", "  hello", "</section>",
})
select_tag(multiline, 1, "class")
expect_pair(multiline, 0, 1, "section", 3, 2, "section")

for _, source in ipairs({ "<br>", "<img/>", "<!-- <div></div> -->",
    "<div>", "</div>" }) do
  local buf = buffer("html", { source })
  api.nvim_win_set_cursor(0, { 1, 2 })
  tags.refresh_highlight({ buf = buf })
  expect_none(buf)
end

local markdown = buffer("markdown", { "Before <em>yes</em> after" })
select_tag(markdown, 0, "<em>")
expect_pair(markdown, 0, 8, "em", 0, 16, "em")
local fenced = buffer("markdown", { "```html", "<em>no</em>", "```" })
select_tag(fenced, 1, "<em>")
expect_none(fenced)
local raw_text = buffer("html", {
  "<script>const s = '<em>no</em>';</script>",
  "<style>p:before { content: '<em>no</em>'; }</style>",
})
select_tag(raw_text, 0, "<em>")
expect_none(raw_text)
select_tag(raw_text, 1, "<em>")
expect_none(raw_text)
local jsx = buffer("typescriptreact", { "const x = <Box><Part /></Box>;" })
select_tag(jsx, 0, "<Box>")
expect_pair(jsx, 0, 11, "Box", 0, 25, "Box")
select_tag(jsx, 0, "<Part />")
expect_none(jsx)
for _, filetype in ipairs({ "vue", "svelte" }) do
  local embedded = buffer(filetype, { "<script>const x = 1</script>",
    "<section><em>yes</em></section>" })
  select_tag(embedded, 1, "<em>")
  expect_pair(embedded, 1, 10, "em", 1, 18, "em")
end
local javascript = buffer("javascriptreact", {
  "const value = '<div>fake</div>';", "const view = <Real>ok</Real>;",
})
select_tag(javascript, 0, "<div>")
expect_none(javascript)
select_tag(javascript, 1, "<Real>")
expect_pair(javascript, 1, 14, "Real", 1, 23, "Real")

local edited = buffer("html", { "<article>one</article>" })
select_tag(edited, 0, "<article>")
expect_pair(edited, 0, 1, "article", 0, 14, "article")
api.nvim_buf_set_text(edited, 0, 2, 0, 2, { "x" })
tags.refresh_highlight({ buf = edited })
expect_none(edited)
api.nvim_buf_set_lines(edited, 0, -1, false, { "<article>one</article>" })
select_tag(edited, 0, "<article>")
expect_pair(edited, 0, 1, "article", 0, 14, "article")
tags.clear_highlight({ buf = edited })
expect_none(edited)
select_tag(edited, 0, "<article>")
api.nvim_win_set_cursor(0, { 1, 10 })
api.nvim_exec_autocmds("CursorMoved", { buffer = edited })
expect_none(edited)
select_tag(edited, 0, "<article>")
api.nvim_buf_set_lines(edited, 0, -1, false, { "plain text" })
api.nvim_exec_autocmds("TextChanged", { buffer = edited })
expect_none(edited)
api.nvim_buf_set_lines(edited, 0, -1, false, { "<article>one</article>" })
select_tag(edited, 0, "<article>")
api.nvim_exec_autocmds("BufLeave", { buffer = edited })
expect_none(edited)
select_tag(edited, 0, "<article>")
api.nvim_exec_autocmds("WinLeave", { buffer = edited })
expect_none(edited)
api.nvim_exec_autocmds("WinEnter", { buffer = edited })
expect_pair(edited, 0, 1, "article", 0, 14, "article")

local missing = buffer("html", { "<p>text</p>" })
select_tag(missing, 0, "<p>")
expect_pair(missing, 0, 1, "p", 0, 9, "p")
local get_parser = vim.treesitter.get_parser
vim.treesitter.get_parser = function() error("parser unavailable") end
local ok, err = pcall(tags.refresh_highlight, { buf = missing })
vim.treesitter.get_parser = get_parser
assert(ok, tostring(err))
expect_none(missing)
select_tag(missing, 0, "<p>")
local parser = vim.treesitter.get_parser(missing, "html")
local own_parse = rawget(parser, "parse")
parser.parse = function() error("parser failed") end
ok, err = pcall(tags.refresh_highlight, { buf = missing })
parser.parse = own_parse
assert(ok, tostring(err))
expect_none(missing)

local plain = buffer("text", { "<p>text</p>" })
select_tag(plain, 0, "<p>")
expect_none(plain)
local special = buffer("html", { "<p>text</p>" })
vim.bo[special].buftype = "nofile"
select_tag(special, 0, "<p>")
expect_none(special)

local large_lines = {}
for index = 1, 5000 do
  large_lines[index] = index == 2500 and "<main><em>text</em></main>"
    or "plain text " .. index
end
local large = buffer("html", large_lines)
select_tag(large, 2499, "<em>")
expect_pair(large, 2499, 7, "em", 2499, 16, "em")
parser = vim.treesitter.get_parser(large, "html")
local original_parse = parser.parse
own_parse = rawget(parser, "parse")
local parsed_ranges = {}
parser.parse = function(self, range, ...)
  parsed_ranges[#parsed_ranges + 1] = range
  return original_parse(self, range, ...)
end
local success, failure = pcall(function()
  for _ = 1, 20 do tags.refresh_highlight({ buf = large }) end
  select_tag(large, 2499, "</em>")
  assert(#marks(large) == 2, "large-buffer marks multiplied")
end)
parser.parse = own_parse
assert(success, failure)
for _, range in ipairs(parsed_ranges) do
  assert(type(range) == "table" and range[1] >= 2499
    and range[3] <= 2500, "highlight requested a full-buffer parse")
end

print("Paired-tag highlighting passed")
