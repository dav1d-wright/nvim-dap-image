local plenary_dir = vim.fn.expand("$HOME/.local/share/nvim/lazy/plenary.nvim")
local dap_dir = vim.fn.expand("$HOME/.local/share/nvim/lazy/nvim-dap")
local image_dir = vim.fn.expand("$HOME/.local/share/nvim/lazy/image.nvim")

vim.opt.rtp:prepend(plenary_dir)
vim.opt.rtp:prepend(dap_dir)
vim.opt.rtp:prepend(image_dir)
vim.opt.rtp:prepend(".")

vim.cmd("runtime plugin/plenary.vim")
