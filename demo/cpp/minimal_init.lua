local dap_dir = vim.fn.expand("$HOME/.local/share/nvim/lazy/nvim-dap")
vim.opt.rtp:prepend(dap_dir)
vim.opt.rtp:prepend(vim.fn.expand("$HOME/projects/nvim-dap-image"))
