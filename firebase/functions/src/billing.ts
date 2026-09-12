// Cobro de la suscripción con Stripe.
//
// Lo que la app puede pedir: un enlace para pagar y un enlace para administrar
// su suscripción. Quien cambia el plan de una cuenta es el webhook de Stripe,
// nunca la app.
//
// Configuración (documento config/stripe, que solo leen estas funciones):
//   prices: { v45, v90, v180, v360 }   ids de precio mensuales de Stripe
//   successUrl, cancelUrl, portalReturnUrl
//
// Secretos:  firebase functions:secrets:set STRIPE_SECRET_KEY
//            firebase functions:secrets:set STRIPE_WEBHOOK_SECRET
import { defineSecret } from "firebase-functions/params";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import Stripe from "stripe";

import { db } from "./firestore";
import { isTier, limitsFor, Tier } from "./plans";

const stripeSecretKey = defineSecret("STRIPE_SECRET_KEY");
const stripeWebhookSecret = defineSecret("STRIPE_WEBHOOK_SECRET");

interface StripeConfig {
  prices: Record<string, string>;
  successUrl: string;
  cancelUrl: string;
  portalReturnUrl?: string;
}

/** Mientras no haya una clave real (sk_…), el cobro responde que falta configurarlo. */
function stripeConfigured(): boolean {
  return stripeSecretKey.value().startsWith("sk_");
}

function stripeClient(): Stripe {
  if (!stripeConfigured()) {
    throw new HttpsError("failed-precondition", "El cobro con Stripe aún no está configurado");
  }
  return new Stripe(stripeSecretKey.value());
}

async function stripeConfig(): Promise<StripeConfig> {
  const snapshot = await db.doc("config/stripe").get();
  const data = snapshot.data();
  if (!data?.prices || !data.successUrl || !data.cancelUrl) {
    throw new HttpsError(
      "failed-precondition",
      "Falta configurar el cobro: crea el documento config/stripe con los precios y las direcciones de regreso",
    );
  }
  return data as StripeConfig;
}

/** Solo el dueño de la cuenta toca la facturación. */
async function requireAccountOwner(accountId: string, uid: string | undefined): Promise<void> {
  if (!uid) {
    throw new HttpsError("unauthenticated", "Entra con tu cuenta primero");
  }
  const member = await db.doc(`accounts/${accountId}/members/${uid}`).get();
  if (!member.exists || member.get("role") !== "owner") {
    throw new HttpsError("permission-denied", "Solo el dueño de la cuenta administra el pago");
  }
}

/** Cliente de Stripe de la cuenta; se crea la primera vez. */
async function customerFor(stripe: Stripe, accountId: string, email: string | undefined): Promise<string> {
  const accountRef = db.doc(`accounts/${accountId}`);
  const account = await accountRef.get();
  const existing = account.get("billing.stripeCustomerId");
  if (typeof existing === "string" && existing.length > 0) {
    return existing;
  }
  const customer = await stripe.customers.create({
    email,
    name: account.get("name"),
    metadata: { accountId },
  });
  await accountRef.set({ billing: { stripeCustomerId: customer.id } }, { merge: true });
  return customer.id;
}

/** Enlace de pago para subir o empezar un plan. */
export const createCheckoutSession = onCall({ secrets: [stripeSecretKey], invoker: "public" }, async (request) => {
  const accountId = typeof request.data?.accountId === "string" ? request.data.accountId : "";
  const tier = request.data?.tier;
  if (!isTier(tier)) {
    throw new HttpsError("invalid-argument", "Elige un plan válido");
  }
  await requireAccountOwner(accountId, request.auth?.uid);

  const config = await stripeConfig();
  const price = config.prices[tier];
  if (!price) {
    throw new HttpsError("failed-precondition", `Falta el precio de Stripe para el plan ${tier}`);
  }

  const stripe = stripeClient();
  const customer = await customerFor(stripe, accountId, request.auth?.token?.email as string | undefined);
  const session = await stripe.checkout.sessions.create({
    mode: "subscription",
    customer,
    line_items: [{ price, quantity: 1 }],
    success_url: config.successUrl,
    cancel_url: config.cancelUrl,
    client_reference_id: accountId,
    subscription_data: { metadata: { accountId, tier } },
    metadata: { accountId, tier },
    allow_promotion_codes: true,
  });
  return { url: session.url };
});

/** Enlace al portal de Stripe: cambiar tarjeta, ver facturas o cancelar. */
export const createBillingPortalSession = onCall({ secrets: [stripeSecretKey], invoker: "public" }, async (request) => {
  const accountId = typeof request.data?.accountId === "string" ? request.data.accountId : "";
  await requireAccountOwner(accountId, request.auth?.uid);

  const config = await stripeConfig();
  const stripe = stripeClient();
  const customer = await customerFor(stripe, accountId, request.auth?.token?.email as string | undefined);
  const session = await stripe.billingPortal.sessions.create({
    customer,
    return_url: config.portalReturnUrl ?? config.successUrl,
  });
  return { url: session.url };
});

/** Plan de una suscripción de Stripe: primero su metadata, si no, el precio. */
async function tierOf(subscription: Stripe.Subscription): Promise<Tier> {
  const fromMetadata = subscription.metadata?.tier;
  if (isTier(fromMetadata)) {
    return fromMetadata;
  }
  const priceId = subscription.items.data[0]?.price.id;
  const config = await stripeConfig();
  for (const [tier, price] of Object.entries(config.prices)) {
    if (price === priceId && isTier(tier)) {
      return tier;
    }
  }
  return "v45";
}

/** Traduce el estado de Stripe al que entiende la app. */
function planStatus(status: Stripe.Subscription.Status): string {
  switch (status) {
    case "active":
    case "trialing":
      return status === "trialing" ? "trial" : "active";
    case "past_due":
    case "unpaid":
      return "past_due";
    default:
      return "canceled";
  }
}

async function applySubscription(subscription: Stripe.Subscription): Promise<void> {
  const accountId = subscription.metadata?.accountId;
  if (!accountId) {
    logger.warn("Suscripción de Stripe sin accountId", { subscription: subscription.id });
    return;
  }
  const tier = await tierOf(subscription);
  const status = planStatus(subscription.status);
  const periodEnd = subscription.items.data[0]?.current_period_end;

  await db.doc(`accounts/${accountId}`).set(
    {
      plan: {
        tier,
        status,
        source: "stripe",
        currentPeriodEnd: periodEnd ? Timestamp.fromMillis(periodEnd * 1000) : FieldValue.delete(),
      },
      limits: limitsFor(tier),
      billing: { stripeSubscriptionId: subscription.id },
    },
    { merge: true },
  );
  logger.info("Plan actualizado", { accountId, tier, status });
}

/** Stripe avisa aquí de cada pago, cambio o cancelación. */
export const stripeWebhook = onRequest(
  { secrets: [stripeSecretKey, stripeWebhookSecret], cors: false, invoker: "public" },
  async (request, response) => {
    const signature = request.get("stripe-signature");
    if (!signature) {
      response.status(400).send("Falta la firma de Stripe");
      return;
    }
    if (!stripeConfigured() || !stripeWebhookSecret.value().startsWith("whsec_")) {
      response.status(503).send("El cobro con Stripe aún no está configurado");
      return;
    }
    const stripe = stripeClient();
    let event: Stripe.Event;
    try {
      event = stripe.webhooks.constructEvent(request.rawBody, signature, stripeWebhookSecret.value());
    } catch (error) {
      logger.warn("Webhook de Stripe rechazado", { error: `${error}` });
      response.status(400).send("Firma inválida");
      return;
    }

    try {
      switch (event.type) {
        case "checkout.session.completed": {
          const session = event.data.object;
          if (typeof session.subscription === "string") {
            const subscription = await stripe.subscriptions.retrieve(session.subscription);
            if (!subscription.metadata?.accountId && session.client_reference_id) {
              subscription.metadata = {
                ...subscription.metadata,
                accountId: session.client_reference_id,
              };
            }
            await applySubscription(subscription);
          }
          break;
        }
        case "customer.subscription.created":
        case "customer.subscription.updated":
        case "customer.subscription.deleted":
          await applySubscription(event.data.object);
          break;
        default:
          logger.debug("Evento de Stripe sin manejar", { type: event.type });
      }
      response.json({ received: true });
    } catch (error) {
      logger.error("Error atendiendo el webhook de Stripe", { type: event.type, error: `${error}` });
      response.status(500).send("Error interno");
    }
  },
);
