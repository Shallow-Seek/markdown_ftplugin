-- vim:fileencoding=utf-8:foldmethod=marker

-- ~/.config/nvim/ftplugin/markdown.lua

-- Create a namespace for our extmarks
local namespace = vim.api.nvim_create_namespace("markdown_rendering")

-- =============================================================================
-- Highlighting and Configuration
-- =============================================================================

-- Define heading styles 
local heading_styles = {
  { fg = '#98971a', bold = true }, -- H1
  { fg = '#b16286', bold = true }, -- H2
  { fg = '#d79921', bold = true }, -- H3
  { fg = '#458588', bold = true }, -- H4
  { fg = '#7e9cd8', bold = true }, -- H5
  { fg = '#689d6a', bold = true }  -- H6
}

-- Define the bullet symbols for each heading level
local bullets = { " ", " 󰮊 ", "   ", "    ", "    󰠖 ", "     󰋑 " }

-- Set up highlight groups
for i, style in ipairs(heading_styles) do
  vim.api.nvim_set_hl(0, string.format("Heading%d", i), style)
end

-- codeblock font color  guifg=#a3b188
vim.cmd([[
  hi! link MarkdownTableBorder Comment
  hi! link MarkdownTableHeader Title
  hi! link MarkdownTableCell Normal
  hi! @Markup.quote guifg=#9aafc4 gui=italic
  hi! markdownCodeBlock guibg=#1f1f28
  hi! link MarkdownListMarker Special
]])

-- =============================================================================
-- Treesitter Query
-- =============================================================================

-- Define the query to match all supported markdown elements
-- Using iter_captures is more robust than positional matching
local query = vim.treesitter.query.parse(
  "markdown",
  [[
        (atx_heading
          [(atx_h1_marker) (atx_h2_marker) (atx_h3_marker)
            (atx_h4_marker) (atx_h5_marker) (atx_h6_marker)] @headlinemarker
          )
        (block_quote) @quote
        (list_item
          [(list_marker_minus) (list_marker_plus) (list_marker_star)] @list_marker
          )
        (fenced_code_block) @codeblock
        (thematic_break) @dash
        (pipe_table) @table
        ]]
)

-- =============================================================================
-- Table Rendering Logic
-- =============================================================================

--- Parses a pipe_table node to extract cell data and alignment info.
--- @param node TSNode The pipe_table node.
--- @param bufnr integer The buffer number.
--- @return table A table with `rows` and `alignments` keys.
local function parse_table_node(node, bufnr)
  local data = { rows = {}, alignments = {} }
  local row_index = 1

  for row_node in node:iter_children() do
    local row_type = row_node:type()
    if row_type == "pipe_table_header" or row_type == "pipe_table_row" then
      data.rows[row_index] = {}
      local col_index = 1
      for cell_node in row_node:iter_children() do
        if cell_node:type() == "pipe_table_cell" then
          local text = vim.treesitter.get_node_text(cell_node, bufnr)
          data.rows[row_index][col_index] = vim.fn.trim(text)
          col_index = col_index + 1
        end
      end
      row_index = row_index + 1
    elseif row_type == "pipe_table_delimiter_row" then
      local col_index = 1
      for cell_node in row_node:iter_children() do
        if cell_node:type() == "pipe_table_delimiter_cell" then
          local text = vim.treesitter.get_node_text(cell_node, bufnr)
          if text:match("^:.*:$") then
            data.alignments[col_index] = 'center'
          elseif text:match(":$") then
            data.alignments[col_index] = 'right'
          else
            data.alignments[col_index] = 'left'
          end
          col_index = col_index + 1
        end
      end
    end
  end
  return data
end

--- Calculates the maximum display width for each column in the table data.
--- @param data table The parsed table data from parse_table_node.
--- @return table An array of column widths.
local function calculate_column_widths(data)
  local widths = {}
  for _, row in ipairs(data.rows) do
    for i, cell in ipairs(row) do
      local cell_width = vim.fn.strwidth(cell)
      widths[i] = math.max(widths[i] or 0, cell_width)
    end
  end
  return widths
end

--- Generates the virtual text for the formatted table.
--- @param data table The parsed table data.
--- @param widths table The calculated column widths.
--- @return table An array of virtual text chunks for each line.
local function generate_virtual_table(data, widths)
  local virtual_lines = {}
  local num_columns = #widths

  -- Helper to pad text based on alignment
  local function pad_text(text, width, align)
    local text_width = vim.fn.strwidth(text)
    local padding = width - text_width
    if padding < 0 then padding = 0 end

    if align == 'right' then
      return string.rep(' ', padding).. text
    elseif align == 'center' then
      local left_pad = math.floor(padding / 2)
      local right_pad = math.ceil(padding / 2)
      return string.rep(' ', left_pad).. text.. string.rep(' ', right_pad)
    else -- left align
      return text.. string.rep(' ', padding)
    end
  end

  -- Helper to build a table line (border, header, row)
  local function build_line(left, sep, right, content_builder)
    local line_chunks = { { left, "MarkdownTableBorder" } }
    for i = 1, num_columns do
      local content_text, content_hl = content_builder(i)

      -- Only add padding spaces to actual cell content, not to the border lines.
      if content_hl == "MarkdownTableBorder" then
        table.insert(line_chunks, { content_text, content_hl })
      else
        table.insert(line_chunks, { " " .. content_text .. " ", content_hl })
      end

      if i < num_columns then
        table.insert(line_chunks, { sep, "MarkdownTableBorder" })
      end
    end
    table.insert(line_chunks, { right, "MarkdownTableBorder" })
    return line_chunks
  end

  -- Top border
  table.insert(virtual_lines, build_line("┌", "┬", "┐", function(i)
    return string.rep("─", widths[i] + 2), "MarkdownTableBorder"
  end))

  -- Header
  table.insert(virtual_lines, build_line("│", "│", "│", function(i)
    local text = data.rows[1] and data.rows[1][i] or ""
    return pad_text(text, widths[i], data.alignments[i]), "MarkdownTableHeader"
  end))

  -- Delimiter
  table.insert(virtual_lines, build_line("├", "┼", "┤", function(i)
    return string.rep("─", widths[i] + 2), "MarkdownTableBorder"
  end))

  -- Data rows
  for row_idx = 2, #data.rows do
    table.insert(virtual_lines, build_line("│", "│", "│", function(i)
      local text = data.rows[row_idx] and data.rows[row_idx][i] or ""
      return pad_text(text, widths[i], data.alignments[i]), "MarkdownTableCell"
    end))
  end

  -- Bottom border
  table.insert(virtual_lines, build_line("└", "┴", "┘", function(i)
    return string.rep("─", widths[i] + 2), "MarkdownTableBorder"
  end))

  return virtual_lines
end

--- Renders a single pipe table node.
--- @param node TSNode The pipe_table node.
--- @param bufnr integer The buffer number.
--- @param ns_id integer The namespace ID for extmarks.
-- Add this helper function at the top of the table rendering section
local function is_line_empty(bufnr, lnum)
  if lnum < 0 or lnum >= vim.api.nvim_buf_line_count(bufnr) then
    return true
  end
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
  return line == nil or line:match("^%s*$") ~= nil
end

-- Then modify the render_table function as follows:
local function render_table(node, bufnr, ns_id)
  local start_row, _, end_row, _ = node:range()

  -- 1. Parse table data from the node
  local data = parse_table_node(node, bufnr)
  if #data.rows == 0 or #data.alignments == 0 then return end

  -- 2. Calculate column widths
  local widths = calculate_column_widths(data)
  if #widths == 0 then return end

  -- 3. Generate the virtual text lines
  local virtual_lines = generate_virtual_table(data, widths)

  -- 4. Apply extmarks
  -- Conceal the entire source table
  vim.api.nvim_buf_set_extmark(bufnr, ns_id, start_row, 0, {
    end_row = end_row,
    conceal = "",
    virt_text_hide = true,
  })

  -- 5. Render virtual lines with adjacent line checks
  for i, line_chunks in ipairs(virtual_lines) do
    -- Skip top border if non-empty line above
    if i == 1 and not is_line_empty(bufnr, start_row - 1) then
      goto continue
    end

    -- Skip bottom border if non-empty line below
    if i == #virtual_lines and not is_line_empty(bufnr, end_row) then
      goto continue
    end

    local target_row
    if i == 1 then  -- Top border should appear above the table
      target_row = start_row - 1
    else  -- Other lines appear within the table
      target_row = start_row + (i - 2)
    end   

    vim.api.nvim_buf_set_extmark(bufnr, ns_id, target_row, 0, {
      virt_text = line_chunks,
      virt_text_pos = 'overlay',
      virt_text_hide = true,
    })
    ::continue::
  end
end

-- =============================================================================
-- Other Element Rendering Logic
-- =============================================================================

local function render_atx_heading(node, bufnr, ns_id)
  local marker_start_row, _, _, _ = node:range()
  local marker_text = vim.treesitter.get_node_text(node, bufnr)
  -- FIX: Directly get the length of the marker text for the level.
  local level = #marker_text

  vim.api.nvim_buf_set_extmark(bufnr, ns_id, marker_start_row, 0, {
    end_row = marker_start_row + 1,
    virt_text = { { bullets[level] or "", string.format("Heading%d", level) } },
    hl_group = string.format("Heading%d", level),
    virt_text_pos = 'overlay',
    virt_text_hide = true,
    hl_eol = true,
  })
end

local function render_block_quote(node, bufnr, ns_id)
  local function find_and_conceal_markers(inner_node)
    local node_type = inner_node:type()
    if node_type == "block_quote_marker" or node_type == "block_continuation" then
      local sr, sc, er, ec = inner_node:range()
      vim.api.nvim_buf_set_extmark(bufnr, ns_id, sr, sc, {
        end_row = er,
        end_col = ec,
        virt_text = { { " ▋", "@Markup.quote" } },
        virt_text_pos = 'overlay',
        virt_text_hide = true,
      })
      return
    end
    for child in inner_node:iter_children() do
      find_and_conceal_markers(child)
    end
  end
  find_and_conceal_markers(node)
end

local function render_list_marker(node, bufnr, ns_id)
  local start_row, start_col, _, end_col = node:range()
  local virt_text_char
  if node:type() == "list_marker_minus" then
    virt_text_char = "■ "
  elseif node:type() == "list_marker_plus" then
    virt_text_char = "● "
  elseif node:type() == "list_marker_star" then
    virt_text_char = "❖ "
  end
  vim.api.nvim_buf_set_extmark(bufnr, ns_id, start_row, end_col-2, {
    end_col = end_col,
    virt_text = { { virt_text_char, "MarkdownListMarker" } },
    virt_text_pos = 'overlay',
    virt_text_hide = true,
  })
end

local function render_code_block(node, bufnr, ns_id)
  local start_row, _, end_row, _ = node:range()
  vim.api.nvim_buf_set_extmark(bufnr, ns_id, start_row, 0, {
    end_row = end_row,
    hl_group = "markdownCodeBlock",
    hl_mode = "combine",
    priority = 100,
    hl_eol = true
  })
end

local function render_thematic_break(node, bufnr, ns_id)
  local start_row, _, _, _ = node:range()
  local width = vim.api.nvim_win_get_width(0)
  vim.api.nvim_buf_set_extmark(bufnr, ns_id, start_row, 0, {
    virt_text = { { string.rep("─", width), "Comment" } },
    virt_text_pos = "overlay",
    virt_text_hide = true,
  })
end

-- =============================================================================
-- Main Refresh Logic and Autocommands
-- =============================================================================


--- Main function to refresh all markdown elements.
local function refresh_all_elements()
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)

  local parser = vim.treesitter.get_parser(bufnr, "markdown")
  if not parser then return end
  local tree = parser:parse()[1]
  if not tree then return end
  local root = tree:root()

  -- Dispatcher loop using the more robust iter_captures
  for capture_id, node, _ in query:iter_captures(root, bufnr) do
    local capture_name = query.captures[capture_id]

    if capture_name == "headlinemarker" then
      render_atx_heading(node, bufnr, namespace)
    elseif capture_name == "quote" then
      render_block_quote(node, bufnr, namespace)
    elseif capture_name == "list_marker" then
      render_list_marker(node, bufnr, namespace)
    elseif capture_name == "codeblock" then
      render_code_block(node, bufnr, namespace)
    elseif capture_name == "dash" then
      render_thematic_break(node, bufnr, namespace)
    elseif capture_name == "table" then
      render_table(node, bufnr, namespace)
    end
  end
end


--- Debounced version of the refresh function for performance.
local refresh_timer = nil
local function debounced_refresh()
  if refresh_timer then
    refresh_timer:stop()
  end
  refresh_timer = vim.defer_fn(refresh_all_elements, 200) -- 200ms delay
end

-- Set up autocommands to trigger the debounced refresh
-- Even if the pattern is set to *.md files, the callback will be applied to non-markdown buffers concurrently,if they the file does not have an extension. 
vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI" }, {
  callback = debounced_refresh,
  pattern = { "*.md"},
  group = vim.api.nvim_create_augroup("MarkdownRender", { clear = true }),
})

refresh_all_elements()

vim.wo.conceallevel = 2
