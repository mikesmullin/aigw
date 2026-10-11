# Reverse proxies from config.yaml `proxies:` (prefix -> upstream), nginx-style with the prefix stripped:
#   proxies: { /search: http://127.0.0.1:2340 }  =>  /search/* -> http://127.0.0.1:2340/*
#
# These are browser UIs, so they cannot send the Bearer API key; access is gated by the
# ALLOWED_CIDRS allowlist against the real socket peer address instead (never X-Forwarded-For).
import { cidrContains, peerIp } from './auth.coffee'

HOP = ['connection', 'keep-alive', 'proxy-authenticate', 'proxy-authorization', 'te', 'trailer', 'transfer-encoding', 'upgrade', 'host']

plain = (status, text) ->
  new Response text, status: status, headers: { 'Content-Type': 'text/plain; charset=utf-8' }

findProxy = (cfg, pathname) ->
  for proxy in cfg.proxies
    return proxy if pathname is proxy.prefix or pathname.startsWith proxy.prefix + '/'
  null

# Returns a Response when the request belongs to a proxied prefix, otherwise null.
proxyRequest = (req, server, cfg) ->
  url = new URL req.url
  proxy = findProxy cfg, url.pathname
  return null unless proxy
  base = proxy.prefix

  # Canonical trailing slash so the app's relative URLs resolve under the prefix.
  if url.pathname is base
    return new Response null, status: 308, headers: { Location: base + '/' + url.search }

  ip = peerIp req, server
  unless ip in ['127.0.0.1', '::1'] or cfg.allowedCidrs.some((c) -> cidrContains c, ip)
    console.warn "[proxy] 403 #{req.method} #{url.pathname} from #{ip or '(unknown)'}"
    return plain 403, "Client IP #{ip or '(unknown)'} is not in ALLOWED_CIDRS."

  server.timeout req, 0  # research streams (SSE) can be quiet for a while

  target = proxy.upstream + url.pathname.slice(base.length) + url.search
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
    console.error "[proxy] #{base} upstream #{proxy.upstream} unreachable: #{err.message or err}"
    return plain 502, "Upstream for #{base}/ is not running (#{proxy.upstream})."

  out = new Headers up.headers
  out.delete h for h in HOP
  if out.has 'content-encoding'  # fetch() already decoded the body
    out.delete 'content-encoding'
    out.delete 'content-length'
  loc = out.get 'location'
  out.set 'location', base + loc if loc?.startsWith '/'
  new Response up.body, status: up.status, statusText: up.statusText, headers: out

export { proxyRequest }
