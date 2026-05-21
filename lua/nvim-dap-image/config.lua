local M = {}

M.defaults = {
  tmp_dir = vim.uv.os_tmpdir() .. "/nvim-dap-image",

  window = {
    width_pct = 0.6,
    height_pct = 0.6,
    border = "rounded",
  },

  auto_close_on_terminate = true,
  auto_cleanup_temp = true,

  extractors = {},
}

M.current = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.current = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  vim.fn.mkdir(M.current.tmp_dir, "p")
end

return M
