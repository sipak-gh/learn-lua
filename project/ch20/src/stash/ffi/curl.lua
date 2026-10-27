-- Raw bindings to libcurl's "easy" interface (from curl/curl.h and
-- curl/easy.h). stash.fetch wraps them.

local ffi = require("ffi")
local load = require("stash.ffi.load")

ffi.cdef [[
typedef struct CURL CURL;
typedef int CURLcode;                         /* C enums are ints */

enum {
  CURLE_OK = 0,
  CURL_GLOBAL_DEFAULT = 3,
  CURL_ERROR_SIZE = 256,

  /* Option numbers are a type base plus an index, see curl.h:
     LONG = 0, OBJECTPOINT/STRINGPOINT = 10000, FUNCTIONPOINT = 20000. */
  CURLOPT_URL = 10002,
  CURLOPT_ERRORBUFFER = 10010,
  CURLOPT_WRITEFUNCTION = 20011,
  CURLOPT_TIMEOUT = 13,
  CURLOPT_USERAGENT = 10018,
  CURLOPT_FAILONERROR = 45,
  CURLOPT_FOLLOWLOCATION = 52,
  CURLOPT_MAXREDIRS = 68,
  CURLOPT_NOSIGNAL = 99,
  CURLOPT_PROTOCOLS = 181,

  CURLPROTO_HTTP = 1,
  CURLPROTO_HTTPS = 2,
  CURLPROTO_FILE = 1024,

  CURLINFO_EFFECTIVE_URL = 0x100001,
  CURLINFO_RESPONSE_CODE = 0x200002,
  CURLINFO_CONTENT_TYPE = 0x100012,
};

/* The write callback: called with each piece of the body as it arrives. */
typedef size_t (*curl_write_callback)(char *data, size_t size, size_t nitems, void *userdata);

CURLcode curl_global_init(long flags);
char *curl_version(void);
const char *curl_easy_strerror(CURLcode code);

CURL *curl_easy_init(void);
CURLcode curl_easy_setopt(CURL *curl, int option, ...);
CURLcode curl_easy_perform(CURL *curl);
CURLcode curl_easy_getinfo(CURL *curl, int info, ...);
void curl_easy_cleanup(CURL *curl);
]]

return load({ "curl", "libcurl.so.4" }, "curl_version")
