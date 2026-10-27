-- The smallest useful libcurl program: download a URL into a Lua string.
-- Run it from the course directory; it reads examples/ch16/page.html.
local ffi = require("ffi")

ffi.cdef [[
typedef struct CURL CURL;
CURL *curl_easy_init(void);
int curl_easy_setopt(CURL *curl, int option, ...);
int curl_easy_perform(CURL *curl);
const char *curl_easy_strerror(int code);
void curl_easy_cleanup(CURL *curl);
typedef size_t (*write_fn)(char *data, size_t size, size_t nitems, void *userdata);
]]
local curl = ffi.load("curl")

local CURLOPT_URL, CURLOPT_WRITEFUNCTION = 10002, 20011

local function get(url)
  local pieces = {}
  local on_write = ffi.cast("write_fn", function(data, size, nitems)
    local n = tonumber(size * nitems)
    pieces[#pieces + 1] = ffi.string(data, n)
    return n                                   -- "I took all n bytes"
  end)
  local handle = curl.curl_easy_init()
  curl.curl_easy_setopt(handle, CURLOPT_URL, url)
  curl.curl_easy_setopt(handle, CURLOPT_WRITEFUNCTION, on_write)
  local rc = curl.curl_easy_perform(handle)    -- on_write runs in here
  curl.curl_easy_cleanup(handle)
  on_write:free()
  if rc ~= 0 then
    return nil, ffi.string(curl.curl_easy_strerror(rc))
  end
  return table.concat(pieces), #pieces
end

local here = "file://" .. os.getenv("PWD") .. "/examples/ch16/"
local body, pieces = get(here .. "page.html")
print(#body .. " bytes in " .. pieces .. " piece(s)")
print(body:match("<title>(.-)</title>"))
print(get(here .. "missing.html"))
