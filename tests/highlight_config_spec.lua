vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:append(vim.env.PAIRED_TAGS_PARSER_RTP
  or (vim.fn.stdpath("data") .. "/lazy/nvim-treesitter"))
vim.cmd("filetype plugin indent on")
local tags = require("paired_tags")
for _, options in ipairs({
  { highlight = false },
  { highlight = { opening = "" } },
  { highlight = { closing = 12 } },
  { highlight = { extra = "Unexpected" } },
}) do
  assert(not pcall(tags.setup, options), "invalid highlight options accepted")
end
local has_group = pcall(vim.api.nvim_get_autocmds, { group = "PairedTags" })
assert(not has_group, "invalid setup registered handlers")

tags.setup({ highlight = { opening = "TestOpening", closing = "TestClosing" } })
local callbacks = #vim.api.nvim_get_autocmds({ group = "PairedTags" })
tags.setup({ highlight = { opening = "OtherOpening" } })
assert(#vim.api.nvim_get_autocmds({ group = "PairedTags" }) == callbacks,
  "repeated setup stacked callbacks")
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = "html"
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "<b>x</b>" })
vim.api.nvim_win_set_cursor(0, { 1, 2 })
tags.refresh_highlight({ buf = buf })
local marks = vim.api.nvim_buf_get_extmarks(buf,
  vim.api.nvim_get_namespaces().PairedTagHighlight, 0, -1, { details = true })
assert(#marks == 2 and marks[1][4].hl_group == "TestOpening"
  and marks[2][4].hl_group == "TestClosing",
  "custom groups or initial setup configuration lost")
print("Paired-tag highlight configuration passed")
