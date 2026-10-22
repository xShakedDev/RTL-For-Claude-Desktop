import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import { rtlMarkdown, rtlPlain, rtlQuestions, stripBidi } from './transform'

const isEnabled = atom({ plugin: 'smart-rtl', key: 'isEnabled' } as const, true)
const STORE_KEY = 'isEnabled'

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'rtl',
      description: 'Toggle RTL (Hebrew/Arabic) direction fixes for messages',
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

  on('ui.render', { component: 'AskUserQuestion' }, async ($, e, next) => {
    if (e.surface === 'terminal' || !(await read($, isEnabled))) return next(e)
    const questions = rtlQuestions(e.props.questions)
    const isSame = JSON.stringify(questions) === JSON.stringify(e.props.questions)

    return isSame ? next(e) : next({ ...e, props: { ...e.props, questions } })
  })

  // The dialog answers with the labels and question text it drew, which now
  // carry bidi controls: they are stripped before the model reads them.
  on('tool.call', { tool: 'AskUserQuestion' }, async ($, e, next) => {
    const out = await next(e)
    if (out.deny !== undefined) return out
    const result = stripBidi(out.result)

    return JSON.stringify(result) === JSON.stringify(out.result) ? out : { ...out, result }
  })
}
