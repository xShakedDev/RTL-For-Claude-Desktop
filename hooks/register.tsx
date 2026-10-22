import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import { blockDir } from './rtl-core'
import { rtlMarkdown, rtlPlain } from './transform'

const isEnabled = atom({ plugin: 'smart-rtl', key: 'isEnabled' } as const, true)
const STORE_KEY = 'isEnabled'
const LAUNCHER = 'windows/claude-ltr.ps1'

// Rows the person typed themselves; notifications and other agents' messages
// keep the engine's own drawing, which frames them.
const OWN_ORIGINS = new Set(['composer', 'bridge', 'sdk'])

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'rtl',
      description: 'Toggle RTL (Hebrew/Arabic) direction fixes for messages',
    })
    await $.command.register({
      name: 'ltr',
      description: 'Restart the Claude desktop app with a left-to-right window layout (Windows)',
    })
    // Every write bumps the atom's version and redraws each message that
    // read it, so the stored value is only written when it differs.
    const stored = await $.store.get(STORE_KEY)
    if (typeof stored === 'boolean' && stored !== (await read($, isEnabled))) {
      await update($, isEnabled, () => stored)
    }

    return next(e)
  })

  on('command.run', { command: 'rtl' }, async $ => {
    const now = await update($, isEnabled, was => !was)
    await $.store.set(STORE_KEY, now)

    return { text: now ? 'RTL fixes on.' : 'RTL fixes off.' }
  })

  on('command.run', { command: 'ltr' }, async $ => {
    // `root` holds plugin.json, which may be the plugin folder or its
    // .claude-plugin folder: the launcher is looked for under both.
    const root = $.plugin.root.replace(/[\\/]$/, '')
    const candidates = [`${root}/${LAUNCHER}`, `${root.replace(/[\\/][^\\/]+$/, '')}/${LAUNCHER}`]
    let script: string | undefined
    for (const path of candidates) {
      const stat = await $.fs.stat(path).catch(() => undefined)
      if (stat?.kind === 'file') {
        script = path
        break
      }
    }
    if (!script) return { text: `${LAUNCHER} was not found in the plugin folder.` }

    // The launcher closes every Claude process, this engine included. It is
    // started through a second PowerShell so it is not a direct child of the
    // engine when the app goes down.
    const args = `-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "${script}"`
    const { exitCode } = await $.process.run([
      'powershell.exe',
      '-NoProfile',
      '-Command',
      `Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '${args.replace(/'/g, "''")}'`,
    ])

    return {
      text:
        exitCode === 0
          ? 'Restarting Claude with a left-to-right window layout.'
          : 'Could not start the launcher (PowerShell exited with an error).',
    }
  })

  // The terminal has no bidi layout to steer, and the controls would print
  // as stray glyphs in some terminals: only the remote surfaces are touched.
  on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => {
    if (e.surface === 'terminal' || !(await read($, isEnabled))) return next(e)
    const text = rtlMarkdown(e.props.text)

    return text === e.props.text ? next(e) : next({ ...e, props: { ...e.props, text } })
  })

  on('ui.render', { component: 'UserMessage' }, async ($, e, next) => {
    if (e.surface === 'terminal' || !(await read($, isEnabled))) return next(e)
    const text = rtlPlain(e.props.text)
    if (text === e.props.text) return next(e)
    const { origin, task, from, isExpanded } = e.props
    const isOwn = OWN_ORIGINS.has(origin.kind) && !task && !from && isExpanded
    if (!isOwn || blockDir(e.props.text) !== 'rtl') return next({ ...e, props: { ...e.props, text } })

    // The person's own RTL prompt is drawn as Text rows with `dir`, which
    // also aligns them to the right; the bidi controls still order each line.
    const { Box, Text } = $.ui.resolve(e)

    return (
      <Box flexDirection="column">
        {text.split('\n').map(line => (
          <Text dir="rtl">{line === '' ? ' ' : line}</Text>
        ))}
      </Box>
    )
  })

  // AskUserQuestion is left alone: the desktop dialog draws bidi controls as
  // visible glyphs ("[U+200F]", a replacement box) instead of applying them.
}
