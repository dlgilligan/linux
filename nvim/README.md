# Description
"Stripped" down version of kickstart neovim. Only really the stuff I use

# Notes
I set an alias such that vi and vim open neovim. That way im not accidentally typing nvim when SSHd into servers.

# Installation
Install a nerd-font, I use JetBrainsMono
For the most part, the kickstart neovim install instructions can be followed. But ripgrep and fd-find are not needed,
as I have removed the telescope plugin.

## Ubuntu
Need unstable or some of the autocmds wont work (needed for yank highlighting and LSP attach)
```
sudo add-apt-repository ppa:neovim-ppa/unstable -y
sudo apt update
sudo apt install make gcc tree-sitter-cli unzip git xclip neovim
```

# Files
init.lua - Plugin install and configuration
lua/
  autocmds.lua - Actions that trigger based on editor events
  options.lua - Vim options
  keymaps.lua - Generic keymaps
  language-servers.lua - List of language servers installed by the LSP plugin

# Plugins
## Colorscheme
kabouzeid/nvim-jellybeans - Colorscheme

# Misc
NMAC427/guess-indent.nvim - Indentation style detection
lewis6991/gitsigns.nvim - Symbols signifying git changes
folke/which-key.nvim - Displays a popup menu of available keybinds after starting a command

# VSCode-like tabs and file explorer
nvim-neo-tree/neo-tree.nvim - File Explorer
akinsho/bufferline.nvim - Tabs representing open buffers
echasnovski/mini.bufremove - Buffer removal

# LSP
neovim/nvim-lspconfig - A collection of LSP server configurations for the NVIM LSP client
stevearc/conform.nvim - Autoformatting
saghen/blink.cmp - Autocompletion
nvim-treesitter/nvim-treesitter - Highlight, edit, and navigate code
