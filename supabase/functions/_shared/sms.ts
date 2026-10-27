// Free-text SMS (staff invites). Supabase Auth only sends sign-in codes, so
// other messages go through an `SmsSender`, picked by SMS_PROVIDER:
//   twilio      Twilio Programmable SMS (hosted; the same account as Auth's SMS)
//   dev_outbox  kept in private.dev_sms_messages instead of being sent (local)

export interface SmsSender {
  /** Sends [body] to [phone] (E.164); throws when the provider refuses. */
  send(phone: string, body: string): Promise<void>;
}

export interface TwilioConfig {
  accountSid: string;
  authToken: string;
  /** A Messaging Service SID (MG…) or a sender number (+…). */
  sender: string;
}

export class TwilioSmsSender implements SmsSender {
  constructor(
    private readonly config: TwilioConfig,
    private readonly fetchFn: typeof fetch = fetch,
  ) {}

  async send(phone: string, body: string): Promise<void> {
    const { accountSid, authToken, sender } = this.config;
    const form = new URLSearchParams({ To: phone, Body: body });
    if (sender.startsWith("MG")) form.set("MessagingServiceSid", sender);
    else form.set("From", sender);
    const response = await this.fetchFn(
      `https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Messages.json`,
      {
        method: "POST",
        headers: {
          Authorization: `Basic ${btoa(`${accountSid}:${authToken}`)}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: form,
      },
    );
    if (!response.ok) {
      throw new Error(`twilio ${response.status}: ${await response.text()}`);
    }
  }
}

/** Keeps the message for a developer to read (see the F08 migration). */
export class DevOutboxSmsSender implements SmsSender {
  constructor(private readonly record: (phone: string, body: string) => Promise<void>) {}

  send(phone: string, body: string): Promise<void> {
    return this.record(phone, body);
  }
}

/** The sender named by SMS_PROVIDER (default dev_outbox). */
export function smsSenderFor(
  env: (name: string) => string | undefined,
  recordDev: (phone: string, body: string) => Promise<void>,
): SmsSender {
  const provider = env("SMS_PROVIDER") ?? "dev_outbox";
  if (provider === "dev_outbox") return new DevOutboxSmsSender(recordDev);
  if (provider === "twilio") {
    const accountSid = env("TWILIO_ACCOUNT_SID");
    const authToken = env("TWILIO_AUTH_TOKEN");
    const sender = env("TWILIO_MESSAGING_SERVICE_SID") ?? env("TWILIO_FROM");
    if (!accountSid || !authToken || !sender) {
      throw new Error(
        "SMS_PROVIDER=twilio needs TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN and a sender",
      );
    }
    return new TwilioSmsSender({ accountSid, authToken, sender });
  }
  throw new Error(`unknown SMS_PROVIDER ${provider}`);
}
