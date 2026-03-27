# Description
Stripped down version of kickstart neovim. Only really the stuff I use

# Ubuntu
Need unstable or some of the autocmds wont work (needed for yank highlighting and LSP attach)

```
sudo add-apt-repository ppa:neovim-ppa/unstable -y
sudo apt update
sudo apt install make gcc tree-sitter-cli unzip git xclip neovim
```
