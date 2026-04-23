/**
 * BillingStore — the full relay state machine.
 *
 * Responsibilities, mirrored from `AIChat Relay/RelayBillingStore.swift`:
 *   · bootstrap / pairing / offline activation flows
 *   · grant scheduling (earliest-expiring first) + compaction
 *   · pre-reservation + post-settlement credit accounting
 *   · StoreKit JWS ingestion (decode only; verification is a v1.2 hook)
 *   · operator admin actions (modify / grant / revoke / pause)
 *
 * State is a single JSON blob written atomically. The `WriteQueue` serialises
 * concurrent mutations. Reads return deep-cloned snapshots so consumers never
 * mutate shared state.
 */

import path from "node:path";
import { config } from "@/lib/config";
import {
  newActivationCode,
  newClientKey,
  newPairingToken,
  uuid,
} from "@/lib/ids";
import { DEFAULT_PLANS, DEFAULT_POLICY } from "@/lib/billing/defaults";
import { decodeJwsPayload } from "@/lib/billing/jws";
import { creditsForUsage, maxOutputTokensForModel, rateForModel } from "@/lib/billing/metering";
import type {
  Account,
  AccessSource,
  AccountStatusResponse,
  ActivationCode,
  Device,
  DevicePlatform,
  Grant,
  Key,
  MeteringPolicy,
  PairingToken,
  Plan,
  Transaction,
  TrialClaim,
  UsageRecord,
} from "@/lib/billing/types";
import { readJsonFile, writeJsonFileAtomic, WriteQueue } from "./persistence";

const FILE = () => path.join(config.dataDir, "billing.json");
const USAGE_CAP = 500;
const PAIRING_TTL_MS = 10 * 60 * 1000;

interface State {
  accounts: Record<string, Account>;
  devices: Record<string, Device>;
  keys: Record<string, Key>;
  grants: Record<string, Grant>;
  usage: UsageRecord[];
  transactions: Record<string, Transaction>;
  trialClaims: Record<string, TrialClaim>;
  pairingTokens: Record<string, PairingToken>;
  activationCodes: Record<string, ActivationCode>;
  policy: MeteringPolicy;
  plans: Plan[];
}

function emptyState(): State {
  return {
    accounts: {},
    devices: {},
    keys: {},
    grants: {},
    usage: [],
    transactions: {},
    trialClaims: {},
    pairingTokens: {},
    activationCodes: {},
    policy: DEFAULT_POLICY,
    plans: DEFAULT_PLANS,
  };
}

function clone<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

function iso(d: Date = new Date()): string {
  return d.toISOString();
}

class BillingStore {
  private state: State = emptyState();
  private loaded = false;
  private queue = new WriteQueue();

  async ensureLoaded(): Promise<void> {
    if (this.loaded) return;
    this.state = await readJsonFile(FILE(), emptyState());
    // Back-fill any missing fields introduced in newer versions.
    this.state.policy = { ...DEFAULT_POLICY, ...this.state.policy };
    this.state.plans = this.state.plans.length ? this.state.plans : DEFAULT_PLANS;
    this.state.activationCodes ??= {};
    this.compact();
    this.loaded = true;
  }

  private compact(now = new Date()) {
    // expire pairing tokens
    for (const [t, p] of Object.entries(this.state.pairingTokens)) {
      if (new Date(p.expiresAt).getTime() < now.getTime()) delete this.state.pairingTokens[t];
    }
    // zero expired grants; mark activation codes expired
    for (const g of Object.values(this.state.grants)) {
      if (g.expiresAt && new Date(g.expiresAt).getTime() < now.getTime()) g.remainingCredits = 0;
    }
    for (const code of Object.values(this.state.activationCodes)) {
      if (code.state === "unused" && code.expiresAt && new Date(code.expiresAt).getTime() < now.getTime()) {
        code.state = "expired";
      }
    }
    // trim usage
    if (this.state.usage.length > USAGE_CAP) {
      this.state.usage = this.state.usage.slice(-USAGE_CAP);
    }
    // recompute account balances
    for (const acc of Object.values(this.state.accounts)) {
      acc.creditBalance = acc.grantIDs
        .map((id) => this.state.grants[id])
        .filter((g): g is Grant => !!g && g.remainingCredits > 0)
        .reduce((sum, g) => sum + g.remainingCredits, 0);
      const nextExpiry = acc.grantIDs
        .map((id) => this.state.grants[id])
        .filter((g): g is Grant => !!g && g.remainingCredits > 0 && !!g.expiresAt)
        .map((g) => g.expiresAt!)
        .sort()[0];
      acc.creditExpiresAt = nextExpiry;
    }
  }

  private async persist() {
    await writeJsonFileAtomic(FILE(), this.state);
  }

  private write<T>(mutator: () => T): Promise<T> {
    return this.queue.run(async () => {
      await this.ensureLoaded();
      const result = mutator();
      await this.persist();
      return result;
    });
  }

  async snapshot(): Promise<State> {
    await this.ensureLoaded();
    return clone(this.state);
  }

  // ---- lookups -----------------------------------------------------------

  async findKeyByValue(value: string): Promise<Key | undefined> {
    await this.ensureLoaded();
    const direct = Object.values(this.state.keys).find((k) => k.keyValue === value);
    return direct ? clone(direct) : undefined;
  }

  async findDevice(deviceID: string): Promise<Device | undefined> {
    await this.ensureLoaded();
    const d = this.state.devices[deviceID];
    return d ? clone(d) : undefined;
  }

  async getAccountStatus(key: Key): Promise<AccountStatusResponse | null> {
    await this.ensureLoaded();
    const acc = this.state.accounts[key.accountID];
    if (!acc) return null;
    const device = key.deviceID ? this.state.devices[key.deviceID] : undefined;
    const grants = acc.grantIDs
      .map((id) => this.state.grants[id])
      .filter(Boolean) as Grant[];
    const recentUsage = this.state.usage.filter((u) => u.accountID === acc.accountID).slice(-50);
    return clone({ account: acc, device, key, grants, recentUsage });
  }

  // ---- trial / bootstrap -------------------------------------------------

  async bootstrapTrial(params: {
    deviceID: string;
    platform: DevicePlatform;
    alias?: string;
  }): Promise<{ account: Account; device: Device; key: Key; grant: Grant }> {
    return this.write(() => {
      const claim = this.state.trialClaims[params.deviceID];
      if (claim && this.state.accounts[claim.accountID]) {
        const account = this.state.accounts[claim.accountID];
        const device = this.state.devices[params.deviceID];
        const key = Object.values(this.state.keys).find(
          (k) => k.accountID === account.accountID && k.deviceID === params.deviceID,
        )!;
        const grant = Object.values(this.state.grants).find(
          (g) => g.accountID === account.accountID && g.source === "trial",
        )!;
        return clone({ account, device, key, grant });
      }

      const now = iso();
      const account: Account = {
        accountID: uuid(),
        state: "active",
        source: "trial",
        creditBalance: this.state.policy.trialCredits,
        deviceIDs: [params.deviceID],
        keyIDs: [],
        grantIDs: [],
        createdAt: now,
      };
      const device: Device = {
        deviceID: params.deviceID,
        accountID: account.accountID,
        platform: params.platform,
        alias: params.alias,
        lastSeenAt: now,
      };
      const key: Key = {
        keyID: uuid(),
        accountID: account.accountID,
        deviceID: params.deviceID,
        keyValue: newClientKey(),
        state: "active",
        source: "trial",
        issuedAt: now,
      };
      device.keyID = key.keyID;
      account.keyIDs.push(key.keyID);
      const expires = new Date();
      expires.setDate(expires.getDate() + this.state.policy.trialDurationDays);
      const grant: Grant = {
        grantID: uuid(),
        accountID: account.accountID,
        source: "trial",
        totalCredits: this.state.policy.trialCredits,
        remainingCredits: this.state.policy.trialCredits,
        grantedAt: now,
        expiresAt: expires.toISOString(),
      };
      account.grantIDs.push(grant.grantID);
      account.creditExpiresAt = grant.expiresAt;

      this.state.accounts[account.accountID] = account;
      this.state.devices[device.deviceID] = device;
      this.state.keys[key.keyID] = key;
      this.state.grants[grant.grantID] = grant;
      this.state.trialClaims[device.deviceID] = {
        deviceID: device.deviceID,
        accountID: account.accountID,
        claimedAt: now,
      };
      return clone({ account, device, key, grant });
    });
  }

  // ---- StoreKit ----------------------------------------------------------

  async preparePurchase(params: { accountID?: string }): Promise<{ appAccountToken: string }> {
    return this.write(() => {
      const token = uuid();
      if (params.accountID && this.state.accounts[params.accountID]) {
        this.state.accounts[params.accountID].appAccountToken = token;
      }
      return { appAccountToken: token };
    });
  }

  async submitPurchase(params: {
    signedTransactionInfo: string;
    accountID?: string;
    deviceID?: string;
    platform?: DevicePlatform;
  }): Promise<{ account: Account; key: Key; grant: Grant }> {
    return this.write(() => {
      const decoded = decodeJwsPayload(params.signedTransactionInfo);
      if (!decoded.transactionID || !decoded.productID) {
        throw new Error("Malformed StoreKit transaction payload.");
      }
      const now = iso();
      const plan = this.state.plans.find((p) => p.productID === decoded.productID);
      const accountID =
        params.accountID ??
        (decoded.originalTransactionID &&
          Object.values(this.state.accounts).find(
            (a) => a.originalTransactionID === decoded.originalTransactionID,
          )?.accountID) ??
        uuid();

      let account = this.state.accounts[accountID];
      if (!account) {
        account = {
          accountID,
          state: "active",
          source: "subscription",
          creditBalance: 0,
          deviceIDs: [],
          keyIDs: [],
          grantIDs: [],
          createdAt: now,
          planID: plan?.id,
          originalTransactionID: decoded.originalTransactionID,
          appAccountToken: decoded.appAccountToken,
        };
        this.state.accounts[accountID] = account;
      } else {
        account.source = "subscription";
        account.state = decoded.revocationDate ? "paused" : "active";
        account.planID = plan?.id ?? account.planID;
        account.originalTransactionID = decoded.originalTransactionID ?? account.originalTransactionID;
      }

      // Bind device + issue key if provided.
      let key: Key | undefined;
      if (params.deviceID) {
        const existing = this.state.devices[params.deviceID];
        if (existing && existing.accountID !== account.accountID) {
          // Detach from old account.
          const old = this.state.accounts[existing.accountID];
          if (old) old.deviceIDs = old.deviceIDs.filter((d) => d !== params.deviceID);
        }
        this.state.devices[params.deviceID] = {
          deviceID: params.deviceID,
          accountID: account.accountID,
          platform: params.platform ?? "unknown",
          lastSeenAt: now,
        };
        if (!account.deviceIDs.includes(params.deviceID)) account.deviceIDs.push(params.deviceID);

        key = Object.values(this.state.keys).find(
          (k) => k.accountID === account.accountID && k.deviceID === params.deviceID,
        );
        if (!key) {
          key = {
            keyID: uuid(),
            accountID: account.accountID,
            deviceID: params.deviceID,
            keyValue: newClientKey(),
            state: "active",
            source: "subscription",
            issuedAt: now,
          };
          this.state.keys[key.keyID] = key;
          account.keyIDs.push(key.keyID);
          this.state.devices[params.deviceID].keyID = key.keyID;
        }
      }

      // Record transaction.
      this.state.transactions[decoded.transactionID] = {
        transactionID: decoded.transactionID,
        originalTransactionID: decoded.originalTransactionID ?? decoded.transactionID,
        productID: decoded.productID,
        environment: decoded.environment ?? "Production",
        signedTransactionInfo: params.signedTransactionInfo,
        purchaseDate: decoded.purchaseDate,
        expirationDate: decoded.expirationDate,
        revokedDate: decoded.revocationDate,
        processedAt: now,
      };

      // Grant credits — cap expiry at expirationDate + 1 month to match macOS.
      const credits = plan?.monthlyCredits ?? 20_000;
      const expiresAt = decoded.expirationDate
        ? new Date(new Date(decoded.expirationDate).getTime() + 30 * 86400 * 1000).toISOString()
        : undefined;
      const grantID = uuid();
      const grant: Grant = {
        grantID,
        accountID: account.accountID,
        source: "subscription",
        totalCredits: credits,
        remainingCredits: credits,
        grantedAt: now,
        expiresAt,
        sourceTransactionID: decoded.transactionID,
      };
      this.state.grants[grantID] = grant;
      account.grantIDs.push(grantID);

      this.compact();
      return clone({ account, key: key ?? ({} as Key), grant });
    });
  }

  async restorePurchases(params: {
    transactions: { signedTransactionInfo: string }[];
    accountID?: string;
    deviceID?: string;
  }): Promise<{ processed: number }> {
    let processed = 0;
    for (const t of params.transactions) {
      try {
        await this.submitPurchase({ ...params, signedTransactionInfo: t.signedTransactionInfo });
        processed += 1;
      } catch {
        // Restore is idempotent & best-effort — swallow individual failures.
      }
    }
    return { processed };
  }

  // ---- pairing -----------------------------------------------------------

  async issuePairingToken(params: {
    accountID: string;
    deviceID: string;
  }): Promise<PairingToken> {
    return this.write(() => {
      const token: PairingToken = {
        token: newPairingToken(),
        accountID: params.accountID,
        issuedBy: params.deviceID,
        expiresAt: new Date(Date.now() + PAIRING_TTL_MS).toISOString(),
      };
      this.state.pairingTokens[token.token] = token;
      return clone(token);
    });
  }

  async joinPaired(params: {
    pairingToken: string;
    deviceID: string;
    platform: DevicePlatform;
    deviceAlias?: string;
  }): Promise<{ account: Account; device: Device; key: Key }> {
    return this.write(() => {
      const token = this.state.pairingTokens[params.pairingToken];
      if (!token || new Date(token.expiresAt).getTime() < Date.now()) {
        throw new Error("Pairing token expired or not found.");
      }
      const account = this.state.accounts[token.accountID];
      if (!account) throw new Error("Paired account no longer exists.");
      if (account.deviceIDs.length >= this.state.policy.maxBoundDevices) {
        throw new Error("Device bind cap reached.");
      }
      const now = iso();
      const device: Device = {
        deviceID: params.deviceID,
        accountID: account.accountID,
        platform: params.platform,
        alias: params.deviceAlias,
        lastSeenAt: now,
      };
      this.state.devices[device.deviceID] = device;
      if (!account.deviceIDs.includes(device.deviceID)) account.deviceIDs.push(device.deviceID);
      const key: Key = {
        keyID: uuid(),
        accountID: account.accountID,
        deviceID: device.deviceID,
        keyValue: newClientKey(),
        state: "active",
        source: account.source,
        issuedAt: now,
      };
      this.state.keys[key.keyID] = key;
      account.keyIDs.push(key.keyID);
      device.keyID = key.keyID;
      token.consumedBy = device.deviceID;
      delete this.state.pairingTokens[token.token];
      return clone({ account, device, key });
    });
  }

  // ---- offline -----------------------------------------------------------

  async exchangeOffline(params: {
    activationCode: string;
    deviceID: string;
    platform: DevicePlatform;
    fingerprint?: string;
  }): Promise<{ account: Account; device: Device; key: Key; grant: Grant }> {
    return this.write(() => {
      const code = this.state.activationCodes[params.activationCode];
      if (!code || code.state !== "unused") throw new Error("Activation code invalid.");
      if (code.fingerprint && code.fingerprint !== params.fingerprint) {
        throw new Error("Activation fingerprint mismatch.");
      }
      const now = iso();
      const account: Account = {
        accountID: uuid(),
        state: "active",
        source: "offlineManual",
        creditBalance: 0,
        deviceIDs: [params.deviceID],
        keyIDs: [],
        grantIDs: [],
        createdAt: now,
        planID: code.plan,
      };
      const device: Device = {
        deviceID: params.deviceID,
        accountID: account.accountID,
        platform: params.platform,
        lastSeenAt: now,
      };
      const key: Key = {
        keyID: uuid(),
        accountID: account.accountID,
        deviceID: device.deviceID,
        keyValue: newClientKey(),
        state: "active",
        source: "offlineManual",
        issuedAt: now,
      };
      device.keyID = key.keyID;
      account.keyIDs.push(key.keyID);
      const grant: Grant = {
        grantID: uuid(),
        accountID: account.accountID,
        source: "offlineManual",
        totalCredits: code.credits,
        remainingCredits: code.credits,
        grantedAt: now,
        expiresAt: code.expiresAt,
        note: code.note,
      };
      account.grantIDs.push(grant.grantID);

      code.state = "redeemed";
      code.redeemedBy = { accountID: account.accountID, deviceID: device.deviceID, redeemedAt: now };

      this.state.accounts[account.accountID] = account;
      this.state.devices[device.deviceID] = device;
      this.state.keys[key.keyID] = key;
      this.state.grants[grant.grantID] = grant;
      this.compact();
      return clone({ account, device, key, grant });
    });
  }

  // ---- credit accounting -------------------------------------------------

  async reserveCredits(params: {
    key: Key;
    endpoint: string;
    modelID?: string;
    estimatedInputTokens: number;
    audioInput: boolean;
  }): Promise<UsageRecord> {
    return this.write(() => {
      const account = this.state.accounts[params.key.accountID];
      if (!account) throw new Error("Account not found.");
      const rate = rateForModel(this.state.policy, params.modelID);
      const reserved = creditsForUsage(this.state.policy, rate, {
        inputTokens: params.estimatedInputTokens,
        outputTokens: maxOutputTokensForModel(params.modelID),
        searchCount: 0,
        audioInput: params.audioInput,
      });
      if (account.creditBalance < reserved) {
        throw Object.assign(new Error("Insufficient credits."), { statusCode: 402 });
      }
      this.debitGrants(account, reserved);
      const record: UsageRecord = {
        requestID: uuid(),
        accountID: account.accountID,
        deviceID: params.key.deviceID,
        keyID: params.key.keyID,
        endpoint: params.endpoint,
        modelID: params.modelID,
        inputTokens: 0,
        outputTokens: 0,
        searchCount: 0,
        reservedCredits: reserved,
        settledCredits: 0,
        createdAt: iso(),
      };
      this.state.usage.push(record);
      this.compact();
      return clone(record);
    });
  }

  async settleCredits(params: {
    requestID: string;
    inputTokens: number;
    outputTokens: number;
    searchCount: number;
    audioInput: boolean;
    modelID?: string;
  }): Promise<UsageRecord> {
    return this.write(() => {
      const record = this.state.usage.find((r) => r.requestID === params.requestID);
      if (!record) throw new Error("Usage record missing.");
      const account = record.accountID ? this.state.accounts[record.accountID] : undefined;
      if (!account) return clone(record);
      const rate = rateForModel(this.state.policy, params.modelID ?? record.modelID);
      const actual = creditsForUsage(this.state.policy, rate, {
        inputTokens: params.inputTokens,
        outputTokens: params.outputTokens,
        searchCount: params.searchCount,
        audioInput: params.audioInput,
      });
      const delta = actual - record.reservedCredits;
      if (delta > 0) {
        this.debitGrants(account, delta);
      } else if (delta < 0) {
        this.refundGrants(account, -delta);
      }
      record.inputTokens = params.inputTokens;
      record.outputTokens = params.outputTokens;
      record.searchCount = params.searchCount;
      record.settledCredits = actual;
      account.lastUsageAt = iso();
      this.compact();
      return clone(record);
    });
  }

  async rollbackReservation(requestID: string): Promise<void> {
    return this.write(() => {
      const record = this.state.usage.find((r) => r.requestID === requestID);
      if (!record || record.settledCredits > 0) return;
      const account = record.accountID ? this.state.accounts[record.accountID] : undefined;
      if (account) this.refundGrants(account, record.reservedCredits);
      record.settledCredits = 0;
      record.reservedCredits = 0;
    });
  }

  private debitGrants(account: Account, credits: number) {
    let remaining = credits;
    const grants = account.grantIDs
      .map((id) => this.state.grants[id])
      .filter((g): g is Grant => !!g && g.remainingCredits > 0)
      .sort((a, b) => (a.expiresAt ?? "9999").localeCompare(b.expiresAt ?? "9999"));
    for (const g of grants) {
      if (remaining <= 0) break;
      const take = Math.min(g.remainingCredits, remaining);
      g.remainingCredits -= take;
      remaining -= take;
    }
  }

  private refundGrants(account: Account, credits: number) {
    let remaining = credits;
    const grants = account.grantIDs
      .map((id) => this.state.grants[id])
      .filter((g): g is Grant => !!g)
      .sort((a, b) => (b.expiresAt ?? "9999").localeCompare(a.expiresAt ?? "9999"));
    for (const g of grants) {
      if (remaining <= 0) break;
      const capacity = g.totalCredits - g.remainingCredits;
      const give = Math.min(capacity, remaining);
      g.remainingCredits += give;
      remaining -= give;
    }
  }

  // ---- operator admin actions -------------------------------------------

  async listAll() {
    await this.ensureLoaded();
    return clone({
      accounts: Object.values(this.state.accounts),
      devices: Object.values(this.state.devices),
      keys: Object.values(this.state.keys),
      grants: Object.values(this.state.grants),
      usage: this.state.usage,
      activationCodes: Object.values(this.state.activationCodes),
      pairingTokens: Object.values(this.state.pairingTokens),
      policy: this.state.policy,
      plans: this.state.plans,
    });
  }

  async modifyAccount(accountID: string, patch: Partial<Account>): Promise<Account> {
    return this.write(() => {
      const acc = this.state.accounts[accountID];
      if (!acc) throw new Error("Account not found.");
      Object.assign(acc, {
        displayName: patch.displayName ?? acc.displayName,
        adminNote: patch.adminNote ?? acc.adminNote,
        state: patch.state ?? acc.state,
        planID: patch.planID ?? acc.planID,
      });
      return clone(acc);
    });
  }

  async modifyDevice(deviceID: string, patch: Partial<Device>): Promise<Device> {
    return this.write(() => {
      const d = this.state.devices[deviceID];
      if (!d) throw new Error("Device not found.");
      Object.assign(d, { alias: patch.alias ?? d.alias, note: patch.note ?? d.note });
      return clone(d);
    });
  }

  async modifyKey(keyID: string, patch: Partial<Key>): Promise<Key> {
    return this.write(() => {
      const k = this.state.keys[keyID];
      if (!k) throw new Error("Key not found.");
      Object.assign(k, { state: patch.state ?? k.state, note: patch.note ?? k.note });
      return clone(k);
    });
  }

  async modifyGrant(grantID: string, patch: Partial<Grant>): Promise<Grant> {
    return this.write(() => {
      const g = this.state.grants[grantID];
      if (!g) throw new Error("Grant not found.");
      if (typeof patch.remainingCredits === "number") g.remainingCredits = patch.remainingCredits;
      if (patch.note !== undefined) g.note = patch.note;
      if (patch.expiresAt !== undefined) g.expiresAt = patch.expiresAt;
      this.compact();
      return clone(g);
    });
  }

  async grantCredits(params: {
    accountID: string;
    credits: number;
    source: AccessSource;
    expiresAt?: string;
    note?: string;
  }): Promise<Grant> {
    return this.write(() => {
      const acc = this.state.accounts[params.accountID];
      if (!acc) throw new Error("Account not found.");
      const g: Grant = {
        grantID: uuid(),
        accountID: acc.accountID,
        source: params.source,
        totalCredits: params.credits,
        remainingCredits: params.credits,
        grantedAt: iso(),
        expiresAt: params.expiresAt,
        note: params.note,
      };
      this.state.grants[g.grantID] = g;
      acc.grantIDs.push(g.grantID);
      this.compact();
      return clone(g);
    });
  }

  async updatePolicy(policy: MeteringPolicy, plans: Plan[]): Promise<void> {
    await this.write(() => {
      this.state.policy = policy;
      this.state.plans = plans;
    });
  }

  async createActivationCodes(params: {
    count: number;
    plan?: string;
    credits: number;
    expiresAt?: string;
    allowedModels?: string[];
    note?: string;
  }): Promise<ActivationCode[]> {
    return this.write(() => {
      const created: ActivationCode[] = [];
      const now = iso();
      for (let i = 0; i < params.count; i++) {
        const code: ActivationCode = {
          code: newActivationCode(),
          plan: params.plan,
          credits: params.credits,
          expiresAt: params.expiresAt,
          allowedModels: params.allowedModels,
          note: params.note,
          createdAt: now,
          state: "unused",
        };
        this.state.activationCodes[code.code] = code;
        created.push(code);
      }
      return clone(created);
    });
  }

  async revokeActivationCode(code: string): Promise<void> {
    await this.write(() => {
      const c = this.state.activationCodes[code];
      if (c && c.state === "unused") c.state = "revoked";
    });
  }
}

// Module-scoped singleton. Next.js dev hot-reloads can instantiate twice; guard
// against that with a global cache.
declare global {
  // eslint-disable-next-line no-var
  var __billingStore: BillingStore | undefined;
}

export function billingStore(): BillingStore {
  if (!globalThis.__billingStore) globalThis.__billingStore = new BillingStore();
  return globalThis.__billingStore;
}
