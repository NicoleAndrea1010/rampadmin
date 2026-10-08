import {initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";
import {defineString} from "firebase-functions/params";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";

initializeApp();
const db = getFirestore();
const auth = getAuth();
const webApiKey = defineString("FIREBASE_WEB_API_KEY");

type Input = Record<string, unknown>;

async function enforceAdminRateLimit(uid: string) {
  const ref = db.collection("adminActionRateLimits").doc(uid);
  const now = Date.now();
  const windowMs = 60_000;
  const limit = 20;
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const savedWindow = snapshot.get("windowStartedAt");
    const windowStartedAt = savedWindow instanceof Timestamp ?
      savedWindow.toMillis() : 0;
    const currentCount = snapshot.get("count");
    const count = typeof currentCount === "number" ? currentCount : 0;
    if (now - windowStartedAt < windowMs && count >= limit) {
      throw new HttpsError(
        "resource-exhausted",
        "Too many administrator actions. Wait a minute and try again.",
      );
    }
    transaction.set(ref, {
      windowStartedAt: now - windowStartedAt >= windowMs ?
        Timestamp.fromMillis(now) : savedWindow,
      count: now - windowStartedAt >= windowMs ? 1 : count + 1,
    });
  });
}

async function requireAdmin(request: CallableRequest<Input>) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in is required.");
  const hasSuperAdminClaim = request.auth.token.role === "super_admin";
  const adminProfile = hasSuperAdminClaim ? null :
    await db.collection("adminProfiles").doc(request.auth.uid).get();
  if (!hasSuperAdminClaim && adminProfile?.data()?.status !== "active") {
    throw new HttpsError("permission-denied", "Super-admin access is required.");
  }
  await enforceAdminRateLimit(request.auth.uid);
  return {
    uid: request.auth.uid,
    email: typeof request.auth.token.email === "string" ? request.auth.token.email : "",
  };
}

function text(data: Input, key: string, required = true): string {
  const value = typeof data[key] === "string" ? data[key].trim() : "";
  if (required && !value) throw new HttpsError("invalid-argument", `${key} is required.`);
  return value;
}

function email(data: Input): string {
  const value = text(data, "email").toLowerCase();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(value)) {
    throw new HttpsError("invalid-argument", "A valid email is required.");
  }
  return value;
}

function validateLandlordDetails(displayName: string, companyName: string, phone: string) {
  if (displayName.length < 2 || displayName.length > 100) {
    throw new HttpsError("invalid-argument", "Display name must be 2 to 100 characters.");
  }
  if (companyName.length < 2 || companyName.length > 120) {
    throw new HttpsError("invalid-argument", "Company name must be 2 to 120 characters.");
  }
  const digits = phone.replace(/\D/g, "");
  if (phone && (digits.length < 7 || digits.length > 15 || !/^[+()\d .-]+$/.test(phone))) {
    throw new HttpsError("invalid-argument", "Phone number is invalid.");
  }
}

function uid(data: Input): string {
  return text(data, "uid");
}

async function audit(
  actor: {uid: string; email: string}, action: string, targetId: string,
  description: string, reason?: string,
) {
  await db.collection("adminAuditLogs").add({
    actorId: actor.uid,
    actorEmail: actor.email,
    action,
    targetType: "landlord",
    targetId,
    description,
    ...(reason ? {reason} : {}),
    timestamp: FieldValue.serverTimestamp(),
  });
}

export const createLandlord = onCall(async (request) => {
  const actor = await requireAdmin(request);
  const normalizedEmail = email(request.data);
  const displayName = text(request.data, "displayName");
  const companyName = text(request.data, "companyName");
  const phone = text(request.data, "phone", false);
  validateLandlordDetails(displayName, companyName, phone);
  let user;
  try {
    user = await auth.createUser({email: normalizedEmail, displayName, disabled: true});
  } catch (error: unknown) {
    if ((error as {code?: string}).code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", "An account with this email already exists.");
    }
    throw error;
  }
  try {
    await auth.setCustomUserClaims(user.uid, {role: "landlord"});
    const now = FieldValue.serverTimestamp();
    const batch = db.batch();
    batch.set(db.collection("landlords").doc(user.uid), {
      email: normalizedEmail, displayName, companyName, phone,
      status: "invited", unitCount: 0,
      schemaVersion: 2,
      createdAt: now, updatedAt: now,
      createdBy: actor.uid, updatedBy: actor.uid,
    });
    batch.set(db.collection("users").doc(user.uid), {
      id: user.uid, uid: user.uid, email: normalizedEmail, displayName,
      role: "landlord", landlordId: user.uid, isApproved: false,
      mustChangePassword: false, createdAt: now, lastLoginAt: now,
    });
    await batch.commit();
    await audit(actor, "LANDLORD_CREATED", user.uid, "Landlord account created");
    return {uid: user.uid};
  } catch (error) {
    await db.collection("landlords").doc(user.uid).delete();
    await db.collection("users").doc(user.uid).delete();
    await auth.deleteUser(user.uid);
    throw error;
  }
});

export const updateLandlord = onCall(async (request) => {
  const actor = await requireAdmin(request);
  const targetId = uid(request.data);
  const ref = db.collection("landlords").doc(targetId);
  const before = await ref.get();
  if (!before.exists) throw new HttpsError("not-found", "Landlord not found.");
  const displayName = text(request.data, "displayName");
  const companyName = text(request.data, "companyName");
  const phone = text(request.data, "phone", false);
  validateLandlordDetails(displayName, companyName, phone);
  await auth.updateUser(targetId, {displayName});
  await ref.update({displayName, companyName, phone, updatedBy: actor.uid, updatedAt: FieldValue.serverTimestamp()});
  await db.collection("users").doc(targetId).set({
    uid: targetId, id: targetId, displayName, role: "landlord",
    landlordId: targetId, updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await audit(actor, "LANDLORD_UPDATED", targetId, "Landlord account updated");
  return {uid: targetId};
});

export const activateLandlord = onCall(async (request) => {
  const actor = await requireAdmin(request);
  const targetId = uid(request.data);
  await auth.updateUser(targetId, {disabled: false});
  await db.collection("landlords").doc(targetId).update({status: "active", updatedBy: actor.uid, updatedAt: FieldValue.serverTimestamp()});
  await db.collection("users").doc(targetId).set({
    uid: targetId, id: targetId, role: "landlord",
    landlordId: targetId, isApproved: true,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await audit(actor, "LANDLORD_ACTIVATED", targetId, "Landlord account activated");
  return {uid: targetId};
});

export const suspendLandlord = onCall(async (request) => {
  const actor = await requireAdmin(request);
  const targetId = uid(request.data);
  const reason = text(request.data, "reason");
  await auth.updateUser(targetId, {disabled: true});
  await auth.revokeRefreshTokens(targetId);
  await db.collection("landlords").doc(targetId).update({
    status: "suspended", suspensionReason: reason, suspendedAt: FieldValue.serverTimestamp(),
    updatedBy: actor.uid, updatedAt: FieldValue.serverTimestamp(),
  });
  await db.collection("users").doc(targetId).set({
    uid: targetId, id: targetId, role: "landlord",
    landlordId: targetId, isApproved: false,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await audit(actor, "LANDLORD_SUSPENDED", targetId, "Landlord account suspended", reason);
  return {uid: targetId};
});

export const reactivateLandlord = onCall(async (request) => {
  const actor = await requireAdmin(request);
  const targetId = uid(request.data);
  await auth.updateUser(targetId, {disabled: false});
  await db.collection("landlords").doc(targetId).update({
    status: "active", suspensionReason: FieldValue.delete(), suspendedAt: FieldValue.delete(),
    updatedBy: actor.uid, updatedAt: FieldValue.serverTimestamp(),
  });
  await db.collection("users").doc(targetId).set({
    uid: targetId, id: targetId, role: "landlord",
    landlordId: targetId, isApproved: true,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await audit(actor, "LANDLORD_REACTIVATED", targetId, "Landlord account reactivated");
  return {uid: targetId};
});

export const archiveLandlord = onCall(async (request) => {
  const actor = await requireAdmin(request);
  const targetId = uid(request.data);
  const ref = db.collection("landlords").doc(targetId);
  const snapshot = await ref.get();
  if (!snapshot.exists) throw new HttpsError("not-found", "Landlord not found.");
  if (snapshot.get("status") !== "suspended") {
    throw new HttpsError("failed-precondition", "Suspend the landlord before archiving.");
  }
  await auth.updateUser(targetId, {disabled: true});
  await auth.revokeRefreshTokens(targetId);
  await ref.update({status: "archived", archivedAt: FieldValue.serverTimestamp(), updatedBy: actor.uid, updatedAt: FieldValue.serverTimestamp()});
  await db.collection("users").doc(targetId).set({
    uid: targetId, id: targetId, role: "landlord",
    landlordId: targetId, isApproved: false,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await audit(actor, "LANDLORD_ARCHIVED", targetId, "Landlord account archived");
  return {uid: targetId};
});

export const sendLandlordPasswordReset = onCall(async (request) => {
  const actor = await requireAdmin(request);
  const targetId = uid(request.data);
  const user = await auth.getUser(targetId);
  if (!user.email) throw new HttpsError("failed-precondition", "The landlord has no email address.");
  const response = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=${webApiKey.value()}`, {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({requestType: "PASSWORD_RESET", email: user.email}),
  });
  if (!response.ok) throw new HttpsError("internal", "Password reset could not be sent.");
  await audit(actor, "PASSWORD_RESET_SENT", targetId, "Password reset email sent");
  return {sent: true};
});
