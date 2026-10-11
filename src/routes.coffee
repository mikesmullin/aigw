# Script routes from config.yaml: GET <path> runs a local script and returns its output as text.
# Gated like the proxies: the real socket peer must be loopback or in ALLOWED_CIDRS.
import { cidrContains, peerIp } from './auth.coffee'

plain = (status, text) ->
  new Response text, status: status, headers: { 'Content-Type': 'text/plain; charset=utf-8' }

runRoute = (req, server, cfg, route) ->
  { run: script, allow } = route
  ip = peerIp req, server
  cidrs = allow or cfg.allowedCidrs
  unless ip in ['127.0.0.1', '::1'] or cidrs.some((c) -> cidrContains c, ip)
    console.warn "[route] 403 #{new URL(req.url).pathname} from #{ip or '(unknown)'}"
    return plain 403, "Client IP #{ip or '(unknown)'} is not allowed for this route."

  console.log "[route] #{new URL(req.url).pathname} -> #{script} (from #{ip})"
  try
    proc = Bun.spawn [script], stdin: 'ignore', stdout: 'pipe', stderr: 'pipe'
  catch err
    return plain 500, "Could not start #{script}: #{err.message or err}"

  [out, errOut] = await Promise.all [new Response(proc.stdout).text(), new Response(proc.stderr).text()]
  code = await proc.exited
  plain (if code is 0 then 200 else 500), """
  $ #{script}
  exit #{code}

  --- stdout ---
  #{out}
  --- stderr ---
  #{errOut}
  """

export { runRoute }
