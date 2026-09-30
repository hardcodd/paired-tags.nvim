--- Install the parsers used by the standalone suites into an isolated path.
--- The pinned nvim-treesitter revision supplies exact grammar revisions.
local parser_rtp = assert(vim.env.PAIRED_TAGS_PARSER_RTP,
  "Set PAIRED_TAGS_PARSER_RTP to an empty parser installation directory")
local treesitter_rtp = assert(vim.env.PAIRED_TAGS_TREESITTER_RTP,
  "Set PAIRED_TAGS_TREESITTER_RTP to the pinned nvim-treesitter checkout")

vim.opt.rtp:append(treesitter_rtp)
local languages = {
  "html", "htmldjango", "jinja", "jinja_inline", "xml", "javascript",
  "tsx", "vue", "svelte", "markdown",
}
local installer = require("nvim-treesitter")
installer.setup({ install_dir = parser_rtp })
installer.install(languages):wait(300000)

for _, language in ipairs(languages) do
  local parser = parser_rtp .. "/parser/" .. language .. ".so"
  assert(vim.fn.filereadable(parser) == 1,
    language .. " parser was not installed at " .. parser)
  local ok, err = vim.treesitter.language.add(language, { path = parser })
  assert(ok, language .. " parser could not be loaded: " .. tostring(err))
end

print("CI parsers installed: " .. table.concat(languages, ", "))
