--- Automated integration test for nvim-dap-image C++ extractors.
--- Launches a real codelldb session, hits a breakpoint, and verifies
--- that the cv::Mat extractor can detect and extract image data.
---
--- Prerequisites:
---   1. Build: cd demo/cpp && bazel build //:demo
---   2. codelldb installed via Mason
---
--- Run with:
---   cd demo/cpp && nvim --headless -u ../../tests/minimal_init.lua \
---     --cmd "set rtp+=../../" -S test_integration.lua

local dap = require("dap")
require("nvim-dap-image").setup()

-- Safety timeout
vim.defer_fn(function()
  io.write("TIMEOUT: integration test took too long\n")
  io.flush()
  vim.cmd("cq")
end, 30000)

local demo_file = vim.fn.fnamemodify("demo.cpp", ":p")
local demo_dir = vim.fn.fnamemodify(".", ":p")

-- Find the built binary
local binary = vim.fn.glob(demo_dir .. "bazel-bin/demo")
if binary == "" then
  -- Try common bazel-bin paths
  binary = vim.fn.glob(demo_dir .. "bazel-out/*/bin/demo")
  if binary == "" then
    io.write("SKIP: Binary not built. Run 'bazel build //:demo' first.\n"); io.flush()
    vim.cmd("qa!")
    return
  end
end

-- Find codelldb
local codelldb_path = vim.fn.stdpath("data") .. "/mason/packages/codelldb/extension/adapter/codelldb"
if vim.fn.filereadable(codelldb_path) == 0 then
  codelldb_path = vim.fn.exepath("codelldb")
  if codelldb_path == "" then
    io.write("SKIP: codelldb not found. Install via Mason.\n"); io.flush()
    vim.cmd("qa!")
    return
  end
end

-- Configure codelldb adapter
dap.adapters.codelldb = {
  type = "server",
  port = "${port}",
  executable = {
    command = codelldb_path,
    args = { "--port", "${port}" },
  },
}

local results = {}

local function record(name, ok, msg)
  table.insert(results, string.format("[%s] %s%s", ok and "PASS" or "FAIL", name, msg and (": " .. msg) or ""))
end

local function finish()
  io.write("\n=== nvim-dap-image C++ integration tests ===\n")
  for _, r in ipairs(results) do
    io.write(r .. "\n")
  end
  local passed = vim.tbl_count(vim.tbl_filter(function(r) return r:match("^%[PASS%]") end, results))
  local failed = vim.tbl_count(vim.tbl_filter(function(r) return r:match("^%[FAIL%]") end, results))
  io.write(string.format("\n%d passed, %d failed\n", passed, failed))
  io.flush()
  vim.cmd(failed > 0 and "cq" or "qa!")
end

local function test_extractor(var_name, expected_name, callback)
  local evaluate = require("nvim-dap-image.evaluate")
  local extractors = require("nvim-dap-image.extractors")

  evaluate.get_filetype = function() return "cpp" end

  extractors.detect_and_extract(var_name, function(err, tmp_path, extractor_name)
    if err then
      record(var_name, false, err)
      callback()
      return
    end

    vim.schedule(function()
      local stat = vim.uv.fs_stat(tmp_path)
      if not stat or stat.size == 0 then
        record(var_name, false, "temp file missing or empty")
      else
        local name_ok = extractor_name == expected_name
        record(
          var_name,
          name_ok,
          string.format("extractor=%s, file=%d bytes", extractor_name, stat.size)
        )
      end
      if tmp_path then vim.fn.delete(tmp_path) end
      callback()
    end)
  end)
end

-- Find the breakpoint line
local lines = vim.fn.readfile(demo_file)
local bp_line = nil
for i, line in ipairs(lines) do
  if line:match("^%s*// BREAKPOINT") then
    bp_line = i + 1 -- Line after the comment
    break
  end
end

if not bp_line then
  io.write("FAIL: Could not find breakpoint line in demo.cpp\n"); io.flush()
  vim.cmd("cq")
  return
end

vim.cmd("edit " .. demo_file)

vim.api.nvim_win_set_cursor(0, { bp_line, 0 })
dap.toggle_breakpoint()

dap.listeners.after.event_stopped["integration_test"] = function()
  vim.defer_fn(function()
    test_extractor("img", "OpenCV cv::Mat", function()
      test_extractor("gray", "OpenCV cv::Mat", function()
        test_extractor("large", "OpenCV cv::Mat", function()
          test_extractor("img_4k", "OpenCV cv::Mat", function()
            test_extractor("bgra", "OpenCV cv::Mat", function()
              local evaluate = require("nvim-dap-image.evaluate")
            evaluate.get_filetype = function() return "cpp" end

              local extractors = require("nvim-dap-image.extractors")
              extractors.detect_and_extract("not_an_image", function(err)
                record("not_an_image (should fail)", err ~= nil, err or "unexpectedly succeeded")
                dap.terminate()
                vim.defer_fn(finish, 500)
              end)
            end)
          end)
        end)
      end)
    end)
  end, 200)
end

-- Launch directly to avoid config picker
dap.run({
  type = "codelldb",
  request = "launch",
  name = "Integration Test",
  program = binary,
  cwd = demo_dir,
})
