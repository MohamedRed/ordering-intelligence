import { GroupOrderParticipant } from "../models";
import { sendGroupOrderNotification } from "../notification_service";

export async function notifyPaymentLink(
  notificationServiceUrl: string | undefined,
  participant: GroupOrderParticipant | undefined,
  groupOrderId: string,
  paymentId: string,
  checkoutUrl: string | null
) {
  try {
    await sendGroupOrderNotification(notificationServiceUrl, participant?.channelContact, {
      title: "Group order payment link",
      body: `Complete your payment: ${checkoutUrl || ""}`,
      data: { groupOrderId, paymentId }
    });
  } catch (err) {
    console.error("group order payment notification failed", err);
  }
}
