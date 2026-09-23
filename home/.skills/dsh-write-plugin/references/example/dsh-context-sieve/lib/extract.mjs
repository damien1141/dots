// extract.mjs — session-event text extraction (zero DSH deps).
//
// Pulls readable text out of the known first-party event shapes so the sieve
// can classify tool results, assistant messages, commands, and summaries.
// Defensive: unknown shapes yield '' rather than throwing.

/**
 * @param {unknown} event - SessionEvent shape ({type, data}).
 * @returns {string} newline-joined readable text; '' for unrecognized events.
 */
export function extractEventText(event) {
  if (event === null || typeof event !== 'object') return ''
  const data = event.data
  if (data === null || typeof data !== 'object') {
    return typeof data === 'string' ? data : ''
  }
  const record = data
  if (Array.isArray(record.content)) return contentText(record.content)
  if (Array.isArray(record.summary)) return contentText(record.summary)
  if (record.message !== null && typeof record.message === 'object') {
    const message = record.message
    if (Array.isArray(message.content)) return contentText(message.content)
    if (typeof message.text === 'string') return message.text
  }
  if (typeof record.name === 'string' && typeof record.arguments === 'string') {
    return `${record.name} ${record.arguments}`
  }
  if (Array.isArray(record.todos)) {
    return record.todos.map((item) => item?.content ?? '').join('\n')
  }
  if (typeof record.text === 'string') return record.text
  return ''
}

function contentText(content) {
  const parts = []
  for (const part of content) {
    if (part && typeof part === 'object' && typeof part.text === 'string' && part.text.length > 0) {
      parts.push(part.text)
    }
  }
  return parts.join('\n')
}
