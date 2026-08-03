local plenary_dir = vim.fn.expand("$HOME/.local/share/nvim/lazy/plenary.nvim")
local dap_dir = vim.fn.expand("$HOME/.local/share/nvim/lazy/nvim-dap")
local image_dir = vim.fn.expand("$HOME/.local/share/nvim/lazy/image.nvim")
-- IMAGE_VIEW_DIR points the suite at a development checkout outside the lazy path.
local image_view_dir = vim.env.IMAGE_VIEW_DIR
  or vim.fn.expand("$HOME/.local/share/nvim/lazy/image-view.nvim")

vim.opt.rtp:prepend(plenary_dir)
vim.opt.rtp:prepend(dap_dir)
vim.opt.rtp:prepend(image_dir)
vim.opt.rtp:prepend(image_view_dir)
vim.opt.rtp:prepend(".")

vim.cmd("runtime plugin/plenary.vim")
