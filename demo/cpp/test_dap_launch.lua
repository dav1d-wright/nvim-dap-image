-- Test: verify all cv::Mat metadata can be extracted via codelldb
local dap = require("dap")

vim.defer_fn(function()
  io.write("TIMEOUT\n")
  io.flush()
  vim.cmd("cq")
end, 15000)

local demo_dir = vim.fn.fnamemodify(".", ":p")
local codelldb_path = vim.fn.stdpath("data") .. "/mason/packages/codelldb/extension/adapter/codelldb"
local binary = demo_dir .. "bazel-bin/demo"
local demo_file = demo_dir .. "demo.cpp"

dap.adapters.codelldb = {
  type = "server",
  port = "${port}",
  executable = {
    command = codelldb_path,
    args = { "--port", "${port}" },
  },
}

local captured_output = {}
dap.listeners.after.event_output["capture"] = function(_, body)
  if body.output and body.output ~= "" then
    local line = (body.output:gsub("\n$", ""))
    table.insert(captured_output, line)
  end
end

--- Evaluate in repl context with `p` prefix, capture result from event_output
local function repl_eval(session, expr, callback)
  captured_output = {}
  session:evaluate({
    expression = "p " .. expr,
    context = "repl",
  }, function()
    vim.defer_fn(function()
      -- Look for the output line containing the result
      local result = nil
      for _, line in ipairs(captured_output) do
        -- codelldb prints: (type) value
        local val = line:match("^%(.-%)%s+(.+)")
        if val then result = val end
      end
      callback(result)
    end, 200)
  end)
end

dap.listeners.after.event_stopped["test"] = function()
  vim.defer_fn(function()
    local session = dap.session()

    -- Test all the metadata we need
    local results = {}
    local tests = {
      { name = "rows", watch_expr = "img.rows" },
      { name = "cols", watch_expr = "img.cols" },
      { name = "channels", repl_expr = "img.channels()" },
      { name = "step", repl_expr = "img.step[0]" },
      { name = "data_ptr", repl_expr = "(size_t)img.data", hex = true },
    }

    local function run_test(i)
      if i > #tests then
        io.write("\n=== RESULTS ===\n")
        for _, t in ipairs(tests) do
          io.write(t.name .. " = " .. tostring(results[t.name]) .. "\n")
        end
        io.flush()

        -- Now try readMemory with the address
        local addr = results["data_ptr"]
        if addr then
          local total = tonumber(results["rows"]) * tonumber(results["step"])
          io.write("readMemory: addr=" .. addr .. " count=" .. tostring(total) .. "\n")
          io.flush()
          session:request("readMemory", {
            memoryReference = addr,
            count = total,
          }, function(err, resp)
            if err then
              io.write("readMemory ERR: " .. (err.message or tostring(err)) .. "\n")
            else
              io.write("readMemory OK! data length=" .. #resp.data .. " (base64)\n")
              -- Decode and check
              local ok, raw = pcall(vim.base64.decode, resp.data)
              if ok then
                io.write("Decoded " .. #raw .. " bytes (expected " .. tostring(total) .. ")\n")
              else
                io.write("Base64 decode failed\n")
              end
            end
            io.flush()
            dap.terminate()
            vim.defer_fn(function() vim.cmd("qa!") end, 500)
          end)
        else
          io.write("FAIL: no data pointer\n")
          io.flush()
          dap.terminate()
          vim.defer_fn(function() vim.cmd("cq") end, 500)
        end
        return
      end

      local t = tests[i]
      if t.watch_expr then
        session:evaluate({ expression = t.watch_expr, context = "watch" }, function(err, resp)
          if err then
            io.write(t.name .. " (watch): ERROR " .. (err.message or tostring(err)) .. "\n")
          else
            results[t.name] = resp.result
            io.write(t.name .. " (watch): " .. tostring(resp.result) .. "\n")
          end
          io.flush()
          run_test(i + 1)
        end)
      else
        captured_output = {}
        local prefix = t.hex and "p/x " or "p "
        session:evaluate({
          expression = prefix .. t.repl_expr,
          context = "repl",
        }, function()
          vim.defer_fn(function()
            local val = nil
            for _, line in ipairs(captured_output) do
              local v = line:match("^%(.-%)%s+(.+)")
              if v then val = v end
            end
            if val then
              results[t.name] = val
              io.write(t.name .. " (repl): " .. val .. "\n")
            else
              io.write(t.name .. " (repl): FAILED - output: " .. vim.inspect(captured_output) .. "\n")
            end
            io.flush()
            run_test(i + 1)
          end, 300)
        end)
      end
    end

    run_test(1)
  end, 500)
end

dap.listeners.after.event_exited["test"] = function()
  io.write("EXITED without breakpoint!\n")
  io.flush()
  dap.terminate()
  vim.defer_fn(function() vim.cmd("cq") end, 500)
end

vim.cmd("edit " .. demo_file)
local lines = vim.fn.readfile(demo_file)
for i, line in ipairs(lines) do
  if line:match("^%s*// BREAKPOINT") then
    vim.api.nvim_win_set_cursor(0, { i + 1, 0 })
    dap.toggle_breakpoint()
    break
  end
end

dap.run({
  type = "codelldb",
  request = "launch",
  name = "Test",
  program = binary,
  cwd = demo_dir,
})
