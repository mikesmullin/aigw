import { readFile } from 'fs/promises'
import { resolve, dirname } from 'path'
import { fileURLToPath } from 'url'
import { homedir } from 'os'

ROOT = resolve dirname(fileURLToPath(import.meta.url)), '..'

parseDotenv = (path) ->
  out = {}
  try
    content = await readFile path, 'utf-8'
    for line in content.split '\n'
      trimmed = line.trim()
      continue if !trimmed or trimmed.startsWith '#'
      idx = trimmed.indexOf '='
      continue if idx is -1
      key = trimmed.slice(0, idx).trim()
      val = trimmed.slice(idx + 1).trim()
      if (val.startsWith('"') and val.endsWith('"')) or (val.startsWith("'") and val.endsWith("'"))
        val = val.slice 1, -1
      out[key] = val
  catch
    # missing is fine
  out

# Merge into process.env as: process.env > aigw/.env > agl/.env
# (AGL providers read process.env.)
mergeEnv = (fromAgl, fromProxy) ->
  original = { ...process.env }
  for own k, v of fromAgl
    process.env[k] = v
  for own k, v of fromProxy
    process.env[k] = v
  for own k, v of original
    process.env[k] = v if v? and v isnt ''
  return

# config.yaml (gitignored, optional): `routes:` maps a GET path to a script on this host;
# `proxies:` maps a path prefix to an upstream URL. Missing file = empty.
readConfigYaml = ->
  try
    text = await readFile resolve(ROOT, 'config.yaml'), 'utf-8'
  catch err
    return {} if err.code is 'ENOENT'
    throw err
  Bun.YAML.parse(text) or {}

normPrefix = (p) -> '/' + String(p).trim().replace(/^\/+|\/+$/g, '')

routesFrom = (doc) ->
  routes = {}
  for own path, spec of (doc.routes or {})
    # Either `"script"` or `{ run: "script", allow: [CIDRs] }` (allow overrides ALLOWED_CIDRS for that route).
    spec = { run: spec } unless spec? and typeof spec is 'object'
    allow = spec.allow
    allow = [allow] if typeof allow is 'string'
    routes[normPrefix path] =
      run: String(spec.run).replace /^~(?=\/|$)/, homedir()
      allow: if allow? then allow.map((c) -> String(c).trim()).filter(Boolean) else null
  routes

proxiesFrom = (doc) ->
  # Without a `proxies:` key, fall back to the SEARCH_* env vars (the web-researcher UI).
  unless doc.proxies?
    upstream = (process.env.SEARCH_UPSTREAM ? 'http://127.0.0.1:2340').trim()
    return [] unless upstream
    return [prefix: normPrefix(process.env.SEARCH_PATH or '/search'), upstream: upstream.replace(/\/+$/, '')]
  (for own prefix, upstream of doc.proxies when String(upstream).trim()
    prefix: normPrefix prefix
    upstream: String(upstream).trim().replace(/\/+$/, ''))

loadConfig = ->
  fromProxy = await parseDotenv resolve ROOT, '.env'
  aglDirRaw = process.env.AGL_DIR or fromProxy.AGL_DIR or resolve ROOT, '../agl'
  aglDir = if aglDirRaw.startsWith '/' then aglDirRaw else resolve ROOT, aglDirRaw

  fromAgl = await parseDotenv resolve aglDir, '.env'
  mergeEnv fromAgl, fromProxy
  doc = await readConfigYaml()

  host: process.env.HOST or '127.0.0.1'
  port: Number process.env.PORT or 1234
  apiKey: (process.env.LLM_PROXY_API_KEY or '').trim()
  authOptional: ['1', 'true', 'yes'].includes String(process.env.LLM_PROXY_AUTH_OPTIONAL or '').toLowerCase()
  allowedCidrs: (process.env.ALLOWED_CIDRS or '127.0.0.1')
    .split ','
    .map (s) -> s.trim()
    .filter Boolean
  # Favorite local model lives in ~/.config/agl/config.yaml (AGL default_model).
  aglDir: aglDir
  routes: routesFrom doc
  proxies: proxiesFrom doc
  tlsCert: process.env.TLS_CERT or ''
  tlsKey: process.env.TLS_KEY or ''
  root: ROOT

# VS Code / clients can send model id "default" (or "fav", "provider:default").
# aigw passes an empty model through to AGL, which reads
# ~/.config/agl/config.yaml default_model on every request.
FAV_ALIASES = ['default', 'fav', 'fav-local', 'fav-local-llm', 'fav_local_llm']

isFavAlias = (raw) ->
  s = String(raw or '').trim().toLowerCase()
  return true if s is ''
  return true if FAV_ALIASES.includes s
  idx = s.lastIndexOf ':'
  return false if idx <= 0
  FAV_ALIASES.includes s.slice(idx + 1)

resolveRequestModel = (raw) ->
  if isFavAlias raw
    requested = String(raw or 'default').trim() or 'default'
    return ok: true, requested: requested, resolved: '', aliased: true
  spec = String(raw or '').trim()
  { ok: true, requested: spec, resolved: spec, aliased: false }

export { loadConfig, ROOT, isFavAlias, resolveRequestModel }
