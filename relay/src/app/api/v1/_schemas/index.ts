/**
 * Zod schemas for every /api/v1 route. Field names match
 * `RelayBillingContracts.swift` and the watch's `RelayAIClient`. We accept
 * both snake_case and camelCase via per-field `pickField` helpers so the
 * dual-key codec used elsewhere in the relay continues to work.
 */

import { z } from "zod";

const PLATFORMS = ["iPhone", "watch", "mac", "unknown"] as const;
const platformSchema = z
  .union([z.enum(PLATFORMS), z.string()])
  .optional()
  .transform((v) => {
    if (!v) return "unknown" as const;
    return (PLATFORMS as readonly string[]).includes(v) ? (v as (typeof PLATFORMS)[number]) : ("unknown" as const);
  });

function dual<T>(camel: string, snake: string, parser: z.ZodType<T>): z.ZodEffects<z.ZodUnknown, T | undefined, unknown> {
  return z.unknown().transform((raw): T | undefined => {
    const obj = raw as Record<string, unknown> | undefined;
    if (!obj) return undefined;
    const value = obj[camel] !== undefined ? obj[camel] : obj[snake];
    if (value === undefined) return undefined;
    const parsed = parser.safeParse(value);
    return parsed.success ? parsed.data : undefined;
  });
}

void dual;

function pickStringField(obj: Record<string, unknown> | undefined, ...keys: string[]): string | undefined {
  if (!obj) return undefined;
  for (const k of keys) {
    const v = obj[k];
    if (typeof v === "string") return v;
  }
  return undefined;
}

export function pickString(obj: Record<string, unknown> | undefined, ...keys: string[]): string | undefined {
  return pickStringField(obj, ...keys);
}

const attachmentSchema = z
  .object({
    mimeType: z.string().optional(),
    base64Data: z.string().optional(),
    filename: z.string().optional(),
  })
  .passthrough();

const messageSchema = z
  .object({
    role: z.string().optional(),
    text: z.string().optional(),
    modelResponseParts: z.array(z.unknown()).optional(),
    attachments: z.array(attachmentSchema).optional(),
  })
  .passthrough();

export const chatRequestSchema = z
  .object({
    model: z.string().optional(),
    systemPrompt: z.string().optional(),
    systemInstructionParts: z.array(z.unknown()).optional(),
    thinkingIntensity: z.string().optional(),
    maxOutputTokens: z.number().optional(),
    includeThoughts: z.boolean().optional(),
    usesGoogleSearch: z.boolean().optional(),
    usesCodeExecution: z.boolean().optional(),
    messages: z.array(messageSchema).optional(),
  })
  .passthrough();

export const transcribeRequestSchema = z
  .object({
    model: z.string().optional(),
    systemPrompt: z.string().optional(),
    prompt: z.string().optional(),
    audio: z
      .object({
        mimeType: z.string().optional(),
        base64Data: z.string().optional(),
        filename: z.string().optional(),
      })
      .passthrough()
      .optional(),
  })
  .passthrough();

export const memoryRequestSchema = z
  .object({
    model: z.string().optional(),
    mode: z.string().optional(),
    conversationTitle: z.string().optional(),
    existingFocusState: z.unknown().optional(),
    existingMemoryItems: z.array(z.unknown()).optional(),
    recentMessages: z.array(z.unknown()).optional(),
    archiveCandidateMessages: z.array(z.unknown()).optional(),
  })
  .passthrough();

export const bootstrapRequestSchema = z
  .object({})
  .passthrough()
  .transform((raw) => {
    const obj = raw as Record<string, unknown>;
    return {
      deviceID: pickStringField(obj, "deviceID", "device_id"),
      platform: pickStringField(obj, "platform"),
      deviceAlias: pickStringField(obj, "deviceAlias", "device_alias"),
    };
  })
  .pipe(
    z.object({
      deviceID: z.string().min(1, "Missing deviceID."),
      platform: platformSchema,
      deviceAlias: z.string().optional(),
    }),
  );

export const pairingTokenRequestSchema = z
  .object({})
  .passthrough()
  .transform((raw) => {
    const obj = raw as Record<string, unknown>;
    return { deviceID: pickStringField(obj, "deviceID", "device_id") };
  });

export const joinPairedRequestSchema = z
  .object({})
  .passthrough()
  .transform((raw) => {
    const obj = raw as Record<string, unknown>;
    return {
      pairingToken: pickStringField(obj, "pairingToken", "pairing_token"),
      deviceID: pickStringField(obj, "deviceID", "device_id"),
      platform: pickStringField(obj, "platform"),
      deviceAlias: pickStringField(obj, "deviceAlias", "device_alias"),
    };
  })
  .pipe(
    z.object({
      pairingToken: z.string().min(1, "Missing pairingToken."),
      deviceID: z.string().min(1, "Missing deviceID."),
      platform: platformSchema,
      deviceAlias: z.string().optional(),
    }),
  );

export const offlineExchangeRequestSchema = z
  .object({})
  .passthrough()
  .transform((raw) => {
    const obj = raw as Record<string, unknown>;
    return {
      activationCode: pickStringField(obj, "activationCode", "activation_code"),
      deviceID: pickStringField(obj, "deviceID", "device_id"),
      platform: pickStringField(obj, "platform"),
      activationFingerprint: pickStringField(obj, "activationFingerprint", "activation_fingerprint"),
      deviceAlias: pickStringField(obj, "deviceAlias", "device_alias"),
    };
  })
  .pipe(
    z.object({
      activationCode: z.string().min(1, "Missing activationCode."),
      deviceID: z.string().min(1, "Missing deviceID."),
      platform: platformSchema,
      activationFingerprint: z.string().optional(),
      deviceAlias: z.string().optional(),
    }),
  );

export const purchasePrepareRequestSchema = z
  .object({})
  .passthrough()
  .transform((raw) => {
    const obj = raw as Record<string, unknown>;
    return {
      accountID: pickStringField(obj, "accountID", "account_id"),
      deviceID: pickStringField(obj, "deviceID", "device_id"),
      platform: pickStringField(obj, "platform"),
    };
  });

export const purchaseSubmitRequestSchema = z
  .object({})
  .passthrough()
  .transform((raw) => {
    const obj = raw as Record<string, unknown>;
    const txn = (obj.transaction ?? {}) as Record<string, unknown>;
    return {
      signedTransactionInfo:
        pickStringField(txn, "signedTransactionInfo", "signed_transaction_info") ??
        pickStringField(obj, "signedTransactionInfo", "signed_transaction_info"),
      accountID: pickStringField(obj, "accountID", "account_id"),
      deviceID: pickStringField(obj, "deviceID", "device_id"),
      platform: pickStringField(obj, "platform"),
    };
  })
  .pipe(
    z.object({
      signedTransactionInfo: z.string().min(1, "Missing signedTransactionInfo."),
      accountID: z.string().optional(),
      deviceID: z.string().optional(),
      platform: platformSchema,
    }),
  );

export const restoreRequestSchema = z
  .object({})
  .passthrough()
  .transform((raw) => {
    const obj = raw as Record<string, unknown>;
    const txns = Array.isArray(obj.transactions) ? (obj.transactions as Record<string, unknown>[]) : [];
    return {
      transactions: txns
        .map((t) => ({
          signedTransactionInfo:
            pickStringField(t, "signedTransactionInfo", "signed_transaction_info") ?? "",
        }))
        .filter((t) => t.signedTransactionInfo.length > 0),
      accountID: pickStringField(obj, "accountID", "account_id"),
      deviceID: pickStringField(obj, "deviceID", "device_id"),
      platform: pickStringField(obj, "platform"),
    };
  });

export function formatZodIssues(error: z.ZodError): string {
  return error.issues.map((issue) => issue.message).join("; ");
}
