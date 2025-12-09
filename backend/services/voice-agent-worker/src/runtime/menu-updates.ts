import { PubSub } from '@google-cloud/pubsub';
import { fetchMenuSnapshot, type MenuSnapshot } from './menu';

const menuPubsubClient = process.env.MENU_UPDATES_TOPIC ? new PubSub() : undefined;
const menuUpdatesTopic = process.env.MENU_UPDATES_TOPIC;
const menuRefreshMutex: Record<string, boolean> = {};

export async function maybeStartMenuUpdateListener(orderServiceUrl?: string, storeId?: string): Promise<MenuSnapshot | undefined> {
  if (!menuPubsubClient || !menuUpdatesTopic || !orderServiceUrl) return undefined;
  // First fetch synchronously so the agent has a menu right away.
  const initial = await fetchMenuSnapshot(orderServiceUrl, storeId);

  const subName = process.env.MENU_UPDATES_SUBSCRIPTION;
  if (!subName) {
    console.warn('voice-agent-worker:MENU_UPDATES_SUBSCRIPTION not set; skipping menu update listener');
    return initial;
  }

  const subscription = menuPubsubClient.subscription(subName, { flowControl: { maxMessages: 1 } });
  subscription.on('message', async (msg) => {
    try {
      const data = JSON.parse(msg.data.toString()) as { storeId?: string };
      const targetStore = data.storeId ?? storeId;
      if (!targetStore) {
        msg.ack();
        return;
      }
      const key = `${orderServiceUrl}-${targetStore}`;
      if (menuRefreshMutex[key]) {
        msg.ack();
        return;
      }
      menuRefreshMutex[key] = true;
      const refreshed = await fetchMenuSnapshot(orderServiceUrl, targetStore);
      if (refreshed) {
        console.log('voice-agent-worker:menu_refreshed', { storeId: targetStore, updated: refreshed.updated });
      }
      msg.ack();
    } catch (e) {
      console.warn('voice-agent-worker:menu_update_parse_error', e);
      msg.nack();
    } finally {
      const key = `${orderServiceUrl}-${storeId}`;
      menuRefreshMutex[key] = false;
    }
  });

  subscription.on('error', (err) => {
    console.warn('voice-agent-worker:menu_update_listener_error', err);
  });

  return initial;
}
