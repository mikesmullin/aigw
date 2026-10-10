ipToInt = (ip) ->
  parts = ip.split('.').map Number
  return null if parts.length isnt 4 or parts.some (n) -> !Number.isFinite(n) or n < 0 or n > 255
  ((parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]) >>> 0

cidrContains = (cidr, ip) ->
  return true if cidr is ip
  return false unless cidr.includes '/'
  [net, bitsStr] = cidr.split '/'
  bits = Number bitsStr
  netInt = ipToInt net
  ipInt = ipToInt ip
  return false if netInt == null or ipInt == null or !Number.isFinite bits
  return true if bits is 0
  mask = if bits is 32 then 0xffffffff else (~0 << (32 - bits)) >>> 0
  (netInt & mask) is (ipInt & mask)

clientIp = (req) ->
  xff = req.headers.get 'x-forwarded-for'
  return xff.split(',')[0].trim() if xff
  req.headers.get('x-real-ip') or ''

extractApiKeys = (req) ->
  keys = []
  push = (v) ->
    return unless v?
    s = String(v).trim()
    keys.push s if s
  auth = req.headers.get('authorization') or ''
  if auth
    bearer = auth.match /^Bearer\s+(.+)$/i
    if bearer then push bearer[1]
    else if !/^(Basic|Digest)\s/i.test auth then push auth
  push req.headers.get 'x-api-key'
  push req.headers.get 'api-key'
  push req.headers.get 'openai-api-key'
  keys

redact = (s) ->
  return '(empty)' unless s
  return "len=#{s.length}" if s.length <= 8
  "#{s.slice(0, 4)}…#{s.slice(-4)} (len=#{s.length})"

jsonError = (status, error) ->
  new Response JSON.stringify({ error }),
    status: status
    headers: { 'Content-Type': 'application/json' }

checkAuth = (req, cfg) ->
  unless cfg.apiKey
    return
      ok: false
      status: 500
      error:
        message: 'Server misconfigured: set LLM_PROXY_API_KEY in .env before exposing this proxy.'
        type: 'server_error'
        code: 'missing_proxy_api_key'

  return { ok: true } if cfg.authOptional

  candidates = extractApiKeys req
  matched = candidates.some (k) -> k is cfg.apiKey
  unless matched
    auth = req.headers.get('authorization') or ''
    console.warn "[auth] 401 #{req.method} #{new URL(req.url).pathname} authorization=#{if auth then redact(auth.replace(/^Bearer\s+/i, '')) else '(missing)'}"
    return
      ok: false
      status: 401
      error:
        message: 'Invalid or missing API key. Use Authorization: Bearer <LLM_PROXY_API_KEY>.'
        type: 'invalid_request_error'
        code: 'invalid_api_key'

  if cfg.allowedCidrs.length
    ip = clientIp req
    loopback = ip is '127.0.0.1' or ip is '::1' or ip is ''
    unless loopback or cfg.allowedCidrs.some (c) -> cidrContains c, ip
      return
        ok: false
        status: 403
        error:
          message: "Client IP #{ip or '(unknown)'} is not in ALLOWED_CIDRS."
          type: 'invalid_request_error'
          code: 'ip_not_allowed'

  { ok: true }

export { checkAuth, jsonError, clientIp, cidrContains }
