local M = {}
local configured = false

local supported = {
  html = true, xml = true, htmldjango = true, javascriptreact = true,
  typescriptreact = true, vue = true, svelte = true, markdown = true,
}
local jsx_filetype = { javascriptreact = true, typescriptreact = true }
local opening = { start_tag = true, STag = true, jsx_opening_element = true }
local closing = { end_tag = true, erroneous_end_tag = true, ETag = true,
  jsx_closing_element = true }
local elements = {
  element = true, jsx_element = true, script_element = true,
  style_element = true,
}
local tag_identifier = "([%a_$\128-\255][%w:._$%-\128-\255]*)"
local html_void = {
  area = true, base = true, br = true, col = true, embed = true,
  hr = true, img = true, input = true, link = true, meta = true,
  param = true, source = true, track = true, wbr = true,
}
local html_syntax = { html = true, htmldjango = true, markdown = true }
local html_text_elements = {
  script = true, style = true, textarea = true, title = true,
  xmp = true, iframe = true, noembed = true, noframes = true,
}
local optional_on_open = {
  li = { li = true },
  dt = { dt = true, dd = true },
  dd = { dt = true, dd = true },
  p = { p = true, address = true, article = true, aside = true,
    blockquote = true, details = true, dialog = true, div = true,
    dl = true, fieldset = true, figcaption = true, figure = true,
    footer = true, form = true, h1 = true, h2 = true, h3 = true,
    h4 = true, h5 = true, h6 = true, header = true, hgroup = true,
    hr = true, main = true, menu = true, nav = true, ol = true, pre = true,
    search = true, section = true, table = true, ul = true },
  rt = { rt = true, rp = true },
  rp = { rt = true, rp = true },
  optgroup = { optgroup = true, hr = true },
  option = { option = true, optgroup = true, hr = true },
  thead = { tbody = true, tfoot = true },
  tbody = { tbody = true, tfoot = true },
  tr = { tr = true },
  td = { td = true, th = true },
  th = { td = true, th = true },
}
local optional_on_close = {
  li = { ul = true, ol = true, menu = true },
  dd = { dl = true },
  p = { address = true, article = true, aside = true, blockquote = true,
    body = true, div = true, fieldset = true, footer = true,
    form = true, header = true, hgroup = true, main = true,
    nav = true, section = true },
  rt = { ruby = true },
  rp = { ruby = true },
  option = { optgroup = true, select = true, datalist = true },
  optgroup = { select = true },
  tbody = { table = true },
  tfoot = { table = true },
  tr = { tbody = true, thead = true, tfoot = true, table = true },
  td = { tr = true, tbody = true, thead = true, tfoot = true, table = true },
  th = { tr = true, tbody = true, thead = true, tfoot = true, table = true },
}
local changing = {} ---@type table<integer, boolean>
local streaming_paste = {} ---@type table<integer, boolean>
local pending_namespace = vim.api.nvim_create_namespace("PairedTagInput")
local tracked_namespace = vim.api.nvim_create_namespace("PairedTagRename")
local key_namespace = vim.api.nvim_create_namespace("PairedTagBeforeEdit")
local normal_edit_keys = {
  c = true, r = true, s = true, x = true, d = true, p = true, P = true,
}

---@class PendingTag
---@field opener integer
---@field ancestor_closers integer[]
local pending = {} ---@type table<integer, PendingTag[]>

---@class TrackedPair
---@field source integer
---@field mate integer
---@field source_closing boolean
---@field mate_closing boolean
local tracked = {} ---@type table<integer, TrackedPair>

---@class TagName
---@field row integer
---@field first integer
---@field last integer
---@field text string

--- Return the name and buffer range of one Tree-sitter tag node.
---@param buf integer
---@param node TSNode
---@param is_closing boolean
---@return TagName?
local function tag_name(buf, node, is_closing)
  local row, column = node:range()
  local source = vim.treesitter.get_node_text(node, buf)
  local text
  if is_closing then
    text = source:match("^</%s*" .. tag_identifier)
  else
    text = source:match("^<%s*" .. tag_identifier)
  end
  if not text then return nil end
  local prefix = source:match(is_closing and "^</%s*" or "^<%s*")
  local start_col = column + #prefix
  return { row = row, first = start_col, last = start_col + #text, text = text }
end

--- Check the parser's final delimiter, excluding `>` inside attributes or types.
---@param node TSNode
---@return boolean
local function completed_tag(node)
  local _, _, end_row, end_col = node:range()
  for child in node:iter_children() do
    if child:type() == ">" or child:type() == "/>" then
      local child_row, child_col, child_end_row, child_end_col = child:range()
      if (child_row ~= child_end_row or child_col ~= child_end_col)
        and child_end_row == end_row and child_end_col == end_col then
        return true
      end
    end
  end
  return false
end

---@param buf integer
---@param name string
---@return boolean
local function is_void(buf, name)
  if vim.bo[buf].filetype == "xml" then return false end
  if html_syntax[vim.bo[buf].filetype] then return html_void[name:lower()] == true end
  return name == name:lower() and html_void[name] == true
end

--- Distinguish a self-closing delimiter from `/` in an unquoted attribute.
---@param source string
---@param name string
---@return boolean
local function self_closing_tag(source, name)
  local slash = source:match("()%/%s*>$")
  if not slash then return false end
  local before = source:sub(1, slash - 1)
  if before:match("%s$") or before:match("[\"'}>]$") then return true end
  return before:match("^<%s*" .. tag_identifier .. "$") == name
end

---@param node TSNode
---@return TSNode?, TSNode?
local function element_tags(node)
  local parent = node:parent()
  while parent and not elements[parent:type()] do
    parent = parent:parent()
  end
  if not parent then return nil, nil end
  local start_tag, end_tag ---@type TSNode?, TSNode?
  for child in parent:iter_children() do
    if opening[child:type()] then start_tag = child end
    if closing[child:type()] then end_tag = child end
  end
  return start_tag, end_tag
end

---@param buf integer
---@param record PendingTag
local function release_pending(buf, record)
  pcall(vim.api.nvim_buf_del_extmark, buf, pending_namespace, record.opener)
  for _, mark in ipairs(record.ancestor_closers) do
    pcall(vim.api.nvim_buf_del_extmark, buf, pending_namespace, mark)
  end
end

--- Remember which closing tags belonged to ancestors before a new `<`.
--- Parser recovery after insertion cannot distinguish a new same-name child
--- from the ancestor that already owns the next closing tag.
---@param event vim.api.keyset.create_autocmd.callback_args
---@return nil
function M.before_char(event)
  if vim.v.char ~= "<" or vim.bo[event.buf].buftype ~= ""
    or not supported[vim.bo[event.buf].filetype] then return end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local available, parser = pcall(vim.treesitter.get_parser, event.buf)
  if not available or not parser or not pcall(function()
    parser:parse({ row - 1, 0, row - 1, col + 1 })
  end) then return end
  local node = vim.treesitter.get_node({ bufnr = event.buf,
    pos = { row - 1, math.max(0, col - 1) }, ignore_injections = false })
  local closers = {} ---@type integer[]
  while node do
    if elements[node:type()] then
      for child in node:iter_children() do
        if closing[child:type()] then
          local end_row, end_col = child:range()
          closers[#closers + 1] = vim.api.nvim_buf_set_extmark(event.buf,
            pending_namespace, end_row, end_col, { right_gravity = true })
        end
      end
    end
    node = node:parent()
  end
  local records = pending[event.buf] or {} ---@type PendingTag[]
  if #records >= 64 then release_pending(event.buf, table.remove(records, 1)) end
  records[#records + 1] = {
    opener = vim.api.nvim_buf_set_extmark(event.buf, pending_namespace,
      row - 1, col, { right_gravity = false }),
    ancestor_closers = closers,
  }
  pending[event.buf] = records
end

--- Discard input snapshots when an Insert session or buffer ends.
---@param event vim.api.keyset.create_autocmd.callback_args
---@return nil
function M.clear_pending(event)
  for _, record in ipairs(pending[event.buf] or {}) do
    release_pending(event.buf, record)
  end
  pending[event.buf] = nil
end

---@param buf integer
---@param tag TSNode
---@return PendingTag?, integer?
local function pending_for(buf, tag)
  local row, col = tag:range()
  local records = pending[buf] or {}
  for index = #records, 1, -1 do
    local position = vim.api.nvim_buf_get_extmark_by_id(buf,
      pending_namespace, records[index].opener, {})
    if position[1] == row and position[2] == col then
      return records[index], index
    end
  end
end

---@param buf integer
---@param record PendingTag
---@param mate TagName
---@return boolean
local function belongs_to_ancestor(buf, record, mate)
  for _, mark in ipairs(record.ancestor_closers) do
    local position = vim.api.nvim_buf_get_extmark_by_id(buf,
      pending_namespace, mark, {})
    if position[1] == mate.row and position[2] == mate.first - 2 then
      return true
    end
  end
  return false
end

--- Detect a same-name ancestor left without a closer by parser recovery.
---@param buf integer
---@param tag TSNode
---@param name string
---@return boolean
local function unclosed_same_name_ancestor(buf, tag, name)
  local parent = tag:parent()
  while parent do
    local start_tag, end_tag ---@type TSNode?, TSNode?
    for child in parent:iter_children() do
      if opening[child:type()] then start_tag = child end
      if closing[child:type()] then end_tag = child end
    end
    local ancestor = start_tag and tag_name(buf, start_tag, false)
    local equal = ancestor and (html_syntax[vim.bo[buf].filetype]
      and ancestor.text:lower() == name:lower() or ancestor.text == name)
    if equal and not end_tag then
      return true
    end
    parent = parent:parent()
  end
  return false
end

---@param buf integer
---@param row integer
---@param col integer
---@return boolean
local function inside_literal(buf, row, col)
  local node = vim.treesitter.get_node({ bufnr = buf, pos = { row, col },
    ignore_injections = false })
  while node do
    local kind = node:type()
    if kind == "string" or kind == "string_fragment"
      or kind == "template_string" or kind == "comment"
      or kind == "CData" or kind == "PI" or kind == "EntityValue"
      or kind == "unpaired_comment" or kind == "paired_comment" then
      return true
    end
    node = node:parent()
  end
  return false
end

--- Parser recovery can expose a new tag inside an unfinished XML instruction.
---@param buf integer
---@param row integer
---@param col integer
---@return boolean
local function inside_xml_processing_instruction(buf, row, col)
  if vim.bo[buf].filetype ~= "xml" then return false end
  local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
  if cursor_row - 1 == row and cursor_col >= col then
    local opener = vim.fn.searchpos("\\V<?", "bnW")
    if opener[1] == 0 or (opener[1] - 1 == row and opener[2] - 1 > col) then
      return false
    end
    local closer = vim.fn.searchpos("\\V?>", "bnW")
    if closer[1] > opener[1] or (closer[1] == opener[1]
      and closer[2] > opener[2]) then return false end
    return not inside_literal(buf, opener[1] - 1, opener[2] - 1)
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, row + 1, false)
  for scan_row = row, 0, -1 do
    local source = lines[scan_row + 1]
    local limit = scan_row == row and math.min(col + 1, #source) or #source
    for index = limit - 1, 1, -1 do
      local marker = source:sub(index, index + 1)
      if marker == "?>" then return false end
      if marker == "<?" then
        return not inside_literal(buf, scan_row, index - 1)
      end
    end
  end
  return false
end

--- A raw CSS text node can be reparsed as apparent markup during a rename.
---@param buf integer
---@param row integer
---@param col integer
---@return boolean
local function inside_style_text(buf, row, col)
  if not html_syntax[vim.bo[buf].filetype] then return false end
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  local left = line:sub(1, col + 1):match(".*()<")
  if not left or line:sub(left + 1, left + 1) == "/" then return false end
  local node = vim.treesitter.get_node({ bufnr = buf, pos = { row, col },
    ignore_injections = true })
  while node do
    if node:type() == "raw_text" and node:parent()
      and node:parent():type() == "style_element" then return true end
    node = node:parent()
  end
  return false
end

--- Scan JavaScript after a Vue interpolation opener, preserving quote state
--- across lines while ignoring comment and regular-expression delimiters.
---@param lines string[]
---@param first_row integer Zero-based row of the interpolation opener.
---@param first_col integer One-based byte column of the opener.
---@param row integer Zero-based row of the edited name.
---@param col integer Zero-based byte column of the edited name.
---@param base_row integer Zero-based row represented by lines[1].
---@return boolean in_string
---@return boolean closed
local function scan_vue_interpolation(lines, first_row, first_col, row, col,
    base_row)
  local quote ---@type string?
  local block_comment = false
  local regex = false
  local regex_class = false
  local regex_allowed = true
  local braces = 0
  for scan_row = first_row, row do
    local source = lines[scan_row - base_row + 1]
    local index = scan_row == first_row and first_col + 2 or 1
    local limit = scan_row == row and math.min(col + 1, #source) or #source
    local line_comment = false
    while index <= limit do
      local char = source:sub(index, index)
      local next_char = source:sub(index + 1, index + 1)
      if line_comment then
        break
      elseif block_comment then
        if char == "*" and next_char == "/" then
          block_comment = false
          index = index + 1
        end
      elseif quote then
        if char == "\\" then
          index = index + 1
        elseif char == quote then
          quote = nil
          regex_allowed = false
        end
      elseif regex then
        if char == "\\" then
          index = index + 1
        elseif char == "[" then
          regex_class = true
        elseif char == "]" then
          regex_class = false
        elseif char == "/" and not regex_class then
          regex = false
          regex_allowed = false
        end
      elseif char == "/" and next_char == "*" then
        block_comment = true
        index = index + 1
      elseif char == "/" and next_char == "/" then
        line_comment = true
      elseif char == "/" and regex_allowed then
        regex = true
      elseif char == '"' or char == "'" or char == "`" then
        quote = char
      elseif char == "{" then
        braces = braces + 1
        regex_allowed = true
      elseif char == "}" then
        if braces == 0 and next_char == "}" then return false, true end
        braces = math.max(0, braces - 1)
        regex_allowed = false
      elseif char:match("[%w_$]") or char == ")" or char == "]"
        or char == "." then
        regex_allowed = false
      elseif not char:match("%s") then
        regex_allowed = true
      end
      index = index + 1
    end
  end
  return quote ~= nil, false
end

--- Vue may recover an apparent tag inside an interpolation as markup.
---@param buf integer
---@param row integer
---@param col integer
---@return boolean
local function inside_vue_interpolation_string(buf, row, col)
  if vim.bo[buf].filetype ~= "vue" then return false end
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  if not line:sub(1, col + 1):find("<", 1, true) then return false end
  local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
  local nearest_row, nearest_col
  if cursor_row - 1 == row and cursor_col >= col then
    local found = vim.fn.searchpos("\\V{{", "bnW")
    if found[1] > 0 and (found[1] - 1 < row
      or found[2] - 1 <= col) then
      nearest_row, nearest_col = found[1] - 1, found[2]
    else
      return false
    end
  end
  local closed_candidate = false
  if nearest_row then
    local lines = vim.api.nvim_buf_get_lines(buf, nearest_row, row + 1, false)
    if not inside_literal(buf, nearest_row, nearest_col - 1) then
      local in_string, closed = scan_vue_interpolation(lines, nearest_row,
        nearest_col, row, col, nearest_row)
      if in_string then return true end
      closed_candidate = closed
    end
  end
  local previous_row = nearest_row or row
  local previous_col = nearest_col and nearest_col - 1 or col + 1
  local previous_lines = vim.api.nvim_buf_get_lines(buf, 0,
    previous_row + 1, false)
  for scan_row = previous_row, 0, -1 do
    local source = previous_lines[scan_row + 1]
    local limit = scan_row == previous_row and previous_col or #source
    while true do
      local first = source:sub(1, limit):match(".*(){{")
      if not first then break end
      if not inside_literal(buf, scan_row, first - 1) then
        local scan_lines = vim.api.nvim_buf_get_lines(buf, scan_row,
          row + 1, false)
        local in_string, closed = scan_vue_interpolation(scan_lines, scan_row,
          first, row, col, scan_row)
        if in_string then return true end
        if closed then
          if closed_candidate then return false end
          closed_candidate = true
        end
      end
      limit = first - 1
    end
  end
  return false
end

--- Check the host Markdown tree before entering any injected HTML tree.
---@param buf integer
---@param row integer
---@param col integer
---@return boolean
local function inside_markdown_code(buf, row, col)
  if vim.bo[buf].filetype ~= "markdown" then return false end
  local node = vim.treesitter.get_node({ bufnr = buf, pos = { row, col },
    ignore_injections = true })
  while node do
    if node:type() == "fenced_code_block" or node:type() == "indented_code_block"
      or node:type() == "code_span" then return true end
    node = node:parent()
  end
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  local index = 1
  local opening_length ---@type integer?
  local opening_end ---@type integer?
  while true do
    local first, last = line:find("`+", index)
    if not first then break end
    local escapes = 0
    for previous = first - 1, 1, -1 do
      if line:sub(previous, previous) ~= "\\" then break end
      escapes = escapes + 1
    end
    if escapes % 2 == 0 then
      local length = last - first + 1
      if not opening_length then
        opening_length, opening_end = length, last
      elseif length == opening_length then
        if col + 1 > opening_end and col + 1 < first then return true end
        opening_length, opening_end = nil, nil
      end
    end
    index = last + 1
  end
  return false
end

--- Scan tag delimiters independently of parser error recovery during renames.
--- A mismatched name can make HTML's parser reparent nested closing tags.
---@param buf integer
---@param first_row integer Zero-based first row to inspect.
---@param last_row integer? Exclusive last row, or the end of the buffer.
---@param visit fun(name: TagName, is_closing: boolean, self_closing: boolean): boolean?
local function scan_tags(buf, first_row, last_row, visit)
  local lines = vim.api.nvim_buf_get_lines(buf, first_row, last_row or -1, false)
  local row, col = 1, 1
  local raw_text ---@type string?
  while row <= #lines do
    local line = lines[row]
    local left = line:find("<", col, true)
    if not left then
      row, col = row + 1, 1
    elseif raw_text and not line:sub(left):lower():match("^</" .. raw_text .. "[%s>]") then
      col = left + 1
    elseif line:sub(left, left + 3) == "<!--"
      or line:sub(left, left + 8) == "<![CDATA[" then
      local comment = line:sub(left, left + 3) == "<!--"
      local marker = comment and "-->" or "]]>"
      local finish = line:find(marker, left + (comment and 4 or 9), true)
      while not finish and row < #lines do
        row = row + 1
        line = lines[row]
        finish = line:find(marker, 1, true)
      end
      col = finish and finish + #marker or #line + 1
    else
      local tail = line:sub(left)
      local slash, text ---@type string?, string?
      if jsx_filetype[vim.bo[buf].filetype] and tail:sub(1, 2) == "<>" then
        slash, text = "", ""
      elseif jsx_filetype[vim.bo[buf].filetype] and tail:sub(1, 3) == "</>" then
        slash, text = "/", ""
      else
        slash, text = tail:match("^<(/?)" .. tag_identifier)
      end
      if not text or inside_literal(buf, first_row + row - 1, left - 1) then
        col = left + 1
      else
        local name = { row = first_row + row - 1, first = left + #slash,
          last = left + #slash + #text, text = text }
        local quote ---@type string?
        local braces = 0
        local scan_row, scan_col = row, left + 1 + #slash + #text
        local found, interrupted = false, false
        while scan_row <= #lines and not found and not interrupted do
          local source = lines[scan_row]
          while scan_col <= #source do
            local char = source:sub(scan_col, scan_col)
            if quote then
              if char == quote and (braces == 0
                or source:sub(scan_col - 1, scan_col - 1) ~= "\\") then
                quote = nil
              end
            elseif char == "'" or char == '"' or (braces > 0 and char == "`") then
              quote = char
            elseif char == "{" then
              braces = braces + 1
            elseif char == "}" and braces > 0 then
              braces = braces - 1
            elseif braces == 0 and char == "<" then
              interrupted = true
              break
            elseif braces == 0 and char == ">" then
              found = true
              break
            end
            scan_col = scan_col + 1
          end
          if not found and not interrupted then scan_row, scan_col = scan_row + 1, 1 end
        end
        if interrupted then
          row, col = scan_row, scan_col
        elseif found then
          local parts = { lines[row]:sub(left) }
          if scan_row == row then
            parts[1] = lines[row]:sub(left, scan_col)
          else
            for middle = row + 1, scan_row - 1 do
              parts[#parts + 1] = lines[middle]
            end
            parts[#parts + 1] = lines[scan_row]:sub(1, scan_col)
          end
          if visit(name, slash == "/",
              self_closing_tag(table.concat(parts, "\n"), name.text)) then return end
          if slash == "/" and raw_text == name.text:lower() then
            raw_text = nil
          elseif slash == "" then
            local lower = name.text:lower()
            local filetype = vim.bo[buf].filetype
            if (html_syntax[filetype] and html_text_elements[lower])
              or ((filetype == "vue" or filetype == "svelte")
                and (lower == "script" or lower == "style")) then
              raw_text = lower
            end
          end
          row, col = scan_row, scan_col + 1
        else
          row, col = #lines + 1, 1
        end
      end
    end
  end
end

---@param buf integer
---@param tag_row integer
---@param tag_col integer
---@param current_is_closing boolean
---@param first_row integer
---@return TagName?
local function lexical_mate_at(buf, tag_row, tag_col,
    current_is_closing, first_row)
  local stack = {} ---@type TagName[]
  local found = false
  local mate ---@type TagName?
  local html_syntax = vim.bo[buf].filetype == "html"
    or vim.bo[buf].filetype == "htmldjango"
    or vim.bo[buf].filetype == "markdown"
  local function implied_by_start(name)
    if not html_syntax then return end
    local top = stack[#stack]
    while top and optional_on_open[top.text:lower()]
      and optional_on_open[top.text:lower()][name.text:lower()] do
      table.remove(stack)
      top = stack[#stack]
    end
  end
  local function implied_by_end(name)
    if not html_syntax then return end
    local top = stack[#stack]
    -- In a closing-side rename, the last opener may be the explicit mate
    -- currently being renamed; only descendants can end implicitly.
    local minimum = current_is_closing and 2 or 1
    while #stack >= minimum and top and optional_on_close[top.text:lower()]
      and optional_on_close[top.text:lower()][name.text:lower()] do
      table.remove(stack)
      top = stack[#stack]
    end
  end
  scan_tags(buf, first_row, current_is_closing and tag_row + 1 or nil,
    function(name, is_closing, self_closing)
      local current = name.row == tag_row and name.first == tag_col + (is_closing and 2 or 1)
      if current_is_closing then
        if is_closing then
          implied_by_end(name)
          local opener = table.remove(stack)
          if current then mate = opener; return true end
        elseif not self_closing and not is_void(buf, name.text) then
          implied_by_start(name)
          stack[#stack + 1] = name
        end
      elseif current then
        found = true
      elseif found then
        if is_closing then
          implied_by_end(name)
          if #stack == 0 then mate = name; return true end
          table.remove(stack)
        elseif not self_closing and not is_void(buf, name.text) then
          implied_by_start(name)
          stack[#stack + 1] = name
        end
      end
    end)
  return mate
end

---@param buf integer
---@param tag TSNode
---@return TagName?
local function lexical_mate(buf, tag)
  local tag_row, tag_col = tag:range()
  local current_is_closing = closing[tag:type()] == true
  local first_row = tag_row
  if current_is_closing then
    local start_tag = element_tags(tag)
    first_row = start_tag and select(1, start_tag:range()) or 0
  end
  return lexical_mate_at(buf, tag_row, tag_col,
    current_is_closing, first_row)
end

---@param buf integer
---@param left string
---@param right string
---@return boolean
local function same_name(buf, left, right)
  local filetype = vim.bo[buf].filetype
  if filetype == "html" or filetype == "htmldjango" or filetype == "markdown" then
    return left:lower() == right:lower()
  end
  return left == right
end

---@param buf integer
---@param row integer
---@param col integer
---@return TSNode?
local function tag_at(buf, row, col)
  if col < 0 then return nil end
  local node = vim.treesitter.get_node({ bufnr = buf, pos = { row, col },
    ignore_injections = false })
  while node do
    if opening[node:type()] or closing[node:type()] then return node end
    node = node:parent()
  end
end

--- Skip apparent tags in HTML text-only elements, but keep their real closers.
---@param buf integer
---@param tag TSNode
---@return boolean
local function inside_html_text_ancestor(buf, tag)
  if not html_syntax[vim.bo[buf].filetype] then return false end
  local row, col = tag:range()
  local host = vim.treesitter.get_node({ bufnr = buf, pos = { row, col },
    ignore_injections = true })
  while host do
    if host:type() == "raw_text" then return true end
    host = host:parent()
  end
  local parent = tag:parent()
  while parent do
    local start_tag ---@type TSNode?
    local own_closer = false
    for child in parent:iter_children() do
      if opening[child:type()] then start_tag = child end
      if closing[tag:type()] and child == tag then own_closer = true end
    end
    if start_tag and start_tag ~= tag then
      local name = tag_name(buf, start_tag, false)
      if name and html_text_elements[name.text:lower()] and not own_closer then
        return true
      end
    end
    parent = parent:parent()
  end
  return false
end

---@param buf integer
---@param row integer
---@param col integer
---@return TagName?, integer?
local function closing_name_at(buf, row, col)
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  local search = 1
  while true do
    local first, last, text = line:find("</%s*" .. tag_identifier .. "%s*>",
      search)
    if not first then return nil end
    local prefix = line:sub(first, last):match("^</%s*")
    local name_first = first - 1 + #prefix
    if col >= name_first and col < name_first + #text then
      return { row = row, first = name_first,
        last = name_first + #text, text = text }, first - 1
    end
    search = last + 1
  end
end

--- Recover an opening name when the parser temporarily rejects markup.
---@param buf integer
---@param row integer
---@param col integer
---@return TagName?, integer?
local function opening_name_at(buf, row, col)
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  local search = 1
  while true do
    local first, last, text = line:find("<%s*" .. tag_identifier .. "[%s/>]",
      search)
    if not first then return nil end
    local prefix = line:sub(first, last):match("^<%s*")
    local name_first = first - 1 + #prefix
    if col >= name_first and col <= name_first + #text then
      return { row = row, first = name_first,
        last = name_first + #text, text = text }, first - 1
    end
    search = last + 1
  end
end

---@param buf integer
local function release_tracked(buf)
  local pair = tracked[buf]
  if not pair then return end
  pcall(vim.api.nvim_buf_del_extmark, buf, tracked_namespace, pair.source)
  pcall(vim.api.nvim_buf_del_extmark, buf, tracked_namespace, pair.mate)
  tracked[buf] = nil
end

---@param buf integer
---@param mark integer
---@param is_closing boolean
---@return TagName?
local function marked_name(buf, mark, is_closing)
  local position = vim.api.nvim_buf_get_extmark_by_id(buf, tracked_namespace,
    mark, {})
  if #position == 0 then return nil end
  local row, col = unpack(position)
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  local prefix = is_closing and "</%s*$" or "<%s*$"
  if not line:sub(1, col):match(prefix) then return nil end
  local text = line:sub(col + 1):match("^" .. tag_identifier)
  if not text then return nil end
  return { row = row, first = col, last = col + #text, text = text }
end

--- Remember the original pair before a rename can disrupt the parser tree.
---@param event vim.api.keyset.create_autocmd.callback_args
---@return nil
function M.capture_pair(event)
  local buf = event.buf
  if vim.api.nvim_get_current_buf() ~= buf or vim.bo[buf].buftype ~= ""
    or not supported[vim.bo[buf].filetype] then return end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  row = row - 1
  local pair = tracked[buf]
  local current = pair and marked_name(buf, pair.source, pair.source_closing)
  if current and current.row == row and col >= current.first
    and col <= current.last then return end
  if pair and not current then
    local position = vim.api.nvim_buf_get_extmark_by_id(buf,
      tracked_namespace, pair.source, {})
    if position[1] == row and col >= position[2] - 1
      and col <= position[2] then
      local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
      local prefix = pair.source_closing and "</%s*$" or "<%s*$"
      local next_char = line:sub(position[2] + 1, position[2] + 1)
      if line:sub(1, position[2]):match(prefix)
        and (next_char == "" or next_char:match("[%s>]") ~= nil) then
        return
      end
    end
  end
  release_tracked(buf)
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  if not line:sub(col + 1, col + 1):match("[%w:._$%-\128-\255]")
    and not line:sub(col, col):match("[%w:._$%-\128-\255]") then
    return
  end
  local before = line:sub(1, col)
  local left = before:match(".*()<")
  local right = before:match(".*()>")
  if not left or (right and right > left) then return end
  local available, parser = pcall(vim.treesitter.get_parser, buf)
  if not available or not parser
    or not pcall(function() parser:parse({ row, 0, row, col + 1 }) end) then
    return
  end
  if inside_markdown_code(buf, row, col)
    or inside_vue_interpolation_string(buf, row, col)
    or inside_xml_processing_instruction(buf, row, col)
    or inside_style_text(buf, row, col) then return end
  local tag = tag_at(buf, row, col)
  local is_closing = true
  local source ---@type TagName?
  local mate_name ---@type TagName?
  if tag then
    if inside_html_text_ancestor(buf, tag) then return end
    is_closing = closing[tag:type()] == true
    source = tag_name(buf, tag, is_closing)
    if not source or col < source.first or col > source.last then return end
    local start_tag, end_tag = element_tags(tag)
    local mate = is_closing and start_tag or end_tag
    mate_name = mate and tag_name(buf, mate, not is_closing)
    if mate_name and not same_name(buf, mate_name.text, source.text) then
      mate_name = nil
    end
    if not mate_name then
      local tag_row, tag_col = tag:range()
      mate_name = lexical_mate_at(buf, tag_row, tag_col, is_closing,
        is_closing and 0 or tag_row)
    end
  else
    local tag_col
    source, tag_col = closing_name_at(buf, row, col)
    if not source then
      is_closing = false
      source, tag_col = opening_name_at(buf, row, col)
    end
    if not source or inside_literal(buf, row, tag_col) then return end
    mate_name = lexical_mate_at(buf, row, tag_col, is_closing,
      is_closing and 0 or row)
    if mate_name and not same_name(buf, mate_name.text, source.text) then
      mate_name = nil
    end
  end
  if not mate_name then return end
  tracked[buf] = {
    source = vim.api.nvim_buf_set_extmark(buf, tracked_namespace,
      source.row, source.first, { right_gravity = false }),
    mate = vim.api.nvim_buf_set_extmark(buf, tracked_namespace,
      mate_name.row, mate_name.first, { right_gravity = false }),
    source_closing = is_closing,
    mate_closing = not is_closing,
  }
end

--- Apply a rename to the mate held at its original buffer position.
---@param buf integer
---@param row integer
---@param col integer
---@return boolean
local function rename_tracked(buf, row, col)
  local pair = tracked[buf]
  if not pair then return false end
  local source = marked_name(buf, pair.source, pair.source_closing)
  if not source or source.row ~= row or col < source.first
    or col > source.last then return false end
  local mate = marked_name(buf, pair.mate, pair.mate_closing)
  if not mate then
    release_tracked(buf)
    return false
  end
  if mate.text ~= source.text then
    changing[buf] = true
    vim.api.nvim_buf_set_text(buf, mate.row, mate.first,
      mate.row, mate.last, { source.text })
    changing[buf] = nil
  end
  return true
end

---@param event vim.api.keyset.create_autocmd.callback_args
---@return nil
function M.clear_tracked(event)
  release_tracked(event.buf)
end

--- Capture a pair before Normal or Insert input can alter its name.
---@param key string
---@return nil
function M.before_key(key)
  local mode = vim.api.nvim_get_mode().mode
  if (mode == "n" and normal_edit_keys[key]) or mode:sub(1, 1) == "i" then
    M.capture_pair({ buf = vim.api.nvim_get_current_buf() })
  end
end

--- Keep closing-tag-like text inside raw script/style quotes and comments literal.
---@param buf integer
---@param start_row integer
---@param start_col integer
---@param end_row integer
---@param end_col integer
---@param script boolean
---@return boolean
local function inside_raw_text_literal(buf, start_row, start_col,
    end_row, end_col, script)
  local lines = vim.api.nvim_buf_get_text(buf, start_row, start_col,
    end_row, end_col, {})
  local quote ---@type string?
  local block_comment = false
  local line_comment = false
  for _, line in ipairs(lines) do
    line_comment = false
    local index = 1
    while index <= #line do
      local char = line:sub(index, index)
      local next_char = line:sub(index + 1, index + 1)
      if line_comment then
        break
      elseif block_comment then
        if char == "*" and next_char == "/" then
          block_comment = false
          index = index + 1
        end
      elseif quote then
        if char == "\\" then
          index = index + 1
        elseif char == quote then
          quote = nil
        end
      elseif char == '"' or char == "'" or (script and char == "`") then
        quote = char
      elseif char == "/" and next_char == "*" then
        block_comment = true
        index = index + 1
      elseif script and char == "/" and next_char == "/" then
        line_comment = true
      end
      index = index + 1
    end
  end
  return quote ~= nil or block_comment or line_comment
end

--- Recover a raw-text closer after its edited name makes HTML parse it as text.
--- A still-valid original closer would place the text under an element node.
---@param buf integer
---@param row integer
---@param col integer
---@return boolean
local function rename_raw_text_closer(buf, row, col)
  if col == 0 then return false end
  local node = vim.treesitter.get_node({ bufnr = buf, pos = { row, col - 1 },
    ignore_injections = false })
  while node and node:type() ~= "raw_text" do node = node:parent() end
  if not node then return false end
  local parent = node:parent()
  if not parent or parent:type() ~= "ERROR" then return false end
  local opener ---@type TSNode?
  for child in parent:iter_children() do
    if opening[child:type()] then opener = child end
    if closing[child:type()] then return false end
  end
  local source = opener and tag_name(buf, opener, false)
  if not source or (source.text:lower() ~= "script"
    and source.text:lower() ~= "style") then return false end

  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  local search = 1
  while true do
    local first, last, name = line:find("</%s*" .. tag_identifier .. "%s*>", search)
    if not first then return false end
    local prefix = line:sub(first, last):match("^</%s*")
    local name_first = first - 1 + #prefix
    if col >= name_first and col <= name_first + #name then
      local _, _, start_row, start_col = opener:range()
      if inside_raw_text_literal(buf, start_row, start_col, row, first - 1,
          source.text:lower() == "script") then return false end
      if source.text ~= name then
        changing[buf] = true
        vim.api.nvim_buf_set_text(buf, source.row, source.first,
          source.row, source.last, { name })
        changing[buf] = nil
      end
      return true
    end
    search = last + 1
  end
end

---@param buf integer
---@param row integer
---@param col integer
---@return boolean
local function rename(buf, row, col)
  for _, offset in ipairs({ -1, 0 }) do
    local tag = tag_at(buf, row, col + offset)
    if tag then
      -- An unfinished new tag has no mate; parser recovery may place it
      -- under a parent whose closing tag belongs to another element.
      if not completed_tag(tag) then
        return false
      end
      local source = tag_name(buf, tag, closing[tag:type()] == true)
      if source and source.row == row and col >= source.first and col <= source.last then
        local start_tag, end_tag = element_tags(tag)
        local direct = tag == start_tag and end_tag or tag == end_tag and start_tag
        local direct_name = direct and tag_name(buf, direct, closing[direct:type()] == true)
        if direct_name and direct_name.text == source.text then return true end
        local target = lexical_mate(buf, tag)
        -- HTML may omit a child's end tag (for example consecutive li or p).
        -- In that valid syntax the lexical depth does not reach the parent's
        -- closer, while Tree-sitter still has an explicit direct pair.
        if not target and direct_name then target = direct_name end
        if target and target.text ~= source.text then
          changing[buf] = true
          vim.api.nvim_buf_set_text(buf, target.row, target.first,
            target.row, target.last, { source.text })
          changing[buf] = nil
        end
        return true
      end
    end
  end
  return rename_raw_text_closer(buf, row, col)
end

---@param buf integer
---@param row integer
---@param col integer
local function close_tag(buf, row, col)
  if col == 0 then return end
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  if line:sub(col, col) ~= ">" then return end
  local tag = tag_at(buf, row, col - 1)
  if not tag or not opening[tag:type()] then return end
  if inside_html_text_ancestor(buf, tag) then return end
  local _, _, end_row, end_col = tag:range()
  if end_row ~= row or end_col ~= col then return end
  local tag_text = vim.treesitter.get_node_text(tag, buf)
  if not completed_tag(tag) then return end
  local fragment = jsx_filetype[vim.bo[buf].filetype] and tag_text == "<>"
  local name = fragment and { text = "" } or tag_name(buf, tag, false)
  if not name then return end
  if self_closing_tag(tag_text, name.text) then return end
  if is_void(buf, name.text) then return end
  local _, direct_closer = element_tags(tag)
  local existing = direct_closer and tag_name(buf, direct_closer, true)
    or lexical_mate(buf, tag)
  local record, index = pending_for(buf, tag)
  local inherited = existing and record
    and belongs_to_ancestor(buf, record, existing)
  if existing and same_name(buf, existing.text, name.text)
    and unclosed_same_name_ancestor(buf, tag, name.text) then
    inherited = true
  end
  if record then
    table.remove(pending[buf], index)
    release_pending(buf, record)
  end
  if existing and same_name(buf, existing.text, name.text) and not inherited then
    return
  end
  changing[buf] = true
  vim.api.nvim_buf_set_text(buf, row, col, row, col,
    { "</" .. name.text .. ">" })
  changing[buf] = nil
end

--- Update the tag at a byte position after an edit; autoclose on a typed `>`.
---@param buf integer
---@param row integer Zero-based row of the edit.
---@param col integer Byte position immediately after the edit.
---@param autoclose boolean Whether a just-typed `>` may create a closing tag.
---@return nil
function M.edit(buf, row, col, autoclose)
  if changing[buf] or vim.bo[buf].buftype ~= ""
    or not supported[vim.bo[buf].filetype] or streaming_paste[buf] then return end
  local available, parser = pcall(vim.treesitter.get_parser, buf)
  if not available or not parser then return end
  local ok = pcall(function() parser:parse({ row, 0, row, col + 1 }) end)
  if not ok then return end
  if inside_markdown_code(buf, row, math.max(0, col - 1)) then return end
  if inside_vue_interpolation_string(buf, row, math.max(0, col - 1)) then return end
  if inside_xml_processing_instruction(buf, row, math.max(0, col - 1)) then return end
  if inside_style_text(buf, row, math.max(0, col - 1)) then return end
  if rename_tracked(buf, row, col) then return end
  local tag = tag_at(buf, row, math.max(0, col - 1))
  if tag and inside_html_text_ancestor(buf, tag) then return end
  if rename(buf, row, col) then return end
  if autoclose then close_tag(buf, row, col) end
end

--- Complete a typed opening tag before the next Insert key is processed.
--- TextChangedI can coalesce rapid input, so it cannot guarantee this order.
---@return nil
function M.complete_current()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  M.edit(vim.api.nvim_get_current_buf(), row - 1, col, true)
end

--- Insert `>` and synchronously complete markup tags in supported buffers.
---@return string
function M.gt()
  if vim.bo.buftype ~= "" or not supported[vim.bo.filetype] then return ">" end
  return "><Cmd>lua require('paired_tags').complete_current()<CR>"
end

--- Find the opening tag ending at the cursor, ignoring quoted angle brackets.
---@param text string
---@return string?
local function opening_name_before_cursor(text)
  local quote ---@type string?
  local start ---@type integer?
  for index = 1, #text do
    local char = text:sub(index, index)
    if quote then
      if char == quote then quote = nil end
    elseif char == "<" then
      start = index
    elseif char == ">" then
      if index == #text and start then
        local tag = text:sub(start)
        if not tag:match("/%s*>$") then
          return tag:match("^<([%a][%w:_%-]*)[%s>]")
        end
      end
      start = nil
    elseif start and (char == '"' or char == "'") then
      quote = char
    end
  end
end

--- Split adjacent matching HTML tags using effective buffer indentation.
--- Other Enter presses retain native behavior.
---@return string
function M.html_enter()
  local filetype = vim.bo.filetype
  if (filetype ~= "html" and filetype ~= "htmldjango")
    or vim.bo.buftype ~= "" or vim.fn.pumvisible() == 1 then
    return "<CR>"
  end

  local line = vim.api.nvim_get_current_line()
  local column = vim.api.nvim_win_get_cursor(0)[2]
  local opening = opening_name_before_cursor(line:sub(1, column))
  local closing = line:sub(column + 1):match("^</([%a][%w:_%-]*)%s*>")
  if opening and closing and opening:lower() == closing:lower() then
    local width = vim.fn.shiftwidth()
    local levels = math.floor(vim.fn.indent(".") / width) + 1
    return "<CR><CR><Up>" .. string.rep("<C-t>", levels)
  end
  return "<CR>"
end

--- Route editor text changes to the tag editor for the current buffer.
---@param event vim.api.keyset.create_autocmd.callback_args
---@return nil
function M.changed(event)
  if vim.api.nvim_get_current_buf() ~= event.buf then return end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  M.edit(event.buf, row - 1, col, event.event == "TextChangedI")
end

---@param event vim.api.keyset.create_autocmd.callback_args
local function clear_streaming_paste(event)
  streaming_paste[event.buf] = nil
end

--- Register mappings and handlers once for current and future buffers.
--- The paste wrapper keeps streamed fragments from triggering partial edits.
---@return nil
function M.setup()
  if configured then return end
  configured = true
  local group = vim.api.nvim_create_augroup("PairedTags", { clear = true })
  vim.on_key(M.before_key, key_namespace)
  local original_paste = vim.paste
  ---@param lines string[]
  ---@param phase -1|1|2|3
  ---@return boolean
  vim.paste = function(lines, phase)
    local buf = vim.api.nvim_get_current_buf()
    if phase == 1 then streaming_paste[buf] = true end
    if phase == -1 then streaming_paste[buf] = nil end
    local ok, result = pcall(original_paste, lines, phase)
    if phase == 3 or not ok or result == false then
      streaming_paste[buf] = nil
    end
    if not ok then error(result) end
    return result
  end
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "InsertEnter" },
    { group = group, callback = M.capture_pair,
      desc = "Remember the paired tag before editing its name" })
  vim.api.nvim_create_autocmd("BufWipeout", { group = group,
    callback = M.clear_tracked, desc = "Release remembered paired tag positions" })
  vim.api.nvim_create_autocmd({ "InsertLeave", "BufWipeout" }, { group = group,
    callback = clear_streaming_paste, desc = "Clear streamed paste state" })
  vim.api.nvim_create_autocmd("InsertCharPre", { group = group,
    callback = M.before_char, desc = "Track ancestors before a new markup tag" })
  vim.api.nvim_create_autocmd({ "InsertLeave", "BufWipeout" }, { group = group,
    callback = M.clear_pending, desc = "Clear pending markup tag positions" })
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, { group = group,
    callback = M.changed, desc = "Close and rename paired markup tags" })
  vim.keymap.set("i", ">", M.gt,
    { expr = true, silent = true, desc = "Close a completed markup tag" })
  vim.keymap.set("i", "<CR>", M.html_enter,
    { expr = true, silent = true, desc = "Indent between matching HTML tags" })
end

return M
