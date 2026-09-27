local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true),
    "xt", false)
  vim.wait(30)
end

local function check(filetype, width, expandtab, expected_indent)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.bo.filetype = filetype
  vim.bo.shiftwidth = width
  vim.bo.tabstop = width
  vim.bo.expandtab = expandtab
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "<div></div>" })
  vim.api.nvim_win_set_cursor(0, { 1, 5 })
  feed("i<CR>content<Esc>")
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false),
    { "<div>", expected_indent .. "content", "</div>" }),
    filetype .. " Enter must use the effective indentation options")
end

check("html", 2, true, "  ")
check("htmldjango", 6, true, "      ")
check("html", 4, false, "\t")

local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.bo.filetype = "html"
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "<div></span>" })
vim.api.nvim_win_set_cursor(0, { 1, 5 })
feed("i<CR><Esc>")
assert(vim.api.nvim_buf_line_count(buf) == 2,
  "nonmatching tags must retain one native Enter")

print("Standalone HTML Enter passed")
