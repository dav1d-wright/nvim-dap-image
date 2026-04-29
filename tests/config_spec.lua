local config = require("nvim-dap-image.config")

describe("config", function()
  before_each(function()
    config.current = vim.deepcopy(config.defaults)
  end)

  describe("defaults", function()
    it("has a tmp_dir", function()
      assert.truthy(config.defaults.tmp_dir)
      assert.truthy(config.defaults.tmp_dir:match("nvim%-dap%-image$"))
    end)

    it("has window settings", function()
      assert.equals(0.6, config.defaults.window.width_pct)
      assert.equals(0.6, config.defaults.window.height_pct)
      assert.equals("rounded", config.defaults.window.border)
    end)

    it("has auto_close_on_terminate enabled", function()
      assert.is_true(config.defaults.auto_close_on_terminate)
    end)

    it("has auto_cleanup_temp enabled", function()
      assert.is_true(config.defaults.auto_cleanup_temp)
    end)

    it("starts with empty user extractors", function()
      assert.same({}, config.defaults.extractors)
    end)
  end)

  describe("setup", function()
    it("merges user options over defaults", function()
      config.setup({ window = { border = "single" } })
      assert.equals("single", config.current.window.border)
      assert.equals(0.6, config.current.window.width_pct)
    end)

    it("overrides tmp_dir", function()
      config.setup({ tmp_dir = "/tmp/custom_dap_image" })
      assert.equals("/tmp/custom_dap_image", config.current.tmp_dir)
    end)

    it("creates tmp_dir on setup", function()
      local test_dir = vim.fn.tempname() .. "/nvim-dap-image-test"
      config.setup({ tmp_dir = test_dir })
      assert.equals(1, vim.fn.isdirectory(test_dir))
      vim.fn.delete(test_dir, "d")
    end)

    it("does not mutate defaults", function()
      local original_border = config.defaults.window.border
      config.setup({ window = { border = "none" } })
      assert.equals(original_border, config.defaults.window.border)
    end)
  end)
end)
