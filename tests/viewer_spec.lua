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

  -- image.nvim cannot render headlessly, so these run against a fake image-view.
  describe("delegation to image-view", function()
    local real_image_view
    local fake

    before_each(function()
      real_image_view = package.loaded["image-view"]
      fake = { opened = {}, closed = {}, close_all_called = false }
      fake.open = function(path, opts)
        local handle = { path = path, opts = opts }
        table.insert(fake.opened, handle)
        return handle
      end
      fake.close = function(handle)
        table.insert(fake.closed, handle)
        if handle.opts.on_close then handle.opts.on_close() end
      end
      fake.close_all = function()
        fake.close_all_called = true
      end
      package.loaded["image-view"] = fake
    end)

    after_each(function()
      package.loaded["image-view"] = real_image_view
    end)

    it("passes the configured window geometry through", function()
      config.setup({ window = { width_pct = 0.42 } })

      viewer.open("/tmp/x.png")

      assert.equals(0.42, fake.opened[1].opts.window.width_pct)
      assert.equals("rounded", fake.opened[1].opts.window.border)
    end)

    it("titles the window with the caller's title", function()
      viewer.open("/tmp/x.png", { title = "img (python)" })

      assert.equals("img (python)", fake.opened[1].opts.title)
    end)

    it("falls back to a default title", function()
      viewer.open("/tmp/x.png")

      assert.equals("Debug Image", fake.opened[1].opts.title)
    end)

    it("registers the handle it opened", function()
      local handle = viewer.open("/tmp/x.png")

      assert.equals(1, #viewer._viewers)
      assert.equals(handle, viewer._viewers[1])
    end)

    it("deletes the temp file on close when auto_cleanup_temp is set", function()
      local tmp = vim.fn.tempname() .. ".png"
      vim.fn.writefile({ "x" }, tmp)
      local handle = viewer.open(tmp)

      viewer.close(handle)

      assert.equals(0, vim.fn.filereadable(tmp))
    end)

    it("keeps the temp file when auto_cleanup_temp is off", function()
      config.setup({ auto_cleanup_temp = false })
      local tmp = vim.fn.tempname() .. ".png"
      vim.fn.writefile({ "x" }, tmp)
      local handle = viewer.open(tmp)

      viewer.close(handle)

      assert.equals(1, vim.fn.filereadable(tmp))
      vim.fn.delete(tmp)
    end)

    it("deregisters a viewer closed by its own keymap", function()
      local handle = viewer.open("/tmp/x.png")

      -- image-view runs on_close for every close path, including `q`.
      handle.opts.on_close()

      assert.equals(0, #viewer._viewers)
    end)

    it("closes only the viewers it opened, never image-view's whole set", function()
      local first = viewer.open("/tmp/a.png")
      local second = viewer.open("/tmp/b.png")

      viewer.close_all()

      assert.is_false(fake.close_all_called)
      assert.equals(2, #fake.closed)
      assert.equals(first, fake.closed[1])
      assert.equals(second, fake.closed[2])
      assert.equals(0, #viewer._viewers)
    end)

    it("closes the focused viewer only", function()
      local first = viewer.open("/tmp/a.png")
      local second = viewer.open("/tmp/b.png")
      second.win = vim.api.nvim_get_current_win()

      viewer.close_focused()

      assert.equals(1, #fake.closed)
      assert.equals(second, fake.closed[1])
      assert.equals(1, #viewer._viewers)
      assert.equals(first, viewer._viewers[1])
    end)
  end)
end)
