local evaluate = require("nvim-dap-image.evaluate")
local config = require("nvim-dap-image.config")

local M = {}

M._extractors = {}

function M.register(extractor)
  local filetypes = extractor.filetypes
  if type(filetypes) == "string" then
    filetypes = { filetypes }
  end
  for _, ft in ipairs(filetypes) do
    if not M._extractors[ft] then
      M._extractors[ft] = {}
    end
    table.insert(M._extractors[ft], extractor)
    table.sort(M._extractors[ft], function(a, b)
      return a.priority < b.priority
    end)
  end
end

function M.get_extractors(filetype)
  return M._extractors[filetype] or {}
end

local function generate_tmp_path(ext)
  local tmp_dir = config.current.tmp_dir
  local id = string.format("%x", math.random(0, 0xFFFFFFFF))
  return tmp_dir .. "/dap_img_" .. id .. (ext or ".png")
end

--- Helpers passed to extractor extract functions for multi-step extraction.
local function make_helpers()
  return {
    evaluate = function(expr, callback)
      evaluate.evaluate(expr, callback)
    end,
    evaluate_full = function(expr, callback)
      evaluate.evaluate_full(expr, callback)
    end,
    repl_evaluate = function(expr, callback, opts)
      evaluate.repl_evaluate(expr, callback, opts)
    end,
    read_memory = function(address, count, callback)
      evaluate.read_memory(address, count, callback)
    end,
  }
end

local function try_extractor(extractor, var_name, extractors_list, index, callback)
  local detect_expr = extractor.detect(var_name)

  evaluate.evaluate(detect_expr, function(err, result)
    if err or not result or result == "False" or result == "false" or result == "0" then
      local next_index = index + 1
      if next_index > #extractors_list then
        callback("No extractor matched variable '" .. var_name .. "'")
        return
      end
      try_extractor(extractors_list[next_index], var_name, extractors_list, next_index, callback)
      return
    end

    -- Detection succeeded; run extraction
    local tmp_path = generate_tmp_path(extractor.tmp_ext)
    local helpers = make_helpers()

    extractor.extract(var_name, tmp_path, helpers, function(extract_err)
      if extract_err then
        callback("Extraction failed (" .. extractor.name .. "): " .. extract_err)
        return
      end
      callback(nil, tmp_path, extractor.name)
    end)
  end)
end

function M.detect_and_extract(var_name, callback)
  local ft = evaluate.get_filetype()
  if not ft or ft == "" then
    callback("Could not determine filetype")
    return
  end

  local extractors = vim.list_slice(M.get_extractors(ft))

  for _, ext in ipairs(config.current.extractors) do
    local user_fts = ext.filetypes
    if type(user_fts) == "string" then user_fts = { user_fts } end
    for _, uft in ipairs(user_fts) do
      if uft == ft then
        table.insert(extractors, ext)
        break
      end
    end
  end

  table.sort(extractors, function(a, b)
    return a.priority < b.priority
  end)

  if #extractors == 0 then
    callback("No extractors registered for filetype '" .. ft .. "'")
    return
  end

  try_extractor(extractors[1], var_name, extractors, 1, callback)
end

return M
