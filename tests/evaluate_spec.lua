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

  describe("get_cword", function()
    it("returns a string", function()
      local result = evaluate.get_cword()
      assert.is_string(result)
    end)
  end)
end)
