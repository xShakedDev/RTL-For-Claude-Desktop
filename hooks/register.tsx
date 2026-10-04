import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import { rtlMarkdown, rtlPlain } from './transform'

const isEnabled = atom({ plugin: 'smart-rtl', key: 'isEnabled' } as const, true)
const STORE_KEY = 'isEnabled'

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'rtl',
      description: 'Toggle RTL (Hebrew/Arabic) direction fixes for messages',
    })
    const stored = await $.store.get(STORE_KEY)
    if (typeof stored === 'boolean') await update($, isEnabled, () => stored)

    return next(e)
  })

  on('command.run', { command: 'rtl' }, async $ => {
    const now = await update($, isEnabled, was => !was)
    await $.store.set(STORE_KEY, now)

    return { text: now ? 'RTL fixes on.' : 'RTL fixes off.' }
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

    return text === e.props.text ? next(e) : next({ ...e, props: { ...e.props, text } })
  })
}
