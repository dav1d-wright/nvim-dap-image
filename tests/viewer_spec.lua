describe("viewer", function()
  local viewer
  local config

  before_each(function()
    package.loaded["nvim-dap-image.viewer"] = nil
    package.loaded["nvim-dap-image.config"] = nil
    config = require("nvim-dap-image.config")
    config.setup()
    viewer = require("nvim-dap-image.viewer")
  end)

  after_each(function()
    viewer.close_all()
  end)

  it("starts with no viewers", function()
    assert.equals(0, #viewer._viewers)
  end)

  describe("open", function()
    it("returns nil for missing image file", function()
      local result = viewer.open("/nonexistent/path.png")
      assert.is_nil(result)
    end)

    it("returns nil for empty image file", function()
      local tmp = vim.fn.tempname() .. ".png"
      vim.fn.writefile({}, tmp)
      local result = viewer.open(tmp)
      assert.is_nil(result)
      vim.fn.delete(tmp)
    end)
  end)

  describe("close_all", function()
    it("handles empty viewer list", function()
      assert.has_no.errors(function()
        viewer.close_all()
      end)
    end)
  end)

  describe("close_focused", function()
    it("handles no focused viewer", function()
      assert.has_no.errors(function()
        viewer.close_focused()
      end)
    end)
  end)
end)
