local registry = require("nvim-dap-image.extractors")

--- Helper: create an extract function that evaluates a single expression.
--- The expression should write the image to tmp_path as a side effect.
local function expr_extract(make_expr)
  return function(var_name, tmp_path, helpers, callback)
    local expr = make_expr(var_name, tmp_path)
    helpers.evaluate(expr, function(err)
      if err then
        callback(err)
        return
      end
      callback(nil)
    end)
  end
end

local function register()
  registry.register({
    name = "OpenCV image",
    filetypes = "python",
    priority = 10,
    detect = function(var_name)
      return "hasattr(" .. var_name .. ", 'shape') and len(" .. var_name .. ".shape) >= 2 and __import__('cv2')"
    end,
    extract = expr_extract(function(var_name, tmp_path)
      return "__import__('cv2').imwrite('" .. tmp_path .. "', " .. var_name .. ")"
    end),
  })

  registry.register({
    name = "PIL Image",
    filetypes = "python",
    priority = 20,
    detect = function(var_name)
      return "isinstance(" .. var_name .. ", __import__('PIL.Image', fromlist=['Image']).Image)"
    end,
    extract = expr_extract(function(var_name, tmp_path)
      return var_name .. ".save('" .. tmp_path .. "', 'PNG')"
    end),
  })

  registry.register({
    name = "NumPy array",
    filetypes = "python",
    priority = 30,
    detect = function(var_name)
      return "isinstance(" .. var_name .. ", __import__('numpy').ndarray) and " .. var_name .. ".ndim in (2, 3)"
    end,
    extract = expr_extract(function(var_name, tmp_path)
      return "__import__('PIL.Image', fromlist=['Image']).fromarray(" .. var_name .. ").save('" .. tmp_path .. "', 'PNG')"
    end),
  })

  registry.register({
    name = "Matplotlib Figure",
    filetypes = "python",
    priority = 40,
    detect = function(var_name)
      return "isinstance(" .. var_name .. ", __import__('matplotlib.figure', fromlist=['Figure']).Figure)"
    end,
    extract = expr_extract(function(var_name, tmp_path)
      return var_name .. ".savefig('" .. tmp_path .. "', format='png', bbox_inches='tight')"
    end),
  })
end

return { register = register }
