local config = require("nvim-dap-image.config")

local M = {}

-- Viewers this plugin opened. close_all must leave viewers the user opened
-- through :ImageView untouched.
M._viewers = {}

---Open `image_path` in an image-view floating window.
---@param image_path string Path to the extracted image, owned by this plugin.
---@param opts table? `{ title?: string }`.
---@return table|nil viewer Handle, or nil if the image could not be shown.
function M.open(image_path, opts)
  opts = opts or {}

  local ok, image_view = pcall(require, "image-view")
  if not ok then
    vim.notify("nvim-dap-image: image-view.nvim is required", vim.log.levels.ERROR)
    return nil
  end

  local viewer
  viewer = image_view.open(image_path, {
    title = opts.title or "Debug Image",
    window = config.current.window,
    -- image-view runs this on every close path, including its own `q` mapping.
    on_close = function()
      for i, v in ipairs(M._viewers) do
        if v == viewer then
          table.remove(M._viewers, i)
          break
        end
      end
      if config.current.auto_cleanup_temp then
        vim.fn.delete(image_path)
      end
    end,
  })
  if not viewer then return nil end

  table.insert(M._viewers, viewer)
  return viewer
end

function M.close(viewer)
  local ok, image_view = pcall(require, "image-view")
  if not ok then return end
  image_view.close(viewer)
end

function M.close_focused()
  local current_win = vim.api.nvim_get_current_win()
  for _, viewer in ipairs(M._viewers) do
    if viewer.win == current_win then
      M.close(viewer)
      return
    end
  end
end

function M.close_all()
  for _, viewer in ipairs(vim.list_slice(M._viewers)) do
    M.close(viewer)
  end
end

return M
