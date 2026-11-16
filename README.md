# RAMP Admin web app

A Python/Flask super-admin website for RAMP. Supabase is the authoritative source for live accounts and business records. The website authenticates approved `super_admin` accounts and reads records under the signed-in administrator's Supabase Row Level Security policies.

If Supabase is not configured, the app opens an empty local preview; it does not invent example accounts or business records.

## Run locally

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python app.py
```

Open http://127.0.0.1:5000. On Nicole's current machine, the app reads the Flutter project's `.env.local.json` automatically. On another development machine, either set `RAMP_SUPABASE_URL` and `RAMP_SUPABASE_PUBLISHABLE_KEY`, or set `RAMP_SUPABASE_CONFIG` to a JSON file containing `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`. Production mode ignores the local Flutter config and requires the Supabase environment variables.

Landlords, properties/units, tenants, and superadmin profiles can be managed. Landlords and superadmins are invited through the existing `invite-admin-account` Edge Function; tenants can be invited after their tenant record exists. Landlords, properties, and tenants can be created, updated, or archived; archiving preserves their history instead of permanently deleting rows. Archived records and activity logs are read-only. Superadmin access can be approved or disabled, but accounts are not hard-deleted; the app prevents disabling the signed-in admin or the last approved superadmin. Writes go through Flask using the signed-in access token and remain subject to Supabase RLS. Validation and Supabase permission errors are shown to the administrator; this app does not bypass database policies.

## Admin control center

The dashboard links to unit, inquiry, payment, maintenance, and lease follow-up
lists. Payment summaries use stored status values and the app's existing
payment-date fallback; overdue is never inferred from a missing or ambiguous
date. Record lists support search, status filters, sorting, CSV export, and
50-row page navigation, and a global search across the visible people and
operational lists. The current Supabase loader retrieves data in
500-row batches and the list filters are applied by the Flask app; large
deployments should move these filters and pagination to PostgREST before the
tables grow substantially.

Details use explicit field allowlists and the signed-in administrator's RLS
session. Sensitive tenant health and emergency-contact information is separated
from ordinary list views. Inquiry decisions use the existing
`review_tenant_inquiry` RPC. Expense records can be created and edited, are
attributed to the signed-in administrator, and support category and month
filtering and totals. Category filters are also preserved in sorting,
pagination, and CSV export. Announcements can be created, edited, and archived without hard
deletion. Existing settings records can be updated, but the app does not create
settings rows. Notifications, events, public listings, tenant-document
metadata, utility-rate history, and RFID access history are read-only; audit
history is also read-only. Audit history uses human-readable action labels and
allowlisted actor/target metadata rather than rendering raw details; timestamps
show relative local time with the exact local time on hover, and future
timestamps are flagged with their absolute local time. Soft-linked records are
linked only when a matching record can be found.
RFID history can be filtered by access result and uses the same local-time
display. Utility rates show PHP per unit (water per m³, electricity per kWh);
the Active badge is derived from the latest effective history entry on or
before the server's current date and is not cross-checked against billing
settings.

Payment proof, tenant document, and photo links are not exposed because this
web project has no verified private Storage URL flow. RFID card identifiers are
not selected or displayed. Door controls remain disabled until the deployed
function contract and superadmin authorization can be verified. No Supabase
schema changes are made by this web app.

Tenant payment receipts use the private `tenant-payment-receipts` Storage bucket.
The admin app requests a five-minute signed URL only after fetching the payment
under the signed-in administrator's Supabase session. Receipt decisions are
submitted to the `review_tenant_payment_receipt` RPC, which locks the payment,
updates only a pending receipt, and writes a minimal audit event. Apply
`supabase/migrations/20261117060000_review_tenant_payment_receipts.sql` to a
reviewed staging project before enabling this workflow; it is not applied to
Supabase automatically.

Only use the Supabase project URL and **publishable** key. Never put a service-role/secret key in this app, hosting variables, or browser code. The Flask server sends the publishable key and the signed-in administrator's Supabase access token to Supabase; access/refresh tokens stay in SQLite on the server and are not exposed to browser JavaScript or the session cookie. The browser does not need the Supabase URL or API key. A publishable key is not a database password; RLS and the signed-in user's permissions remain essential.

## Offline behavior

On a trusted browser device, the service worker caches authenticated pages the admin has visited for up to eight hours. Supported record edits and archive/access changes made while offline are kept in that browser's IndexedDB queue and posted to Supabase after connectivity returns. The UI shows queued, syncing, and conflict states; an edit is not presented as synced until Supabase accepts it. Sync checks record versions and leaves conflicting changes queued for review rather than overwriting newer server data. Email invitations require a live connection. Sign-out is blocked while changes are pending; after the queue is empty, the app clears that browser's cached pages and local queue.

The interface icons, favicon, and installable app icon manifest are served locally
and included in the service-worker shell cache, so icons do not depend on a
third-party icon CDN.

Offline editing is limited to the supported landlord, unit, tenant, and
superadmin-profile workflows. Expense and announcement forms, settings changes,
and invitations require an active connection; new records are not queued while
offline.

## Terms, help, and guardrails

The Settings area includes an internal Terms & Conditions draft for review; this
admin-only site does not collect tenant lease acceptance. Tenant lease terms and
acceptance belong in the tenant app, with its own owner-approved lease details
and privacy notice.

The question-mark help menu gives administrators a short guide to navigation,
search, filters, editing, archiving, and offline sync. New and changed date
entries and expense-month filters are limited to January 1, 2025 onward.
Sign-in and password-reset requests are limited to five attempts per email
address per 15-minute window using the server SQLite database. This complements
but does not replace hosting-provider and Supabase Auth rate limits.

Audit, utility-rate, and RFID access histories are grouped under System
navigation. List pages retain their data and routes while placing secondary row
actions in an accessible menu. Displayed timestamps omit timezone abbreviations.

## Door status and control

The unit page is monitoring-only and does not send unlock/close requests or read
`public.door_commands` directly. A verified request/status contract for the
existing `door-device-command` and `rfid-access-event` functions is not present
in this web project, so the app does not call them or infer physical door state.
Do not apply or rely on the older custom door RPC migration from this app. Door
controls can be enabled only after confirming the deployed function contract and
its superadmin authorization behavior; no Supabase schema changes are made by
this web app.

Browser offline storage is device-local web storage (Cache Storage and IndexedDB), not SQLite. It is not encrypted by this app, so use only trusted, access-controlled devices and HTTPS. Offline pages are available only after the device has loaded them online; offline login is not supported. Use normal online sign-in to establish the admin session before disconnecting.

The SQLite path defaults to `instance/ramp_admin.sqlite3`. Set `RAMP_WEB_DATABASE` to a path on persistent storage when deploying, for example `/var/lib/ramp/ramp_admin.sqlite3`. The directory must be writable by the app and the file should only be accessible to the app account because it contains Supabase session tokens and offline-sync idempotency markers. Back it up and do not commit it. Server SQLite does not replace Supabase or serve as the browser's offline database.

## Hosting checklist

This is a server-rendered Flask app, not a static site. Deploy it to a Python
web-service host that supports a persistent writable disk and the supplied
`Procfile` (Gunicorn). Configure the variables shown in `.env.example` in the
host's environment/secret settings; do not upload a real `.env` file or paste
keys into source control. Generate a unique `RAMP_WEB_SECRET_KEY` with at least
32 random characters. Production startup fails if the secret or Supabase
environment configuration is missing or invalid. `RAMP_ENV=production`
automatically enables secure session cookies; keep HTTPS enabled.

Set `RAMP_WEB_DATABASE` to a private path on the host's persistent disk. The
Procfile runs one Gunicorn worker because server sessions and offline-sync
idempotency use SQLite; do not add replicas or workers without moving that state
to a shared persistent database. A host with ephemeral storage can lose sessions
and sync markers on restart and is not suitable without a persistent volume.
Configure Supabase Auth's site URL and redirect allowlist for the deployed
HTTPS domain, and verify production RLS policies before inviting administrators.
Keep the Supabase URL and publishable key as server environment variables; never
use a `service_role` or secret key.

The local `python app.py` command runs Flask's development server on
`127.0.0.1`; do not use it as the production start command. HTTPS is required
for browser service-worker offline caching. Hosting-provider settings vary, so
check that the provider supports Python/Gunicorn, persistent storage, environment
secrets, and HTTPS before choosing it.

The supplied `Procfile` forces production mode, so a Procfile-based deployment
fails at startup if the production secret or Supabase configuration is missing.
Keep local `.env` files and SQLite databases out of manual uploads as well as
source control; `.gitignore` only protects Git-based deployments.

## Tests

```powershell
python -m unittest discover -s tests
```
