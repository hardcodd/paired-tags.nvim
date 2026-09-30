vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:append(vim.env.PAIRED_TAGS_PARSER_RTP
  or (vim.fn.stdpath("data") .. "/lazy/nvim-treesitter"))
if vim.env.PAIRED_TAGS_TREESITTER_RTP then
  vim.opt.rtp:append(vim.env.PAIRED_TAGS_TREESITTER_RTP)
end
vim.cmd("filetype plugin indent on")
vim.treesitter.language.register("javascript", "javascriptreact")
vim.treesitter.language.register("tsx", "typescriptreact")
vim.o.shiftwidth = 2
vim.o.tabstop = 2
vim.o.expandtab = true
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "javascriptreact", "typescriptreact" },
  callback = function() vim.opt_local.iskeyword:append({ "$", "#" }) end,
})
require("paired_tags").setup()
