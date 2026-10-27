import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import { DevOutboxSmsSender, smsSenderFor, TwilioSmsSender } from "./sms.ts";

Deno.test("Twilio sends a form POST with basic auth", async () => {
  const calls: { url: string; init: RequestInit }[] = [];
  const fakeFetch = ((url: string, init: RequestInit) => {
    calls.push({ url, init });
    return Promise.resolve(new Response("{}", { status: 201 }));
  }) as unknown as typeof fetch;
  await new TwilioSmsSender({ accountSid: "AC1", authToken: "tok", sender: "MG9" }, fakeFetch)
    .send("+85512345678", "Hello");

  assertEquals(calls[0].url, "https://api.twilio.com/2010-04-01/Accounts/AC1/Messages.json");
  assertEquals(
    (calls[0].init.headers as Record<string, string>).Authorization,
    `Basic ${btoa("AC1:tok")}`,
  );
  const form = calls[0].init.body as URLSearchParams;
  assertEquals(form.get("To"), "+85512345678");
  assertEquals(form.get("Body"), "Hello");
  assertEquals(form.get("MessagingServiceSid"), "MG9");
});

Deno.test("Twilio uses From for a sender number and throws on refusal", async () => {
  let form: URLSearchParams | undefined;
  const refuse = ((_: string, init: RequestInit) => {
    form = init.body as URLSearchParams;
    return Promise.resolve(new Response("bad number", { status: 400 }));
  }) as unknown as typeof fetch;
  await assertRejects(
    () =>
      new TwilioSmsSender({ accountSid: "AC1", authToken: "t", sender: "+15005550006" }, refuse)
        .send("+855", "x"),
    Error,
    "twilio 400",
  );
  assertEquals(form?.get("From"), "+15005550006");
});

Deno.test("the dev outbox records instead of sending", async () => {
  const kept: string[] = [];
  await new DevOutboxSmsSender((phone, body) => {
    kept.push(`${phone}:${body}`);
    return Promise.resolve();
  }).send("+85512345678", "Hi");
  assertEquals(kept, ["+85512345678:Hi"]);
});

Deno.test("SMS_PROVIDER picks the sender", () => {
  const record = () => Promise.resolve();
  const env = (values: Record<string, string>) => (name: string) => values[name];
  assertEquals(smsSenderFor(env({}), record) instanceof DevOutboxSmsSender, true);
  assertEquals(
    smsSenderFor(
      env({
        SMS_PROVIDER: "twilio",
        TWILIO_ACCOUNT_SID: "AC1",
        TWILIO_AUTH_TOKEN: "t",
        TWILIO_FROM: "+1",
      }),
      record,
    ) instanceof TwilioSmsSender,
    true,
  );
  assertThrows(() => smsSenderFor(env({ SMS_PROVIDER: "twilio" }), record), Error, "TWILIO");
  assertThrows(() => smsSenderFor(env({ SMS_PROVIDER: "pigeon" }), record), Error, "unknown");
});
