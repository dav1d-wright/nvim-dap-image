describe("dapui variable tree", function()
  local dapui
  -- The icons nvim-dap-ui renders expandable entries with.
  local icons = { expanded = "▾", collapsed = "▸", current_frame = "▸" }

  before_each(function()
    package.loaded["nvim-dap-image.dapui"] = nil
    dapui = require("nvim-dap-image.dapui")
  end)

  describe("is_variable_tree", function()
    it("accepts the scopes, watches and hover windows", function()
      assert.is_true(dapui.is_variable_tree("dapui_scopes"))
      assert.is_true(dapui.is_variable_tree("dapui_watches"))
      assert.is_true(dapui.is_variable_tree("dapui_hover"))
    end)

    it("rejects source and other dap windows", function()
      assert.is_false(dapui.is_variable_tree("cpp"))
      assert.is_false(dapui.is_variable_tree("dapui_breakpoints"))
      assert.is_false(dapui.is_variable_tree("dap-repl"))
    end)
  end)

  describe("name_path", function()
    -- A scopes window with `container` expanded, as nvim-dap-ui renders it:
    -- one space of indent per level, an icon for expandable entries and a
    -- space for leaves.
    local scopes = {
      icons.expanded .. " Locals:",
      " " .. icons.collapsed .. " cv_img cv::Mat = {...}",
      " " .. icons.expanded .. " container ImageContainer = {...}",
      "  " .. icons.collapsed .. " image cv::Mat",
      "  " .. icons.collapsed .. ' path std::string = "demo.png"',
      "   not_an_image int = 42",
      "",
      icons.collapsed .. " Registers:",
    }

    it("returns the scope and variable for a top level variable", function()
      assert.same({ "Locals:", "cv_img" }, dapui.name_path(scopes, 2, icons))
    end)

    it("returns the full path for a nested variable", function()
      assert.same({ "Locals:", "container", "image" }, dapui.name_path(scopes, 4, icons))
    end)

    it("treats a leaf at the same depth as a sibling", function()
      assert.same({ "Locals:", "not_an_image" }, dapui.name_path(scopes, 6, icons))
    end)

    it("returns just the scope on a scope line", function()
      assert.same({ "Locals:" }, dapui.name_path(scopes, 1, icons))
    end)

    it("returns nil on a blank line", function()
      assert.is_nil(dapui.name_path(scopes, 7, icons))
    end)

    it("returns nil past the end of the buffer", function()
      assert.is_nil(dapui.name_path(scopes, 99, icons))
    end)

    it("reads a hover window where the root is an expression", function()
      local hover = {
        icons.expanded .. " image ImageInput & = {...}",
        " " .. icons.collapsed .. " image cv::Mat",
        " " .. icons.collapsed .. ' path std::string = "face1.png"',
      }
      assert.same({ "image", "image" }, dapui.name_path(hover, 2, icons))
      assert.same({ "image" }, dapui.name_path(hover, 1, icons))
    end)
  end)
end)
