# review.nvim

`review.nvim` is a small Neovim workflow for reviewing the files changed by a Git branch. It builds a checklist from the branch diff, keeps progress between sessions, and lets you move through pending files without leaving the editor.

## What it does

- compares `HEAD` with the merge-base of `main`, `master`, or the remote default branch;
- tracks modified, added, renamed, copied, and deleted files;
- shows per-file and total addition/deletion counts;
- opens deleted files from the merge-base snapshot;
- jumps forward or backward through pending files, with wraparound;
- restores progress only when `HEAD` and the merge-base still match, avoiding stale “reviewed” marks;
- stores state outside the repository by default, so it does not dirty `git status`;
- uses argument-based Git calls, so branch names and paths are not evaluated by a shell.

Requires Neovim 0.10+ and Git.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "douglasbrandao/review.nvim",
  opts = {},
}
```

With [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
  "douglasbrandao/review.nvim",
  config = function()
    require("review").setup()
  end,
}
```

Calling `setup()` is optional; defaults are installed on `VimEnter` when no explicit setup was made.

## Workflow

1. Run `:ReviewGitDiff`, optionally followed by a base branch such as `origin/main`.
2. Open the list with `<leader>rl`.
3. Press `<CR>` to open a file or `x`/`Space` to toggle it directly in the list.
4. Use `<leader>rn` and `<leader>rp` to move between pending files.
5. Toggle the current file with `<leader>rx`.

The diff represents committed branch changes from the merge-base through `HEAD`. Refreshing it on the same revision retains progress. A new commit starts a fresh checklist so changes are not accidentally treated as reviewed.

The list uses Git's familiar status letters (`A`, `M`, `R`, `C`, `D`) and displays repository-relative paths. Its size is automatically capped to the current editor dimensions.

### List keymaps

| Key | Action |
| --- | --- |
| `<CR>` | Open the selected file |
| `x`, `<Space>` | Toggle the selected file |
| `q`, `<Esc>` | Close the list |

## Commands

| Command | Description |
| --- | --- |
| `:ReviewGitDiff [base]` | Load or refresh the branch diff; base branches are completed |
| `:ReviewList` | Open the review list |
| `:ReviewToggle` | Toggle the current file |
| `:ReviewNext` | Open the next pending file |
| `:ReviewPrev` | Open the previous pending file |
| `:ReviewAdd` | Add the current file manually |
| `:ReviewRemove` | Remove the current file |
| `:ReviewClear` | Empty the in-memory review list |
| `:ReviewSave` | Save progress immediately |
| `:ReviewLoad` | Restore saved progress |
| `:ReviewClearState` | Delete saved progress |

## Configuration

```lua
require("review").setup({
  keymaps = {
    enable = true,
    insert = "<leader>ri",
    remove = "<leader>rr",
    list = "<leader>rl",
    toggle_reviewed = "<leader>rx",
    git_diff = "<leader>rg",
    next_unreviewed = "<leader>rn",
    prev_unreviewed = "<leader>rp",
  },
  window = {
    width = 100,
    height = 30,
    border = "rounded",
    show_help = true,
  },
  icons = {
    reviewed = "✓",
    not_reviewed = "○",
  },
  git = {
    default_base = nil, -- auto-detect origin/HEAD, main, or master
    show_diff_stats = true,
  },
  persistence = {
    enable = true,
    filename = nil, -- nil: stdpath("state")/review.nvim/<repository-hash>.json
    auto_save = true,
    auto_load = true,
  },
})
```

Set an individual keymap to `false` to omit it. Setting `persistence.filename` to a relative path stores the file under the repository root; an absolute path is also accepted.

The highlight groups `ReviewDone`, `ReviewPending`, `ReviewAdded`, `ReviewDeleted`, and `ReviewHelp` can be customized by a colorscheme or user configuration.

## Lua API

```lua
local review = require("review")

review.populate_from_git_diff("main") -- nil enables base auto-detection
review.show_buffers()
review.mark_buffer()
review.unmark_buffer()
review.mark_file_as_reviewed()
review.goto_next_unreviewed()
review.goto_prev_unreviewed()
review.save_state()
review.load_state()
review.clear_state()
review.clear_all_buffers()
```

## Development

Run the headless integration suite with:

```sh
make test
```

The suite creates a temporary Git repository and covers modified paths with spaces, renames, deletions, diff statistics, deleted-file previews, persistence, and safe refresh behavior.

## License

MIT — see [LICENSE](LICENSE).
