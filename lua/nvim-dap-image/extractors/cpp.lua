local registry = require("nvim-dap-image.extractors")

local function pack_le16(n)
  return string.char(n % 256, math.floor(n / 256) % 256)
end

local function pack_le32(n)
  return string.char(
    n % 256,
    math.floor(n / 256) % 256,
    math.floor(n / 65536) % 256,
    math.floor(n / 16777216) % 256
  )
end

--- Write raw BGR/grayscale pixel data as a BMP file.
--- BMP natively uses BGR byte order, matching cv::Mat's default format.
local function write_bmp(path, width, height, channels, step, raw_data)
  local bpp = channels * 8
  local row_size = math.floor((bpp * width + 31) / 32) * 4
  local palette_size = channels == 1 and 1024 or 0
  local pixel_offset = 54 + palette_size
  local pixel_data_size = row_size * height
  local file_size = pixel_offset + pixel_data_size

  local f = io.open(path, "wb")
  if not f then return "Failed to open " .. path end

  -- BMP file header (14 bytes)
  f:write("BM")
  f:write(pack_le32(file_size))
  f:write("\0\0\0\0")
  f:write(pack_le32(pixel_offset))

  -- BITMAPINFOHEADER (40 bytes)
  f:write(pack_le32(40))
  f:write(pack_le32(width))
  f:write(pack_le32(height))
  f:write(pack_le16(1))
  f:write(pack_le16(bpp))
  f:write(pack_le32(0))
  f:write(pack_le32(pixel_data_size))
  f:write(pack_le32(2835))
  f:write(pack_le32(2835))
  f:write(pack_le32(channels == 1 and 256 or 0))
  f:write(pack_le32(0))

  -- Grayscale palette (256 entries, 4 bytes each: B G R 0)
  if channels == 1 then
    for i = 0, 255 do
      f:write(string.char(i, i, i, 0))
    end
  end

  -- Pixel data (BMP is bottom-up)
  local padding = row_size - width * channels
  for y = height - 1, 0, -1 do
    local row_start = y * step + 1
    local row_end = row_start + width * channels - 1
    f:write(raw_data:sub(row_start, row_end))
    if padding > 0 then
      f:write(string.rep("\0", padding))
    end
  end

  f:close()
  return nil
end

--- Extract a hex address from a string. Handles formats:
--- - "0x000000097a800000" (codelldb repl output)
--- - "0x00000009bc800000 \"\"" (cppdbg watch result for uchar*)
--- - "41817210880" (decimal, from cppdbg (size_t) cast)
local function parse_hex_address(str)
  if not str then return nil end
  local hex = str:match("(0x%x+)")
  if hex then return hex end
  local dec = tonumber(str)
  if dec then return string.format("0x%x", dec) end
  return nil
end

--- cv::Mat depth constants (lower 3 bits of flags)
local CV_DEPTH_BYTES = {
  [0] = 1, -- CV_8U
  [1] = 1, -- CV_8S
  [2] = 2, -- CV_16U
  [3] = 2, -- CV_16S
  [4] = 4, -- CV_32S
  [5] = 4, -- CV_32F
  [6] = 8, -- CV_64F
  [7] = 2, -- CV_16F
}

--- Parse cv::Mat flags field to extract channels and depth.
--- This is how OpenImageDebugger and CV DebugMate do it, avoiding
--- the need to call channels() which requires repl context in codelldb.
--- See: opencv2/core/types_c.h for the bit layout.
local function parse_mat_flags(flags)
  local depth = bit.band(flags, 7)
  local channels = bit.band(bit.rshift(flags, 3), 0x1FF) + 1
  local elem_bytes = CV_DEPTH_BYTES[depth]
  return channels, depth, elem_bytes
end

--- Get the data pointer address. Strategy:
--- 1. Try evaluate_full on var.data — cppdbg returns memoryReference directly
--- 2. Try parsing hex address from the result string (cppdbg: "0x... \"\"")
--- 3. Fall back to repl with p/x (size_t)var.data (codelldb)
local function get_data_pointer(var_name, helpers, callback)
  helpers.evaluate_full(var_name .. ".data", function(err, resp)
    if not err and resp then
      if resp.memoryReference then
        local addr = parse_hex_address(tostring(resp.memoryReference))
        if addr then
          callback(nil, addr)
          return
        end
      end
      local addr = parse_hex_address(resp.result)
      if addr then
        callback(nil, addr)
        return
      end
    end
    -- Fall back to repl cast (codelldb)
    helpers.repl_evaluate("(size_t)" .. var_name .. ".data", function(repl_err, result)
      if repl_err then
        callback("Failed to get data pointer: " .. repl_err)
        return
      end
      local addr = parse_hex_address(result)
      if addr then
        callback(nil, addr)
      else
        callback("Could not parse address from: " .. tostring(result))
      end
    end, { hex = true })
  end)
end

--- Get step[0] (row stride). Watch context works on cppdbg,
--- needs repl fallback on codelldb (array indexing not supported).
local function get_step(var_name, helpers, callback)
  helpers.evaluate(var_name .. ".step[0]", function(err, result)
    if not err and result then
      callback(nil, result)
      return
    end
    helpers.repl_evaluate(var_name .. ".step[0]", function(repl_err, repl_result)
      if repl_err then
        callback("Failed to get step: " .. repl_err)
        return
      end
      callback(nil, repl_result)
    end)
  end)
end

--- Gather cv::Mat metadata. Uses watch context for all simple member
--- access (rows, cols, flags). Channels and depth are derived from the
--- flags bitfield (matching OpenImageDebugger / CV DebugMate approach)
--- rather than calling channels(), which avoids the repl fallback.
--- step[0] still needs watch-then-repl since it's array indexing.
local function gather_mat_metadata(var_name, helpers, callback)
  local meta = {}
  -- All simple member accesses that work in watch context for both adapters
  local watch_fields = {
    { key = "rows", expr = var_name .. ".rows" },
    { key = "cols", expr = var_name .. ".cols" },
    { key = "flags", expr = var_name .. ".flags" },
  }

  local i = 0
  local function eval_watch_fields()
    i = i + 1
    if i > #watch_fields then
      -- Now get step[0] (array indexing, needs repl fallback on codelldb)
      get_step(var_name, helpers, function(err, step_val)
        if err then
          callback(err)
          return
        end
        meta.step = step_val
        get_data_pointer(var_name, helpers, function(ptr_err, ptr)
          if ptr_err then
            callback(ptr_err)
            return
          end
          meta.data_ptr = ptr
          callback(nil, meta)
        end)
      end)
      return
    end

    local f = watch_fields[i]
    helpers.evaluate(f.expr, function(err, result)
      if err then
        callback(string.format("Failed to evaluate '%s': %s", f.expr, err))
        return
      end
      meta[f.key] = result
      eval_watch_fields()
    end)
  end
  eval_watch_fields()
end

local function register()
  registry.register({
    name = "OpenCV cv::Mat",
    filetypes = { "cpp", "c" },
    priority = 10,
    tmp_ext = ".bmp",

    detect = function(var_name)
      return var_name .. ".rows"
    end,

    extract = function(var_name, tmp_path, helpers, callback)
      gather_mat_metadata(var_name, helpers, function(err, meta)
        if err then
          callback(err)
          return
        end

        local rows = tonumber(meta.rows)
        local cols = tonumber(meta.cols)
        local flags = tonumber(meta.flags)
        local step = tonumber(meta.step)
        local ptr = meta.data_ptr

        if not rows or not cols or not flags or not step then
          callback("Failed to parse cv::Mat metadata")
          return
        end

        local channels, depth, elem_bytes = parse_mat_flags(flags)

        if not elem_bytes then
          callback(string.format("Unknown cv::Mat depth: %d", depth))
          return
        end

        if depth ~= 0 then
          callback(string.format("Only 8-bit images supported (depth=%d)", depth))
          return
        end

        if channels ~= 1 and channels ~= 3 and channels ~= 4 then
          callback(string.format("Unsupported channel count: %d", channels))
          return
        end

        if not ptr then
          callback("Failed to get data pointer address")
          return
        end

        local total_size = rows * step

        helpers.read_memory(ptr, total_size, function(mem_err, base64_data)
          if mem_err then
            callback("readMemory failed: " .. mem_err)
            return
          end

          local ok, raw_data = pcall(vim.base64.decode, base64_data)
          if not ok then
            callback("Failed to decode base64 data")
            return
          end

          -- For 4-channel images (BGRA), drop alpha and write as 3-channel
          local write_channels = channels == 4 and 3 or channels
          local write_data = raw_data
          local write_step = step

          if channels == 4 then
            local parts = {}
            for y = 0, rows - 1 do
              for x = 0, cols - 1 do
                local offset = y * step + x * 4 + 1
                table.insert(parts, raw_data:sub(offset, offset + 2))
              end
            end
            write_data = table.concat(parts)
            write_step = cols * 3
          end

          local write_err = write_bmp(tmp_path, cols, rows, write_channels, write_step, write_data)
          if write_err then
            callback(write_err)
            return
          end

          callback(nil)
        end)
      end)
    end,
  })
end

return { register = register }
