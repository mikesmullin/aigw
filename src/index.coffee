# aigw — OpenAI-compatible LAN gateway. All providers live in agl-ai.
import { chatCompletions, listModels, embeddingsRequest, resolveDefaultModel } from 'agl-ai'
import { loadConfig, resolveRequestModel } from './config.coffee'
import { checkAuth, jsonError } from './auth.coffee'
import { loadTls } from './tls.coffee'
import { proxySearch } from './search.coffee'

cfg = await loadConfig()

CORS =
  'Access-Control-Allow-Origin': '*'
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS'
  'Access-Control-Allow-Headers':
    'Authorization, Content-Type, x-api-key, api-key, OpenAI-Organization'

withCors = (res) ->
  headers = new Headers res.headers
  headers.set k, v for k, v of CORS
  new Response res.body, status: res.status, statusText: res.statusText, headers: headers

rewriteModel = (res, displayModel) ->
  return res unless displayModel
  ct = res.headers.get('content-type') or ''
  if ct.includes('text/event-stream') or ct.includes('application/x-ndjson')
    encoder = new TextEncoder()
    decoder = new TextDecoder()
    buf = ''
    transformed = new ReadableStream
      start: (controller) ->
        reader = res.body.getReader()
        try
          loop
            { done, value } = await reader.read()
            break if done
            buf += decoder.decode value, stream: true
            while (nl = buf.indexOf '\n') isnt -1
              line = buf.slice 0, nl
              buf = buf.slice nl + 1
              if line.startsWith('data: ') and line.slice(6).trim() isnt '[DONE]'
                try
                  obj = JSON.parse line.slice 6
                  obj.model = displayModel if obj and typeof obj is 'object'
                  line = "data: #{JSON.stringify obj}"
                catch
                  # leave
              controller.enqueue encoder.encode line + '\n'
          controller.enqueue encoder.encode buf if buf
          controller.close()
        catch err
          controller.error err
    headers = new Headers res.headers
    headers.set 'Content-Type', 'text/event-stream; charset=utf-8'
    headers.set 'Cache-Control', 'no-cache'
    headers.set 'Connection', 'keep-alive'
    headers.set 'X-Accel-Buffering', 'no'
    return new Response transformed, status: 200, headers: headers

  if ct.includes 'application/json'
    try
      obj = await res.json()
      obj.model = displayModel if obj and typeof obj is 'object' and !obj.error
      return new Response JSON.stringify(obj),
        status: res.status
        headers: { 'Content-Type': 'application/json' }
    catch
      # fall through
  res

handler = (req, server) ->
  # Web UI route (own allowlist check; browsers can't send the Bearer key)
  searched = await proxySearch req, server, cfg
  return searched if searched

  url = new URL req.url
  if req.method is 'OPTIONS'
    return new Response null, status: 204, headers: CORS

  if req.method is 'GET' and (url.pathname is '/health' or url.pathname is '/')
    return withCors new Response JSON.stringify(
      ok: true
      service: 'aigw'
      default_model: await resolveDefaultModel()
      default_alias: 'default'
    ), status: 200, headers: { 'Content-Type': 'application/json' }

  path = url.pathname.replace(/\/+$/, '') or '/'
  auth = checkAuth req, cfg
  unless auth.ok
    return withCors jsonError auth.status, auth.error

  if req.method is 'GET' and (path is '/v1/models' or path is '/models')
    try
      models = await listModels()
      models.data = [
        {
          id: 'default'
          object: 'model'
          created: 0
          owned_by: 'aigw'
          root: await resolveDefaultModel()
        }
        ...(models.data or [])
      ]
      return withCors new Response JSON.stringify(models),
        status: 200
        headers: { 'Content-Type': 'application/json' }
    catch err
      return withCors jsonError 500,
        message: err.message or String err
        type: 'server_error'
        code: 'models_error'

  if req.method is 'POST' and (path is '/v1/chat/completions' or path is '/chat/completions')
    try
      body = await req.json()
    catch
      return withCors jsonError 400,
        message: 'Request body must be JSON'
        type: 'invalid_request_error'
        code: 'invalid_json'
    resolved = resolveRequestModel body.model
    unless resolved.ok
      return withCors jsonError 500,
        message: resolved.error or 'default model unset.'
        type: 'server_error'
        code: 'missing_default_model'
    body.model = resolved.resolved
    display = resolved.requested
    if resolved.aliased
      console.log "[chat] #{resolved.requested} -> AGL default_model stream=#{Boolean body.stream} msgs=#{body.messages?.length or 0}"
    else
      console.log "[chat] #{display} stream=#{Boolean body.stream} msgs=#{body.messages?.length or 0}"
    try
      res = await chatCompletions body
      return withCors await rewriteModel res, display
    catch err
      console.error '[chat] error:', err
      return withCors jsonError err.status or 500,
        message: err.message or String err
        type: 'server_error'
        code: err.code or 'proxy_error'

  if req.method is 'POST' and (path is '/v1/embeddings' or path is '/embeddings')
    try
      body = await req.json()
    catch
      return withCors jsonError 400,
        message: 'Request body must be JSON'
        type: 'invalid_request_error'
        code: 'invalid_json'
    resolved = resolveRequestModel body.model
    unless resolved.ok
      return withCors jsonError 500,
        message: resolved.error or 'default model unset.'
        type: 'server_error'
        code: 'missing_default_model'
    body.model = resolved.resolved
    try
      return withCors await embeddingsRequest body
    catch err
      return withCors jsonError err.status or 500,
        message: err.message or String err
        type: 'server_error'
        code: err.code or 'proxy_error'

  withCors jsonError 404,
    message: "Not found: #{req.method} #{url.pathname}"
    type: 'invalid_request_error'
    code: 'not_found'

tls = await loadTls cfg
serveOpts =
  hostname: cfg.host
  port: cfg.port
  fetch: handler
  idleTimeout: 255
if tls
  serveOpts.tls = { cert: tls.cert, key: tls.key }

server = Bun.serve serveOpts
scheme = if tls then 'https' else 'http'
keyHint = if cfg.apiKey then "#{cfg.apiKey.slice(0, 4)}…#{cfg.apiKey.slice(-4)} (#{cfg.apiKey.length} chars)" else 'MISSING — set LLM_PROXY_API_KEY'

console.log """
aigw listening on #{scheme}://#{cfg.host}:#{cfg.port}
  health:  GET  /health
  models:  GET  /v1/models
  chat:    POST /v1/chat/completions
  embed:   POST /v1/embeddings
  search:  #{if cfg.searchUpstream then "ANY  #{cfg.searchPath}/ -> #{cfg.searchUpstream}" else 'off'}

  default model: #{await resolveDefaultModel()} (~/.config/agl/config.yaml)
  api key:       #{keyHint}
  agl dir:       #{cfg.aglDir}
  tls:           #{if tls then tls.certFile else 'off'}
"""
