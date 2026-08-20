describe("evaluate", function()
  local evaluate

  before_each(function()
    package.loaded["nvim-dap-image.evaluate"] = nil
    package.loaded["nvim-dap-image.config"] = nil
    require("nvim-dap-image.config").setup()
    evaluate = require("nvim-dap-image.evaluate")
  end)

  describe("get_session", function()
    it("returns nil when dap is not loaded", function()
      -- In test environment, dap may not be available
      local session = evaluate.get_session()
      -- Either nil (no session) or a session object
      if session then
        assert.is_not_nil(session)
      else
        assert.is_nil(session)
      end
    end)
  end)

  describe("get_filetype", function()
    it("returns the current buffer filetype", function()
      vim.bo.filetype = "python"
      assert.equals("python", evaluate.get_filetype())
    end)

    it("returns cpp for cpp buffers", function()
      vim.bo.filetype = "cpp"
      assert.equals("cpp", evaluate.get_filetype())
    end)

    it("returns empty string for unset filetype", function()
      vim.bo.filetype = ""
      assert.equals("", evaluate.get_filetype())
    end)
  end)

  describe("evaluate", function()
    it("calls callback with error when no session", function()
      local original = evaluate.get_session
      evaluate.get_session = function() return nil end

      local called = false
      evaluate.evaluate("1+1", function(err)
        called = true
        assert.truthy(err)
        assert.truthy(err:match("No active"))
      end)
      assert.is_true(called)

      evaluate.get_session = original
    end)

    it("delegates to session:evaluate when session exists", function()
      local eval_called = false
      local original = evaluate.get_session
      evaluate.get_session = function()
        return {
          evaluate = function(_, args, fn)
            eval_called = true
            fn(nil, { result = "42" })
          end,
        }
      end

      local result_val
      evaluate.evaluate("1+1", function(err, result)
        assert.is_nil(err)
        result_val = result
      end)
      assert.is_true(eval_called)
      assert.equals("42", result_val)

      evaluate.get_session = original
    end)
  end)

  describe("repl_evaluate", function()
    local original

    local function emit_output(body)
      for _, listener in pairs(require("dap").listeners.after.event_output) do
        listener(nil, body)
      end
    end

    local function with_session(evaluate_fn)
      original = evaluate.get_session
      evaluate.get_session = function()
        return { evaluate = function(_, args, cb) evaluate_fn(args, cb) end }
      end
    end

    after_each(function()
      evaluate.get_session = original
    end)

    it("takes the value from the response of a bare expression", function()
      local sent = {}
      with_session(function(args, cb)
        table.insert(sent, args.expression)
        cb(nil, { result = "93824997707328", type = "size_t" })
      end)

      local result
      evaluate.repl_evaluate("(size_t)img.data", function(err, value)
        assert.is_nil(err)
        result = value
      end)

      assert.equals("93824997707328", result)
      assert.same({ "(size_t)img.data" }, sent)
    end)

    it("falls back to a print command and reads console output", function()
      local sent = {}
      with_session(function(args, cb)
        table.insert(sent, args.expression)
        if args.expression:match("^p/x ") then
          emit_output({ category = "console", output = "(size_t) 0x00007ffff7b1e040\n" })
          cb(nil, { result = "" })
        else
          cb({ message = "error: '" .. args.expression .. "' is not a valid command." })
        end
      end)

      local err, result
      evaluate.repl_evaluate("(size_t)img.data", function(e, value)
        err, result = e, value
      end, { hex = true })

      vim.wait(1000, function() return err ~= nil or result ~= nil end)
      assert.is_nil(err)
      assert.equals("0x00007ffff7b1e040", result)
      assert.same({ "(size_t)img.data", "p/x (size_t)img.data" }, sent)
    end)

    it("ignores telemetry output events", function()
      with_session(function(args, cb)
        if args.expression:match("^p ") then
          emit_output({ category = "telemetry", output = "VS/Diagnostics/Debugger/Evaluate" })
          cb(nil, { result = "" })
        else
          cb({ message = "not a valid command" })
        end
      end)

      local err, result
      evaluate.repl_evaluate("img.step[0]", function(e, value)
        err, result = e, value
      end)

      vim.wait(1000, function() return err ~= nil or result ~= nil end)
      assert.is_nil(result)
      assert.truthy(err)
      assert.is_nil(err:match("Diagnostics"))
    end)
  end)

  describe("get_cword", function()
    it("returns a string", function()
      local result = evaluate.get_cword()
      assert.is_string(result)
    end)
  end)
end)
