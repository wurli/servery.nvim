<div align="center">

# servery.nvim

![Nvim](https://img.shields.io/badge/nvim-0.12+-57A143?style=flat-square)
![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)

Jump between Neovim sessions using your favourite fuzzy finder 💨

</div>

https://github.com/user-attachments/assets/17ae8112-29fa-4467-ad2b-98180412a127

## The workflow

1. Configure the directories you want to appear in the UI
2. Use `:Sv` (or configure a keymap) to jump between them
3. Profit

## Features

* Sessions outlive the terminal emulator unless you close them, e.g. with `:qa`

* Supports session management via a bunch of ui providers:
  * Built-in ui
  * [Snacks/picker](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md)
  * [fzf-lua](https://github.com/ibhagwan/fzf-lua)
  * [mini.pick](https://github.com/nvim-mini/mini.pick)
  * [telescope](https://github.com/nvim-telescope/telescope.nvim)

* `:Sv` does all the stuff

## Install/configure

> [!NOTE]
> servery.nvim requires nvim 0.12+!

`vim.pack` (nvim 0.12+):

``` lua
vim.pack.add({ "https://github.com/wurli/servery.nvim" })

-- The following are the defaults - you don't need to change them
-- but you probably should at least set `dirs` and `ui.provider`.
require("servery").setup({
	-- Either supply the directories as an array of strings, or a function
	-- which returns an array. Shorthands like `~` are expanded.
	dirs = { "~" }, ---@type string[] | fun(): string[]
	session_dir = vim.fs.joinpath(vim.fn.stdpath("cache"), "servery.nvim"),
	ui = {
		-- Options: "builtin" | "snacks" | "fzf" | "telescope" | "mini_pick"
		provider = "builtin", ---@type servery.ui_provider
		prompt = "Switch Nvim Session",
		icons = {
			current = "",
			active = "",
			inactive = "",
		},
		actions = {
			["<enter>"] = "switch",
			["<c-g>"] = "switch_and_detach",
			["<c-x>"] = "detach",
			["<c-s>"] = "spawn",
		},
		-- fzf-lua uses fzf's keymap notation, so it gets its own actions table
		fzf_actions = {
			["enter"] = "switch",
			["ctrl-g"] = "switch_and_detach",
			["ctrl-x"] = "detach",
			["ctrl-s"] = "spawn",
		},
	},
})
```

<details>
<summary>Or using lazy.nvim:</summary>

``` lua
{
    "wurli/servery",
    opts = {
        dirs = { "~" },
        -- ... See above for more
    },
    lazy = false
},
```

</details>


## Keybinds/commands

* `:Sv`: Open the servery ui
* `:[N]Sv`: Go to the nth last visited session
* `:Sv [dir]`: Go to the session in `[dir]`, creating it if it's not already open

Keymaps should be set up manually:

``` lua
vim.keymap.set("n", "<c-f>", "<cmd>Sv<cr>", { desc = "Switch nvim sessions" })
vim.keymap.set("n", "ZV", "<cmd>1Sv<cr>", { desc = "Go to previous session" })
```

## Why servery.nvim?

I previously managed sessions with Prime's
[`tmux-sessionizer`](https://github.com/theprimeagen/tmux-sessionizer). Tmux
served me well but has some rough edges which I'd prefer to avoid, so once
Neovim added `:connect` and `:detach` I decided to just move my whole life into
Neovim.

