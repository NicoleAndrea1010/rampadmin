const DB_NAME = "ramp-admin-offline";
const DB_VERSION = 2;
let syncPromise = null;
const MUTABLE_FIELDS = {
  properties: [
    ["unit_number", "Unit number", "text"],
    ["name", "Property name", "text"],
    ["location", "Location", "text"],
    ["landlord_id", "Landlord ID", "text"],
    ["monthly_rent", "Monthly rent", "number"],
    ["status", "Status", "select", ["Occupied", "Vacant", "Reserved", "Inactive"]],
  ],
  tenants: [
    ["name", "Full name", "text"],
    ["email", "Email", "email"],
    ["phone", "Phone", "tel"],
    ["unit_id", "Property ID", "text"],
    ["landlord_id", "Landlord ID", "text"],
    ["status", "Status", "select", ["Active", "Former"]],
    ["monthly_rent", "Monthly rent", "number"],
    ["lease_start", "Lease starts", "date"],
    ["lease_end", "Lease ends", "date"],
    ["balance", "Balance", "number"],
  ],
  landlords: [
    ["name", "Full name", "text"],
    ["company", "Company name", "text"],
    ["phone", "Phone", "tel"],
  ],
  superadmins: [["display_name", "Full name", "text"]],
};
const MAX_FIELD_LENGTHS = {
  unit_number: 100,
  name: 160,
  location: 240,
  landlord_id: 80,
  unit_id: 80,
  email: 254,
  phone: 40,
  company: 120,
  display_name: 100,
};

function openOfflineDb() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains("pending")) {
        db.createObjectStore("pending", { keyPath: "id" });
      }
      if (db.objectStoreNames.contains("records")) db.deleteObjectStore("records");
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function withStore(name, mode, action) {
  const db = await openOfflineDb();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(name, mode);
    const result = action(transaction.objectStore(name));
    transaction.oncomplete = () => {
      db.close();
      resolve(result?.result);
    };
    transaction.onerror = () => {
      db.close();
      reject(transaction.error);
    };
  });
}

function getPending(scope) {
  return withStore("pending", "readonly", (store) => store.getAll()).then(
    (items) => items
      .filter((item) => item.scope === scope)
      .sort((left, right) => left.createdAt.localeCompare(right.createdAt)),
  );
}

function savePending(item) {
  return withStore("pending", "readwrite", (store) => store.put(item));
}

function removePending(id) {
  return withStore("pending", "readwrite", (store) => store.delete(id));
}

function createHidden(form, name, value) {
  const input = document.createElement("input");
  input.type = "hidden";
  input.name = name;
  input.value = value ?? "";
  form.append(input);
}

function showMessage(message, kind = "info") {
  let stack = document.querySelector(".flash-stack");
  if (!stack) {
    stack = document.createElement("div");
    stack.className = "flash-stack";
    document.querySelector(".page-content")?.prepend(stack);
  }
  const notice = document.createElement("div");
  notice.className = `flash flash-${kind}`;
  notice.setAttribute("role", kind === "error" ? "alert" : "status");
  notice.textContent = message;
  window.rampFormUX.addDismissButton(notice);
  stack.replaceChildren(notice);
}

function showFormError(form, message) {
  window.rampFormUX.showFormError(form, message);
}

function prepareFormValidation(form) {
  window.rampFormUX.prepareFormValidation(form);
}

function setFormSubmitting(form, isSubmitting, submitter = null) {
  window.rampFormUX.setSubmitting(form, isSubmitting, submitter);
}

function formatLocalAuditTimes() {
  if (typeof Intl.RelativeTimeFormat !== "function") return;
  const relativeTime = new Intl.RelativeTimeFormat(undefined, { numeric: "auto" });
  const dateOnlyPattern = /^\d{4}-\d{2}-\d{2}$/;
  document.querySelectorAll("time[data-local-time][datetime]").forEach((time) => {
    const raw = time.dateTime;
    const isDateOnly = dateOnlyPattern.test(raw);
    const parsed = new Date(isDateOnly ? `${raw}T00:00:00` : raw);
    if (Number.isNaN(parsed.getTime())) return;
    const exactOptions = isDateOnly
      ? { dateStyle: "medium" }
      : { dateStyle: "medium", timeStyle: "medium" };
    const exact = new Intl.DateTimeFormat(undefined, exactOptions).format(parsed);
    time.title = `${exact} (local time)`;
    time.setAttribute("aria-label", exact);
    if (isDateOnly) {
      time.textContent = exact;
      return;
    }

    const secondsFromNow = (parsed.getTime() - Date.now()) / 1000;
    if (secondsFromNow > 60) {
      time.classList.add("audit-time-future");
      time.textContent = `Future · ${exact}`;
      time.setAttribute("aria-label", `Future timestamp; ${exact}`);
      return;
    }

    time.classList.remove("audit-time-future");
    let value = secondsFromNow;
    let unit = "second";
    for (const [threshold, nextUnit] of [
      [60, "minute"],
      [60, "hour"],
      [24, "day"],
      [7, "week"],
      [4.35, "month"],
      [12, "year"],
    ]) {
      if (Math.abs(value) < threshold) break;
      value /= threshold;
      unit = nextUnit;
    }
    time.textContent = relativeTime.format(Math.round(value), unit);
  });
}

async function responseErrorMessage(response) {
  const contentType = response.headers.get("Content-Type") || "";
  if (contentType.includes("application/json")) {
    try {
      const payload = await response.json();
      if (typeof payload.error === "string" && payload.error) return payload.error;
    } catch {
      return "The server returned an invalid error response.";
    }
  }
  return `The change was not saved (server error ${response.status}).`;
}

function recordTitle(section, record, creating) {
  if (creating) return `Add ${section === "properties" ? "property" : "tenant"}`;
  const name = record?.name || record?.display_name || record?.unit_number || record?.id;
  return `Edit ${name || section.slice(0, -1)}`;
}

function openRecordEditor(section, href, record = null) {
  const fields = MUTABLE_FIELDS[section];
  if (!fields) return;
  const pageScript = document.getElementById("offlinePageData");
  const pageData = pageScript ? JSON.parse(pageScript.textContent) : null;
  const dialog = document.createElement("dialog");
  dialog.className = "record-editor-dialog";
  const title = recordTitle(section, record, !record);
  const heading = document.createElement("h2");
  heading.textContent = title;
  const form = document.createElement("form");
  form.method = "post";
  form.action = href;
  form.dataset.offlineQueue = "true";
  form.dataset.offlineTitle = title;
  form.dataset.loadingLabel = "Saving…";
  form.dataset.confirm = record ? "Save changes to this record?" : "";
  const grid = document.createElement("div");
  grid.className = "form-grid";

  if (record && ["landlords", "superadmins"].includes(section)) {
    const emailField = document.createElement("div");
    emailField.className = "form-field";
    const label = document.createElement("span");
    label.textContent = "Email address";
    const value = document.createElement("strong");
    value.textContent = record.email || "";
    emailField.append(label, value);
    grid.append(emailField);
  }

  for (const [key, labelText, type, options] of fields) {
    const field = document.createElement("label");
    field.className = "form-field";
    const label = document.createElement("span");
    label.textContent = labelText;
    const value =
      key === "monthly_rent" && record
        ? record.monthly_rent ?? record.rent
        : key === "company" && record
          ? record.company ?? record.company_name
          : record?.[key];
    const relatedRows = key === "landlord_id"
      ? pageData?.landlords || []
      : key === "unit_id"
          ? pageData?.properties || []
          : [];
    let input;
    if (options) {
      input = document.createElement("select");
      input.name = key;
      const current = value === undefined || value === null
        ? section === "properties" ? "Vacant" : "Active"
        : String(value);
      if (!options.includes(current)) {
        const existing = document.createElement("option");
        existing.value = current;
        existing.textContent = `Current status: ${current}`;
        input.append(existing);
      }
      for (const optionValue of options) {
        const option = document.createElement("option");
        option.value = optionValue;
        option.textContent = optionValue;
        input.append(option);
      }
      input.value = current;
    } else if (["landlord_id", "unit_id"].includes(key)) {
      input = document.createElement("select");
      input.name = key;
      const empty = document.createElement("option");
      empty.value = "";
      empty.textContent = "Unassigned";
      input.append(empty);
      for (const related of relatedRows) {
          if (related.is_archived) continue;
          const option = document.createElement("option");
          option.value = String(key === "landlord_id" ? related.uid || related.id : related.id);
          option.textContent = key === "landlord_id"
            ? [related.name, related.company].filter(Boolean).join(" · ")
            : [related.unit_number || related.name || related.id, related.location].filter(Boolean).join(" · ");
          input.append(option);
      }
      if (value !== undefined && value !== null && ![...input.options].some((option) => option.value === String(value))) {
          const option = document.createElement("option");
          option.value = String(value);
          option.textContent = "Current relationship (not in loaded records)";
          input.append(option);
      }
      if (value !== undefined && value !== null) input.value = String(value);
    } else {
      input = document.createElement("input");
      input.type = type;
      input.name = key;
      input.maxLength = key === "name" && ["tenants", "landlords"].includes(section)
        ? 100
        : MAX_FIELD_LENGTHS[key] || 240;
      if (value !== undefined && value !== null) input.value = String(value);
      if (type === "date" && (!value || String(value) >= "2025-01-01")) {
        input.min = "2025-01-01";
      }
      if (type === "number") {
          input.min = key === "balance" ? "0" : "0.01";
          input.step = "0.01";
      }
    }
    if (["unit_number", "name", "status"].includes(key) && section === "properties") input.required = true;
    if (key === "name" && section === "tenants") input.required = true;
    if (key === "display_name") input.required = true;
    field.append(label, input);
    grid.append(field);
  }
  form.append(grid);
  if (pageData?.csrf) createHidden(form, "csrf_token", pageData.csrf);
  if (record?.updated_at) createHidden(form, "updated_at", record.updated_at);
  if (!record && ["properties", "tenants"].includes(section)) {
    createHidden(form, "record_id", crypto.randomUUID());
  }

  const actions = document.createElement("div");
  actions.className = "form-actions";
  const cancel = document.createElement("button");
  cancel.type = "button";
  cancel.className = "button button-secondary";
  cancel.textContent = "Cancel";
  cancel.addEventListener("click", () => dialog.close());
  const save = document.createElement("button");
  save.type = "submit";
  save.className = "button button-primary";
  save.textContent = record ? "Save changes" : "Create record";
  actions.append(cancel, save);
  form.append(actions);
  dialog.append(heading, form);
  document.body.append(dialog);
  prepareFormValidation(form);
  dialog.addEventListener("close", () => dialog.remove(), { once: true });
  dialog.showModal();
  form.querySelector("input:not([type=hidden])")?.focus();
}

function labelForField(name) {
  return {
    name: "Name",
    display_name: "Name",
    company: "Company",
    company_name: "Company",
    email: "Email",
    phone: "Phone",
    unit_number: "Unit",
    location: "Location",
    landlord_id: "Landlord",
    unit_id: "Property",
    monthly_rent: "Rent",
    status: "Status",
    lease_start: "Lease start",
    lease_end: "Lease end",
    balance: "Balance",
    approved: "Access",
  }[name] || name.replaceAll("_", " ");
}

function changeSummary(item) {
  const path = new URL(item.url, window.location.origin).pathname;
  const section = path.split("/")[1];
  const entity = { properties: "property", tenants: "tenant", landlords: "landlord", superadmins: "superadmin" }[section] || "record";
  const values = new URLSearchParams(item.body);
  const action = path.endsWith("/archive")
    ? "Archive"
    : path.endsWith("/transition")
      ? `${values.get("action") || "Update"}`
      : path.endsWith("/approval")
        ? values.get("approved") === "true" ? "Approve" : "Disable"
        : path.endsWith("/new")
          ? "Create"
          : "Update";
  const key = values.get("name") || values.get("display_name") || values.get("unit_number") || values.get("email");
  const changes = [];
  for (const [name, value] of values.entries()) {
    if (["csrf_token", "updated_at", "record_id", "action", "approved"].includes(name) || !value) continue;
    changes.push(`${labelForField(name)}: ${value}`);
    if (changes.length === 2) break;
  }
  return `${action} ${entity}${key ? ` · ${key}` : ""}${changes.length ? ` — ${changes.join(", ")}` : ""}`;
}

function setRowStatus(row, text) {
  const cell = row.querySelector('[data-field="status"]');
  if (!cell) return;
  const pill = document.createElement("span");
  pill.className = "status-pill status-pending-sync";
  pill.textContent = text;
  cell.replaceChildren(pill);
}

function updateVisibleRow(section, recordId, values, path) {
  const row = [...document.querySelectorAll("tr[data-record-id]")].find(
    (item) => item.dataset.recordId === recordId,
  );
  if (!row) return;
  const map = section === "properties"
    ? { name: values.get("name") || values.get("unit_number"), location: values.get("location"), rent: values.get("monthly_rent"), status: values.get("status") }
    : section === "tenants"
      ? { name: values.get("name"), email: values.get("email"), status: values.get("status"), balance: values.get("balance") }
      : section === "landlords"
        ? { name: values.get("name"), company: values.get("company"), phone: values.get("phone") }
        : { display_name: values.get("display_name") };
  for (const [key, value] of Object.entries(map)) {
    if (value === null) continue;
    const cell = row.querySelector(`[data-field="${key}"]`);
    if (cell) cell.textContent = value || "—";
  }
  if (path.endsWith("/archive")) setRowStatus(row, "Archived · pending");
  else if (values.has("status")) setRowStatus(row, `${values.get("status")} · pending`);
  else if (section === "superadmins" && values.has("approved")) setRowStatus(row, `${values.get("approved") === "true" ? "Active" : "Disabled"} · pending`);
  row.classList.add("row-pending-sync");
  row.querySelectorAll("a, button").forEach((control) => {
    if (path.endsWith("/archive")) {
      control.setAttribute("aria-disabled", "true");
      control.classList.add("pending-disabled");
      if (control instanceof HTMLAnchorElement) control.removeAttribute("href");
      if (control instanceof HTMLButtonElement) control.disabled = true;
    }
  });
  if (path.endsWith("/archive")) row.classList.add("row-pending-archive");
}

function addPendingRow(section, recordId, values) {
  const table = document.querySelector(".data-table tbody");
  const pageScript = document.getElementById("offlinePageData");
  if (!table || !pageScript) return;
  if ([...table.querySelectorAll("tr[data-record-id]")].some((row) => row.dataset.recordId === recordId)) return;
  const data = JSON.parse(pageScript.textContent);
  const columns = data.columns || [];
  const rowData = Object.fromEntries(values.entries());
  for (const key of ["csrf_token", "updated_at", "record_id", "action", "approved"]) delete rowData[key];
  rowData.id = recordId;
  if (section === "properties") {
    rowData.rent = rowData.monthly_rent;
    rowData.name = rowData.name || rowData.unit_number;
  } else if (section === "tenants") {
    rowData.property = rowData.unit_number || "—";
  }
  const recordForEdit = { ...rowData };
  rowData.status = `${rowData.status || "Pending"} · pending`;
  const row = document.createElement("tr");
  row.dataset.recordId = recordId;
  row.className = "row-pending-sync";
  for (const [key, label] of columns) {
    const cell = document.createElement("td");
    cell.dataset.field = key;
    cell.dataset.label = label;
    if (["rent", "monthly_rent", "amount", "balance"].includes(key)) {
      cell.dataset.numeric = "true";
    }
    cell.textContent = rowData[key] || "—";
    if (key === "status") {
      const pill = document.createElement("span");
      pill.className = "status-pill status-pending-sync";
      pill.textContent = rowData.status;
      cell.replaceChildren(pill);
    }
    row.append(cell);
  }
  const action = document.createElement("td");
  action.className = "row-actions";
  action.dataset.label = "Actions";
  const edit = document.createElement("a");
  edit.className = "table-action";
  edit.href = `/${section}/${encodeURIComponent(recordId)}/edit`;
  edit.textContent = "Edit";
  edit.dataset.offlineEdit = section;
  edit.dataset.record = JSON.stringify(recordForEdit);
  action.append(edit, document.createTextNode(" Pending sync"));
  row.append(action);
  table.prepend(row);
}

function updateConnectionState() {
  const notice = document.getElementById("connectionNotice") ||
    document.querySelector(".preview-notice");
  if (!notice) return;
  const cachedFallback = Boolean(document.querySelector('meta[name="ramp-cache-fallback"]'));
  if (!navigator.onLine || cachedFallback) {
    notice.classList.add("offline-notice");
    notice.textContent = cachedFallback
      ? "Cached copy · Supabase is unavailable"
      : "Offline · showing cached data";
  } else if (notice.id === "connectionNotice" && notice.classList.contains("offline-notice")) {
    notice.classList.remove("offline-notice");
    notice.textContent = "Network restored · reconnecting to Supabase";
  }
}

async function renderPending(scope) {
  const panel = document.getElementById("offlineQueue");
  const list = document.getElementById("offlineQueueItems");
  const title = document.getElementById("offlineQueueTitle");
  if (!panel || !list || !title) return;
  const items = await getPending(scope);
  panel.hidden = items.length === 0;
  title.textContent = `${items.length} unsynced ${items.length === 1 ? "change" : "changes"}`;
  list.replaceChildren();
  for (const item of items) {
    const li = document.createElement("li");
    const summary = document.createElement("span");
    summary.textContent = `${changeSummary(item)} · ${item.state === "conflict" ? "Needs review" : item.state === "error" ? "Sync paused" : "Waiting to sync"}`;
    li.append(summary);
    if (item.state === "conflict" || item.state === "error") {
      const review = document.createElement("a");
      review.className = "table-action";
      review.href = item.returnUrl;
      review.textContent = "Review";
      li.append(review);
    }
    const discard = document.createElement("button");
    discard.type = "button";
    discard.className = "table-action muted-action";
    discard.textContent = "Discard";
    discard.dataset.discardChange = item.id;
    li.append(discard);
    list.append(li);
  }
  const syncButton = document.getElementById("syncOfflineChanges");
  if (syncButton) syncButton.disabled = !navigator.onLine || items.some((item) => item.state === "conflict");
}

async function queueForm(form, scope) {
  if (scope === "preview") {
    showFormError(form, "Local preview changes cannot be queued for Supabase sync.");
    return;
  }
  const values = new URLSearchParams(new FormData(form));
  const changeId = crypto.randomUUID();
  const path = new URL(form.action, window.location.origin).pathname;
  const section = path.split("/")[1];
  const recordId = path.split("/")[2];
  const item = {
    id: changeId,
    changeId,
    scope,
    section,
    recordId: values.get("record_id") || recordId || "",
    url: form.action,
    method: "POST",
    body: values.toString(),
    title: form.dataset.offlineTitle || form.dataset.loadingLabel || "Record update",
    returnUrl: window.location.pathname + window.location.search,
    createdAt: new Date().toISOString(),
    state: "queued",
  };
  try {
    await savePending(item);
  } catch {
    showFormError(form, "This device could not save the pending change. Keep this page open and reconnect before retrying.");
    return;
  }
  if (path.endsWith("/new")) {
    addPendingRow(section, item.recordId, values);
  } else {
    updateVisibleRow(section, item.recordId, values, path);
  }
  form.closest("dialog")?.close();
  showMessage("Saved on this device. It will sync to Supabase when the connection returns.", "success");
  await renderPending(scope);
}

async function sendForm(form, scope, submitter = null) {
  const values = new URLSearchParams(new FormData(form));
  setFormSubmitting(form, true, submitter);
  form.setAttribute("aria-busy", "true");
  try {
    if (!navigator.onLine) throw new TypeError("Browser is offline");
    const response = await fetch(form.action, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
        "X-Ramp-Form-Request": "1",
      },
      body: values.toString(),
    });
    if (response.ok) {
      if (response.redirected && new URL(response.url).pathname === "/login") {
        showFormError(form, "Your session expired. Sign in again, then retry the change.");
        return;
      }
      window.location.assign(response.url || form.action);
      return;
    }
    if ([502, 503, 504].includes(response.status)) {
      await queueForm(form, scope);
      return;
    }
    showFormError(form, await responseErrorMessage(response));
  } catch (error) {
    if (error instanceof TypeError || !navigator.onLine) {
      await queueForm(form, scope);
    } else {
      showFormError(form, "The change could not be saved.");
    }
  } finally {
    if (form.isConnected) {
      form.removeAttribute("aria-busy");
      setFormSubmitting(form, false);
    }
  }
}

function syncPending(scope) {
  if (!navigator.onLine || scope === "preview") return Promise.resolve();
  if (syncPromise) return syncPromise;
  syncPromise = performSyncPending(scope).finally(() => {
    syncPromise = null;
  });
  return syncPromise;
}

async function performSyncPending(scope) {
  const items = await getPending(scope);
  for (const item of items) {
    if (item.state === "conflict") break;
    item.state = "syncing";
    await savePending(item);
    await renderPending(scope);
    try {
      const response = await fetch(item.url, {
        method: item.method,
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
          "X-Ramp-Offline-Replay": "1",
          "X-Ramp-Offline-Change": item.changeId,
        },
        body: item.body,
      });
      if (response.ok) {
        if (response.redirected || !response.headers.get("Content-Type")?.includes("application/json")) {
          item.state = "error";
          item.error = response.status;
          await savePending(item);
          showMessage("Sign in again before syncing offline changes.", "error");
          await renderPending(scope);
          break;
        }
        const result = await response.json();
        if (result.synced) {
          await removePending(item.id);
          continue;
        }
      }
      item.state = response.status === 409 || response.status === 400 ? "conflict" : "error";
      item.error = response.status;
      await savePending(item);
      const errorMessage = await responseErrorMessage(response);
      showMessage(errorMessage, "error");
      await renderPending(scope);
      break;
    } catch {
      item.state = "queued";
      await savePending(item);
      showMessage("Sync paused because the server could not be reached.", "error");
      break;
    }
    await renderPending(scope);
  }
  await renderPending(scope);
  const remaining = await getPending(scope);
  if (items.length && remaining.length === 0) {
    showMessage("All offline changes were synced to Supabase.", "success");
    window.setTimeout(() => window.location.reload(), 700);
  }
}

async function restorePendingRows(scope, section) {
  const items = await getPending(scope);
  for (const item of items) {
    const path = new URL(item.url, window.location.origin).pathname;
    const itemSection = path.split("/")[1];
    if (itemSection !== section) continue;
    const values = new URLSearchParams(item.body);
    if (path.endsWith("/new")) addPendingRow(section, item.recordId, values);
    else updateVisibleRow(section, item.recordId, values, path);
  }
}

async function clearLocalData(scope) {
  const db = await openOfflineDb();
  await new Promise((resolve, reject) => {
    const transaction = db.transaction("pending", "readwrite");
    const pending = transaction.objectStore("pending").getAll();
    pending.onsuccess = () => pending.result
      .filter((item) => item.scope === scope)
      .forEach((item) => transaction.objectStore("pending").delete(item.id));
    transaction.oncomplete = () => { db.close(); resolve(); };
    transaction.onerror = () => { db.close(); reject(transaction.error); };
  });
  navigator.serviceWorker?.controller?.postMessage({ type: "CLEAR_RAMP_CACHE" });
}

document.addEventListener("DOMContentLoaded", () => {
  formatLocalAuditTimes();
  const sidebar = document.getElementById("sidebar");
  const scrim = document.getElementById("mobileScrim");
  const menuToggle = document.getElementById("menuToggle");
  const pageLoading = document.getElementById("pageLoading");
  const scope = document.body.dataset.offlineScope || "preview";
  const pageScript = document.getElementById("offlinePageData");
  const pageData = pageScript ? JSON.parse(pageScript.textContent) : null;
  let loadingTimer;

  const showLoading = () => {
    window.clearTimeout(loadingTimer);
    loadingTimer = window.setTimeout(() => {
      if (pageLoading) pageLoading.hidden = false;
      document.querySelector("main")?.setAttribute("aria-busy", "true");
      document.body.classList.add("navigation-pending");
    }, 180);
  };

  const closeMenu = () => {
    sidebar?.classList.remove("sidebar-open");
    scrim?.classList.remove("scrim-visible");
  };

  menuToggle?.addEventListener("click", () => {
    sidebar?.classList.toggle("sidebar-open");
    scrim?.classList.toggle("scrim-visible");
  });
  scrim?.addEventListener("click", closeMenu);
  sidebar?.querySelectorAll(".nav-link").forEach((link) => {
    link.addEventListener("click", closeMenu);
  });

  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("/service-worker.js", { updateViaCache: "none" })
      .then((registration) => registration.update())
      .catch(() => {
        showMessage("Offline page caching could not start. Use HTTPS and reload to enable it.", "error");
      });
  }
  updateConnectionState();
  window.addEventListener("offline", updateConnectionState);
  window.addEventListener("online", async () => {
    updateConnectionState();
    syncPending(scope).catch(() =>
      showMessage("Offline changes could not be checked. Try again.", "error"),
    );
    if (document.querySelector('meta[name="ramp-cache-fallback"]')) {
      try {
        const response = await fetch(window.location.href, { cache: "no-store" });
        if (response.ok) window.location.reload();
      } catch {
        showMessage("The Supabase connection is still unavailable.", "error");
      }
    }
  });
  renderPending(scope).catch(() =>
    showMessage("This browser could not access its offline change queue.", "error"),
  );
  if (pageData) {
    restorePendingRows(scope, pageData.section).catch(() =>
      showMessage("Pending changes could not be restored on this page.", "error"),
    );
  }
  syncPending(scope).catch(() =>
    showMessage("Offline changes could not be checked. Try again.", "error"),
  );

  document.addEventListener("click", (event) => {
    if (!(event.target instanceof Element)) return;
    const discard = event.target.closest("[data-discard-change]");
    if (discard) {
      const confirmation = "Discard this unsynced change? It will be removed from this device and will not sync to Supabase.";
      if (!window.confirm(confirmation)) return;
      removePending(discard.dataset.discardChange)
        .then(() => renderPending(scope))
        .catch(() => showMessage("The pending change could not be discarded.", "error"));
      return;
    }
    const syncButton = event.target.closest("#syncOfflineChanges");
    if (syncButton) {
      syncPending(scope).catch(() =>
        showMessage("Offline changes could not be checked. Try again.", "error"),
      );
      return;
    }
    const editLink = event.target.closest("a[data-offline-edit]");
    const createLink = event.target.closest("a[data-offline-create]");
    if (editLink) {
      event.preventDefault();
      let record;
      try {
        record = JSON.parse(editLink.dataset.record || "{}");
      } catch {
        showMessage("This record could not be opened for editing.", "error");
        return;
      }
      openRecordEditor(editLink.dataset.offlineEdit, editLink.href, record);
    } else if (createLink) {
      event.preventDefault();
      openRecordEditor(createLink.dataset.offlineCreate, createLink.href);
    }
  });

  document.addEventListener("submit", (event) => {
    const form = event.target;
    if (!(form instanceof HTMLFormElement)) return;
    if (form.getAttribute("aria-busy") === "true") {
      event.preventDefault();
      return;
    }
    if (event.defaultPrevented) return;
    if (form.dataset.requiresOnline === "true" && !navigator.onLine) {
      event.preventDefault();
      showFormError(form, "Reconnect to the internet before submitting this change.");
      return;
    }
    if (form.dataset.confirm && !window.confirm(form.dataset.confirm)) {
      event.preventDefault();
      return;
    }
    setFormSubmitting(form, true, event.submitter);
    form.setAttribute("aria-busy", "true");
    showLoading();
  });

  document.addEventListener("submit", async (event) => {
    const form = event.target;
    if (!(form instanceof HTMLFormElement)) return;
    if (form.getAttribute("aria-busy") === "true") {
      event.preventDefault();
      return;
    }
    if (form.action.endsWith("/logout")) return;
    if (form.dataset.offlineQueue !== "true") return;
    if (form.dataset.confirm && !window.confirm(form.dataset.confirm)) {
      event.preventDefault();
      return;
    }
    event.preventDefault();
    await sendForm(form, scope, event.submitter);
  }, { capture: true });

  document.querySelectorAll('form[data-debounce-search="true"] input[type="search"]').forEach((input) => {
    let timer;
    input.addEventListener("input", (event) => {
      if (event.isComposing) return;
      window.clearTimeout(timer);
      timer = window.setTimeout(() => {
        input.form?.requestSubmit();
      }, 350);
    });
  });

  document.addEventListener("click", (event) => {
    if (
      event.defaultPrevented ||
      event.button !== 0 ||
      event.metaKey ||
      event.ctrlKey ||
      event.shiftKey ||
      event.altKey
    ) return;
    const target = event.target;
    const link = target instanceof Element ? target.closest("a[href]") : null;
    if (
      !link ||
      link.target ||
      link.hasAttribute("download") ||
      link.hasAttribute("data-offline-edit") ||
      link.hasAttribute("data-offline-create") ||
      link.href === window.location.href
    ) return;
    const destination = new URL(link.href, window.location.href);
    if (
      destination.origin !== window.location.origin ||
      destination.pathname.endsWith(".csv") ||
      (destination.pathname === window.location.pathname &&
        destination.search === window.location.search)
    ) return;
    showLoading();
  });

  document.querySelectorAll('form[action$="/logout"]').forEach((form) => {
    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      try {
        const pending = await getPending(scope);
        if (pending.length) {
          showMessage("Sync or discard pending changes before signing out.", "error");
          return;
        }
        await clearLocalData(scope);
        form.submit();
      } catch {
        showMessage("Local changes could not be checked or cleared. Sign-out was cancelled.", "error");
      }
    });
  });

});

window.addEventListener("pageshow", () => {
  document.getElementById("pageLoading")?.setAttribute("hidden", "");
  document.querySelector("main")?.removeAttribute("aria-busy");
  document.body.classList.remove("navigation-pending");
});
