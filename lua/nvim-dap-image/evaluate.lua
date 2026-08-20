local M = {}

function M.get_session()
  local ok, dap = pcall(require, "dap")
  if not ok then return nil end
  return dap.session()
end

--- The filetype that selects extractors. It comes from the stopped frame's
--- source file, because the cursor can sit in a window that holds no source at
--- all, such as a nvim-dap-ui variables window.
function M.get_filetype()
  local session = M.get_session()
  local frame = session and session.current_frame
  local path = frame and frame.source and frame.source.path
  if path then
    local ft = vim.filetype.match({ filename = path })
    if ft then return ft end
  end
  return vim.bo.filetype
end

function M.evaluate(expr, callback, context)
  local session = M.get_session()
  if not session then
    callback("No active debug session")
    return
  end

  session:evaluate(
    { expression = expr, context = context or "watch" },
    function(err, response)
      if err then
        callback(err.message or tostring(err))
        return
      end
      callback(nil, response.result)
    end
  )
end

--- Like evaluate but returns the full DAP response object.
function M.evaluate_full(expr, callback, context)
  local session = M.get_session()
  if not session then
    callback("No active debug session")
    return
  end

  session:evaluate(
    { expression = expr, context = context or "watch" },
    function(err, response)
      if err then
        callback(err.message or tostring(err))
        return
      end
      callback(nil, response)
    end
  )
end

--- Output event categories that carry debugger output. Anything else, such as
--- cppdbg's "telemetry" events, is noise for expression results.
local OUTPUT_CATEGORIES = { console = true, stdout = true, stderr = true }

local function error_message(err)
  if not err then return nil end
  return err.message or tostring(err)
end

--- Evaluate a bare expression in repl context. cppdbg answers with the value in
--- the response body.
local function evaluate_bare(session, expr, callback)
  session:evaluate({ expression = expr, context = "repl" }, function(err, response)
    if err then
      callback(error_message(err))
      return
    end
    local result = response and response.result
    if not result or result == "" then
      callback("empty response")
      return
    end
    callback(nil, result)
  end)
end

--- Evaluate through a debugger print command, reading the value back from
--- console output. codelldb takes repl input as an LLDB command, so an
--- expression only produces a value this way.
local function evaluate_command(session, expr, opts, callback)
  local dap = require("dap")
  local captured = {}
  local listener_key = "nvim_dap_image_repl_" .. tostring(math.random(0, 0xFFFFFF))

  dap.listeners.after.event_output[listener_key] = function(_, body)
    if body.output and body.output ~= "" and OUTPUT_CATEGORIES[body.category or "console"] then
      table.insert(captured, (body.output:gsub("\n$", "")))
    end
  end

  local prefix = (opts and opts.hex) and "p/x " or "p "
  session:evaluate({ expression = prefix .. expr, context = "repl" }, function(err, response)
    vim.defer_fn(function()
      dap.listeners.after.event_output[listener_key] = nil

      local result = nil
      for _, line in ipairs(captured) do
        -- codelldb output format: (type) value
        local val = line:match("^%(.-%)%s+(.+)")
        if val then result = val end
      end
      if not result and response and response.result and response.result ~= "" then
        result = response.result
      end

      if result then
        callback(nil, result)
      else
        callback(error_message(err) or ("no output for '" .. prefix .. expr .. "'"))
      end
    end, 200)
  end)
end

--- Evaluate an expression via the adapter's repl. Needed for expressions that
--- watch context can't handle, such as array indexing in codelldb.
--- @param expr string Expression to evaluate
--- @param callback function(err, result_string)
--- @param opts? {hex: boolean}
function M.repl_evaluate(expr, callback, opts)
  local session = M.get_session()
  if not session then
    callback("No active debug session")
    return
  end

  -- The bare expression goes first: cppdbg reports a print command as a
  -- successful evaluation whose result holds the debugger's error text, which
  -- can't be told apart from a value.
  evaluate_bare(session, expr, function(bare_err, bare_result)
    if bare_result then
      callback(nil, bare_result)
      return
    end
    evaluate_command(session, expr, opts, function(cmd_err, cmd_result)
      if cmd_result then
        callback(nil, cmd_result)
        return
      end
      callback(string.format("%s (bare expression: %s)", cmd_err, bare_err))
    end)
  end)
end

function M.read_memory(address, count, callback)
  local session = M.get_session()
  if not session then
    callback("No active debug session")
    return
  end

  session:request("readMemory", {
    memoryReference = address,
    count = count,
  }, function(err, response)
    if err then
      callback(err.message or tostring(err))
      return
    end
    callback(nil, response.data)
  end)
end

function M.get_cword()
  return vim.fn.expand("<cword>")
end

return M
