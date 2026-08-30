import { readFile } from 'fs/promises'
import { resolve } from 'path'

loadTls = (cfg) ->
  certPath = (cfg.tlsCert or '').trim()
  keyPath = (cfg.tlsKey or '').trim()
  return null unless certPath and keyPath
  certFile = if certPath.startsWith '/' then certPath else resolve cfg.root, certPath
  keyFile = if keyPath.startsWith '/' then keyPath else resolve cfg.root, keyPath
  cert = await readFile certFile
  key = await readFile keyFile
  { cert, key, certFile, keyFile }

export { loadTls }
