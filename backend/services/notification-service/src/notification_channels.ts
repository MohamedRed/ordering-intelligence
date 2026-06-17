import type admin from "firebase-admin";
import type { NotificationConfig, NotifyRequest } from "./types";

export type NotificationDeliveryChannel = "push" | "sms" | "email";

export type NotificationCounters = {
  pushSent: number;
  smsSent: number;
  emailSent: number;
  pushFailed: number;
  smsFailed: number;
  emailFailed: number;
};

type TwilioMessageClient = {
  messages: {
    create: (params: { to: string; from: string; body: string }) => Promise<unknown>;
  };
};

type MailClient = {
  send: (params: { to: string; from: string; subject: string; text: string }) => Promise<unknown>;
};

type MessagingClient = Pick<admin.messaging.Messaging, "send" | "sendEachForMulticast">;

export class NotificationChannels {
  private readonly counters: NotificationCounters = {
    pushSent: 0,
    smsSent: 0,
    emailSent: 0,
    pushFailed: 0,
    smsFailed: 0,
    emailFailed: 0
  };

  constructor(
    private readonly deps: {
      config: NotificationConfig;
      dryRun: boolean;
      messaging: MessagingClient;
      twilioClient?: TwilioMessageClient;
      mailClient: MailClient;
    }
  ) {}

  getCounters(): NotificationCounters {
    return { ...this.counters };
  }

  metricsText(): string {
    return (
      `notifications_push_sent_total ${this.counters.pushSent}\n` +
      `notifications_sms_sent_total ${this.counters.smsSent}\n` +
      `notifications_email_sent_total ${this.counters.emailSent}\n` +
      `notifications_push_failed_total ${this.counters.pushFailed}\n` +
      `notifications_sms_failed_total ${this.counters.smsFailed}\n` +
      `notifications_email_failed_total ${this.counters.emailFailed}\n` +
      `notifications_dry_run ${this.deps.dryRun ? 1 : 0}\n`
    );
  }

  recordFailure(channel: NotificationDeliveryChannel): void {
    if (channel === "push") this.counters.pushFailed += 1;
    if (channel === "sms") this.counters.smsFailed += 1;
    if (channel === "email") this.counters.emailFailed += 1;
  }

  async sendPushNotification(payload: NotifyRequest, source: string): Promise<void> {
    const target = payload.target;
    if (!target.deviceTokens?.length && !target.topic) {
      throw new Error("missing push target");
    }

    const baseDataEntries = Object.entries(payload.payload.data ?? {}).map(([key, value]) => [
      key,
      String(value)
    ]);
    const baseData: Record<string, string> = Object.fromEntries([
      ["source", source],
      ...baseDataEntries
    ]);

    if (target.deviceTokens?.length) {
      if (this.deps.dryRun) {
        this.counters.pushSent += target.deviceTokens.length;
        console.log(
          JSON.stringify({
            level: "info",
            event: "push_multicast_dry_run",
            source,
            tokens: target.deviceTokens.length,
            title: payload.payload.title
          })
        );
      } else {
        const multicast: admin.messaging.MulticastMessage = {
          tokens: target.deviceTokens,
          data: baseData,
          notification: {
            title: payload.payload.title,
            body: payload.payload.body
          }
        };
        await this.deps.messaging.sendEachForMulticast(multicast);
        this.counters.pushSent += target.deviceTokens.length;
        console.log(
          JSON.stringify({
            level: "info",
            event: "push_multicast_sent",
            source,
            tokens: target.deviceTokens.length,
            title: payload.payload.title
          })
        );
      }
    }

    if (target.topic) {
      if (this.deps.dryRun) {
        this.counters.pushSent += 1;
        console.log(
          JSON.stringify({
            level: "info",
            event: "push_topic_dry_run",
            source,
            topic: target.topic,
            title: payload.payload.title
          })
        );
        return;
      }
      const message: admin.messaging.Message = {
        topic: target.topic,
        data: baseData,
        notification: {
          title: payload.payload.title,
          body: payload.payload.body
        }
      };
      await this.deps.messaging.send(message);
      this.counters.pushSent += 1;
      console.log(
        JSON.stringify({
          level: "info",
          event: "push_topic_sent",
          source,
          topic: target.topic,
          title: payload.payload.title
        })
      );
    }
  }

  async sendSmsNotification(payload: NotifyRequest): Promise<void> {
    const config = this.deps.config;
    if (this.deps.dryRun) {
      this.counters.smsSent += 1;
      console.log(
        JSON.stringify({
          level: "info",
          event: "sms_dry_run",
          to: payload.target.phoneNumber ?? config.OPS_PHONE,
          title: payload.payload.title
        })
      );
      return;
    }
    if (!this.deps.twilioClient) {
      return;
    }
    const phoneNumber = payload.target.phoneNumber ?? config.OPS_PHONE;
    if (!phoneNumber) {
      throw new Error("missing phoneNumber for sms channel");
    }
    if (!config.TWILIO_MESSAGING_NUMBER) {
      throw new Error("missing TWILIO_MESSAGING_NUMBER");
    }

    await this.deps.twilioClient.messages.create({
      to: phoneNumber,
      from: config.TWILIO_MESSAGING_NUMBER,
      body: payload.payload.body
    });
    this.counters.smsSent += 1;
    console.log(
      JSON.stringify({
        level: "info",
        event: "sms_sent",
        to: phoneNumber,
        title: payload.payload.title
      })
    );
  }

  async sendCustomerSms(params: { to: string; from: string; body: string }): Promise<void> {
    if (this.deps.dryRun) {
      this.counters.smsSent += 1;
      console.log(JSON.stringify({ level: "info", event: "customer_sms_dry_run", to: params.to, from: params.from }));
      return;
    }
    if (!this.deps.twilioClient) return;
    await this.deps.twilioClient.messages.create({
      to: params.to,
      from: params.from,
      body: params.body
    });
    this.counters.smsSent += 1;
    console.log(JSON.stringify({ level: "info", event: "customer_sms_sent", to: params.to, from: params.from }));
  }

  async sendEmailNotification(payload: NotifyRequest): Promise<void> {
    const config = this.deps.config;
    if (this.deps.dryRun) {
      this.counters.emailSent += 1;
      console.log(
        JSON.stringify({
          level: "info",
          event: "email_dry_run",
          to: payload.target.email ?? config.OPS_EMAIL,
          title: payload.payload.title
        })
      );
      return;
    }
    if (!config.SENDGRID_API_KEY) {
      return;
    }
    const email = payload.target.email ?? config.OPS_EMAIL;
    if (!email) {
      throw new Error("missing email target");
    }

    await this.deps.mailClient.send({
      to: email,
      from: config.SENDGRID_FROM_EMAIL ?? "alerts@ordering-intelligence.test",
      subject: payload.payload.title,
      text: payload.payload.body
    });
    this.counters.emailSent += 1;
    console.log(
      JSON.stringify({
        level: "info",
        event: "email_sent",
        to: email,
        title: payload.payload.title
      })
    );
  }
}
