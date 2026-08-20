--- Automated integration test for resolving the variable under the cursor in
--- nvim-dap-ui windows. Renders the scopes and hover elements against a live
--- codelldb session, then extracts the image the cursor is on.
---
--- Prerequisites:
---   1. Build: cd demo/cpp && bazel build //:demo
---   2. codelldb, nvim-dap-ui and nvim-nio installed
---
--- Run with:
---   cd demo/cpp && nvim --headless -u ../../tests/minimal_init.lua \
---     --cmd "set rtp+=../../" -S test_dapui.lua

local lazy_dir = vim.fn.expand("$HOME/.local/share/nvim/lazy/")
for _, plugin in ipairs({ "nvim-dap-ui", "nvim-nio" }) do
  if vim.fn.isdirectory(lazy_dir .. plugin) == 0 then
    io.write("SKIP: " .. plugin .. " not found\n"); io.flush()
    vim.cmd("qa!")
    return
  end
  vim.opt.rtp:prepend(lazy_dir .. plugin)
end

local dap = require("dap")
local dapui = require("dapui")
local resolver = require("nvim-dap-image.dapui")
local extractors = require("nvim-dap-image.extractors")

require("nvim-dap-image").setup()
dapui.setup()

vim.defer_fn(function()
  io.write("TIMEOUT: dap-ui test took too long\n"); io.flush()
  vim.cmd("cq")
end, 120000)

local demo_dir = vim.fn.fnamemodify(".", ":p")
local demo_file = demo_dir .. "demo.cpp"
local binary = demo_dir .. "bazel-bin/demo"

if vim.fn.filereadable(binary) == 0 then
  io.write("SKIP: Binary not built. Run 'bazel build //:demo' first.\n"); io.flush()
  vim.cmd("qa!")
  return
end

local codelldb_path = vim.fn.stdpath("data") .. "/mason/packages/codelldb/extension/adapter/codelldb"
if vim.fn.filereadable(codelldb_path) == 0 then
  codelldb_path = vim.fn.exepath("codelldb")
  if codelldb_path == "" then
    io.write("SKIP: codelldb not found. Install via Mason.\n"); io.flush()
    vim.cmd("qa!")
    return
  end
end

dap.adapters.codelldb = {
  type = "server",
  port = "${port}",
  executable = { command = codelldb_path, args = { "--port", "${port}" } },
}

local results = {}

local function record(name, ok, msg)
  table.insert(results, string.format("[%s] %s%s", ok and "PASS" or "FAIL", name, msg and (": " .. msg) or ""))
end

local function finish()
  io.write("\n=== nvim-dap-image nvim-dap-ui tests ===\n")
  for _, r in ipairs(results) do
    io.write(r .. "\n")
  end
  local failed = vim.tbl_count(vim.tbl_filter(function(r) return r:match("^%[FAIL%]") end, results))
  local passed = vim.tbl_count(vim.tbl_filter(function(r) return r:match("^%[PASS%]") end, results))
  io.write(string.format("\n%d passed, %d failed\n", passed, failed))
  io.flush()
  vim.cmd(failed > 0 and "cq" or "qa!")
end

local function window_for_filetype(filetype)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == filetype then
      return win
    end
  end
end

local function line_holding(win, needle)
  local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
  for i, line in ipairs(lines) do
    if line:find(needle, 1, true) then return i end
  end
end

--- Trigger the expand mapping on the line the cursor is on.
local function expand(win)
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
end

--- Put the cursor on the nested `image` member and check that it resolves to an
--- expression the cv::Mat extractor can read.
local function check_nested_image(name, filetype, callback)
  local win = window_for_filetype(filetype)
  if not win then
    record(name, false, "no " .. filetype .. " window")
    callback()
    return
  end

  local lnum = line_holding(win, "image cv::Mat")
  if not lnum then
    record(name, false, "no expanded 'image' member")
    callback()
    return
  end

  vim.api.nvim_set_current_win(win)
  vim.api.nvim_win_set_cursor(win, { lnum, 0 })
  resolver.resolve(function(resolve_err, expr)
    if resolve_err then
      record(name, false, resolve_err)
      callback()
      return
    end
    extractors.detect_and_extract(expr, function(extract_err, tmp_path)
      if extract_err then
        record(name, false, expr .. ": " .. extract_err)
        callback()
        return
      end
      vim.schedule(function()
        local stat = vim.uv.fs_stat(tmp_path)
        local size = stat and stat.size or 0
        record(name, size > 0, string.format("expr=%s, file=%d bytes", expr, size))
        vim.fn.delete(tmp_path)
        callback()
      end)
    end)
  end)
end

local function test_scopes(callback)
  local win = window_for_filetype("dapui_scopes")
  if not win then
    record("scopes", false, "no dapui_scopes window")
    callback()
    return
  end

  local lnum = line_holding(win, "container ImageContainer")
  if not lnum then
    record("scopes", false, "no 'container' variable")
    callback()
    return
  end

  vim.api.nvim_win_set_cursor(win, { lnum, 0 })
  expand(win)
  vim.defer_fn(function()
    check_nested_image("scopes container.image", "dapui_scopes", callback)
  end, 2000)
end

local function test_hover(callback)
  dapui.eval("container", { enter = true })
  vim.defer_fn(function()
    local win = window_for_filetype("dapui_hover")
    if not win then
      record("hover", false, "no dapui_hover window")
      callback()
      return
    end
    expand(win)
    vim.defer_fn(function()
      check_nested_image("hover container.image", "dapui_hover", callback)
    end, 2000)
  end, 2000)
end

local lines = vim.fn.readfile(demo_file)
local bp_line
for i, line in ipairs(lines) do
  if line:match("^%s*// BREAKPOINT") then
    bp_line = i + 1
    break
  end
end

vim.cmd("edit " .. demo_file)
vim.api.nvim_win_set_cursor(0, { bp_line, 0 })
dap.toggle_breakpoint()

dap.listeners.after.event_stopped["dapui_test"] = function()
  vim.defer_fn(function()
    dapui.open()
    vim.defer_fn(function()
      test_scopes(function()
        test_hover(function()
          dap.terminate()
          vim.defer_fn(finish, 500)
        end)
      end)
    end, 2000)
  end, 500)
end

dap.run({
  type = "codelldb",
  request = "launch",
  name = "dap-ui Test",
  program = binary,
  cwd = demo_dir,
})
