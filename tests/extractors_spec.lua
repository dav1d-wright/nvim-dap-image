describe("extractors", function()
  local registry

  before_each(function()
    package.loaded["nvim-dap-image.extractors"] = nil
    package.loaded["nvim-dap-image.extractors.python"] = nil
    package.loaded["nvim-dap-image.extractors.cpp"] = nil
    package.loaded["nvim-dap-image.config"] = nil
    require("nvim-dap-image.config").setup()
    registry = require("nvim-dap-image.extractors")
  end)

  describe("register", function()
    it("registers an extractor for a single filetype", function()
      registry.register({
        name = "test",
        filetypes = "python",
        priority = 10,
        detect = function() return "True" end,
        extract = function() end,
      })

      local extractors = registry.get_extractors("python")
      assert.equals(1, #extractors)
      assert.equals("test", extractors[1].name)
    end)

    it("registers an extractor for multiple filetypes", function()
      registry.register({
        name = "multi",
        filetypes = { "cpp", "c" },
        priority = 10,
        detect = function() return "1" end,
        extract = function() end,
      })

      assert.equals(1, #registry.get_extractors("cpp"))
      assert.equals(1, #registry.get_extractors("c"))
      assert.equals("multi", registry.get_extractors("cpp")[1].name)
      assert.equals("multi", registry.get_extractors("c")[1].name)
    end)

    it("sorts extractors by priority", function()
      registry.register({ name = "low", filetypes = "python", priority = 50, detect = function() end, extract = function() end })
      registry.register({ name = "high", filetypes = "python", priority = 10, detect = function() end, extract = function() end })
      registry.register({ name = "mid", filetypes = "python", priority = 30, detect = function() end, extract = function() end })

      local extractors = registry.get_extractors("python")
      assert.equals("high", extractors[1].name)
      assert.equals("mid", extractors[2].name)
      assert.equals("low", extractors[3].name)
    end)

    it("keeps filetypes separate", function()
      registry.register({ name = "py", filetypes = "python", priority = 10, detect = function() end, extract = function() end })
      registry.register({ name = "cpp", filetypes = "cpp", priority = 10, detect = function() end, extract = function() end })

      assert.equals(1, #registry.get_extractors("python"))
      assert.equals(1, #registry.get_extractors("cpp"))
    end)

    it("returns empty list for unknown filetype", function()
      assert.same({}, registry.get_extractors("rust"))
    end)
  end)

  describe("python extractors", function()
    before_each(function()
      require("nvim-dap-image.extractors.python").register()
    end)

    it("registers four extractors", function()
      local extractors = registry.get_extractors("python")
      assert.equals(4, #extractors)
    end)

    it("orders OpenCV first", function()
      local extractors = registry.get_extractors("python")
      assert.equals("OpenCV image", extractors[1].name)
    end)

    it("orders PIL second", function()
      local extractors = registry.get_extractors("python")
      assert.equals("PIL Image", extractors[2].name)
    end)

    it("orders NumPy third", function()
      local extractors = registry.get_extractors("python")
      assert.equals("NumPy array", extractors[3].name)
    end)

    it("orders Matplotlib fourth", function()
      local extractors = registry.get_extractors("python")
      assert.equals("Matplotlib Figure", extractors[4].name)
    end)

    describe("OpenCV detect expression", function()
      it("checks for shape attribute and cv2 import", function()
        local extractors = registry.get_extractors("python")
        local expr = extractors[1].detect("img")
        assert.truthy(expr:match("shape"))
        assert.truthy(expr:match("cv2"))
      end)
    end)

    describe("OpenCV extract", function()
      it("evaluates cv2.imwrite expression", function()
        local extractors = registry.get_extractors("python")
        local evaluated_expr = nil
        local mock_helpers = {
          evaluate = function(expr, callback)
            evaluated_expr = expr
            callback(nil)
          end,
        }
        extractors[1].extract("my_image", "/tmp/test.png", mock_helpers, function(err)
          assert.is_nil(err)
        end)
        assert.truthy(evaluated_expr:match("cv2.*imwrite"))
        assert.truthy(evaluated_expr:match("my_image"))
        assert.truthy(evaluated_expr:match("/tmp/test.png"))
      end)
    end)

    describe("PIL detect expression", function()
      it("checks isinstance with PIL.Image", function()
        local extractors = registry.get_extractors("python")
        local expr = extractors[2].detect("pil_img")
        assert.truthy(expr:match("isinstance.*pil_img"))
        assert.truthy(expr:match("PIL"))
      end)
    end)

    describe("PIL extract", function()
      it("evaluates save expression with PNG format", function()
        local extractors = registry.get_extractors("python")
        local evaluated_expr = nil
        local mock_helpers = {
          evaluate = function(expr, callback)
            evaluated_expr = expr
            callback(nil)
          end,
        }
        extractors[2].extract("pil_img", "/tmp/out.png", mock_helpers, function(err)
          assert.is_nil(err)
        end)
        assert.truthy(evaluated_expr:match("pil_img.*save"))
        assert.truthy(evaluated_expr:match("PNG"))
        assert.truthy(evaluated_expr:match("/tmp/out.png"))
      end)
    end)

    describe("NumPy detect expression", function()
      it("checks isinstance with ndarray and dimensionality", function()
        local extractors = registry.get_extractors("python")
        local expr = extractors[3].detect("arr")
        assert.truthy(expr:match("ndarray"))
        assert.truthy(expr:match("ndim"))
      end)
    end)

    describe("NumPy extract", function()
      it("evaluates PIL.Image.fromarray expression", function()
        local extractors = registry.get_extractors("python")
        local evaluated_expr = nil
        local mock_helpers = {
          evaluate = function(expr, callback)
            evaluated_expr = expr
            callback(nil)
          end,
        }
        extractors[3].extract("arr", "/tmp/arr.png", mock_helpers, function(err)
          assert.is_nil(err)
        end)
        assert.truthy(evaluated_expr:match("fromarray%(arr%)"))
        assert.truthy(evaluated_expr:match("/tmp/arr.png"))
      end)
    end)

    describe("Matplotlib detect expression", function()
      it("checks isinstance with Figure", function()
        local extractors = registry.get_extractors("python")
        local expr = extractors[4].detect("fig")
        assert.truthy(expr:match("isinstance.*fig"))
        assert.truthy(expr:match("Figure"))
      end)
    end)

    describe("Matplotlib extract", function()
      it("evaluates savefig expression with png format", function()
        local extractors = registry.get_extractors("python")
        local evaluated_expr = nil
        local mock_helpers = {
          evaluate = function(expr, callback)
            evaluated_expr = expr
            callback(nil)
          end,
        }
        extractors[4].extract("fig", "/tmp/fig.png", mock_helpers, function(err)
          assert.is_nil(err)
        end)
        assert.truthy(evaluated_expr:match("savefig"))
        assert.truthy(evaluated_expr:match("png"))
        assert.truthy(evaluated_expr:match("/tmp/fig.png"))
      end)
    end)
  end)

  describe("cpp extractors", function()
    before_each(function()
      require("nvim-dap-image.extractors.cpp").register()
    end)

    it("registers one extractor for cpp", function()
      local extractors = registry.get_extractors("cpp")
      assert.equals(1, #extractors)
    end)

    it("registers same extractor for c filetype", function()
      local extractors = registry.get_extractors("c")
      assert.equals(1, #extractors)
      assert.equals("OpenCV cv::Mat", extractors[1].name)
    end)

    it("registers OpenCV cv::Mat extractor", function()
      local extractors = registry.get_extractors("cpp")
      assert.equals("OpenCV cv::Mat", extractors[1].name)
    end)

    describe("cv::Mat detect expression", function()
      it("evaluates .rows on the variable", function()
        local extractors = registry.get_extractors("cpp")
        local expr = extractors[1].detect("mat")
        assert.equals("mat.rows", expr)
      end)
    end)

    it("uses .bmp extension", function()
      local extractors = registry.get_extractors("cpp")
      assert.equals(".bmp", extractors[1].tmp_ext)
    end)
  end)
end)
