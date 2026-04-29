local config = require("nvim-dap-image.config")

local M = {}

M._viewers = {}

function M.open(image_path, opts)
  opts = opts or {}
  local ok, image = pcall(require, "image")
  if not ok then
    vim.notify("nvim-dap-image: image.nvim is required", vim.log.levels.ERROR)
    return nil
  end

  local file_stat = vim.uv.fs_stat(image_path)
  if not file_stat or file_stat.size == 0 then
    vim.notify("nvim-dap-image: Image file is empty or missing: " .. image_path, vim.log.levels.ERROR)
    return nil
  end

  local win_opts = config.current.window
  local editor_width = vim.o.columns
  local editor_height = vim.o.lines
  local width = math.floor(editor_width * win_opts.width_pct)
  local height = math.floor(editor_height * win_opts.height_pct)
  if win_opts.max_width then width = math.min(width, win_opts.max_width) end
  if win_opts.max_height then height = math.min(height, win_opts.max_height) end
  local col = math.floor((editor_width - width) / 2)
  local row = math.floor((editor_height - height) / 2)

  local buf = vim.api.nvim_create_buf(false, true)

  local title = opts.title or "Debug Image"
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = col,
    row = row,
    style = "minimal",
    border = win_opts.border,
    title = " " .. title .. " ",
    title_pos = "center",
  })

  local img = image.hijack_buffer(image_path, win, buf)

  local viewer = {
    win = win,
    buf = buf,
    image = img,
    tmp_path = image_path,
  }

  vim.keymap.set("n", "q", function() M.close(viewer) end, { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", function() M.close(viewer) end, { buffer = buf, silent = true })

  table.insert(M._viewers, viewer)
  return viewer
end

function M.close(viewer)
  for i, v in ipairs(M._viewers) do
    if v == viewer then
      if v.image then
        pcall(function() v.image:clear() end)
      end
      if vim.api.nvim_win_is_valid(v.win) then
        vim.api.nvim_win_close(v.win, true)
      end
      if config.current.auto_cleanup_temp and v.tmp_path then
        vim.fn.delete(v.tmp_path)
      end
      table.remove(M._viewers, i)
      return
    end
  end
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
  local viewers = vim.list_slice(M._viewers)
  for _, viewer in ipairs(viewers) do
    M.close(viewer)
  end
end

return M
