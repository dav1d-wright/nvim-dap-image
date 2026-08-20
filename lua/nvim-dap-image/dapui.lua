local evaluate = require("nvim-dap-image.evaluate")

local M = {}

--- nvim-dap-ui windows that render a variable tree, and how their root lines
--- are addressed: a scope holds variables, while hover and watches roots are
--- expressions that were evaluated.
local VARIABLE_TREES = {
  dapui_scopes = "scope",
  dapui_hover = "expression",
  dapui_watches = "expression",
}

function M.is_variable_tree(filetype)
  return VARIABLE_TREES[filetype] ~= nil
end

--- Split a rendered nvim-dap-ui line into the column its name starts at and the
--- name itself. Every entry is written as
--- `<indent><expand icon or space> <name> [<type>] [= <value>]`, so the name
--- column gives the nesting depth. The icon counts as one cell regardless of
--- how many bytes it takes.
local function parse_entry(line, icons)
  local indent, rest = line:match("^( *)(.*)$")
  if rest == "" then return nil end

  for _, icon in pairs(icons) do
    if icon ~= "" and rest:sub(1, #icon + 1) == icon .. " " then
      local name = rest:sub(#icon + 2):match("^(%S+)")
      return name and { col = #indent + 2, name = name }
    end
  end

  local name = rest:match("^(%S+)")
  return name and { col = #indent, name = name }
end

--- Names from the root of the tree down to the entry on `lnum`, e.g.
--- `{ "Locals", "container", "image" }`.
--- @param lines string[] Rendered buffer lines
--- @param lnum number 1-based line number
--- @param icons table nvim-dap-ui expand icons
--- @return string[]|nil
function M.name_path(lines, lnum, icons)
  local entry = parse_entry(lines[lnum] or "", icons)
  if not entry then return nil end

  local path = { entry.name }
  local col = entry.col
  for i = lnum - 1, 1, -1 do
    local parent = parse_entry(lines[i], icons)
    if parent and parent.col < col then
      table.insert(path, 1, parent.name)
      col = parent.col
    end
  end
  return path
end

--- Walk down a variable tree, matching one name per level, and return the
--- adapter's evaluate name for the last one.
local function descend(session, reference, names, callback)
  session:request("variables", { variablesReference = reference }, function(err, response)
    if err then
      callback(err.message or tostring(err))
      return
    end

    local name = names[1]
    for _, variable in ipairs(response.variables) do
      if variable.name == name then
        if #names == 1 then
          if not variable.evaluateName then
            callback("Adapter gave no evaluate name for '" .. name .. "'")
            return
          end
          callback(nil, variable.evaluateName)
          return
        end
        if variable.variablesReference == 0 then
          callback("'" .. name .. "' has no members")
          return
        end
        descend(session, variable.variablesReference, vim.list_slice(names, 2), callback)
        return
      end
    end
    callback("No variable named '" .. name .. "' at this level")
  end)
end

local function resolve_in_scope(session, names, callback)
  session:request("scopes", { frameId = session.current_frame.id }, function(err, response)
    if err then
      callback(err.message or tostring(err))
      return
    end

    local scope_name = names[1]:gsub(":$", "")
    for _, scope in ipairs(response.scopes) do
      if scope.name == scope_name then
        descend(session, scope.variablesReference, vim.list_slice(names, 2), callback)
        return
      end
    end
    callback("No scope named '" .. scope_name .. "'")
  end)
end

local function resolve_under_expression(session, names, callback)
  local expression = names[1]
  session:evaluate({ expression = expression, context = "hover" }, function(err, response)
    if err then
      callback(err.message or tostring(err))
      return
    end
    if not response.variablesReference or response.variablesReference == 0 then
      callback("'" .. expression .. "' has no members")
      return
    end
    descend(session, response.variablesReference, vim.list_slice(names, 2), callback)
  end)
end

--- Resolve the expression for the variable the cursor is on in an
--- nvim-dap-ui variable tree.
--- @param callback fun(err?: string, expr?: string)
function M.resolve(callback)
  local session = evaluate.get_session()
  if not session or not session.current_frame then
    callback("No stopped debug session")
    return
  end

  local kind = VARIABLE_TREES[vim.bo.filetype]
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local names = M.name_path(lines, lnum, require("dapui.config").icons)
  if not names then
    callback("No variable on this line")
    return
  end

  if #names == 1 then
    if kind == "scope" then
      callback("Line " .. lnum .. " is a scope, not a variable")
      return
    end
    callback(nil, names[1])
    return
  end

  if kind == "scope" then
    resolve_in_scope(session, names, callback)
  else
    resolve_under_expression(session, names, callback)
  end
end

return M
