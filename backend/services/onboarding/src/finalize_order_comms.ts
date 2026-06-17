export function buildDefaultOrderComms() {
  return {
    default_wait_minutes: 15,
    statuses: {
      pending: {
        default_channel: 'none',
        default_template_id: 'default',
        templates: [{ id: 'default', label: 'Default', body: 'Your order was received.' }],
      },
      confirmed: {
        default_channel: 'none',
        default_template_id: 'default',
        templates: [{ id: 'default', label: 'Default', body: 'Your order has been confirmed.' }],
      },
      ready: {
        default_channel: 'none',
        default_template_id: 'default',
        templates: [{ id: 'default', label: 'Default', body: 'Your order is ready for pickup.' }],
      },
      completed: {
        default_channel: 'none',
        default_template_id: 'default',
        templates: [{ id: 'default', label: 'Default', body: 'Thanks — your order is marked completed.' }],
      },
      cancelled: {
        default_channel: 'none',
        default_template_id: 'default',
        templates: [{ id: 'default', label: 'Default', body: 'Your order was cancelled. Please contact the store if you have questions.' }],
      },
      delay: {
        default_channel: 'none',
        default_template_id: 'default',
        templates: [{ id: 'default', label: 'Default', body: 'Your order is running a bit late.' }],
      },
    },
    ready_escalation_enabled: false,
    ready_escalation_minutes: 5,
    ready_escalation_channel: 'call',
  };
}
