-- Fetching pages with libcurl: http://, https:// and file:// URLs.
--
-- curl delivers the body in pieces to a write callback: a Lua function
-- that C calls. We make that callback once and reuse it for every
-- download (see "callbacks" in Chapter 16).

local ffi = require("ffi")
local Buffer = require("stash.buffer")
local C = require("stash.ffi.curl")

local M = {}

M.MAX_SIZE = 5 * 1024 * 1024                 -- larger pages are refused

assert(C.curl_global_init(C.CURL_GLOBAL_DEFAULT) == C.CURLE_OK, "cannot initialize libcurl")

-- The download in progress, filled by on_write. A Buffer (Chapter 14)
-- takes the bytes straight from curl's memory, no Lua string per piece.
local body = Buffer.new()
local too_large = false

-- C calls this; it must never raise a Lua error, because an error cannot
-- unwind through curl's C frames. Returning anything other than the
-- number of bytes received makes curl stop with CURLE_WRITE_ERROR.
local function on_write(data, size, nitems)
  local n = tonumber(size * nitems)          -- size_t arrives as a 64-bit cdata number
  if #body + n > M.MAX_SIZE then
    too_large = true
    return 0
  end
  local ok = pcall(body.append, body, data, n)
  return ok and n or 0
end

-- ffi.cast turns the Lua function into a C function pointer. It stays
-- alive as long as this module does: forever, which is what we want.
local write_callback = ffi.cast("curl_write_callback", on_write)

-- Reads a string-valued piece of information about the last transfer.
local function info_string(handle, what)
  local out = ffi.new("char *[1]")
  if C.curl_easy_getinfo(handle, what, out) == C.CURLE_OK and out[0] ~= nil then
    return ffi.string(out[0])
  end
end

function M.version()
  return ffi.string(C.curl_version())
end

-- Downloads url. options: user_agent (string), timeout (seconds).
-- Returns the body and a table { status=, url=, content_type= }, or nil
-- and an error message.
function M.get(url, options)
  options = options or {}
  local handle = C.curl_easy_init()
  if handle == nil then
    return nil, "cannot start libcurl"
  end
  handle = ffi.gc(handle, C.curl_easy_cleanup)
  local errbuf = ffi.new("char[?]", C.CURL_ERROR_SIZE)

  -- curl_easy_setopt is variadic (...), so the FFI cannot know the type
  -- curl expects: a Lua number would be passed as a double. Options that
  -- take a long get an explicit ffi.cast("long", ...).
  local function long(n)
    return ffi.cast("long", n)
  end
  C.curl_easy_setopt(handle, C.CURLOPT_URL, url)
  C.curl_easy_setopt(handle, C.CURLOPT_WRITEFUNCTION, write_callback)
  C.curl_easy_setopt(handle, C.CURLOPT_ERRORBUFFER, errbuf)
  C.curl_easy_setopt(handle, C.CURLOPT_PROTOCOLS,
                     long(bit.bor(C.CURLPROTO_HTTP, C.CURLPROTO_HTTPS, C.CURLPROTO_FILE)))
  C.curl_easy_setopt(handle, C.CURLOPT_FOLLOWLOCATION, long(1))
  C.curl_easy_setopt(handle, C.CURLOPT_MAXREDIRS, long(5))
  C.curl_easy_setopt(handle, C.CURLOPT_FAILONERROR, long(1))      -- HTTP 4xx/5xx are errors
  C.curl_easy_setopt(handle, C.CURLOPT_NOSIGNAL, long(1))
  C.curl_easy_setopt(handle, C.CURLOPT_TIMEOUT, long(options.timeout or 10))
  C.curl_easy_setopt(handle, C.CURLOPT_USERAGENT, options.user_agent or "stash")

  body:reset()
  too_large = false
  local rc = C.curl_easy_perform(handle)     -- calls on_write while it runs
  if too_large then
    return nil, ("page is larger than %d bytes"):format(M.MAX_SIZE)
  elseif rc ~= C.CURLE_OK then
    local message = ffi.string(errbuf)       -- details, when curl wrote any
    if message == "" then
      message = ffi.string(C.curl_easy_strerror(rc))
    end
    return nil, message
  end

  local status = ffi.new("long[1]")
  C.curl_easy_getinfo(handle, C.CURLINFO_RESPONSE_CODE, status)
  local info = {
    status = tonumber(status[0]),            -- 0 for file:// URLs
    url = info_string(handle, C.CURLINFO_EFFECTIVE_URL),
    content_type = info_string(handle, C.CURLINFO_CONTENT_TYPE),
  }
  return body:tostring(), info
end

-- curl_easy_perform calls back into Lua, so the function that calls it
-- must not be JIT-compiled (see Stmt.step in stash/db.lua).
jit.off(M.get)

return M
