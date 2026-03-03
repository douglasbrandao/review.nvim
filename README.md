# review.nvim

A Neovim plugin for tracking code review progress. Keep track of which files you've reviewed in a branch, navigate between unreviewed files, and persist your review state across sessions.

## Features

- **Git Integration** - Automatically load changed files from git diff
- **Review Tracking** - Mark files as reviewed/not reviewed with visual indicators
- **Quick Navigation** - Jump between unreviewed files with keymaps
- **Diff Stats** - See additions/deletions (+/-) for each file
- **State Persistence** - Save and restore review progress between sessions
- **Floating Window UI** - Clean interface showing review progress

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "douglasbrandao/review.nvim",
  config = function()
    require("review").setup()
  end,
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "douglasbrandao/review.nvim",
  config = function()
    require("review").setup()
  end,
}
```

## Configuration

Here is the default configuration:

```lua
require("review").setup({
  keymaps = {
    enable = true,
    insert = "<leader>ri",         -- Add current buffer to review list
    remove = "<leader>rr",         -- Remove current buffer from review list
    list = "<leader>rl",           -- Show review list
    toggle_reviewed = "<leader>rx", -- Toggle reviewed status
    git_diff = "<leader>rg",       -- Load files from git diff
    next_unreviewed = "<leader>rn", -- Go to next unreviewed file
    prev_unreviewed = "<leader>rp", -- Go to previous unreviewed file
  },
  window = {
    width = 100,
    height = 30,
    border = "rounded",
  },
  icons = {
    reviewed = "✅",
    not_reviewed = "❌",
  },
  git = {
    default_base = nil,            -- nil means auto-detect (main/master)
    show_diff_stats = true,        -- Show +/- line stats in the list
  },
  persistence = {
    enable = true,                 -- Enable automatic state persistence
    filename = ".review-state.json", -- State file name (relative to git root)
    auto_save = true,              -- Auto-save on buffer mark/unmark
    auto_load = true,              -- Auto-load state when git diff is populated
  },
})
```

## Usage

### Basic Workflow

1. **Load files from git diff:**
   ```
   :ReviewGitDiff
   ```
   Or press `<leader>rg` to load all changed files in the current branch compared to main/master.

2. **Navigate through files:**
   - `<leader>rn` - Go to next unreviewed file
   - `<leader>rp` - Go to previous unreviewed file

3. **Mark files as reviewed:**
   - `<leader>rx` - Toggle reviewed status on current file

4. **View progress:**
   - `<leader>rl` - Open the review list window

### Commands

| Command | Description |
|---------|-------------|
| `:ReviewAdd` | Add current buffer to review list |
| `:ReviewRemove` | Remove current buffer from review list |
| `:ReviewList` | Show all buffers in review list |
| `:ReviewToggle` | Toggle reviewed status of current buffer |
| `:ReviewClear` | Clear all buffers from review list |
| `:ReviewGitDiff [branch]` | Populate review list from git diff (optional: specify base branch) |
| `:ReviewNext` | Go to next unreviewed file |
| `:ReviewPrev` | Go to previous unreviewed file |
| `:ReviewSave` | Manually save review state |
| `:ReviewLoad` | Load review state from file |
| `:ReviewClearState` | Delete saved review state file |

### Review List Window

The review list shows:
- Progress indicator: `Review List - 3/10 (30%)`
- Total diff stats: `+150 -42`
- File list with status icons and individual diff stats

**Keymaps in the review window:**
- `<CR>` - Jump to the selected file
- `q` - Close the window

## API

You can also use the plugin programmatically:

```lua
local review = require("review")

-- Add/remove buffers
review.mark_buffer()
review.unmark_buffer()

-- Toggle reviewed status
review.mark_file_as_reviewed()

-- Navigation
review.goto_next_unreviewed()
review.goto_prev_unreviewed()

-- Git integration
review.populate_from_git_diff("main")  -- or nil for auto-detect

-- State management
review.save_state()
review.load_state()
review.clear_state()
review.clear_all_buffers()

-- Show UI
review.show_buffers()
```

## Project Structure

```
lua/review/
├── init.lua       # Main module and public API
├── config.lua     # Default configuration
├── state.lua      # State management and persistence
├── git.lua        # Git integration
├── navigation.lua # Navigation between files
├── ui.lua         # Floating window UI
└── utils.lua      # Utility functions
```

## State Persistence

Review state is automatically saved to `.review-state.json` in the git root directory. This allows you to:

- Close Neovim and resume your review later
- Share review progress (if you choose to commit the file)
- Track which files you've already reviewed

The state file is automatically created when you use `:ReviewGitDiff` and is updated whenever you mark/unmark files.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) for details.
