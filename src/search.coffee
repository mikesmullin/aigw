# Reverse proxy for the web-researcher UI: <SEARCH_PATH>/* -> SEARCH_UPSTREAM, prefix stripped
# (nginx `location /search/ { proxy_pass http://127.0.0.1:2340/; }`).
#
# This is a browser UI, so it cannot send the Bearer API key; access is gated by the
# ALLOWED_CIDRS allowlist against the real socket peer address instead (never X-Forwarded-For).
import { cidrContains } from './auth.coffee'

HOP = ['connection', 'keep-alive', 'proxy-authenticate', 'proxy-authorization', 'te', 'trailer', 'transfer-encoding', 'upgrade', 'host']

peerIp = (req, server) ->
  (server?.requestIP(req)?.address or '').replace /^::ffff:/i, ''

plain = (status, text) ->
  new Response text, status: status, headers: { 'Content-Type': 'text/plain; charset=utf-8' }

# Returns a Response when the request belongs to the search route, otherwise null.
proxySearch = (req, server, cfg) ->
  base = cfg.searchPath
  url = new URL req.url
  return null unless cfg.searchUpstream and (url.pathname is base or url.pathname.startsWith base + '/')

  # Canonical trailing slash so the app's relative URLs resolve under the prefix.
  if url.pathname is base
    return new Response null, status: 308, headers: { Location: base + '/' + url.search }

  ip = peerIp req, server
  unless ip in ['127.0.0.1', '::1'] or cfg.allowedCidrs.some((c) -> cidrContains c, ip)
    console.warn "[search] 403 #{req.method} #{url.pathname} from #{ip or '(unknown)'}"
    return plain 403, "Client IP #{ip or '(unknown)'} is not in ALLOWED_CIDRS."

  server.timeout req, 0  # research streams (SSE) can be quiet for a while

  target = cfg.searchUpstream.replace(/\/+$/, '') + url.pathname.slice(base.length) + url.search
  headers = new Headers req.headers
  headers.delete h for h in HOP
  headers.delete 'authorization'  # never forward the gateway key
  headers.set 'x-forwarded-for', ip
  headers.set 'x-forwarded-prefix', base
  headers.set 'x-forwarded-proto', if url.protocol is 'https:' then 'https' else 'http'

  try
    up = await fetch target,
      method: req.method
      headers: headers
      body: if req.method in ['GET', 'HEAD'] then undefined else req.body
      redirect: 'manual'
      signal: req.signal  # client disconnect aborts the upstream request (stops the agent run)
  catch err
    return null if req.signal.aborted
    console.error "[search] upstream #{cfg.searchUpstream} unreachable: #{err.message or err}"
    return plain 502, "Search UI is not running (#{cfg.searchUpstream})."

  out = new Headers up.headers
  out.delete h for h in HOP
  if out.has 'content-encoding'  # fetch() already decoded the body
    out.delete 'content-encoding'
    out.delete 'content-length'
  loc = out.get 'location'
  out.set 'location', base + loc if loc?.startsWith '/'
  new Response up.body, status: up.status, statusText: up.statusText, headers: out

export { proxySearch }
