# Markdown File Type Plugin for Neovim

A simple and lightweighted markdown render plugin.
## Elements rendered 

### 1. Custom Heading Rendering
- Renders ATX headings (##, ###, etc.) with custom bullet symbols and colors:
  - H1:  (green)
  - H2: 󰮊 (purple)
  - H3:  (yellow)
  - H4:  (blue)
  - H5: 󰠖 (light blue)
  - H6: 󰋑 (green)

### 2. Table Rendering
- Converts pipe tables into visually formatted tables with proper borders
- Supports alignment (left, right, center) based on delimiter formatting
- Automatically calculates column widths for optimal display
- Renders with Unicode box-drawing characters for a clean look

### 3. Block Quote Styling
- Replaces markdown quote markers (> ) with a stylish vertical bar (▋)
- Applies italic styling with a distinct color

### 4. List Marker Enhancement
- Transforms standard list markers into more visually appealing symbols:
  - `-` becomes ■
  - `+` becomes ●
  - `*` becomes ❖

### 5. Code Block Highlighting
- Adds a distinct background color to fenced code blocks for better visibility

### 6. Thematic Break Visualization
- Converts markdown thematic breaks (---) into full-width horizontal lines

## Installation

Simply place `markdown.lua` in your Neovim's `ftplugin` directory (typically `~/.config/nvim/ftplugin/`). No additional plugin manager is required.

## How It Works

The plugin uses Tree-sitter to parse markdown files and applies extmarks with virtual text to render elements visually. It leverages Neovim's conceal feature to hide original markdown syntax while displaying the enhanced visual elements.

## Customization

Colors and symbols can be customized by modifying the `heading_styles` and `bullets` tables in the plugin file. The plugin also defines several highlight groups that can be overridden in your Neovim configuration or in this file. Change the delay to 0 if want the rendering to be immediate. The default delay is 0.2 sec.
