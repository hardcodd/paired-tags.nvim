local tags = require("paired_tags")
local api = vim.api

local function buffer(lines)
  local buf = api.nvim_create_buf(true, false)
  api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = "html"
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local parser = vim.treesitter.get_parser(buf, "html")
  parser:parse()
  return buf, parser
end

local function count_parses(parser, action)
  local original = parser.parse
  local own_parse = rawget(parser, "parse")
  local calls = 0
  parser.parse = function(self, ...)
    calls = calls + 1
    return original(self, ...)
  end
  local ok, err = pcall(action)
  parser.parse = own_parse
  assert(ok, err)
  return calls
end

local function line(buf, row)
  return api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
end

local opening, opening_parser = buffer({
  "<main>", "  <section>text</section>", "</main>",
})
api.nvim_win_set_cursor(0, { 2, 4 })
tags.capture_pair({ buf = opening })
for _, names in ipairs({ { "section", "article" }, { "article", "section" } }) do
  local old, new = unpack(names)
  local parses = count_parses(opening_parser, function()
    tags.capture_pair({ buf = opening })
    api.nvim_buf_set_text(opening, 1, 3, 1, 3 + #old, { new })
    tags.edit(opening, 1, 3 + #new, false)
  end)
  assert(parses == 0, "tracked opening rename must not reparse HTML")
  assert(line(opening, 1) == "  <" .. new .. ">text</" .. new .. ">",
    "tracked opening rename must update its mate")
end

local closing, closing_parser = buffer({ "<section>text</section>" })
api.nvim_win_set_cursor(0, { 1, #"<section>text</" + 1 })
tags.capture_pair({ buf = closing })
for _, names in ipairs({ { "section", "main" }, { "main", "section" } }) do
  local old, new = unpack(names)
  local source = line(closing, 0)
  local name_col = assert(source:find("</" .. old .. ">", 1, true)) + 1
  api.nvim_win_set_cursor(0, { 1, name_col + 1 })
  local parses = count_parses(closing_parser, function()
    tags.capture_pair({ buf = closing })
    api.nvim_buf_set_text(closing, 0, name_col, 0, name_col + #old, { new })
    tags.edit(closing, 0, name_col + #new, false)
  end)
  assert(parses == 0, "tracked closing rename must not reparse HTML")
  assert(line(closing, 0) == "<" .. new .. ">text</" .. new .. ">",
    "tracked closing rename must update its mate")
end

local unrelated, unrelated_parser = buffer({ "<section>text</section>" })
api.nvim_win_set_cursor(0, { 1, 2 })
tags.capture_pair({ buf = unrelated })
api.nvim_buf_set_text(unrelated, 0, #"<section>", 0, #"<section>", { "x" })
local fallback_parses = count_parses(unrelated_parser, function()
  api.nvim_buf_set_text(unrelated, 0, 1, 0, 8, { "article" })
  tags.edit(unrelated, 0, 8, false)
end)
assert(fallback_parses > 0, "unrelated edits must use parser-checked behavior")
assert(line(unrelated, 0) == "<article>xtext</article>",
  "fallback must preserve paired renaming")

local plain, plain_parser = buffer({ "<main>", "plain text", "</main>" })
local plain_parses = count_parses(plain_parser, function()
  api.nvim_buf_set_text(plain, 1, 5, 1, 5, { "x" })
  tags.edit(plain, 1, 6, true)
end)
assert(plain_parses == 0, "ordinary text input must not reparse HTML")
assert(line(plain, 1) == "plainx text", "ordinary text must remain unchanged")

local commented, commented_parser = buffer({ "<section></section>" })
api.nvim_win_set_cursor(0, { 1, 2 })
tags.capture_pair({ buf = commented })
api.nvim_buf_set_text(commented, 0, 0, 0, 0, { "<!-- " })
api.nvim_buf_set_text(commented, 0, #line(commented, 0), 0,
  #line(commented, 0), { " -->" })
local comment_parses = count_parses(commented_parser, function()
  api.nvim_buf_set_text(commented, 0, 6, 0, 13, { "article" })
  tags.edit(commented, 0, 13, false)
end)
assert(comment_parses > 0, "comment conversion must invalidate the fast path")
assert(line(commented, 0) == "<!-- <article></section> -->",
  "a tag inside a comment must not rename its former mate: " .. line(commented, 0))

local unavailable = buffer({ "<section></section>" })
api.nvim_win_set_cursor(0, { 1, 2 })
tags.capture_pair({ buf = unavailable })
api.nvim_buf_set_text(unavailable, 0, 1, 0, 8, { "article" })
local get_parser = vim.treesitter.get_parser
vim.treesitter.get_parser = function() error("parser unavailable") end
local ok, err = pcall(tags.edit, unavailable, 0, 8, false)
vim.treesitter.get_parser = get_parser
assert(ok, "missing parser must not raise an error: " .. tostring(err))
assert(line(unavailable, 0) == "<article></section>",
  "missing parser must not update a tracked mate")

print("Tracked rename fast path passed")
