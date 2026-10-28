// Every notification K sends (N-01 customer and business, N-02 rider and
// admin): which inbox tab it lands in, which S-08d switch can silence its
// push, where a tap opens, and the copy in English and Khmer.
//
// Copy follows the "Writing a push" rules on N-01: the title says what
// happened; the body adds the order or quote number and the next step.
// Placeholders are `{key}` or `{key:format}`, filled from the `data` the
// caller passes (see `format` below). Adding an event = adding an entry here.

/** S-07 tab. `account` shows under All only. */
export type Category = "orders" | "quotes" | "chat" | "account";

/** S-08d card whose Push switch applies; null = always sent (payments,
 * refunds, account security, rider jobs). */
export type PrefGroup = "orders" | "quotes" | "chat" | "reviews" | null;

export type Locale = "en" | "km";

export type Role = "customer" | "business" | "rider" | "staff";

export interface Recipient {
  id: string;
  role: Role;
  locale: Locale;
}

export interface NotificationType {
  category: Category;
  pref: PrefGroup;
  /** In-app path a tap opens; ids come from `data`. */
  route: (data: Record<string, unknown>, to: Recipient) => string;
  /** `data` keys the route needs on top of the copy's placeholders. */
  routeKeys?: string[];
  /** Rider job alerts play their own sound (N-02). */
  sound?: "job";
  title: Record<Locale, string>;
  body: Record<Locale, string>;
}

/** Customer or business shell, by the recipient's current role. */
const shell = (to: Recipient) => (to.role === "business" ? "/business" : "/customer");

const order = (d: Record<string, unknown>, to: Recipient) => `${shell(to)}/orders/${d.order_id}`;
const quote = (d: Record<string, unknown>) => `/business/quotes/${d.rfq_id}`;
const chat = (d: Record<string, unknown>, to: Recipient) =>
  `${shell(to)}/chat/${d.conversation_id}`;
const account = (_: Record<string, unknown>, to: Recipient) => `${shell(to)}/account`;
// Rider jobs (R-01) and the admin lists (A-01…) are later tasks; until then a
// tap opens the role's home.
const riderHome = () => "/rider";
const adminHome = () => "/admin";
const adminInventory = () => "/admin/inventory";

/** Where a `test` notification opens (S-08d dev tool, README). */
const TEST_TARGETS: Record<string, (d: Record<string, unknown>, to: Recipient) => string> = {
  inbox: (_, to) => `${shell(to)}/inbox`,
  order,
  quote,
  chat,
};

export const NOTIFICATION_TYPES: Record<string, NotificationType> = {
  // ---------------------------------------------------------------- orders
  order_confirmed_cod: {
    category: "orders",
    pref: "orders",
    route: order,
    routeKeys: ["order_id"],
    title: { en: "Order confirmed", km: "ការបញ្ជាទិញត្រូវបានបញ្ជាក់" },
    body: {
      en: "#{order_number} · Pay {amount:money} in cash when it arrives.",
      km: "#{order_number} · បង់ {amount:money} ជាសាច់ប្រាក់ពេលទំនិញមកដល់។",
    },
  },
  payment_received: {
    category: "orders",
    pref: null,
    route: order,
    routeKeys: ["order_id"],
    title: { en: "Payment received", km: "បានទទួលការទូទាត់" },
    body: {
      en: "We got {amount:money} by KHQR for #{order_number}. Your order is confirmed.",
      km: "យើងបានទទួល {amount:money} តាម KHQR សម្រាប់ #{order_number}។ ការបញ្ជាទិញរបស់អ្នកត្រូវបានបញ្ជាក់។",
    },
  },
  payment_expired: {
    category: "orders",
    pref: null,
    route: order,
    routeKeys: ["order_id"],
    title: { en: "Payment time ran out", km: "ផុតពេលទូទាត់" },
    body: {
      en:
        "#{order_number} wasn’t paid within 15 minutes, so we released the items. Tap to try again.",
      km: "#{order_number} មិនបានទូទាត់ក្នុងរយៈពេល 15 នាទី ដូច្នេះយើងបានដោះលែងទំនិញវិញ។ ចុចដើម្បីសាកម្តងទៀត។",
    },
  },
  order_packing: {
    category: "orders",
    pref: "orders",
    route: order,
    routeKeys: ["order_id"],
    title: { en: "We’re packing your order", km: "យើងកំពុងវេចខ្ចប់ការបញ្ជាទិញរបស់អ្នក" },
    body: {
      en: "#{order_number} is being packed. We’ll let you know when it leaves the store.",
      km: "#{order_number} កំពុងត្រូវបានវេចខ្ចប់។ យើងនឹងប្រាប់អ្នកពេលវាចេញពីហាង។",
    },
  },
  order_out_for_delivery: {
    category: "orders",
    pref: "orders",
    route: order,
    routeKeys: ["order_id"],
    title: { en: "Your order is on the way", km: "ការបញ្ជាទិញរបស់អ្នកកំពុងដឹកមក" },
    body: {
      en: "{rider_name} is delivering #{order_number}. Arriving in about {eta_minutes} min.",
      km: "{rider_name} កំពុងដឹក #{order_number}។ នឹងមកដល់ក្នុងរយៈពេលប្រហែល {eta_minutes} នាទី។",
    },
  },
  order_delivered: {
    category: "orders",
    pref: "orders",
    route: order,
    routeKeys: ["order_id"],
    title: { en: "Delivered", km: "បានដឹកជូនរួចរាល់" },
    body: {
      en:
        "#{order_number} was delivered at {delivered_at:time}. Returns are open until {returns_until:day}.",
      km:
        "#{order_number} ត្រូវបានដឹកជូននៅម៉ោង {delivered_at:time}។ អាចស្នើសុំត្រឡប់ទំនិញបានរហូតដល់ {returns_until:day}។",
    },
  },
  delivery_failed: {
    category: "orders",
    pref: "orders",
    route: order,
    routeKeys: ["order_id"],
    title: { en: "We couldn’t deliver your order", km: "យើងមិនអាចដឹកជូនការបញ្ជាទិញរបស់អ្នកបានទេ" },
    body: {
      en: "Our rider couldn’t reach you for #{order_number}. We’ll call to arrange a new time.",
      km: "អ្នកដឹកជញ្ជូនមិនអាចទាក់ទងអ្នកបានសម្រាប់ #{order_number}។ យើងនឹងហៅទូរសព្ទដើម្បីណាត់ពេលថ្មី។",
    },
  },
  bank_transfer_confirmed: {
    category: "orders",
    pref: null,
    route: order,
    routeKeys: ["order_id"],
    title: { en: "Payment confirmed", km: "ការទូទាត់ត្រូវបានបញ្ជាក់" },
    body: {
      en: "We confirmed your bank transfer for #{order_number}. Your order is being prepared.",
      km: "យើងបានបញ្ជាក់ការផ្ទេរប្រាក់តាមធនាគាររបស់អ្នកសម្រាប់ #{order_number}។ ការបញ្ជាទិញរបស់អ្នកកំពុងរៀបចំ។",
    },
  },
  bank_slip_rejected: {
    category: "orders",
    pref: null,
    route: order,
    routeKeys: ["order_id"],
    title: { en: "Transfer slip rejected", km: "បង្កាន់ដៃផ្ទេរប្រាក់ត្រូវបានបដិសេធ" },
    body: {
      en:
        "We couldn’t match your slip to #{order_number}. Please upload a new slip by {deadline:date}.",
      km: "យើងមិនអាចផ្ទៀងផ្ទាត់បង្កាន់ដៃរបស់អ្នកជាមួយ #{order_number} បានទេ។ សូមផ្ញើបង្កាន់ដៃថ្មីមុន {deadline:date}។",
    },
  },

  // ---------------------------------------------------------- after delivery
  review_reminder: {
    category: "orders",
    pref: "reviews",
    route: order,
    routeKeys: ["order_id"],
    title: { en: "How was your order?", km: "តើការបញ្ជាទិញរបស់អ្នកយ៉ាងម៉េចដែរ?" },
    body: {
      en: "Rate {product_name} from #{order_number} and help other shoppers.",
      km: "វាយតម្លៃ {product_name} ពី #{order_number} ដើម្បីជួយអ្នកទិញផ្សេងទៀត។",
    },
  },
  return_approved: {
    category: "orders",
    pref: "orders",
    route: order,
    routeKeys: ["order_id"],
    title: { en: "Return approved", km: "ការស្នើសុំត្រឡប់ទំនិញត្រូវបានយល់ព្រម" },
    body: {
      en:
        "A rider will pick up {product_name} on {pickup_date:day}, {pickup_window}. Please have {fee:money} ready for the return fee.",
      km:
        "អ្នកដឹកជញ្ជូននឹងមកយក {product_name} នៅ {pickup_date:day} ម៉ោង {pickup_window}។ សូមរៀបចំ {fee:money} សម្រាប់ថ្លៃត្រឡប់ទំនិញ។",
    },
  },
  return_rejected: {
    category: "orders",
    pref: "orders",
    route: order,
    routeKeys: ["order_id"],
    title: { en: "Return not approved", km: "ការស្នើសុំត្រឡប់ទំនិញមិនត្រូវបានយល់ព្រម" },
    body: {
      en: "We couldn’t approve {return_number}. Tap to see details.",
      km: "យើងមិនអាចយល់ព្រម {return_number} បានទេ។ ចុចដើម្បីមើលព័ត៌មានលម្អិត។",
    },
  },
  refund_sent: {
    category: "orders",
    pref: null,
    route: order,
    routeKeys: ["order_id"],
    title: { en: "Refund sent", km: "បានផ្ញើប្រាក់សង" },
    body: {
      en: "{amount:money} for return {return_number} (#{order_number}) is on its way to you.",
      km: "{amount:money} សម្រាប់ការត្រឡប់ទំនិញ {return_number} (#{order_number}) កំពុងផ្ញើទៅអ្នក។",
    },
  },

  // ---------------------------------------------------------------- chat
  chat_message: {
    category: "chat",
    pref: "chat",
    route: chat,
    routeKeys: ["conversation_id"],
    title: { en: "K Support replied", km: "K Support បានឆ្លើយតប" },
    body: { en: "{sender_name}: {preview}", km: "{sender_name}: {preview}" },
  },

  // ---------------------------------------------------- business account
  business_approved: {
    category: "account",
    pref: null,
    route: account,
    title: { en: "Your business account is active", km: "គណនីអាជីវកម្មរបស់អ្នកដំណើរការហើយ" },
    body: {
      en: "{company_name} is verified. You can now request quotes.",
      km: "{company_name} ត្រូវបានផ្ទៀងផ្ទាត់។ ឥឡូវនេះអ្នកអាចស្នើសុំសម្រង់តម្លៃបានហើយ។",
    },
  },
  business_rejected: {
    category: "account",
    pref: null,
    route: account,
    title: { en: "We couldn’t verify your business", km: "យើងមិនអាចផ្ទៀងផ្ទាត់អាជីវកម្មរបស់អ្នកបានទេ" },
    body: {
      en: "{reason} Tap to edit and resubmit.",
      km: "{reason} ចុចដើម្បីកែប្រែ និងដាក់ស្នើម្តងទៀត។",
    },
  },

  // ---------------------------------------------------------------- quotes
  quote_ready: {
    category: "quotes",
    pref: "quotes",
    route: quote,
    routeKeys: ["rfq_id"],
    title: { en: "Your quote is ready", km: "សម្រង់តម្លៃរបស់អ្នករួចរាល់ហើយ" },
    body: {
      en: "{rfq_number} · {amount:money} · valid until {valid_until:date}. Review and accept.",
      km: "{rfq_number} · {amount:money} · មានសុពលភាពដល់ {valid_until:date}។ ពិនិត្យ និងទទួលយក។",
    },
  },
  quote_revised: {
    category: "quotes",
    pref: "quotes",
    route: quote,
    routeKeys: ["rfq_id"],
    title: { en: "Quote updated", km: "សម្រង់តម្លៃត្រូវបានធ្វើបច្ចុប្បន្នភាព" },
    body: {
      en: "Sales sent version {version} of {rfq_number}. Check the new prices.",
      km: "ផ្នែកលក់បានផ្ញើកំណែទី {version} នៃ {rfq_number}។ សូមពិនិត្យតម្លៃថ្មី។",
    },
  },
  quote_expiring: {
    category: "quotes",
    pref: "quotes",
    route: quote,
    routeKeys: ["rfq_id"],
    title: { en: "Quote expires tomorrow", km: "សម្រង់តម្លៃនឹងផុតកំណត់ថ្ងៃស្អែក" },
    body: {
      en: "{rfq_number} is valid until {valid_until:date}. Accept it to keep these prices.",
      km: "{rfq_number} មានសុពលភាពដល់ {valid_until:date}។ ទទួលយកវាដើម្បីរក្សាតម្លៃទាំងនេះ។",
    },
  },

  // ---------------------------------------------------------------- rider
  job_assigned: {
    category: "orders",
    pref: null,
    route: riderHome,
    sound: "job",
    title: { en: "New delivery assigned", km: "ការដឹកជញ្ជូនថ្មីត្រូវបានចាត់ឱ្យ" },
    body: {
      en: "#{order_number} · {area}. Tap to view the job.",
      km: "#{order_number} · {area}។ ចុចដើម្បីមើលការងារ។",
    },
  },
  return_pickup_assigned: {
    category: "orders",
    pref: null,
    route: riderHome,
    sound: "job",
    title: { en: "Return pickup assigned", km: "ការទៅយកទំនិញត្រឡប់ត្រូវបានចាត់ឱ្យ" },
    body: {
      en:
        "Collect {product_name} from {customer_name} (#{order_number}) on {pickup_date:day}, {pickup_window}. Collect {fee:money} fee.",
      km:
        "ទៅយក {product_name} ពី {customer_name} (#{order_number}) នៅ {pickup_date:day} ម៉ោង {pickup_window}។ ប្រមូលថ្លៃ {fee:money}។",
    },
  },
  job_reassigned: {
    category: "orders",
    pref: null,
    route: riderHome,
    title: { en: "Job moved to another rider", km: "ការងារត្រូវបានផ្ទេរទៅអ្នកដឹកជញ្ជូនផ្សេង" },
    body: {
      en: "#{order_number} was reassigned. Your job list is updated.",
      km: "#{order_number} ត្រូវបានផ្ទេរ។ បញ្ជីការងាររបស់អ្នកត្រូវបានធ្វើបច្ចុប្បន្នភាព។",
    },
  },

  // ---------------------------------------------------------------- admin
  admin_new_order: {
    category: "orders",
    pref: null,
    route: adminHome,
    title: { en: "New order #{order_number}", km: "ការបញ្ជាទិញថ្មី #{order_number}" },
    body: { en: "{customer_name} · {amount:money}.", km: "{customer_name} · {amount:money}។" },
  },
  admin_new_rfq: {
    category: "quotes",
    pref: null,
    route: adminHome,
    title: { en: "New quote request", km: "សំណើសម្រង់តម្លៃថ្មី" },
    body: {
      en: "{company_name} sent {rfq_number} · {item_count} items. Quote due within 1 business day.",
      km: "{company_name} បានផ្ញើ {rfq_number} · {item_count} មុខ។ ត្រូវផ្តល់សម្រង់តម្លៃក្នុងរយៈពេល 1 ថ្ងៃធ្វើការ។",
    },
  },
  admin_bank_slip: {
    category: "orders",
    pref: null,
    route: adminHome,
    title: { en: "Bank slip to confirm", km: "បង្កាន់ដៃធនាគាររង់ចាំបញ្ជាក់" },
    body: {
      en: "{company_name} uploaded a slip for #{order_number} · {amount:money}.",
      km: "{company_name} បានផ្ញើបង្កាន់ដៃសម្រាប់ #{order_number} · {amount:money}។",
    },
  },
  admin_return_requested: {
    category: "orders",
    pref: null,
    route: adminHome,
    title: { en: "Return requested", km: "មានការស្នើសុំត្រឡប់ទំនិញ" },
    body: {
      en: "{return_number} · {product_name} (#{order_number}) · reason: {reason}.",
      km: "{return_number} · {product_name} (#{order_number}) · មូលហេតុ៖ {reason}។",
    },
  },
  admin_business_request: {
    category: "account",
    pref: null,
    route: adminHome,
    title: { en: "Business verification request", km: "សំណើផ្ទៀងផ្ទាត់អាជីវកម្ម" },
    body: {
      en: "{company_name} submitted its licence and VAT TIN.",
      km: "{company_name} បានដាក់ស្នើអាជ្ញាប័ណ្ណ និងលេខ VAT TIN។",
    },
  },
  admin_low_stock: {
    category: "orders",
    pref: null,
    route: adminInventory,
    title: { en: "Low stock", km: "ស្តុកជិតអស់" },
    body: {
      en: "{product_name} has {stock} left. Low-stock level is {threshold}.",
      km: "{product_name} នៅសល់ {stock}។ កម្រិតស្តុកទាបគឺ {threshold}។",
    },
  },
  admin_delivery_failed: {
    category: "orders",
    pref: null,
    route: adminHome,
    title: { en: "Delivery failed", km: "ការដឹកជញ្ជូនមិនបានសម្រេច" },
    body: {
      en: "#{order_number} · {reason} · reported by {rider_name}.",
      km: "#{order_number} · {reason} · រាយការណ៍ដោយ {rider_name}។",
    },
  },
  admin_chat_waiting: {
    category: "chat",
    pref: null,
    route: adminHome,
    title: { en: "Chat waiting", km: "មានការជជែករង់ចាំ" },
    body: {
      en: "{customer_name} has waited {minutes} min for a reply.",
      km: "{customer_name} បានរង់ចាំការឆ្លើយតប {minutes} នាទីហើយ។",
    },
  },

  // ---------------------------------------------------------------- testing
  // "Done when": a test push opens the right screen. `target` is one of
  // TEST_TARGETS; order/quote/chat also need their id.
  test: {
    category: "account",
    pref: null,
    route: (d, to) => (TEST_TARGETS[String(d.target ?? "inbox")] ?? TEST_TARGETS.inbox)(d, to),
    title: { en: "Test notification", km: "ការជូនដំណឹងសាកល្បង" },
    body: {
      en: "Tap to check it opens the right screen.",
      km: "ចុចដើម្បីពិនិត្យថាវាបើកអេក្រង់ត្រឹមត្រូវ។",
    },
  },
};

export const TEST_TARGET_NAMES = Object.keys(TEST_TARGETS);

/** The id each test target needs in `data`. */
export const TEST_TARGET_IDS: Record<string, string | undefined> = {
  order: "order_id",
  quote: "rfq_id",
  chat: "conversation_id",
};

// ---------------------------------------------------------------- copy

const MONTHS: Record<Locale, string[]> = {
  en: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"],
  km: [
    "មករា",
    "កុម្ភៈ",
    "មីនា",
    "មេសា",
    "ឧសភា",
    "មិថុនា",
    "កក្កដា",
    "សីហា",
    "កញ្ញា",
    "តុលា",
    "វិច្ឆិកា",
    "ធ្នូ",
  ],
};
const WEEKDAYS: Record<Locale, string[]> = {
  en: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"],
  km: ["អាទិត្យ", "ចន្ទ", "អង្គារ", "ពុធ", "ព្រហស្បតិ៍", "សុក្រ", "សៅរ៍"],
};

/** Cambodia is UTC+7 all year (no daylight saving). */
const PHNOM_PENH_OFFSET_MS = 7 * 60 * 60 * 1000;

function phnomPenh(value: unknown): Date {
  const date = new Date(String(value));
  if (Number.isNaN(date.getTime())) throw new TypeError(`not a date: ${value}`);
  // A bare `YYYY-MM-DD` is already a local calendar date.
  return /^\d{4}-\d{2}-\d{2}$/.test(String(value))
    ? date
    : new Date(date.getTime() + PHNOM_PENH_OFFSET_MS);
}

/** USD cents → "$2,260.50" (prices are USD incl. VAT). */
function money(value: unknown): string {
  const cents = Number(value);
  if (!Number.isInteger(cents)) throw new TypeError(`not cents: ${value}`);
  const sign = cents < 0 ? "-" : "";
  const abs = Math.abs(cents);
  const dollars = Math.floor(abs / 100).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  return `${sign}$${dollars}.${String(abs % 100).padStart(2, "0")}`;
}

/**
 * `{key}` → the value as text; `{key:money}` cents → "$92.00";
 * `{key:date}` → "5 Nov"; `{key:day}` → "Sun 25 Oct"; `{key:time}` → "2:01 PM",
 * all in Phnom Penh time.
 */
export function format(value: unknown, kind: string | undefined, locale: Locale): string {
  switch (kind) {
    case undefined:
      return String(value);
    case "money":
      return money(value);
    case "date": {
      const d = phnomPenh(value);
      return `${d.getUTCDate()} ${MONTHS[locale][d.getUTCMonth()]}`;
    }
    case "day": {
      const d = phnomPenh(value);
      return `${WEEKDAYS[locale][d.getUTCDay()]} ${d.getUTCDate()} ${
        MONTHS[locale][d.getUTCMonth()]
      }`;
    }
    case "time": {
      const d = phnomPenh(value);
      const h = d.getUTCHours();
      const m = String(d.getUTCMinutes()).padStart(2, "0");
      return `${h % 12 === 0 ? 12 : h % 12}:${m} ${h < 12 ? "AM" : "PM"}`;
    }
    default:
      throw new TypeError(`unknown format ${kind}`);
  }
}

const PLACEHOLDER = /\{(\w+)(?::(\w+))?\}/g;

/** Every `data` key a type needs: its placeholders plus its route ids. */
export function requiredKeys(type: NotificationType): string[] {
  const keys = new Set(type.routeKeys ?? []);
  for (const text of [type.title.en, type.body.en]) {
    for (const [, key] of text.matchAll(PLACEHOLDER)) keys.add(key);
  }
  return [...keys];
}

export function render(template: string, data: Record<string, unknown>, locale: Locale): string {
  return template.replace(
    PLACEHOLDER,
    (_, key: string, kind?: string) => format(data[key], kind, locale),
  );
}
