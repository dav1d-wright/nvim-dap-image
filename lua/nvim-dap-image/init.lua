local config = require("nvim-dap-image.config")
local dapui = require("nvim-dap-image.dapui")
local evaluate = require("nvim-dap-image.evaluate")
local extractors = require("nvim-dap-image.extractors")
local viewer = require("nvim-dap-image.viewer")

local M = {}

local function notify_error(msg)
  vim.schedule(function()
    vim.notify("nvim-dap-image: " .. msg, vim.log.levels.ERROR)
  end)
end

--- The expression under the cursor. In an nvim-dap-ui variable tree the word
--- under the cursor is only the leaf name, so the adapter's evaluate name for
--- the whole path is resolved instead.
local function resolve_expression(callback)
  if dapui.is_variable_tree(vim.bo.filetype) then
    dapui.resolve(callback)
    return
  end

  local cword = evaluate.get_cword()
  if cword == "" then
    callback("No expression to evaluate")
    return
  end
  callback(nil, cword)
end

local function view_expression(expr)
  extractors.detect_and_extract(expr, function(err, tmp_path, extractor_name)
    if err then
      notify_error(err)
      return
    end

    vim.schedule(function()
      viewer.open(tmp_path, {
        title = expr .. " (" .. extractor_name .. ")",
      })
    end)
  end)
end

function M.view(expr)
  local session = evaluate.get_session()
  if not session then
    vim.notify("nvim-dap-image: No active debug session", vim.log.levels.WARN)
    return
  end

  if expr and expr ~= "" then
    view_expression(expr)
    return
  end

  resolve_expression(function(err, resolved)
    if err then
      notify_error(err)
      return
    end
    view_expression(resolved)
  end)
end

function M.close()
  viewer.close_focused()
end

function M.close_all()
  viewer.close_all()
end

M.register_extractor = extractors.register

local function register_dap_listeners()
  local ok, dap = pcall(require, "dap")
  if not ok then return end

  if config.current.auto_close_on_terminate then
    dap.listeners.before.event_terminated["nvim-dap-image"] = function()
      viewer.close_all()
    end
    dap.listeners.before.event_exited["nvim-dap-image"] = function()
      viewer.close_all()
    end
  end
end

local function create_commands()
  vim.api.nvim_create_user_command("DapImageView", function(cmd)
    local expr = cmd.args ~= "" and cmd.args or nil
    M.view(expr)
  end, { nargs = "?" })

  vim.api.nvim_create_user_command("DapImageClose", function()
    M.close()
  end, {})

  vim.api.nvim_create_user_command("DapImageCloseAll", function()
    M.close_all()
  end, {})
end

function M.setup(opts)
  config.setup(opts)

  require("nvim-dap-image.extractors.cpp").register()
  require("nvim-dap-image.extractors.python").register()

  create_commands()
  register_dap_listeners()
end

return M
