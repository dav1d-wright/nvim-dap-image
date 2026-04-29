describe("integration", function()
  local registry
  local evaluate
  local config

  before_each(function()
    package.loaded["nvim-dap-image.extractors"] = nil
    package.loaded["nvim-dap-image.extractors.python"] = nil
    package.loaded["nvim-dap-image.extractors.cpp"] = nil
    package.loaded["nvim-dap-image.evaluate"] = nil
    package.loaded["nvim-dap-image.config"] = nil

    config = require("nvim-dap-image.config")
    config.setup()
    evaluate = require("nvim-dap-image.evaluate")
    registry = require("nvim-dap-image.extractors")
  end)

  describe("detect_and_extract with mocked DAP session", function()
    it("calls callback with error when filetype is empty", function()
      evaluate.get_filetype = function() return "" end

      require("nvim-dap-image.extractors.python").register()

      local err_msg
      registry.detect_and_extract("img", function(err)
        err_msg = err
      end)
      assert.truthy(err_msg)
      assert.truthy(err_msg:match("filetype"))
    end)

    it("calls callback with error for filetype with no extractors", function()
      evaluate.get_filetype = function() return "haskell" end

      local err_msg
      registry.detect_and_extract("img", function(err)
        err_msg = err
      end)
      assert.truthy(err_msg)
      assert.truthy(err_msg:match("No extractors"))
    end)

    it("tries extractors in priority order until one matches", function()
      evaluate.get_filetype = function() return "python" end

      local detect_calls = {}
      local extract_call = nil

      evaluate.evaluate = function(expr, callback)
        if expr:match("shape") then
          table.insert(detect_calls, "opencv")
          callback(nil, "False")
        elseif expr:match("PIL") then
          table.insert(detect_calls, "pil")
          callback(nil, "True")
        elseif expr:match("save") then
          extract_call = expr
          callback(nil, "None")
        else
          callback(nil, "False")
        end
      end

      require("nvim-dap-image.extractors.python").register()

      local result_path, result_name
      registry.detect_and_extract("my_img", function(err, path, name)
        assert.is_nil(err)
        result_path = path
        result_name = name
      end)

      assert.equals("opencv", detect_calls[1])
      assert.equals("pil", detect_calls[2])
      assert.equals("PIL Image", result_name)
      assert.truthy(result_path:match("%.png$"))
      assert.truthy(extract_call:match("my_img"))
    end)

    it("reports error when no extractor matches", function()
      evaluate.get_filetype = function() return "python" end

      evaluate.evaluate = function(_, callback)
        callback(nil, "False")
      end

      require("nvim-dap-image.extractors.python").register()

      local err_msg
      registry.detect_and_extract("x", function(err)
        err_msg = err
      end)
      assert.truthy(err_msg)
      assert.truthy(err_msg:match("No extractor matched"))
    end)

    it("reports extraction error", function()
      evaluate.get_filetype = function() return "cpp" end

      -- detect succeeds (mat.rows returns a number), but extraction fails
      -- because evaluate_full returns an error for mat.data
      evaluate.evaluate = function(expr, callback)
        if expr == "mat.rows" then
          callback(nil, "480")  -- detect succeeds
        elseif expr == "mat.cols" then
          callback(nil, "640")
        elseif expr == "mat.flags" then
          callback(nil, "16")  -- CV_8UC3
        else
          callback("not supported")
        end
      end

      evaluate.evaluate_full = function(_, callback)
        callback("cannot read data pointer")
      end

      evaluate.repl_evaluate = function(_, callback)
        callback("repl also failed")
      end

      require("nvim-dap-image.extractors.cpp").register()

      local err_msg
      registry.detect_and_extract("mat", function(err)
        err_msg = err
      end)
      assert.truthy(err_msg)
      assert.truthy(err_msg:match("Extraction failed"))
    end)

    it("uses user-provided extractors from config", function()
      evaluate.get_filetype = function() return "python" end

      config.current.extractors = {
        {
          name = "Custom Tensor",
          filetypes = "python",
          priority = 5,
          detect = function(var) return "hasattr(" .. var .. ", 'is_cuda')" end,
          extract = function(var, tmp_path, helpers, callback)
            local expr = "__import__('torchvision.utils', fromlist=['save_image']).save_image(" .. var .. ", '" .. tmp_path .. "')"
            helpers.evaluate(expr, function(err)
              callback(err)
            end)
          end,
        },
      }

      local detect_expr
      evaluate.evaluate = function(expr, callback)
        if not detect_expr then
          detect_expr = expr
          callback(nil, "True")
        else
          callback(nil, "None")
        end
      end

      require("nvim-dap-image.extractors.python").register()

      local result_name
      registry.detect_and_extract("tensor", function(err, _, name)
        assert.is_nil(err)
        result_name = name
      end)

      assert.equals("Custom Tensor", result_name)
      assert.truthy(detect_expr:match("is_cuda"))
    end)

    it("handles detect expression that errors", function()
      evaluate.get_filetype = function() return "python" end

      local call_count = 0
      evaluate.evaluate = function(_, callback)
        call_count = call_count + 1
        if call_count == 1 then
          callback("NameError: cv2")
        elseif call_count == 2 then
          callback(nil, "True")
        else
          callback(nil, "None")
        end
      end

      require("nvim-dap-image.extractors.python").register()

      local result_name
      registry.detect_and_extract("img", function(err, _, name)
        assert.is_nil(err)
        result_name = name
      end)
      assert.equals("PIL Image", result_name)
    end)

    it("finds cpp extractors when filetype is c", function()
      evaluate.get_filetype = function() return "c" end

      -- Mock responses for cv::Mat metadata extraction.
      -- flags=16 encodes CV_8UC3: depth=0 (8U), channels=((16>>3)&0x1FF)+1=3
      local watch_responses = {
        ["mat.rows"] = "480",
        ["mat.cols"] = "640",
        ["mat.flags"] = "16",
        -- step[0] fails in watch (codelldb), triggering repl fallback
      }
      local repl_responses = {
        ["mat.step[0]"] = "1920",
      }

      evaluate.evaluate = function(expr, callback)
        local result = watch_responses[expr]
        if result then
          callback(nil, result)
        else
          callback("not supported in watch")
        end
      end

      evaluate.evaluate_full = function(expr, callback)
        if expr == "mat.data" then
          callback(nil, { result = '0x0000001000000000 ""', memoryReference = "0x1000000000" })
        else
          callback("not supported")
        end
      end

      evaluate.repl_evaluate = function(expr, callback)
        local result = repl_responses[expr]
        if result then
          callback(nil, result)
        else
          callback("repl failed: " .. expr)
        end
      end

      evaluate.read_memory = function(_, count, callback)
        -- Return fake pixel data as base64
        local raw = string.rep("\0", count)
        callback(nil, vim.base64.encode(raw))
      end

      require("nvim-dap-image.extractors.cpp").register()

      local result_name
      registry.detect_and_extract("mat", function(err, _, name)
        assert.is_nil(err)
        result_name = name
      end)
      assert.equals("OpenCV cv::Mat", result_name)
    end)
  end)
end)
