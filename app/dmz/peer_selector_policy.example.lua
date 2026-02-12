-- SPIRE-like selector policy for ingress peer verification.
-- The backproxy treats each selector as an AND constraint.
-- Format: "unix:key:value"
--
-- Supported keys:
--   uid
--   gid
--   transport
--   path
--   path_prefix
--   cmdline_prefix
--   sha256
--
-- Example use:
--   HTTP_PEER_SELECTOR_POLICY_FILE=/abs/path/to/this/file.lua
--   DMZ_HTTP_TRANSPORT=unix
--   HTTP_PEER_VERIFY_MODE=enforce

return {
    mode = "enforce",
    selectors = {
        "unix:transport:unix",
        "unix:uid:33",
        "unix:gid:33",
        "unix:path_prefix:/usr/sbin/nginx",
        "unix:cmdline_prefix:nginx: worker process",
        -- Optional hardening:
        -- "unix:sha256:<hex digest>",
    },
}
