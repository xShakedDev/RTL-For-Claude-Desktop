export type SmartRtlEnabled = boolean

declare module 'claude-code' {
  interface PluginState {
    'smart-rtl': { isEnabled: SmartRtlEnabled }
  }
}
