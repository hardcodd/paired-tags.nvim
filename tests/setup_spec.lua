local tags = require("paired_tags")

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true),
    "xt", false)
  vim.wait(30)
end

local function new_buffer(filetype, contents)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.bo.filetype = filetype
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { contents })
  return buf
end

local callbacks = vim.api.nvim_get_autocmds({ group = "PairedTags" })
assert(#callbacks > 0, "setup must register tag callbacks")
local original_paste = vim.paste
tags.setup()
assert(vim.paste == original_paste, "repeated setup must not wrap paste again")
assert(#vim.api.nvim_get_autocmds({ group = "PairedTags" }) == #callbacks,
  "repeated setup must not duplicate callbacks")
for _, key in ipairs({ ">", "{", "%", "#", "}", "<CR>" }) do
  local mapping = vim.fn.maparg(key, "i", false, true)
  assert(mapping.expr == 1 and mapping.silent == 1 and mapping.noremap == 1,
    "setup must install a silent nonrecursive expression mapping for " .. key)
end

new_buffer("text", "<div>")
vim.api.nvim_win_set_cursor(0, { 1, 5 })
feed("a><Esc>")
assert(vim.api.nvim_get_current_line() == "<div>>",
  "unsupported filetypes must keep literal greater-than input")

new_buffer("text", "<div></div>")
vim.api.nvim_win_set_cursor(0, { 1, 5 })
feed("i<CR><Esc>")
assert(vim.api.nvim_buf_line_count(0) == 2,
  "unsupported filetypes must keep native Enter")

local missing = new_buffer("html", "<div>")
local get_parser = vim.treesitter.get_parser
vim.treesitter.get_parser = function() error("parser unavailable") end
local ok, err = pcall(tags.edit, missing, 0, 5, true)
vim.treesitter.get_parser = get_parser
assert(ok, "missing parser must be harmless: " .. tostring(err))
assert(vim.api.nvim_get_current_line() == "<div>",
  "missing parser must preserve buffer text")

print("Standalone setup passed")
