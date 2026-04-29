--- Automated integration test for nvim-dap-image with cppdbg (OpenDebugAD7).
--- Same tests as test_integration.lua but using the real cppdbg adapter.
local dap = require("dap")
require("nvim-dap-image").setup()

vim.defer_fn(function()
  io.write("TIMEOUT: cppdbg test took too long\n")
  io.flush()
  vim.cmd("cq")
end, 60000)

local demo_dir = vim.fn.fnamemodify(".", ":p")
local binary = demo_dir .. "bazel-bin/demo"
local demo_file = demo_dir .. "demo.cpp"
local cppdbg_path = vim.fn.stdpath("data")
  .. "/mason/packages/cpptools/extension/debugAdapters/bin/OpenDebugAD7"

if vim.fn.filereadable(cppdbg_path) == 0 then
  io.write("SKIP: OpenDebugAD7 not found\n"); io.flush()
  vim.cmd("qa!")
  return
end

dap.adapters.cppdbg = {
  id = "cppdbg",
  type = "executable",
  command = cppdbg_path,
}

local results = {}

local function record(name, ok, msg)
  table.insert(results, string.format("[%s] %s%s", ok and "PASS" or "FAIL", name, msg and (": " .. msg) or ""))
end

local function finish()
  io.write("\n=== nvim-dap-image C++ cppdbg tests ===\n")
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
        record(var_name, name_ok, string.format("extractor=%s, file=%d bytes", extractor_name, stat.size))
      end
      if tmp_path then vim.fn.delete(tmp_path) end
      callback()
    end)
  end)
end

local lines = vim.fn.readfile(demo_file)
local bp_line = nil
for i, line in ipairs(lines) do
  if line:match("^%s*// BREAKPOINT") then
    bp_line = i + 1
    break
  end
end

vim.cmd("edit " .. demo_file)
vim.api.nvim_win_set_cursor(0, { bp_line, 0 })
dap.toggle_breakpoint()

dap.listeners.after.event_stopped["cppdbg_test"] = function()
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
  end, 500)
end

dap.listeners.after.event_exited["cppdbg_test"] = function()
  io.write("EXITED without breakpoint!\n"); io.flush()
  dap.terminate()
  vim.defer_fn(function() vim.cmd("cq") end, 500)
end

dap.run({
  type = "cppdbg",
  request = "launch",
  name = "cppdbg Test",
  program = binary,
  cwd = demo_dir,
  stopAtEntry = false,
  MIMode = "lldb",
})
