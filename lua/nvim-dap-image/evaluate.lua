local M = {}

function M.get_session()
  local ok, dap = pcall(require, "dap")
  if not ok then return nil end
  return dap.session()
end

function M.get_filetype()
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

--- Evaluate an expression via LLDB/GDB repl, capturing the result from
--- console output events. Needed for expressions that watch context can't
--- handle (function calls, casts, array indexing in codelldb).
--- The expression is sent with a `p` prefix (or `p/x` if opts.hex is set).
--- @param expr string Expression to evaluate
--- @param callback function(err, result_string)
--- @param opts? {hex: boolean}
function M.repl_evaluate(expr, callback, opts)
  local session = M.get_session()
  if not session then
    callback("No active debug session")
    return
  end

  local dap = require("dap")
  local captured = {}
  local listener_key = "nvim_dap_image_repl_" .. tostring(math.random(0, 0xFFFFFF))

  dap.listeners.after.event_output[listener_key] = function(_, body)
    if body.output and body.output ~= "" then
      table.insert(captured, (body.output:gsub("\n$", "")))
    end
  end

  local prefix = (opts and opts.hex) and "p/x " or "p "
  session:evaluate({
    expression = prefix .. expr,
    context = "repl",
  }, function()
    vim.defer_fn(function()
      dap.listeners.after.event_output[listener_key] = nil

      local result = nil
      for _, line in ipairs(captured) do
        -- codelldb output format: (type) value
        local val = line:match("^%(.-%)%s+(.+)")
        if val then result = val end
      end

      if result then
        callback(nil, result)
      else
        callback("No result from repl evaluate: " .. vim.inspect(captured))
      end
    end, 200)
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
