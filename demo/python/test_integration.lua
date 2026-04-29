--- Automated integration test for nvim-dap-image Python extractors.
--- Launches a real debugpy session, hits a breakpoint, and verifies
--- that each extractor can detect and extract image data.
---
--- Run with:
---   cd demo/python && nvim --headless -u ../../tests/minimal_init.lua \
---     --cmd "set rtp+=../../" -S test_integration.lua

local dap = require("dap")
require("nvim-dap-image").setup()

local demo_file = vim.fn.fnamemodify("demo.py", ":p")
local venv_python = vim.fn.fnamemodify(".venv/bin/python", ":p")

if vim.fn.filereadable(venv_python) == 0 then
  print("SKIP: Python venv not set up. Run ./setup.sh first.")
  vim.cmd("qa!")
  return
end

-- Configure debugpy adapter
dap.adapters.debugpy = {
  type = "executable",
  command = venv_python,
  args = { "-m", "debugpy.adapter" },
}

local results = {}

local function record(name, ok, msg)
  local status = ok and "PASS" or "FAIL"
  table.insert(results, string.format("[%s] %s%s", status, name, msg and (": " .. msg) or ""))
end

local function finish()
  print("")
  print("=== nvim-dap-image Python integration tests ===")
  for _, r in ipairs(results) do
    print(r)
  end
  local passed = #vim.tbl_filter(function(r) return r:match("^%[PASS%]") end, results)
  local failed = #vim.tbl_filter(function(r) return r:match("^%[FAIL%]") end, results)
  print(string.format("\n%d passed, %d failed", passed, failed))
  vim.cmd(failed > 0 and "cq" or "qa!")
end

local function test_extractor(var_name, expected_name, callback)
  local evaluate = require("nvim-dap-image.evaluate")
  local extractors = require("nvim-dap-image.extractors")

  evaluate.get_filetype = function() return "python" end

  extractors.detect_and_extract(var_name, function(err, tmp_path, extractor_name)
    if err then
      record(var_name, false, err)
      callback()
      return
    end

    vim.schedule(function()
      local stat = vim.uv.fs_stat(tmp_path)
      if not stat or stat.size == 0 then
        record(var_name, false, "temp file missing or empty: " .. (tmp_path or "nil"))
      else
        local name_ok = extractor_name == expected_name
        record(
          var_name,
          name_ok,
          string.format("extractor=%s, file=%d bytes%s", extractor_name, stat.size, name_ok and "" or " (expected " .. expected_name .. ")")
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
  if line:match("All images created") then
    bp_line = i
    break
  end
end

if not bp_line then
  print("FAIL: Could not find breakpoint line in demo.py")
  vim.cmd("cq")
  return
end

-- Open the file and set breakpoint
vim.cmd("edit " .. demo_file)
vim.api.nvim_win_set_cursor(0, { bp_line, 0 })
dap.toggle_breakpoint()

-- When session stops at breakpoint, run tests (defer to let nvim-dap finish processing)
dap.listeners.after.event_stopped["integration_test"] = function()
  vim.defer_fn(function()
    test_extractor("cv_img", "OpenCV image", function()
      test_extractor("pil_img", "PIL Image", function()
        test_extractor("np_arr", "OpenCV image", function()
          test_extractor("fig", "Matplotlib Figure", function()
            test_extractor("large_img", "OpenCV image", function()
              test_extractor("img_4k", "OpenCV image", function()
                local evaluate = require("nvim-dap-image.evaluate")
                evaluate.get_filetype = function() return "python" end

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
    end)
  end, 200)
end

-- Launch directly with dap.run() to avoid config picker
dap.run({
  type = "debugpy",
  request = "launch",
  name = "Integration Test",
  program = demo_file,
  pythonPath = venv_python,
})
