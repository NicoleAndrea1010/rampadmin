from __future__ import annotations

import csv
import hashlib
import hmac
import io
import json
import math
import os
import re
import secrets
import sqlite3
import time
from contextlib import contextmanager
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any, Iterator
from uuid import UUID, uuid4

from flask import (
    Flask,
    abort,
    flash,
    g,
    has_request_context,
    jsonify,
    make_response,
    redirect,
    render_template,
    request,
    session,
    url_for,
)
from openpyxl import Workbook
from openpyxl.styles import Font
from werkzeug.exceptions import HTTPException

import supabase_backend


ROOT = Path(__file__).resolve().parent
MIN_ENTRY_DATE = date(2025, 1, 1)
AUTH_RATE_LIMIT_WINDOW_SECONDS = 15 * 60
AUTH_RATE_LIMIT_MAX_ATTEMPTS = 5
UNIT_PHOTO_MAX_FILES = 5
UNIT_PHOTO_MAX_FILE_BYTES = 5 * 1024 * 1024
UNIT_PHOTO_MAX_TOTAL_BYTES = 20 * 1024 * 1024


def _database_path() -> Path:
    configured = os.environ.get("RAMP_WEB_DATABASE", "").strip()
    if configured:
        return Path(configured).expanduser().resolve()
    return ROOT / "instance" / "ramp_admin.sqlite3"


DATABASE = _database_path()
RECORDS_PAGE_SIZE = 50


def _valid_email_address(value: str) -> bool:
    value = value.strip()
    if len(value) > 254 or value.count("@") != 1 or any(char.isspace() for char in value):
        return False
    local, domain = value.rsplit("@", 1)
    if (
        not local
        or len(local) > 64
        or local.startswith(".")
        or local.endswith(".")
        or ".." in local
        or re.fullmatch(r"[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+", local) is None
    ):
        return False
    labels = domain.split(".")
    return (
        len(labels) >= 2
        and all(
            len(label) <= 63
            and re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?", label)
            is not None
            for label in labels[:-1]
        )
        and len(labels[-1]) >= 2
        and re.fullmatch(
            r"[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?",
            labels[-1],
        ) is not None
        and any(char.isalpha() for char in labels[-1])
    )


_DISPOSABLE_EMAIL_DOMAINS = {
    "10minutemail.com",
    "mailinator.com",
    "tempmail.com",
}


def _valid_contact_email(value: str) -> bool:
    if not _valid_email_address(value):
        return False
    domain = value.strip().rsplit("@", 1)[1].casefold()
    return not any(
        domain == blocked or domain.endswith(f".{blocked}")
        for blocked in _DISPOSABLE_EMAIL_DOMAINS
    )


def _normalize_ph_mobile(value: str) -> str | None:
    normalized = re.sub(r"[\s().-]", "", value)
    if not normalized:
        return ""
    if re.fullmatch(r"09\d{9}|\+639\d{9}", normalized) is None:
        return None
    subscriber = normalized[2:] if normalized.startswith("09") else normalized[4:]
    if len(set(subscriber)) == 1 or subscriber in {
        "012345678",
        "123456789",
        "987654321",
        "876543210",
    }:
        return None
    return normalized


def _normalized_text(value: str, *, uppercase: bool = False) -> str:
    normalized = " ".join(value.split())
    return normalized.upper() if uppercase else normalized


def _valid_person_name(value: str) -> bool:
    return (
        sum(char.isalpha() for char in value) >= 2
        and all(char.isalpha() or char in " .'-" for char in value)
    )


app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 26 * 1024 * 1024
_production = os.environ.get("RAMP_ENV", "").strip().casefold() == "production"
_configured_secret = os.environ.get("RAMP_WEB_SECRET_KEY", "").strip()
if _production and len(_configured_secret) < 32:
    raise RuntimeError(
        "Production requires RAMP_WEB_SECRET_KEY to be set to at least 32 characters."
    )
if _production:
    try:
        supabase_backend.settings()
    except supabase_backend.SupabaseConfigurationError as error:
        raise RuntimeError(
            "Production requires valid Supabase environment configuration."
        ) from error
app.config["SECRET_KEY"] = _configured_secret or secrets.token_hex(32)
app.config.update(
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Lax",
    SESSION_COOKIE_SECURE=_production or os.environ.get("RAMP_COOKIE_SECURE") == "1",
    PERMANENT_SESSION_LIFETIME=timedelta(hours=8),
)

SECTIONS: dict[str, dict[str, Any]] = {
    "landlords": {
        "title": "Landlords",
        "description": "Landlord profiles and access.",
        "table": "landlords",
        "columns": [
            ("name", "Landlord"),
            ("company", "Company"),
            ("email", "Email"),
            ("phone", "Phone"),
            ("units", "Properties"),
            ("status", "Status"),
        ],
    },
    "superadmins": {
        "title": "Superadmins",
        "description": "Administrator accounts and access.",
        "table": "users",
        "columns": [
            ("display_name", "Name"),
            ("email", "Email"),
            ("role", "Role"),
            ("status", "Access"),
        ],
    },
    "properties": {
        "title": "Units",
        "description": "Availability, rent, and occupancy.",
        "table": "properties",
        "columns": [
            ("unit_number", "Unit"),
            ("name", "Property"),
            ("location", "Location"),
            ("property_type", "Type"),
            ("landlord", "Landlord"),
            ("tenant", "Tenant"),
            ("rent", "Monthly rent"),
            ("status", "Status"),
        ],
    },
    "tenants": {
        "title": "Tenants",
        "description": "Tenant profiles and lease details.",
        "table": "tenants",
        "columns": [
            ("name", "Tenant"),
            ("email", "Email"),
            ("phone", "Phone"),
            ("property", "Property"),
            ("lease_start", "Lease starts"),
            ("lease_end", "Lease ends"),
            ("lease_status", "Lease status"),
            ("monthly_rent", "Monthly rent"),
            ("balance", "Balance"),
            ("status", "Status"),
        ],
    },
    "payments": {
        "title": "Payments",
        "description": "Rent and payment status.",
        "table": "payments",
        "columns": [
            ("reference", "Reference"),
            ("tenant", "Tenant"),
            ("property", "Property"),
            ("month", "Month"),
            ("amount", "Amount"),
            ("method", "Method"),
            ("status", "Status"),
            ("paid_on", "Date"),
        ],
    },
    "maintenance": {
        "title": "Maintenance",
        "description": "Repair requests and status.",
        "table": "maintenance",
        "columns": [
            ("title", "Request"),
            ("property", "Property"),
            ("tenant", "Tenant"),
            ("priority", "Priority"),
            ("status", "Stage"),
            ("assigned_to_name", "Assigned to"),
            ("sla_due_date", "SLA due"),
            ("created", "Created"),
        ],
    },
    "inquiries": {
        "title": "Tenant inquiries",
        "description": "Prospective tenants and property questions.",
        "table": "inquiries",
        "columns": [
            ("sender", "From"),
            ("email", "Email"),
            ("phone", "Phone"),
            ("property", "Property"),
            ("message", "Inquiry"),
            ("received", "Received"),
            ("status", "Status"),
        ],
    },
    "expenses": {
        "title": "Expenses",
        "description": "Operating costs by period, category, and unit.",
        "table": "expenses",
        "columns": [
            ("title", "Expense"),
            ("category", "Category"),
            ("amount", "Amount"),
            ("date", "Date"),
            ("unit", "Unit"),
            ("recorded_by", "Recorded by"),
        ],
    },
    "public-listings": {
        "title": "Public listings",
        "description": "",
        "table": "public_listings",
        "columns": [
            ("title", "Listing"),
            ("unit_number", "Unit"),
            ("location", "Location"),
            ("property_type", "Type"),
            ("rent", "Rent"),
            ("updated_at", "Updated"),
        ],
    },
    "documents": {
        "title": "Tenant documents",
        "description": "",
        "table": "tenant_documents",
        "columns": [
            ("tenant", "Tenant"),
            ("title", "Document"),
            ("type", "Type"),
            ("file_name", "File"),
            ("file_size", "Size"),
            ("uploaded_at", "Uploaded"),
        ],
    },
    "announcements": {
        "title": "Announcements",
        "description": "Published and archived messages.",
        "table": "announcements",
        "columns": [
            ("title", "Announcement"),
            ("category", "Category"),
            ("author", "Author"),
            ("timestamp", "Published"),
            ("importance", "Important"),
            ("status", "Status"),
        ],
    },
    "notifications": {
        "title": "Notifications",
        "description": "",
        "table": "notifications",
        "columns": [
            ("title", "Notification"),
            ("type", "Type"),
            ("status", "State"),
            ("timestamp", "Date"),
            ("entity_type", "Related type"),
            ("action", "Action"),
        ],
    },
    "events": {
        "title": "Events / calendar",
        "description": "",
        "table": "events",
        "columns": [
            ("title", "Event"),
            ("date", "Date"),
            ("type", "Type"),
            ("priority", "Priority"),
            ("status", "State"),
            ("location", "Location"),
        ],
    },
    "rfid-access": {
        "title": "RFID access history",
        "description": "Read-only access events. Card identifiers are intentionally excluded.",
        "table": "rfid_access_logs",
        "columns": [
            ("created", "Time"),
            ("device", "Device"),
            ("unit", "Unit"),
            ("tenant", "Tenant"),
            ("action", "Action"),
            ("access_status", "Result"),
        ],
    },
    "utility-history": {
        "title": "Utility rate history",
        "description": "Read-only history of utility rate changes.",
        "table": "utility_rate_logs",
        "columns": [
            ("utility", "Utility"),
            ("status", "Rate status"),
            ("previous_rate", "Previous rate (₱/unit)"),
            ("new_rate", "New rate (₱/unit)"),
            ("rate_unit", "Rate unit"),
            ("effective_at", "Effective"),
            ("note", "Note"),
        ],
    },
    "settings": {
        "title": "Settings",
        "description": "Review and update the existing global settings records.",
        "table": "settings",
        "columns": [
            ("default_due_day", "Due day"),
            ("default_late_fee", "Default late fee"),
            ("water_rate", "Water rate"),
            ("electricity_rate", "Electricity rate"),
            ("auto_late_fee_enabled", "Auto late fee"),
            ("auto_backup_enabled", "Auto backup"),
            ("updated_at", "Updated"),
        ],
    },
    "activity": {
        "title": "Audit history",
        "description": "Review recorded administrative activity. History is read-only.",
        "table": "activity",
        "columns": [
            ("summary", "Activity"),
            ("occurred", "When"),
        ],
    },
}

NAV_ITEMS = [
    ("Overview", "Dashboard", "dashboard", "dashboard"),
    ("Portfolio", "Units", "building", "properties"),
    ("Portfolio", "Public listings", "listing", "public-listings"),
    ("People", "Landlords", "users", "landlords"),
    ("People", "Tenants", "user", "tenants"),
    ("People", "Accounts & access", "shield", "superadmins"),
    ("Operations", "Payments", "card", "payments"),
    ("Operations", "Maintenance", "wrench", "maintenance"),
    ("Operations", "Tenant inquiries", "message", "inquiries"),
    ("Operations", "Expenses", "receipt", "expenses"),
    ("Operations", "Documents", "file", "documents"),
    ("Operations", "Announcements", "megaphone", "announcements"),
    ("Operations", "Notifications", "bell", "notifications"),
    ("Operations", "Events / calendar", "calendar", "events"),
    ("System", "RFID access history", "shield", "rfid-access"),
    ("System", "Audit history", "history", "activity"),
    ("System", "Utility rate history", "chart", "utility-history"),
    ("System", "Settings", "settings", "settings"),
]

ENTITY_TABLES = {
    "properties": "units",
    "tenants": "tenants",
    "expenses": "expenses",
    "announcements": "announcements",
}

ENTITY_FIELDS = {
    "properties": (
        "id,landlord_id,unit_number,name,title,location,rent,monthly_rent,status,"
        "is_archived,tenant_id,tenant_name,image_url,images,updated_at"
    ),
    "tenants": (
        "id,name,email,phone,unit_id,unit_number,landlord_id,"
        "monthly_rent,lease_start,lease_end,due_date,balance,status,is_archived,updated_at"
    ),
    "expenses": (
        "id,title,category,amount,date,unit_id,unit_number,recorded_by,notes,"
        "created_at,updated_at"
    ),
    "announcements": (
        "id,title,message,timestamp,author,is_important,category,is_archived"
    ),
}

DETAIL_TABLES = {
    "landlords": "landlords",
    "properties": "units",
    "tenants": "tenants",
    "payments": "payments",
    "maintenance": "maintenance_tickets",
    "inquiries": "tenant_inquiries",
    "expenses": "expenses",
    "public-listings": "public_listings",
    "documents": "tenant_documents",
    "announcements": "announcements",
    "notifications": "notifications",
    "events": "events",
    "rfid-access": "rfid_access_logs",
    "utility-history": "utility_rate_logs",
    "settings": "settings",
    "activity": "audit_logs",
    "superadmins": "users",
}

DETAIL_FIELDS = {
    "landlords": (
        "id,uid,name,company_name,email,phone,status,created_at,updated_at"
    ),
    "properties": (
        "id,landlord_id,unit_number,name,title,floor,location,rent,monthly_rent,"
        "status,description,area_sqm,bedrooms,bathrooms,amenities,inclusions,"
        "tenant_id,tenant_name,current_tenancy_id,due_date,is_archived,is_published,"
        "details_completed,vacant_days,property_type,furnishing_status,security_deposit,"
        "advance_rent_months,minimum_lease_months,rent_due_day,late_fee,"
        "water_rate_override,electricity_rate_override,image_url,images,updated_at"
    ),
    "tenants": (
        "id,landlord_id,name,email,phone,contact_number,address,unit_id,unit_number,"
        "monthly_rent,lease_start,lease_end,due_date,balance,status,is_archived,"
        "current_tenancy_id,security_deposit_held,utility_deposit_held,"
        "emergency_contact_name,emergency_contact_phone,emergency_contact_relation,"
        "co_occupants,vehicle_plate,vehicle_model,parking_slot,pet_details,lease_status,"
        "notify_email,notify_sms,notify_push,health_status,updated_at"
    ),
    "payments": (
        "id,landlord_id,month,amount,method,payment_method,date,payment_date,status,"
        "unit_id,reference_number,base_rent,water_bill,electric_bill,late_fee,"
        "other_charge,tenant_name,unit_number,tenant_id,tenancy_id,remarks,"
        "decline_reason,transaction_type,ticket_id,proof_image_url,created_at"
    ),
    "maintenance": (
        "id,landlord_id,unit_id,unit_number,tenant_id,tenant_name,title,description,"
        "category,priority,status,assigned_to,assigned_to_name,vendor_id,estimated_cost,"
        "actual_cost,vendor_cost,date,created_at,sla_due_date,rating,rating_feedback,"
        "responsible_party,payment_required,payment_status,status_history,tenancy_id,"
        "affected_areas,issue_started_at,visit_scheduled_at,visit_time_window,"
        "replacement_items,repair_scheduled_at,repair_time_window,repairer,"
        "completion_summary,updated_at,repairer_phone,is_tenant_chargeable,labor_cost,"
        "materials_cost,vendor_category,tenant_feedback"
    ),
    "inquiries": (
        "id,created_at,updated_at,full_name,email,phone,preferred_unit_id,message,"
        "status,assigned_unit_id,tenant_id,reviewed_by,reviewed_at,internal_note"
    ),
    "expenses": (
        "id,title,category,amount,date,unit_id,unit_number,recorded_by,notes,"
        "created_at,updated_at"
    ),
    "public-listings": (
        "id,title,name,unit_number,location,rent,monthly_rent,description,area,"
        "area_sqm,bedrooms,bathrooms,amenities,inclusions,property_type,"
        "furnishing_status,security_deposit,advance_rent_months,"
        "minimum_lease_months,updated_at"
    ),
    "documents": (
        "id,tenant_id,tenant_name,title,type,file_name,file_size,uploaded_at"
    ),
    "announcements": (
        "id,title,message,timestamp,author,is_important,category,is_archived"
    ),
    "notifications": (
        "id,title,message,timestamp,is_read,is_archived,type,entity_type,entity_id,action"
    ),
    "events": (
        "id,title,date,type,tenant_id,unit_id,ticket_id,unit_number,description,"
        "is_completed,priority,time_window,location,created_at,updated_at"
    ),
    "rfid-access": (
        "id,device_id,tenant_id,unit_id,action,access_status,created_at,event_id"
    ),
    "utility-history": (
        "id,utility,previous_rate,new_rate,effective_at,note"
    ),
    "settings": (
        "id,default_late_fee,default_due_day,auto_late_fee_enabled,"
        "auto_backup_enabled,dark_mode,landlord_name,landlord_role,landlord_contact,"
        "water_rate,electricity_rate,updated_at"
    ),
    "activity": "id,landlord_id,action,details,timestamp",
    "superadmins": (
        "id,uid,email,display_name,role,is_approved,must_change_password,created_at,"
        "last_login_at,updated_at"
    ),
}

DETAIL_GROUPS = {
    "landlords": [
        ("Profile", (("Name", "name"), ("Company", "company_name"), ("Email", "email"), ("Phone", "phone"))),
        ("Account", (("Status", "status"), ("Created", "created_at"), ("Updated", "updated_at"))),
    ],
    "properties": [
        ("Unit overview", (
            ("Unit number", "unit_number"), ("Name", "name"), ("Title", "title"),
            ("Floor", "floor"), ("Location", "location"), ("Property type", "property_type"),
            ("Furnishing", "furnishing_status"), ("Area", "area_sqm"),
            ("Bedrooms", "bedrooms"), ("Bathrooms", "bathrooms"),
            ("Description", "description"), ("Amenities", "amenities"),
            ("Inclusions", "inclusions"),
        )),
        ("Availability", (
            ("Status", "status"), ("Archived", "is_archived"),
            ("Published", "is_published"), ("Details completed", "details_completed"),
            ("Vacant days", "vacant_days"),
        )),
        ("Rent and lease", (
            ("Rent", "rent"), ("Monthly rent", "monthly_rent"),
            ("Security deposit", "security_deposit"), ("Advance rent months", "advance_rent_months"),
            ("Minimum lease months", "minimum_lease_months"), ("Rent due day", "rent_due_day"),
            ("Late fee", "late_fee"), ("Due date", "due_date"),
        )),
        ("Occupancy and utilities", (
            ("Tenant", "tenant_name"), ("Tenant ID", "tenant_id"),
            ("Current tenancy ID", "current_tenancy_id"),
            ("Water rate override", "water_rate_override"),
            ("Electricity rate override", "electricity_rate_override"),
        )),
    ],
    "tenants": [
        ("Profile", (
            ("Name", "name"), ("Email", "email"), ("Phone", "phone"),
            ("Contact number", "contact_number"), ("Address", "address"),
        )),
        ("Tenancy", (
            ("Unit number", "unit_number"), ("Unit ID", "unit_id"),
            ("Monthly rent", "monthly_rent"), ("Lease starts", "lease_start"),
            ("Lease ends", "lease_end"), ("Lease status", "lease_status"),
            ("Tenant status", "status"), ("Due date", "due_date"),
            ("Current tenancy ID", "current_tenancy_id"), ("Balance", "balance"),
        )),
        ("Deposits and household", (
            ("Security deposit held", "security_deposit_held"),
            ("Utility deposit held", "utility_deposit_held"),
            ("Co-occupants", "co_occupants"), ("Vehicle plate", "vehicle_plate"),
            ("Vehicle model", "vehicle_model"), ("Parking slot", "parking_slot"),
            ("Pet details", "pet_details"),
        )),
        ("Notifications and access", (
            ("Email notifications", "notify_email"), ("SMS notifications", "notify_sms"),
            ("Push notifications", "notify_push"),
        )),
        ("Private details", (
            ("Emergency contact", "emergency_contact_name"),
            ("Emergency contact phone", "emergency_contact_phone"),
            ("Emergency contact relation", "emergency_contact_relation"),
            ("Health status", "health_status"),
        )),
    ],
    "payments": [
        ("Payment", (
            ("Reference", "reference_number"), ("Status", "status"),
            ("Month", "month"), ("Date", "payment_date"), ("Recorded date", "date"),
            ("Amount", "amount"), ("Method", "payment_method"),
            ("Transaction type", "transaction_type"), ("Remarks", "remarks"),
            ("Decline reason", "decline_reason"),
        )),
        ("Breakdown", (
            ("Base rent", "base_rent"), ("Water bill", "water_bill"),
            ("Electric bill", "electric_bill"), ("Late fee", "late_fee"),
            ("Other charge", "other_charge"),
        )),
    ],
    "maintenance": [
        ("Request", (
            ("Title", "title"), ("Description", "description"),
            ("Category", "category"), ("Affected areas", "affected_areas"),
            ("Priority", "priority"), ("Status", "status"),
            ("Created", "created_at"), ("Issue started", "issue_started_at"),
            ("SLA due", "sla_due_date"),
        )),
        ("Assignment and schedule", (
            ("Responsible party", "responsible_party"), ("Assigned to", "assigned_to_name"),
            ("Visit scheduled", "visit_scheduled_at"), ("Visit time window", "visit_time_window"),
            ("Repair scheduled", "repair_scheduled_at"), ("Repair time window", "repair_time_window"),
            ("Repairer", "repairer"),
        )),
        ("Costs and completion", (
            ("Estimated cost", "estimated_cost"), ("Actual cost", "actual_cost"),
            ("Vendor cost", "vendor_cost"), ("Labor cost", "labor_cost"),
            ("Materials cost", "materials_cost"), ("Replacement items", "replacement_items"),
            ("Completion summary", "completion_summary"), ("Rating", "rating"),
            ("Feedback", "tenant_feedback"),
        )),
    ],
    "inquiries": [
        ("Applicant", (
            ("Name", "full_name"), ("Email", "email"), ("Phone", "phone"),
            ("Message", "message"), ("Created", "created_at"), ("Updated", "updated_at"),
        )),
        ("Review", (
            ("Status", "status"), ("Preferred unit ID", "preferred_unit_id"),
            ("Assigned unit ID", "assigned_unit_id"), ("Tenant ID", "tenant_id"),
            ("Internal note", "internal_note"), ("Reviewed by", "reviewed_by"),
            ("Reviewed at", "reviewed_at"),
        )),
    ],
    "expenses": [
        ("Expense", (
            ("Title", "title"), ("Category", "category"), ("Amount", "amount"),
            ("Date", "date"), ("Unit", "unit_number"), ("Recorded by", "recorded_by"),
            ("Notes", "notes"), ("Created", "created_at"), ("Updated", "updated_at"),
        )),
    ],
    "public-listings": [
        ("Listing", (
            ("Title", "title"), ("Name", "name"), ("Unit number", "unit_number"),
            ("Location", "location"), ("Property type", "property_type"),
            ("Furnishing", "furnishing_status"), ("Rent", "rent"),
            ("Monthly rent", "monthly_rent"), ("Security deposit", "security_deposit"),
            ("Advance rent months", "advance_rent_months"),
            ("Minimum lease months", "minimum_lease_months"),
            ("Area", "area_sqm"), ("Bedrooms", "bedrooms"), ("Bathrooms", "bathrooms"),
            ("Description", "description"), ("Amenities", "amenities"),
            ("Inclusions", "inclusions"), ("Updated", "updated_at"),
        )),
    ],
    "documents": [
        ("Document metadata", (
            ("Tenant", "tenant_name"), ("Title", "title"), ("Type", "type"),
            ("File name", "file_name"), ("File size", "file_size"),
            ("Uploaded", "uploaded_at"),
        )),
    ],
    "announcements": [
        ("Announcement", (
            ("Title", "title"), ("Message", "message"), ("Category", "category"),
            ("Author", "author"), ("Published", "timestamp"),
            ("Important", "is_important"), ("Archived", "is_archived"),
        )),
    ],
    "notifications": [
        ("Notification", (
            ("Title", "title"), ("Message", "message"), ("Type", "type"),
            ("Timestamp", "timestamp"), ("Read", "is_read"),
            ("Archived", "is_archived"), ("Related type", "entity_type"),
            ("Related record ID", "entity_id"), ("Action", "action"),
        )),
    ],
    "events": [
        ("Event", (
            ("Title", "title"), ("Date", "date"), ("Type", "type"),
            ("Priority", "priority"), ("Completed", "is_completed"),
            ("Time window", "time_window"), ("Location", "location"),
            ("Description", "description"), ("Created", "created_at"),
            ("Updated", "updated_at"),
        )),
    ],
    "rfid-access": [
        ("Access event", (
            ("Device", "device_id"), ("Action", "action"),
            ("Result", "access_status"), ("Time", "created_at"),
            ("Event ID", "event_id"),
        )),
    ],
    "utility-history": [
        ("Rate change", (
            ("Utility", "utility"), ("Previous rate (₱/unit)", "previous_rate"),
            ("New rate (₱/unit)", "new_rate"), ("Rate unit", "rate_unit"),
            ("Effective", "effective_at"),
            ("Note", "note"),
        )),
    ],
    "settings": [
        ("Defaults", (
            ("Default late fee", "default_late_fee"), ("Default due day", "default_due_day"),
            ("Automatic late fee", "auto_late_fee_enabled"),
            ("Automatic backup", "auto_backup_enabled"),
            ("Water rate", "water_rate"), ("Electricity rate", "electricity_rate"),
        )),
        ("Property contact and display", (
            ("Landlord name", "landlord_name"), ("Landlord role", "landlord_role"),
            ("Landlord contact", "landlord_contact"), ("Dark mode", "dark_mode"),
            ("Updated", "updated_at"),
        )),
    ],
    "activity": [
        ("Audit entry", (
            ("Action", "action"), ("Activity", "details"),
            ("Timestamp", "timestamp"),
        )),
    ],
    "superadmins": [
        ("Account", (
            ("Name", "display_name"), ("Email", "email"), ("Role", "role"),
            ("Approved", "is_approved"),
            ("Must change password", "must_change_password"),
        )),
        ("Activity", (
            ("Created", "created_at"), ("Last login", "last_login_at"),
            ("Updated", "updated_at"),
        )),
    ],
}


@contextmanager
def get_db() -> Iterator[sqlite3.Connection]:
    DATABASE.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(DATABASE)
    connection.row_factory = sqlite3.Row
    try:
        with connection:
            yield connection
    finally:
        connection.close()


def init_db() -> None:
    supabase_backend.init_sessions(DATABASE)
    with get_db() as db:
        db.execute(
            """CREATE TABLE IF NOT EXISTS landlords (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                company TEXT NOT NULL,
                email TEXT NOT NULL UNIQUE,
                phone TEXT NOT NULL DEFAULT '',
                units INTEGER NOT NULL DEFAULT 0,
                status TEXT NOT NULL DEFAULT 'Invited',
                created_at TEXT NOT NULL
            )"""
        )
        db.execute(
            """CREATE TABLE IF NOT EXISTS records (
                section TEXT NOT NULL,
                id INTEGER NOT NULL,
                data TEXT NOT NULL,
                PRIMARY KEY (section, id)
            )"""
        )
        db.execute(
            """CREATE TABLE IF NOT EXISTS offline_sync_changes (
                user_uid TEXT NOT NULL,
                change_id TEXT NOT NULL,
                created_at TEXT NOT NULL,
                PRIMARY KEY (user_uid, change_id)
            )"""
        )
        db.execute(
            """CREATE TABLE IF NOT EXISTS auth_rate_limits (
                endpoint TEXT NOT NULL,
                identity_hash TEXT NOT NULL,
                window_started_at INTEGER NOT NULL,
                attempts INTEGER NOT NULL,
                PRIMARY KEY (endpoint, identity_hash)
            )"""
        )
        db.execute(
            """CREATE TABLE IF NOT EXISTS app_migrations (
                name TEXT PRIMARY KEY,
                applied_at TEXT NOT NULL
            )"""
        )
        demo_migration = "remove_sample_preview_records_v1"
        if not db.execute(
            "SELECT 1 FROM app_migrations WHERE name = ?", (demo_migration,)
        ).fetchone():
            db.execute(
                """DELETE FROM landlords
                   WHERE email IN (
                     'amara@santosgroup.ph', 'daniel@reyesresidences.ph',
                     'mikaela@cruzliving.ph', 'noah@northpoint.ph',
                     'sofia@garciahomes.ph', 'ethan@limurban.ph'
                   )"""
            )
            db.execute("DELETE FROM records WHERE id BETWEEN 1 AND 6")
            db.execute(
                "INSERT INTO app_migrations (name, applied_at) VALUES (?, ?)",
                (demo_migration, datetime.now(timezone.utc).isoformat()),
            )


def _json_dumps(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False)


def _audit_metadata(value: Any) -> dict[str, Any]:
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except json.JSONDecodeError:
            return {}
    return value if isinstance(value, dict) else {}


def _looks_like_sql(value: str) -> bool:
    return re.match(
        r"^\s*(?:SELECT\b[\s\S]*?\bFROM\b|INSERT\s+INTO\b|"
        r"UPDATE\b[\s\S]*?\bSET\b|DELETE\s+FROM\b|"
        r"(?:CREATE|ALTER|DROP)\s+(?:TABLE|SCHEMA|FUNCTION|POLICY)\b)",
        value,
        re.IGNORECASE,
    ) is not None


def _safe_audit_text(value: Any, maximum: int = 180) -> str:
    if not isinstance(value, (str, int, float)):
        return ""
    text = str(value).strip()
    lowered = text.casefold()
    if (
        not text
        or _looks_like_sql(text)
        or any(marker in lowered for marker in ("sqlstate", "traceback", "supabaserequesterror"))
    ):
        return ""
    return text[:maximum]


def _normalize_audit_row(row: dict[str, Any]) -> dict[str, Any]:
    if "summary" in row and "action_kind" in row:
        return row
    metadata = _audit_metadata(row.get("details"))
    actor = _safe_audit_text(
        metadata.get("actor_name")
        or metadata.get("actor_email")
        or metadata.get("actor")
        or metadata.get("user_name")
        or metadata.get("user_email")
        or metadata.get("performed_by")
    ) or "Administrator"

    raw_action = _safe_audit_text(row.get("action"), 80)
    action_key = re.sub(r"[\s-]+", "_", raw_action).upper()
    resource_action = re.fullmatch(
        r"(?P<verb>add|create|insert|update|edit|delete|remove|archive|approve|decline|invite)"
        r"\s+(?:a\s+|an\s+)?(?P<resource>tenant|tenants|unit|units|property|properties|"
        r"landlord|landlords|inquiry|inquiries|payment|payments|maintenance(?:\s+request)?|"
        r"announcement|announcements|expense|expenses|account|accounts)"
        r"(?:\s+record)?",
        raw_action,
        re.IGNORECASE,
    )
    action_resource = ""
    if resource_action:
        action_key = resource_action.group("verb").upper()
        action_resource = resource_action.group("resource").casefold()
    action_labels = {
        "ADD": "Added",
        "ADDED": "Added",
        "INSERT": "Created",
        "CREATE": "Created",
        "CREATED": "Created",
        "UPDATE": "Updated",
        "UPDATED": "Updated",
        "EDIT": "Updated",
        "DELETE": "Deleted",
        "DELETED": "Deleted",
        "REMOVE": "Deleted",
        "ARCHIVE": "Archived",
        "ARCHIVED": "Archived",
        "APPROVE": "Approved",
        "APPROVED": "Approved",
        "DECLINE": "Declined",
        "DECLINED": "Declined",
        "INVITE": "Sent invitation",
        "INVITED": "Sent invitation",
        "LOGIN": "Signed in",
        "LOGIN_FAILED": "Failed sign-in",
        "DISABLE": "Disabled",
        "DISABLED": "Disabled",
        "ACTIVATE": "Activated",
        "ACTIVATED": "Activated",
        "SUSPEND": "Suspended",
        "SUSPENDED": "Suspended",
    }
    if _looks_like_sql(raw_action):
        action, action_kind = "Activity recorded", "neutral"
    elif action_key in action_labels:
        action = action_labels[action_key]
        action_kind = (
            "danger" if action in {"Deleted", "Declined", "Disabled", "Failed sign-in"}
            else "success" if action in {"Added", "Created", "Approved", "Sent invitation", "Activated"}
            else "updated" if action == "Updated"
            else "neutral"
        )
    else:
        action = re.sub(r"[_\s]+", " ", raw_action).strip().capitalize()
        action = action or "Activity recorded"
        action_kind = "neutral"

    description = _safe_audit_text(
        metadata.get("description")
        or metadata.get("target_name")
        or metadata.get("resource_name")
        or metadata.get("record_name")
        or metadata.get("tenant_name")
        or metadata.get("unit_number")
    )
    target_id = _safe_audit_text(
        metadata.get("target_id")
        or metadata.get("record_id")
        or metadata.get("entity_id")
        or metadata.get("tenant_id")
        or metadata.get("unit_id")
        or metadata.get("property_id"),
        100,
    )
    resource = _safe_audit_text(
        metadata.get("target_type")
        or metadata.get("resource_type")
        or metadata.get("entity_type")
        or metadata.get("table")
        or action_resource
    )
    resource_labels = {
        "tenant": "Tenant",
        "units": "Unit",
        "unit": "Unit",
        "properties": "Property",
        "property": "Property",
        "landlord": "Landlord",
        "tenants": "Tenant",
        "inquiry": "Inquiry",
        "inquiries": "Inquiry",
        "landlords": "Landlord",
        "payment": "Payment",
        "tenant_inquiries": "Inquiry",
        "payments": "Payment",
        "maintenance": "Maintenance request",
        "maintenance_tickets": "Maintenance request",
        "announcement": "Announcement",
        "announcements": "Announcement",
        "expense": "Expense",
        "expenses": "Expense",
        "account": "Account",
        "accounts": "Account",
        "users": "Account",
    }
    resource_label = resource_labels.get(resource.casefold(), resource.replace("_", " ").title())
    if description:
        target = description
    elif target_id:
        short_id = (
            f"{target_id[:8]}…{target_id[-4:]}"
            if len(target_id) > 16
            else target_id
        )
        target = f"{resource_label or 'Record'} #{short_id}"
    elif resource_label:
        article = "an" if resource_label[0].casefold() in "aeiou" else "a"
        target = f"{article} {resource_label.casefold()} record"
    else:
        target = "a record"

    if action == "Failed sign-in":
        summary = f"Failed sign-in for {actor}."
    elif action == "Signed in":
        summary = f"{actor} signed in."
    else:
        verb = {
            "Sent invitation": "sent an invitation for",
            "Activity recorded": "recorded activity for",
        }.get(action, action.casefold())
        summary = f"{actor} {verb} {target}."

    return {
        **row,
        "actor": actor,
        "action": action,
        "action_kind": action_kind,
        "target": target,
        "summary": summary,
        "details": summary,
        "occurred": row.get("timestamp") or "—",
    }


def _utility_key_and_unit(value: Any) -> tuple[str, str]:
    utility = str(value or "").strip().casefold()
    if "water" in utility:
        return "water", "m³"
    if "electric" in utility:
        return "electricity", "kWh"
    return utility, "Not specified" if utility else "—"


def _normalize_utility_rate_rows(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    today = date.today()
    parsed_rows: list[tuple[str, datetime | None, str]] = []
    latest_effective: dict[str, tuple[datetime, list[int]]] = {}

    for index, row in enumerate(rows):
        utility_key, rate_unit = _utility_key_and_unit(row.get("utility"))
        effective_at = _as_datetime(row.get("effective_at"))
        parsed_rows.append((utility_key, effective_at, rate_unit))
        if not utility_key or effective_at is None or effective_at.date() > today:
            continue

        current = latest_effective.get(utility_key)
        if current is None or effective_at > current[0]:
            latest_effective[utility_key] = (effective_at, [index])
        elif effective_at == current[0]:
            current[1].append(index)

    normalized = []
    for index, row in enumerate(rows):
        utility_key, effective_at, rate_unit = parsed_rows[index]
        if not utility_key or effective_at is None:
            status = "Unknown"
        elif effective_at.date() > today:
            status = "Scheduled"
        else:
            latest = latest_effective.get(utility_key)
            if latest is not None and effective_at == latest[0]:
                status = "Active" if len(latest[1]) == 1 else "Review"
            else:
                status = "Historical"
        normalized.append({**row, "rate_unit": rate_unit, "status": status})
    return normalized


def rows_for(section: str) -> list[dict[str, Any]]:
    config = getattr(g, "supabase_config", None) if has_request_context() else None
    if config is not None:
        return live_rows_for(section)
    with get_db() as db:
        if section == "landlords":
            return [dict(row) for row in db.execute("SELECT * FROM landlords ORDER BY id")]
        records = db.execute(
            "SELECT data FROM records WHERE section = ? ORDER BY id DESC", (section,)
        ).fetchall()
    rows = [json.loads(row["data"]) for row in records]
    if section == "activity":
        rows = [_normalize_audit_row(row) for row in rows]
    elif section == "utility-history":
        rows = _normalize_utility_rate_rows(rows)
    elif section == "announcements":
        rows = [
            {
                **row,
                "importance": "Important" if row.get("is_important") is True else "Standard",
                "status": "Archived" if row.get("is_archived") is True else "Published",
            }
            for row in rows
        ]
    elif section == "expenses":
        rows = [
            {**row, "unit": row.get("unit_number") or "Unlinked"}
            for row in rows
        ]
    return rows


def filtered_rows(section: str) -> tuple[list[dict[str, Any]], str, str]:
    query = request.args.get("q", "").strip()
    status = request.args.get("status", "All").strip()
    category = request.args.get("category", "").strip()
    if len(category) > 80:
        abort(400, description="Category filters must be 80 characters or fewer.")
    all_rows = rows_for(section)
    rows = all_rows
    if section == "expenses":
        period = request.args.get("period", "").strip()
        if period:
            if not re.fullmatch(r"\d{4}-\d{2}", period):
                abort(400, description="Choose a valid expense month.")
            try:
                selected_month = date.fromisoformat(f"{period}-01")
            except ValueError:
                abort(400, description="Choose a valid expense month.")
            if selected_month < MIN_ENTRY_DATE:
                abort(400, description="Choose an expense month from January 2025 onward.")
            rows = [
                row for row in rows
                if str(row.get("date") or "").startswith(period)
            ]
    if category:
        rows = [
            row for row in rows
            if str(row.get("category") or "").casefold() == category.casefold()
        ]
    if query:
        needle = query.casefold()
        rows = [
            row
            for row in rows
            if needle in " ".join(str(value) for value in row.values()).casefold()
        ]
    if status != "All":
        status_key = "access_status" if section == "rfid-access" else "status"
        rows = [row for row in rows if row.get(status_key) == status]
    return rows, query, status


def sorted_rows(
    section: str, rows: list[dict[str, Any]]
) -> tuple[list[dict[str, Any]], str, str]:
    sort_key = request.args.get("sort", "").strip()
    direction = request.args.get("direction", "asc").strip().lower()
    if direction not in {"asc", "desc"}:
        abort(400, description="Choose ascending or descending sort order.")
    if not sort_key:
        default_sorts = {
            "activity": "occurred",
            "rfid-access": "created",
            "utility-history": "effective_at",
        }
        if section in default_sorts:
            sort_key, direction = default_sorts[section], "desc"
        else:
            return rows, "", direction
    valid_keys = {key for key, _ in SECTIONS[section]["columns"]}
    if sort_key not in valid_keys:
        abort(400, description="Choose a valid sort column.")

    def value_key(row: dict[str, Any]) -> tuple[int, Any]:
        value = row.get(sort_key)
        if value is None or value == "":
            return (0, "")
        if isinstance(value, bool):
            return (1, int(value))
        if isinstance(value, (int, float)):
            return (1, float(value))
        parsed_date = _as_datetime(str(value))
        if parsed_date is not None:
            return (2, parsed_date.timestamp())
        text = str(value).strip()
        if re.fullmatch(r"-?\d+(?:\.\d+)?", text):
            return (1, float(text))
        return (3, text.casefold())

    return (
        sorted(rows, key=value_key, reverse=direction == "desc"),
        sort_key,
        direction,
    )


def currency(value: int | float) -> str:
    return f"₱{value:,.0f}"


def currency_precise(value: int | float) -> str:
    return f"₱{value:,.2f}"


def format_utility_rate(value: Any) -> str:
    if value is None or value == "":
        return "—"
    try:
        amount = float(value)
    except (TypeError, ValueError):
        return str(value)
    if not math.isfinite(amount):
        return str(value)
    return currency_precise(amount)


def format_display_value(value: Any, field_name: str = "") -> str:
    if value is None:
        return "—"
    if isinstance(value, datetime):
        parsed = value
        has_time = True
    elif isinstance(value, date):
        parsed = datetime.combine(value, datetime.min.time())
        has_time = False
    elif isinstance(value, str):
        text = value.strip()
        if field_name == "month" and re.fullmatch(r"\d{4}-\d{2}", text):
            try:
                return datetime.strptime(text, "%Y-%m").strftime("%B %Y")
            except ValueError:
                return value
        is_date_field = (
            field_name in {
                "date", "paid_on", "received", "created", "occurred",
                "lease_start", "lease_end", "due_date", "month",
            }
            or field_name.endswith(("_at", "_date", "_on"))
        )
        if not is_date_field:
            return value
        has_time = "T" in text or " " in text
        try:
            parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
        except ValueError:
            return value
    else:
        return str(value)

    date_label = parsed.strftime("%b %d, %Y").replace(" 0", " ")
    if not has_time:
        return date_label
    time_label = parsed.strftime("%I:%M %p").lstrip("0")
    return f"{date_label} · {time_label}"


def format_structured_value(value: Any, field_name: str = "") -> str:
    if isinstance(value, dict):
        return " · ".join(
            f"{str(key).replace('_', ' ').capitalize()}: "
            f"{format_structured_value(item, str(key))}"
            for key, item in value.items()
        )
    if isinstance(value, list):
        return " · ".join(format_structured_value(item) for item in value)
    return format_display_value(value, field_name)


app.jinja_env.filters["display_value"] = format_display_value
app.jinja_env.filters["utility_rate"] = format_utility_rate


@app.context_processor
def inject_globals() -> dict[str, Any]:
    return {
        "nav_items": NAV_ITEMS,
        "current_date": date.today().strftime("%A, %B %d, %Y").replace(" 0", " "),
        "currency": currency,
        "currency_precise": currency_precise,
        "preview_mode": getattr(g, "preview_mode", True),
        "supabase_connected": getattr(g, "supabase_config", None) is not None,
        "current_user": getattr(g, "current_user", None),
        "csrf_token": getattr(g, "csrf_token", ""),
    }


@app.before_request
def prepare_database() -> None:
    init_db()
    if request.endpoint in {"static", "service_worker"}:
        return
    try:
        g.supabase_config = supabase_backend.settings()
    except supabase_backend.SupabaseConfigurationError:
        app.logger.exception("Supabase configuration is invalid.")
        abort(503, description="Supabase configuration is incomplete or invalid.")
    g.preview_mode = g.supabase_config is None
    g.offline_replay = request.headers.get("X-Ramp-Offline-Replay") == "1"
    if g.supabase_config is None:
        g.csrf_token = session.setdefault("csrf_token", secrets.token_urlsafe(32))
        if request.method == "POST":
            validate_csrf(g.csrf_token)
        return
    g.csrf_token = session.get("csrf_token", "")
    sid = session.get("supabase_session_id")
    g.current_user = None
    g.authenticated = None
    if sid:
        try:
            authenticated = supabase_backend.load_session(
                g.supabase_config, DATABASE, sid
            )
        except supabase_backend.SupabaseRequestError:
            app.logger.exception("Supabase session validation failed.")
            abort(503, description="Could not validate the Supabase session.")
        if authenticated is not None:
            g.authenticated, g.csrf_token = authenticated
            g.current_user = g.authenticated["profile"]
    if request.endpoint in {"login", "forgot_password"}:
        if g.current_user is None:
            g.csrf_token = session.setdefault(
                "login_csrf_token", secrets.token_urlsafe(32)
            )
        return
    if g.current_user is None:
        if g.offline_replay:
            return jsonify({"error": "Sign in again before syncing offline changes."}), 401
        session.clear()
        return redirect(url_for("login", next=request.full_path.rstrip("?")))
    if g.offline_replay and request.method == "POST":
        change_id = request.headers.get("X-Ramp-Offline-Change", "")
        if change_id:
            with get_db() as db:
                exists = db.execute(
                    "SELECT 1 FROM offline_sync_changes WHERE user_uid = ? AND change_id = ?",
                    (g.current_user.get("uid", ""), change_id),
                ).fetchone()
            if exists:
                return jsonify({"synced": True, "duplicate": True})
    if request.method == "POST":
        validate_csrf(g.csrf_token)


def validate_csrf(expected: str) -> None:
    supplied = request.form.get("csrf_token", "")
    if not expected or not secrets.compare_digest(expected, supplied):
        abort(400, description="The form expired. Reload the page and try again.")


def _auth_identity_hash(email: str) -> str:
    return hmac.new(
        app.config["SECRET_KEY"].encode("utf-8"),
        email.casefold().encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def _auth_rate_limit(endpoint: str, email: str) -> int:
    identity_hash = _auth_identity_hash(email)
    now = int(time.time())
    with get_db() as db:
        db.execute(
            "DELETE FROM auth_rate_limits WHERE window_started_at <= ?",
            (now - AUTH_RATE_LIMIT_WINDOW_SECONDS,),
        )
        row = db.execute(
            """SELECT window_started_at, attempts FROM auth_rate_limits
               WHERE endpoint = ? AND identity_hash = ?""",
            (endpoint, identity_hash),
        ).fetchone()
        if row is not None:
            retry_after = (
                row["window_started_at"] + AUTH_RATE_LIMIT_WINDOW_SECONDS - now
            )
            if row["attempts"] >= AUTH_RATE_LIMIT_MAX_ATTEMPTS:
                return max(1, retry_after)
            db.execute(
                """UPDATE auth_rate_limits SET attempts = attempts + 1
                   WHERE endpoint = ? AND identity_hash = ?""",
                (endpoint, identity_hash),
            )
        else:
            db.execute(
                """INSERT INTO auth_rate_limits
                   (endpoint, identity_hash, window_started_at, attempts)
                   VALUES (?, ?, ?, 1)""",
                (endpoint, identity_hash, now),
            )
    return 0


def _clear_auth_rate_limit(endpoint: str, email: str) -> None:
    identity_hash = _auth_identity_hash(email)
    with get_db() as db:
        db.execute(
            "DELETE FROM auth_rate_limits WHERE endpoint = ? AND identity_hash = ?",
            (endpoint, identity_hash),
        )


@app.after_request
def finalize_offline_replay(response):
    if (
        not getattr(g, "offline_replay", False)
        or request.method != "POST"
        or not 300 <= response.status_code < 400
    ):
        return response
    change_id = request.headers.get("X-Ramp-Offline-Change", "")
    user_uid = (getattr(g, "current_user", None) or {}).get("uid", "")
    if change_id and user_uid:
        with get_db() as db:
            db.execute(
                """INSERT OR IGNORE INTO offline_sync_changes
                   (user_uid, change_id, created_at) VALUES (?, ?, ?)""",
                (user_uid, change_id, datetime.now(timezone.utc).isoformat()),
            )
    response.set_data(json.dumps({"synced": True}))
    response.status_code = 200
    response.headers["Content-Type"] = "application/json"
    response.headers.pop("Location", None)
    return response


def fetch_supabase_table(table: str) -> list[dict[str, Any]]:
    cache = getattr(g, "supabase_table_cache", None)
    if cache is None:
        cache = {}
        g.supabase_table_cache = cache
    if table in cache:
        return cache[table]
    config = getattr(g, "supabase_config", None)
    auth = getattr(g, "authenticated", None)
    if config is None or auth is None:
        raise RuntimeError("A signed-in Supabase session is required.")
    result: list[dict[str, Any]] = []
    offset = 0
    page_size = 500
    fields = {
        "landlords": "id,uid,name,company_name,email,phone,status,created_at,updated_at",
        "units": "id,landlord_id,unit_number,name,title,location,property_type,rent,monthly_rent,status,is_archived,tenant_id,tenant_name,image_url,images,updated_at",
        "tenants": "id,name,email,phone,unit_id,unit_number,lease_start,lease_end,lease_status,monthly_rent,balance,status,is_archived,landlord_id,updated_at",
        "payments": "id,reference_number,tenant_name,unit_number,month,amount,method,payment_method,status,unit_id,tenant_id,payment_date,date,transaction_type,created_at",
        "maintenance_tickets": "id,unit_id,unit_number,tenant_id,tenant_name,title,priority,status,assigned_to_name,sla_due_date,created_at,date",
        "tenant_inquiries": "id,created_at,updated_at,full_name,email,phone,preferred_unit_id,message,status,assigned_unit_id,tenant_id",
        "expenses": "id,title,category,amount,date,unit_id,unit_number,recorded_by,notes,created_at,updated_at",
        "public_listings": "id,title,name,unit_number,location,rent,monthly_rent,description,area,area_sqm,bedrooms,bathrooms,amenities,inclusions,property_type,furnishing_status,security_deposit,advance_rent_months,minimum_lease_months,updated_at",
        "tenant_documents": "id,tenant_id,tenant_name,title,type,file_name,file_size,uploaded_at",
        "announcements": "id,title,message,timestamp,author,is_important,category,is_archived",
        "notifications": "id,title,message,timestamp,is_read,is_archived,type,entity_type,entity_id,action",
        "events": "id,title,date,type,tenant_id,unit_id,ticket_id,unit_number,description,is_completed,priority,time_window,location,created_at,updated_at",
        "rfid_access_logs": "id,device_id,tenant_id,unit_id,action,access_status,created_at,event_id",
        "utility_rate_logs": "id,utility,previous_rate,new_rate,effective_at,note",
        "settings": "id,default_late_fee,default_due_day,auto_late_fee_enabled,auto_backup_enabled,dark_mode,landlord_name,landlord_role,landlord_contact,water_rate,electricity_rate,updated_at",
        "audit_logs": "id,landlord_id,action,details,timestamp",
        "users": "id,uid,email,display_name,role,is_approved,must_change_password,created_at,last_login_at,updated_at",
    }
    if table not in fields:
        raise ValueError("Unsupported Supabase table.")
    ordering = {
        "landlords": "created_at.desc",
        "tenant_inquiries": "created_at.desc",
        "expenses": "date.desc",
        "tenant_documents": "uploaded_at.desc",
        "announcements": "timestamp.desc",
        "notifications": "timestamp.desc",
        "events": "date.asc",
        "rfid_access_logs": "created_at.desc",
        "utility_rate_logs": "effective_at.desc",
        "public_listings": "updated_at.desc",
        "audit_logs": "timestamp.desc",
        "users": "created_at.desc",
    }.get(table, "id.asc")
    while True:
        page = supabase_backend.api_request(
            config,
            auth["access_token"],
            table,
            query={
                "select": fields[table],
                "order": ordering,
                "limit": str(page_size),
                "offset": str(offset),
            },
        )
        if not isinstance(page, list):
            raise supabase_backend.SupabaseRequestError(502, "invalid_response")
        result.extend(
            row
            for row in page
            if isinstance(row, dict)
            and (table != "users" or row.get("role") == "super_admin")
        )
        if len(page) < page_size:
            cache[table] = result
            return result
        offset += page_size


def live_rows_for(section: str) -> list[dict[str, Any]]:
    table_by_section = {
        "landlords": "landlords",
        "properties": "units",
        "tenants": "tenants",
        "payments": "payments",
        "maintenance": "maintenance_tickets",
        "inquiries": "tenant_inquiries",
        "expenses": "expenses",
        "public-listings": "public_listings",
        "documents": "tenant_documents",
        "announcements": "announcements",
        "notifications": "notifications",
        "events": "events",
        "rfid-access": "rfid_access_logs",
        "utility-history": "utility_rate_logs",
        "settings": "settings",
        "activity": "audit_logs",
        "superadmins": "users",
    }
    table = table_by_section.get(section)
    if table is None:
        return []
    raw_rows = fetch_supabase_table(table)
    landlords = fetch_supabase_table("landlords") if section == "properties" else []
    tenants = (
        fetch_supabase_table("tenants")
        if section in {
            "properties", "payments", "maintenance", "expenses",
            "documents", "events", "rfid-access",
        }
        else []
    )
    units = (
        fetch_supabase_table("units")
        if section in {
            "tenants", "payments", "maintenance", "inquiries",
            "expenses", "documents", "events", "rfid-access",
        }
        else []
    )
    landlord_names = {
        row.get("uid"): row.get("name") or row.get("email", "")
        for row in landlords
    }
    unit_by_id = {row.get("id"): row for row in units}
    tenant_by_id = {row.get("id"): row for row in tenants}
    landlord_unit_counts: dict[str, int] = {}
    if section == "landlords":
        for unit in fetch_supabase_table("units"):
            owner = unit.get("landlord_id")
            if owner:
                landlord_unit_counts[owner] = landlord_unit_counts.get(owner, 0) + 1
    normalized = []
    for row in raw_rows:
        if section == "superadmins":
            normalized.append(
                {
                    **row,
                    "display_name": row.get("display_name") or (row.get("email") or "").split("@")[0],
                    "status": "Active" if row.get("is_approved") is True else "Disabled",
                }
            )
        elif section == "landlords":
            display_status = _display_status(row.get("status"))
            normalized.append(
                {
                    **row,
                    "name": row.get("name") or (row.get("email") or "").split("@")[0],
                    "company": row.get("company_name") or "",
                    "units": landlord_unit_counts.get(row.get("uid"), 0),
                    "status": display_status,
                }
            )
        elif section == "properties":
            tenant = tenant_by_id.get(row.get("tenant_id"), {})
            normalized.append(
                {
                    **row,
                    "name": row.get("name") or row.get("title") or row.get("unit_number") or "Unnamed property",
                    "location": row.get("location") or "",
                    "landlord": landlord_names.get(row.get("landlord_id"), "Unassigned"),
                    "tenant": row.get("tenant_name") or tenant.get("name") or "—",
                    "rent": row.get("monthly_rent", row.get("rent", 0)) or 0,
                    "status": "Archived" if row.get("is_archived") is True else _display_status(row.get("status")),
                }
            )
        elif section == "tenants":
            unit = unit_by_id.get(row.get("unit_id"), {})
            normalized.append(
                {
                    **row,
                    "name": row.get("name") or "Unnamed tenant",
                    "property": row.get("unit_number") or unit.get("unit_number") or "—",
                    "lease_end": row.get("lease_end") or "—",
                    "balance": row.get("balance") or 0,
                    "status": "Archived" if row.get("is_archived") is True else _display_status(row.get("status")),
                }
            )
        elif section == "payments":
            unit = unit_by_id.get(row.get("unit_id"), {})
            tenant = tenant_by_id.get(row.get("tenant_id"), {})
            normalized.append(
                {
                    **row,
                    "reference": row.get("reference_number") or row.get("id"),
                    "tenant": row.get("tenant_name") or tenant.get("name") or "—",
                    "property": row.get("unit_number") or unit.get("unit_number") or "—",
                    "month": row.get("month") or "—",
                    "amount": row.get("amount") or 0,
                    "method": row.get("payment_method") or row.get("method") or "—",
                    "status": _display_status(row.get("status")),
                    "paid_on": row.get("payment_date") or row.get("date") or "—",
                }
            )
        elif section == "maintenance":
            unit = unit_by_id.get(row.get("unit_id"), {})
            tenant = tenant_by_id.get(row.get("tenant_id"), {})
            normalized.append(
                {
                    **row,
                    "property": row.get("unit_number") or unit.get("unit_number") or "—",
                    "tenant": row.get("tenant_name") or tenant.get("name") or "—",
                    "priority": _display_status(row.get("priority")),
                    "status": _display_status(row.get("status")),
                    "created": row.get("created_at") or row.get("date") or "—",
                }
            )
        elif section == "inquiries":
            preferred_unit = next(
                (unit for unit in units if unit.get("id") == row.get("preferred_unit_id")),
                {},
            )
            normalized.append(
                {
                    **row,
                    "sender": row.get("full_name") or "—",
                    "email": row.get("email") or "—",
                    "property": preferred_unit.get("unit_number") or preferred_unit.get("name") or "—",
                    "message": row.get("message") or "",
                    "received": row.get("created_at") or row.get("timestamp") or "—",
                    "status": _display_status(row.get("status")),
                }
            )
        elif section == "expenses":
            unit = unit_by_id.get(row.get("unit_id"), {})
            normalized.append(
                {
                    **row,
                    "unit": row.get("unit_number") or unit.get("unit_number") or "Unlinked",
                }
            )
        elif section == "public-listings":
            normalized.append(
                {
                    **row,
                    "title": row.get("title") or row.get("name") or "Untitled listing",
                    "rent": row.get("monthly_rent", row.get("rent", 0)) or 0,
                }
            )
        elif section == "documents":
            tenant = tenant_by_id.get(row.get("tenant_id"), {})
            normalized.append(
                {
                    **row,
                    "tenant": tenant.get("name") or row.get("tenant_name") or "Unlinked",
                }
            )
        elif section == "announcements":
            normalized.append(
                {
                    **row,
                    "importance": "Important" if row.get("is_important") is True else "Standard",
                    "status": "Archived" if row.get("is_archived") is True else "Published",
                }
            )
        elif section == "notifications":
            if row.get("is_archived") is True:
                status = "Archived"
            else:
                status = "Read" if row.get("is_read") is True else "Unread"
            normalized.append({**row, "status": status})
        elif section == "events":
            unit = unit_by_id.get(row.get("unit_id"), {})
            tenant = tenant_by_id.get(row.get("tenant_id"), {})
            normalized.append(
                {
                    **row,
                    "unit_number": row.get("unit_number") or unit.get("unit_number") or "Unlinked",
                    "tenant_name": tenant.get("name") or "Unlinked",
                    "status": "Completed" if row.get("is_completed") is True else "Upcoming",
                }
            )
        elif section == "rfid-access":
            unit = unit_by_id.get(row.get("unit_id"), {})
            tenant = tenant_by_id.get(row.get("tenant_id"), {})
            normalized.append(
                {
                    **row,
                    "device": row.get("device_id") or "—",
                    "unit": unit.get("unit_number") or "Unlinked",
                    "tenant": tenant.get("name") or "Unlinked",
                    "created": row.get("created_at") or "—",
                    "access_status": _display_status(row.get("access_status")),
                }
            )
        elif section in {"utility-history", "settings"}:
            normalized.append(dict(row))
        else:
            normalized.append(_normalize_audit_row(row))
    return (
        _normalize_utility_rate_rows(normalized)
        if section == "utility-history"
        else normalized
    )


def _display_status(value: Any) -> str:
    text = str(value or "Unknown").replace("_", " ").strip()
    return text[:1].upper() + text[1:]


def _is_available_review_unit(unit: dict[str, Any]) -> bool:
    return (
        unit.get("is_archived") is not True
        and str(unit.get("status") or "").strip().casefold() == "vacant"
        and not str(unit.get("tenant_id") or "").strip()
    )


def _is_private_payment_receipt(payment: dict[str, Any], payment_id: str) -> bool:
    tenant_id = str(payment.get("tenant_id") or "").strip()
    path = str(payment.get("proof_image_url") or "").strip()
    if (
        re.fullmatch(r"[A-Za-z0-9_-]{1,128}", tenant_id) is None
        or re.fullmatch(r"[A-Za-z0-9_-]{1,128}", payment_id) is None
        or "\\" in path
        or path.startswith("/")
    ):
        return False
    parts = path.split("/")
    return (
        len(parts) >= 3
        and parts[0] == tenant_id
        and parts[1] == payment_id
        and all(part not in {"", ".", ".."} for part in parts)
    )


def _fetch_supabase_record(
    table: str, record_id: str, fields: str, *, role: str | None = None
) -> dict[str, Any] | None:
    config = getattr(g, "supabase_config", None)
    auth = getattr(g, "authenticated", None)
    if config is None or auth is None:
        raise RuntimeError("A signed-in Supabase session is required.")
    query = {"select": fields, "id": f"eq.{record_id}", "limit": "1"}
    if role:
        query["role"] = f"eq.{role}"
    result = supabase_backend.api_request(
        config, auth["access_token"], table, query=query
    )
    if not isinstance(result, list):
        raise supabase_backend.SupabaseRequestError(502, "invalid_response")
    return dict(result[0]) if result and isinstance(result[0], dict) else None


def _fetch_supabase_related(
    table: str,
    relation_column: str,
    related_id: Any,
    fields: str,
    *,
    order: str = "id.desc",
    limit: int = 20,
) -> list[dict[str, Any]]:
    config = getattr(g, "supabase_config", None)
    auth = getattr(g, "authenticated", None)
    if config is None or auth is None:
        raise RuntimeError("A signed-in Supabase session is required.")
    if not relation_column.replace("_", "").isalnum() or not str(related_id).strip():
        return []
    result = supabase_backend.api_request(
        config,
        auth["access_token"],
        table,
        query={
            "select": fields,
            relation_column: f"eq.{related_id}",
            "order": order,
            "limit": str(limit),
        },
    )
    if not isinstance(result, list):
        raise supabase_backend.SupabaseRequestError(502, "invalid_response")
    return [dict(row) for row in result if isinstance(row, dict)]


def _detail_groups(section: str, record: dict[str, Any]) -> list[dict[str, Any]]:
    money_fields = {
        "rent", "monthly_rent", "security_deposit", "late_fee",
        "security_deposit_held", "utility_deposit_held", "balance", "amount",
        "base_rent", "water_bill", "electric_bill", "other_charge",
        "estimated_cost", "actual_cost", "vendor_cost", "labor_cost", "materials_cost",
    }
    groups = []
    for title, fields in DETAIL_GROUPS[section]:
        values = []
        for label, key in fields:
            value = record.get(key)
            if value is None or value == "":
                continue
            if section == "utility-history" and key in {"previous_rate", "new_rate"}:
                value = format_utility_rate(value)
            elif key in money_fields:
                try:
                    value = currency(float(value))
                except (TypeError, ValueError):
                    value = str(value)
            elif isinstance(value, bool):
                value = "Yes" if value else "No"
            elif isinstance(value, (list, dict)):
                value = format_structured_value(value, key)
            else:
                value = format_display_value(value, key)
            values.append({"label": label, "value": str(value)})
        if values:
            groups.append({"title": title, "fields": values})
    return groups


def _related_link(section: str, record: dict[str, Any] | None, title: str, meta: str = "") -> dict[str, str] | None:
    if not record or record.get("id") is None:
        return None
    return {
        "title": title,
        "meta": meta,
        "url": url_for(
            "record_detail", section=section, record_id=str(record["id"])
        ),
    }


@app.get("/")
def dashboard():
    landlords = rows_for("landlords")
    properties = rows_for("properties")
    payments = rows_for("payments")
    expenses = rows_for("expenses")
    maintenance = rows_for("maintenance")
    tenants = rows_for("tenants")
    inquiries = rows_for("inquiries")
    now = datetime.now()
    today = now.date()
    period = request.args.get("period", "").strip()
    if period:
        if not re.fullmatch(r"\d{4}-\d{2}", period):
            abort(400, description="Choose a valid month.")
        try:
            selected_month = datetime.strptime(period, "%Y-%m")
        except ValueError:
            abort(400, description="Choose a valid month.")
        if selected_month.date() < MIN_ENTRY_DATE:
            abort(400, description="Choose a month from January 2025 onward.")
    else:
        selected_month = now.replace(day=1)
    trend_months = []
    for offset in range(5, -1, -1):
        month_index = selected_month.year * 12 + selected_month.month - 1 - offset
        trend_months.append(
            datetime(month_index // 12, month_index % 12 + 1, 1)
        )
    trend_totals = {
        month.strftime("%Y-%m"): {"revenue": 0.0, "expenses": 0.0}
        for month in trend_months
    }
    paid_this_month = 0
    for payment in payments:
        if (
            str(payment.get("status", "")).casefold() != "paid"
            or str(payment.get("transaction_type", "rent")).casefold() != "rent"
        ):
            continue
        paid_at = _as_datetime(
            payment.get("payment_date")
            or payment.get("paid_at")
            or payment.get("date")
            or payment.get("paid_on")
        )
        if paid_at is not None:
            month_key = paid_at.strftime("%Y-%m")
            if month_key in trend_totals:
                trend_totals[month_key]["revenue"] += _number(
                    payment.get("amount")
                )
            if (paid_at.year, paid_at.month) == (
                selected_month.year,
                selected_month.month,
            ):
                paid_this_month += _number(payment.get("amount"))
    for expense in expenses:
        expense_date = _as_datetime(expense.get("date"))
        if expense_date is not None:
            month_key = expense_date.strftime("%Y-%m")
            if month_key in trend_totals:
                trend_totals[month_key]["expenses"] += _number(
                    expense.get("amount")
                )

    chart_left = 80
    chart_right = 620
    chart_top = 18
    chart_bottom = 132
    chart_maximum = max(
        (
            amount
            for totals in trend_totals.values()
            for amount in totals.values()
        ),
        default=0,
    ) or 1
    chart_step = (chart_right - chart_left) / max(len(trend_months) - 1, 1)
    chart_ticks = [
        {"y": chart_top + 4, "label": currency(chart_maximum)},
        {
            "y": round((chart_top + chart_bottom) / 2) + 4,
            "label": currency(chart_maximum / 2),
        },
        {"y": chart_bottom + 4, "label": currency(0)},
    ]
    trend_series = []
    for index, month in enumerate(trend_months):
        totals = trend_totals[month.strftime("%Y-%m")]
        x = round(chart_left + index * chart_step, 1)
        trend_series.append(
            {
                "label": month.strftime("%b"),
                "full_label": month.strftime("%B %Y"),
                "x": x,
                "revenue": totals["revenue"],
                "expenses": totals["expenses"],
                "revenue_y": round(
                    chart_bottom
                    - totals["revenue"] / chart_maximum * (chart_bottom - chart_top),
                    1,
                ),
                "expenses_y": round(
                    chart_bottom
                    - totals["expenses"] / chart_maximum * (chart_bottom - chart_top),
                    1,
                ),
            }
        )
    def smooth_chart_path(y_key: str) -> str:
        chart_points = [
            (point["x"], point[y_key]) for point in trend_series
        ]
        commands = [f"M {chart_points[0][0]} {chart_points[0][1]}"]
        for index in range(len(chart_points) - 1):
            current = chart_points[index]
            following = chart_points[index + 1]
            previous = chart_points[index - 1] if index else current
            after_following = (
                chart_points[index + 2]
                if index + 2 < len(chart_points)
                else following
            )
            first_control = (
                current[0] + (following[0] - previous[0]) / 6,
                current[1] + (following[1] - previous[1]) / 6,
            )
            second_control = (
                following[0] - (after_following[0] - current[0]) / 6,
                following[1] - (after_following[1] - current[1]) / 6,
            )
            commands.append(
                f"C {first_control[0]:.1f} {first_control[1]:.1f} "
                f"{second_control[0]:.1f} {second_control[1]:.1f} "
                f"{following[0]} {following[1]}"
            )
        return " ".join(commands)

    revenue_path = smooth_chart_path("revenue_y")
    expense_path = smooth_chart_path("expenses_y")
    revenue_area_path = (
        f"{revenue_path} L {trend_series[-1]['x']} {chart_bottom} "
        f"L {trend_series[0]['x']} {chart_bottom} Z"
    )
    trend_has_data = any(
        totals["revenue"] or totals["expenses"]
        for totals in trend_totals.values()
    )
    revenue_has_data = any(
        totals["revenue"] for totals in trend_totals.values()
    )
    previous_month_revenue = trend_series[-2]["revenue"]
    revenue_change_percent = (
        round(
            (trend_series[-1]["revenue"] - previous_month_revenue)
            / previous_month_revenue
            * 100
        )
        if previous_month_revenue
        else None
    )

    active_properties = [
        item for item in properties
        if item.get("is_archived") is not True
        and str(item.get("status", "")).casefold() != "archived"
    ]
    unit_status_counts: dict[str, int] = {}
    for unit in active_properties:
        unit_status = str(unit.get("status") or "Unknown")
        unit_status_counts[unit_status] = unit_status_counts.get(unit_status, 0) + 1
    occupied_properties = sum(
        str(item.get("status", "")).casefold() == "occupied"
        for item in active_properties
    )
    vacant_properties = sum(
        str(item.get("status", "")).casefold() == "vacant"
        for item in active_properties
    )
    reserved_properties = sum(
        str(item.get("status", "")).casefold() == "reserved"
        for item in active_properties
    )
    maintenance_properties = sum(
        str(item.get("status", "")).casefold() in {"maintenance", "under maintenance"}
        for item in active_properties
    )
    open_tickets = [
        ticket
        for ticket in maintenance
        if str(ticket.get("status", "")).casefold()
        not in {"completed", "closed", "resolved", "cancelled", "canceled"}
    ]
    high_priority_tickets = sum(
        str(ticket.get("priority", "")).casefold() in {"high", "urgent", "critical"}
        for ticket in open_tickets
    )
    pending_inquiries = [
        inquiry for inquiry in inquiries
        if str(inquiry.get("status", "")).casefold() == "pending"
    ]
    pending_payments = [
        payment for payment in payments
        if str(payment.get("status", "")).casefold() == "pending"
    ]
    overdue_payments = [
        payment for payment in payments
        if str(payment.get("status", "")).casefold() == "overdue"
    ]
    lease_ending_soon = []
    active_leases = []
    for tenant in tenants:
        if tenant.get("is_archived") is True:
            continue
        if str(tenant.get("status", "")).casefold() not in {"active", "current"}:
            continue
        active_leases.append(tenant)
        lease_end = _as_datetime(tenant.get("lease_end"))
        if lease_end and today <= lease_end.date() <= today + timedelta(days=30):
            lease_ending_soon.append(tenant)

    stats = {
        "landlords": sum(
            str(row.get("status", "")).casefold() == "active" for row in landlords
        ),
        "properties": len(active_properties),
        "active_leases": len(active_leases),
        "collected": paid_this_month,
        "occupancy_rate": round(
            occupied_properties / len(active_properties) * 100
        ) if active_properties else 0,
        "occupied_properties": occupied_properties,
        "vacant_properties": vacant_properties,
        "reserved_properties": reserved_properties,
        "maintenance_properties": maintenance_properties,
        "pending_inquiries": len(pending_inquiries),
        "pending_payments": len(pending_payments),
        "overdue_payments": len(overdue_payments),
        "open_tickets": len(open_tickets),
        "high_priority_tickets": high_priority_tickets,
        "lease_ending_soon": len(lease_ending_soon),
    }
    attention_items = []
    if open_tickets:
        attention_items.append(
            {
                "count": len(open_tickets),
                "title": "Open maintenance",
                "unit": "request",
                "unit_plural": "requests",
                "section": "maintenance",
            }
        )
    if pending_inquiries:
        attention_items.append(
            {
                "count": len(pending_inquiries),
                "title": "Pending inquiries",
                "unit": "inquiry",
                "unit_plural": "inquiries",
                "section": "inquiries",
                "status": "Pending",
            }
        )
    if pending_payments:
        attention_items.append(
            {
                "count": len(pending_payments),
                "title": "Pending payments",
                "unit": "payment",
                "unit_plural": "payments",
                "section": "payments",
                "status": "Pending",
            }
        )
    if overdue_payments:
        attention_items.append(
            {
                "count": len(overdue_payments),
                "title": "Marked overdue",
                "unit": "payment",
                "unit_plural": "payments",
                "section": "payments",
                "status": "Overdue",
            }
        )
    if lease_ending_soon:
        attention_items.append(
            {
                "count": len(lease_ending_soon),
                "title": "Leases ending soon",
                "unit": "lease",
                "unit_plural": "leases",
                "section": "tenants",
            }
        )

    recent_activity = []
    recent_sources = (
        ("activity", rows_for("activity"), "occurred", "action"),
        ("inquiries", inquiries, "received", "sender"),
        ("payments", payments, "created_at", "reference"),
        ("maintenance", maintenance, "created", "title"),
    )
    for section, source_rows, date_key, title_key in recent_sources:
        for row in source_rows:
            occurred_raw = (
                row.get(date_key)
                or row.get("paid_on")
                or row.get("date")
            )
            occurred = (
                _as_datetime(occurred_raw)
            )
            if occurred is None:
                continue
            recent_activity.append(
                {
                    "section": section,
                    "record_id": row.get("id"),
                    "title": str(
                        row.get("summary")
                        if section == "activity"
                        else row.get(title_key) or row.get("action") or "Record updated"
                    ),
                    "detail": str(
                        "" if section == "activity"
                        else row.get("status") or row.get("target") or ""
                    ),
                    "occurred": occurred,
                    "occurred_raw": str(occurred_raw),
                    "occurred_field": date_key,
                }
            )
    recent_activity.sort(key=lambda item: item["occurred"], reverse=True)
    for item in recent_activity:
        if item["record_id"] is not None:
            item["url"] = url_for(
                "record_detail",
                section=item["section"],
                record_id=str(item["record_id"]),
            )
        item["occurred_label"] = format_display_value(
            item["occurred_raw"], item["occurred_field"]
        )

    return render_template(
        "dashboard.html",
        stats=stats,
        attention_items=attention_items,
        month_label=selected_month.strftime("%B %Y"),
        selected_period=selected_month.strftime("%Y-%m"),
        unit_status_counts=unit_status_counts,
        trend_series=trend_series,
        revenue_path=revenue_path,
        revenue_area_path=revenue_area_path,
        expense_path=expense_path,
        chart_ticks=chart_ticks,
        trend_has_data=trend_has_data,
        revenue_has_data=revenue_has_data,
        revenue_change_percent=revenue_change_percent,
        recent_activity=recent_activity[:6],
    )


@app.get("/search")
def global_search():
    query = request.args.get("q", "").strip()
    if len(query) > 120:
        abort(400, description="Search terms must be 120 characters or fewer.")
    results = []
    if query:
        sections = (
            "properties", "tenants", "landlords", "superadmins",
            "inquiries", "payments", "maintenance", "expenses",
            "public-listings", "documents", "announcements", "notifications",
            "events", "rfid-access", "utility-history", "settings",
        )
        needle = query.casefold()
        for section in sections:
            matches = [
                row for row in rows_for(section)
                if needle in " ".join(str(value) for value in row.values()).casefold()
            ]
            display_items = []
            for row in matches[:5]:
                title = (
                    row.get("unit_number") or row.get("name") or row.get("display_name")
                    or row.get("sender") or row.get("title")
                    or row.get("reference") or row.get("reference_number")
                    or row.get("email") or str(row.get("id") or "Record")
                )
                subtitle = " · ".join(
                    str(row[key])
                    for key in ("email", "property", "status", "month", "paid_on", "priority")
                    if row.get(key)
                )
                link = _related_link(section, row, str(title), subtitle)
                if link is not None:
                    display_items.append(link)
            if matches:
                results.append(
                    {
                        "section": section,
                        "title": SECTIONS[section]["title"],
                        "count": len(matches),
                        "items": display_items,
                        "more_url": url_for(
                            "records_page", section=section, q=query
                        ),
                    }
                )
    return render_template(
        "search_results.html", query=query, results=results
    )


@app.get("/<section>")
def records_page(section: str):
    if section in {"connections", "access"}:
        return render_template("placeholder.html", section=section)
    if section not in SECTIONS:
        abort(404)
    filtered, query, status = filtered_rows(section)
    filtered, sort, direction = sorted_rows(section, filtered)
    all_rows = rows_for(section)
    period = request.args.get("period", "").strip() if section == "expenses" else ""
    category = request.args.get("category", "").strip()
    expense_total = sum(_number(row.get("amount")) for row in filtered) if section == "expenses" else 0
    try:
        page_number = int(request.args.get("page", "1"))
    except ValueError:
        abort(400, description="Choose a valid page number.")
    page_count = max(1, math.ceil(len(filtered) / RECORDS_PAGE_SIZE))
    if page_number < 1 or page_number > page_count:
        abort(404, description="That page does not exist.")
    page_numbers = sorted(
        {1, page_count, *range(max(2, page_number - 2), min(page_count, page_number + 2) + 1)}
    )
    start_index = (page_number - 1) * RECORDS_PAGE_SIZE
    rows = filtered[start_index : start_index + RECORDS_PAGE_SIZE]
    if section == "inquiries":
        for row in rows:
            row["inquiry_is_application"] = str(
                row.get("message") or ""
            ).lstrip().casefold().startswith("[rental application]")
    page_start = start_index + 1 if rows else 0
    page_end = start_index + len(rows)
    status_key = "access_status" if section == "rfid-access" else "status"
    statuses = sorted(
        {str(row[status_key]) for row in all_rows if row.get(status_key)}
    )
    categories = sorted(
        {
            str(row["category"])
            for row in all_rows
            if row.get("category") and section in {"expenses", "announcements"}
        },
        key=str.casefold,
    )
    related_landlords = rows_for("landlords") if section in {"properties", "tenants"} else []
    related_properties = rows_for("properties") if section == "tenants" else []
    return render_template(
        "records.html",
        section=section,
        config=SECTIONS[section],
        rows=rows,
        query=query,
        status=status,
        sort=sort,
        direction=direction,
        statuses=statuses,
        categories=categories,
        category=category,
        filtered_total=len(filtered),
        page_number=page_number,
        page_count=page_count,
        page_numbers=page_numbers,
        page_label=f"Page {page_number} of {page_count}",
        page_start=page_start,
        page_end=page_end,
        rows_for_count=len(all_rows),
        status_counts={
            item: sum(row.get(status_key) == item for row in all_rows)
            for item in statuses
        },
        related_landlords=related_landlords,
        related_properties=related_properties,
        period=period,
        expense_total=expense_total,
    )


@app.get("/payments/<record_id>/receipt")
def payment_receipt(record_id: str):
    if g.supabase_config is None:
        abort(503, description="Receipt access requires a live Supabase connection.")
    if re.fullmatch(r"[A-Za-z0-9_-]{1,128}", record_id) is None:
        abort(404)
    payment = _fetch_supabase_record(
        "payments", record_id, "id,tenant_id,proof_image_url"
    )
    if payment is None:
        abort(404)
    path = str(payment.get("proof_image_url") or "").strip()
    if not _is_private_payment_receipt(payment, record_id):
        abort(404)
    signed_url = supabase_backend.create_signed_storage_url(
        g.supabase_config,
        g.authenticated["access_token"],
        "tenant-payment-receipts",
        path,
        expires_in=300,
    )
    return redirect(signed_url, code=302)


@app.post("/payments/<record_id>/review")
def review_payment_receipt(record_id: str):
    if g.supabase_config is None:
        abort(503, description="Payment review requires a live Supabase connection.")
    if re.fullmatch(r"[A-Za-z0-9_-]{1,128}", record_id) is None:
        abort(404)
    payment = _fetch_supabase_record(
        "payments", record_id, "id,status,tenant_id,proof_image_url"
    )
    if payment is None:
        abort(404)
    if str(payment.get("status") or "").strip().casefold() not in {
        "pending",
        "overdue",
        "pending review",
    }:
        abort(409, description="Only unreviewed payment receipts can be reviewed.")
    if not str(payment.get("proof_image_url") or "").strip():
        abort(409, description="This payment has no submitted receipt.")
    decision = request.form.get("decision", "").strip()
    if decision not in {"approve", "decline"}:
        abort(400, description="Choose whether to approve or decline this receipt.")
    decline_reason = _normalized_text(request.form.get("decline_reason", ""))
    if len(decline_reason) > 500:
        abort(400, description="The decline reason must be 500 characters or fewer.")
    if decision == "decline" and not decline_reason:
        abort(400, description="Provide a reason before declining the receipt.")
    supabase_backend.rpc_request(
        g.supabase_config,
        g.authenticated["access_token"],
        "review_tenant_payment_receipt",
        {
            "p_payment_id": record_id,
            "p_decision": decision,
            "p_decline_reason": decline_reason or None,
        },
    )
    flash(
        "Payment receipt approved; payment marked paid."
        if decision == "approve"
        else "Payment receipt declined.",
        "success",
    )
    return redirect(url_for("record_detail", section="payments", record_id=record_id))


@app.get("/settings/terms")
def terms_draft():
    return render_template("terms_draft.html")


@app.get("/<section>/<record_id>")
def record_detail(section: str, record_id: str):
    if section not in DETAIL_FIELDS:
        abort(404)
    if getattr(g, "supabase_config", None) is None:
        record = next(
            (row for row in rows_for(section) if str(row.get("id")) == record_id),
            None,
        )
    else:
        record = _fetch_supabase_record(
            DETAIL_TABLES[section],
            record_id,
            DETAIL_FIELDS[section],
            role="super_admin" if section == "superadmins" else None,
        )
    if record is None:
        abort(404)
    if section == "activity":
        record = _normalize_audit_row(record)
    elif section == "utility-history":
        _, rate_unit = _utility_key_and_unit(record.get("utility"))
        record = {**record, "rate_unit": rate_unit}

    related_groups: list[dict[str, Any]] = []
    review_units: list[dict[str, Any]] = []

    def add_group(title: str, items: list[dict[str, Any] | None]) -> None:
        related_groups.append(
            {"title": title, "items": [item for item in items if item is not None]}
        )

    def find_related(section_name: str, table: str, related_id: Any, fields: str):
        if related_id is None or str(related_id).strip() == "":
            return None
        if getattr(g, "supabase_config", None) is None:
            rows = rows_for(section_name)
            return next(
                (row for row in rows if str(row.get("id")) == str(related_id)),
                None,
            )
        return _fetch_supabase_record(table, str(related_id), fields)

    def add_linked_record(
        title: str, section_name: str, table: str, related_id: Any, fields: str, label: str
    ) -> dict[str, str]:
        linked = find_related(section_name, table, related_id, fields)
        if linked is None:
            return {"title": title, "meta": "Unlinked", "url": ""}
        return _related_link(
            section_name, linked, label(linked), str(linked.get("status") or "")
        ) or {"title": title, "meta": "Unlinked", "url": ""}

    if section == "landlords":
        landlord_uid = record.get("uid")
        if landlord_uid and getattr(g, "supabase_config", None) is not None:
            units = _fetch_supabase_related(
                "units", "landlord_id", landlord_uid,
                "id,unit_number,name,title,status,is_archived",
                order="unit_number.asc", limit=50,
            )
        else:
            units = [
                unit for unit in rows_for("properties")
                if unit.get("landlord_id") in {landlord_uid, record.get("id")}
            ]
        add_group(
            "Linked units",
            [
                _related_link(
                    "properties",
                    unit,
                    str(unit.get("unit_number") or unit.get("name") or unit.get("title") or "Unit"),
                    _display_status(unit.get("status")),
                )
                for unit in units
            ],
        )
    elif section == "properties":
        landlord_id = record.get("landlord_id")
        if landlord_id:
            if getattr(g, "supabase_config", None) is not None:
                landlords = _fetch_supabase_related(
                    "landlords", "uid", landlord_id,
                    "id,uid,name,company_name,email,status",
                    limit=1,
                )
                landlord = landlords[0] if landlords else None
            else:
                landlord = next(
                    (
                        item for item in rows_for("landlords")
                        if str(item.get("uid") or item.get("id")) == str(landlord_id)
                    ),
                    None,
                )
            add_group(
                "Landlord",
                [
                    _related_link(
                        "landlords", landlord,
                        str(landlord.get("name") or landlord.get("email") or "Landlord"),
                        _display_status(landlord.get("status")),
                    ) if landlord else {"title": "Landlord", "meta": "Unlinked", "url": ""}
                ],
            )
        add_group(
            "Assigned tenant",
            [add_linked_record(
                "Tenant", "tenants", "tenants", record.get("tenant_id"),
                "id,name,email,status,is_archived,unit_id",
                lambda item: str(item.get("name") or item.get("email") or "Tenant"),
            )] if record.get("tenant_id") else [],
        )
        if getattr(g, "supabase_config", None) is not None:
            payment_rows = _fetch_supabase_related(
                "payments", "unit_id", record_id,
                "id,reference_number,month,amount,status,unit_id",
                limit=10,
            )
            ticket_rows = _fetch_supabase_related(
                "maintenance_tickets", "unit_id", record_id,
                "id,title,status,priority,unit_id",
                limit=10,
            )
        else:
            payment_rows = [row for row in rows_for("payments") if str(row.get("unit_id")) == record_id]
            ticket_rows = [row for row in rows_for("maintenance") if str(row.get("unit_id")) == record_id]
        add_group(
            "Recent payments",
            [
                _related_link(
                    "payments", item,
                    str(item.get("reference_number") or item.get("month") or "Payment"),
                    f"{currency(_number(item.get('amount')))} · {_display_status(item.get('status'))}",
                )
                for item in payment_rows
            ],
        )
        add_group(
            "Maintenance requests",
            [
                _related_link(
                    "maintenance", item, str(item.get("title") or "Maintenance request"),
                    f"{_display_status(item.get('priority'))} · {_display_status(item.get('status'))}",
                )
                for item in ticket_rows
            ],
        )
    elif section == "tenants":
        if record.get("unit_id"):
            add_group(
                "Assigned unit",
                [add_linked_record(
                    "Unit", "properties", "units", record.get("unit_id"),
                    "id,unit_number,name,title,status,is_archived",
                    lambda item: str(item.get("unit_number") or item.get("name") or item.get("title") or "Unit"),
                )],
            )
        for table, related_section, title, fields in (
            ("payments", "payments", "Recent payments", "id,reference_number,month,amount,status,tenant_id"),
            ("maintenance_tickets", "maintenance", "Maintenance requests", "id,title,status,priority,tenant_id"),
            ("tenant_inquiries", "inquiries", "Related inquiries", "id,full_name,status,created_at,tenant_id"),
        ):
            if getattr(g, "supabase_config", None) is not None:
                items = _fetch_supabase_related(
                    table, "tenant_id", record_id, fields, limit=10
                )
            else:
                items = [
                    item for item in rows_for(related_section)
                    if str(item.get("tenant_id")) == record_id
                ]
            add_group(
                title,
                [
                    _related_link(
                        related_section, item,
                        str(item.get("reference_number") or item.get("title") or item.get("full_name") or item.get("month") or "Record"),
                        _display_status(item.get("status")),
                    )
                    for item in items
                ],
            )
    elif section == "payments":
        for title, related_section, table, related_id, fields, label in (
            ("Unit", "properties", "units", record.get("unit_id"), "id,unit_number,name,title,status,is_archived", lambda item: str(item.get("unit_number") or item.get("name") or item.get("title") or "Unit")),
            ("Tenant", "tenants", "tenants", record.get("tenant_id"), "id,name,email,status,is_archived", lambda item: str(item.get("name") or item.get("email") or "Tenant")),
        ):
            if related_id:
                add_group(title, [add_linked_record(title, related_section, table, related_id, fields, label)])
    elif section == "maintenance":
        for title, related_section, table, related_id, fields, label in (
            ("Unit", "properties", "units", record.get("unit_id"), "id,unit_number,name,title,status,is_archived", lambda item: str(item.get("unit_number") or item.get("name") or item.get("title") or "Unit")),
            ("Tenant", "tenants", "tenants", record.get("tenant_id"), "id,name,email,status,is_archived", lambda item: str(item.get("name") or item.get("email") or "Tenant")),
        ):
            if related_id:
                add_group(title, [add_linked_record(title, related_section, table, related_id, fields, label)])
        if getattr(g, "supabase_config", None) is not None:
            comments = _fetch_supabase_related(
                "ticket_comments", "ticket_id", record_id,
                "id,ticket_id,message,created_at",
                order="created_at.asc", limit=200,
            )
            add_group(
                "Ticket conversation",
                [
                    {"title": str(comment.get("message") or "Comment"),
                     "meta": str(comment.get("created_at") or ""),
                     "url": ""}
                    for comment in comments
                ],
            )
    elif section == "inquiries":
        for title, related_section, table, related_id, fields, label in (
            ("Preferred unit", "properties", "units", record.get("preferred_unit_id"), "id,unit_number,name,title,status,is_archived", lambda item: str(item.get("unit_number") or item.get("name") or item.get("title") or "Unit")),
            ("Assigned unit", "properties", "units", record.get("assigned_unit_id"), "id,unit_number,name,title,status,is_archived", lambda item: str(item.get("unit_number") or item.get("name") or item.get("title") or "Unit")),
            ("Created tenant", "tenants", "tenants", record.get("tenant_id"), "id,name,email,status,is_archived", lambda item: str(item.get("name") or item.get("email") or "Tenant")),
        ):
            if related_id:
                add_group(title, [add_linked_record(title, related_section, table, related_id, fields, label)])
        if str(record.get("status") or "").casefold() == "pending" and not getattr(g, "preview_mode", True):
            review_units = [
                unit for unit in fetch_supabase_table("units")
                if _is_available_review_unit(unit)
            ]
    elif section == "expenses":
        if record.get("unit_id"):
            add_group(
                "Unit",
                [add_linked_record(
                    "Unit", "properties", "units", record.get("unit_id"),
                    "id,unit_number,name,title,status,is_archived",
                    lambda item: str(item.get("unit_number") or item.get("name") or item.get("title") or "Unit"),
                )],
            )
    elif section == "documents":
        if record.get("tenant_id"):
            add_group(
                "Tenant",
                [add_linked_record(
                    "Tenant", "tenants", "tenants", record.get("tenant_id"),
                    "id,name,email,status,is_archived",
                    lambda item: str(item.get("name") or item.get("email") or "Tenant"),
                )],
            )
    elif section == "events":
        for title, related_section, table, related_id, fields, label in (
            ("Unit", "properties", "units", record.get("unit_id"),
             "id,unit_number,name,title,status,is_archived",
             lambda item: str(item.get("unit_number") or item.get("name") or item.get("title") or "Unit")),
            ("Tenant", "tenants", "tenants", record.get("tenant_id"),
             "id,name,email,status,is_archived",
             lambda item: str(item.get("name") or item.get("email") or "Tenant")),
            ("Maintenance request", "maintenance", "maintenance_tickets", record.get("ticket_id"),
             "id,title,status,priority",
             lambda item: str(item.get("title") or "Maintenance request")),
        ):
            if related_id:
                add_group(
                    title,
                    [add_linked_record(
                        title, related_section, table, related_id, fields, label
                    )],
                )
    elif section == "rfid-access":
        for title, related_section, table, related_id, fields, label in (
            ("Unit", "properties", "units", record.get("unit_id"),
             "id,unit_number,name,title,status,is_archived",
             lambda item: str(item.get("unit_number") or item.get("name") or item.get("title") or "Unit")),
            ("Tenant", "tenants", "tenants", record.get("tenant_id"),
             "id,name,email,status,is_archived",
             lambda item: str(item.get("name") or item.get("email") or "Tenant")),
        ):
            if related_id:
                add_group(
                    title,
                    [add_linked_record(
                        title, related_section, table, related_id, fields, label
                    )],
                )
    elif section == "notifications":
        entity_types = {
            "unit": ("properties", "units", "id,unit_number,name,title,status,is_archived",
                     lambda item: str(item.get("unit_number") or item.get("name") or item.get("title") or "Unit")),
            "units": ("properties", "units", "id,unit_number,name,title,status,is_archived",
                      lambda item: str(item.get("unit_number") or item.get("name") or item.get("title") or "Unit")),
            "tenant": ("tenants", "tenants", "id,name,email,status,is_archived",
                       lambda item: str(item.get("name") or item.get("email") or "Tenant")),
            "tenants": ("tenants", "tenants", "id,name,email,status,is_archived",
                        lambda item: str(item.get("name") or item.get("email") or "Tenant")),
            "payment": ("payments", "payments", "id,reference_number,month,amount,status",
                        lambda item: str(item.get("reference_number") or item.get("month") or "Payment")),
            "payments": ("payments", "payments", "id,reference_number,month,amount,status",
                         lambda item: str(item.get("reference_number") or item.get("month") or "Payment")),
            "maintenance": ("maintenance", "maintenance_tickets", "id,title,status,priority",
                            lambda item: str(item.get("title") or "Maintenance request")),
            "maintenance_ticket": ("maintenance", "maintenance_tickets", "id,title,status,priority",
                                   lambda item: str(item.get("title") or "Maintenance request")),
            "event": ("events", "events", "id,title,date,type,is_completed",
                      lambda item: str(item.get("title") or "Event")),
            "events": ("events", "events", "id,title,date,type,is_completed",
                       lambda item: str(item.get("title") or "Event")),
        }
        related = entity_types.get(str(record.get("entity_type") or "").casefold())
        if related and record.get("entity_id"):
            related_section, table, fields, label = related
            add_group(
                "Related record",
                [add_linked_record(
                    "Related record", related_section, table,
                    record.get("entity_id"), fields, label,
                )],
            )

    edit_url = None
    if section == "landlords" and str(record.get("status") or "").casefold() != "archived":
        edit_url = url_for("landlord_form", landlord_id=record_id)
    elif section == "properties" and record.get("is_archived") is not True:
        edit_url = url_for("property_form", record_id=record_id)
    elif section == "tenants" and record.get("is_archived") is not True:
        edit_url = url_for("tenant_form", record_id=record_id)
    elif section == "superadmins":
        edit_url = url_for("superadmin_form", account_id=record_id)
    elif section == "expenses":
        edit_url = url_for("expense_form", record_id=record_id)
    elif section == "announcements" and record.get("is_archived") is not True:
        edit_url = url_for("announcement_form", record_id=record_id)
    elif section == "settings":
        edit_url = url_for("settings_form", record_id=record_id)
    record_label = (
        record.get("unit_number") or record.get("name") or record.get("title")
        or record.get("reference_number") or record.get("full_name")
        or record.get("display_name") or record.get("email") or record_id
    )
    return render_template(
        "record_detail.html",
        section=section,
        section_title=SECTIONS[section]["title"],
        record=record,
        record_label=record_label,
        unit_photos=_unit_photo_items(record) if section == "properties" else [],
        detail_groups=_detail_groups(section, record),
        related_groups=related_groups,
        edit_url=edit_url,
        review_units=review_units,
        payment_receipt_url=(
            url_for("payment_receipt", record_id=record_id)
            if section == "payments"
            and _is_private_payment_receipt(record, record_id)
            else None
        ),
        can_review_payment=(
            section == "payments"
            and str(record.get("status") or "").strip().casefold()
            in {"pending", "overdue", "pending review"}
            and _is_private_payment_receipt(record, record_id)
            and not getattr(g, "preview_mode", True)
        ),
        can_review=(
            section == "inquiries"
            and str(record.get("status") or "").casefold() == "pending"
            and not getattr(g, "preview_mode", True)
        ),
    )


def _settings_form_values(record: dict[str, Any]) -> dict[str, Any]:
    if record.get("updated_at") and request.form.get("updated_at", "") != str(
        record.get("updated_at")
    ):
        abort(409, description="Settings changed after you opened this page. Reload before saving.")

    values: dict[str, Any] = {}
    for key, label in (
        ("default_late_fee", "Default late fee"),
        ("water_rate", "Water rate"),
        ("electricity_rate", "Electricity rate"),
    ):
        raw_value = request.form.get(key, "").strip()
        try:
            value = float(raw_value)
        except ValueError:
            abort(400, description=f"Enter a valid {label.lower()}.")
        if not math.isfinite(value) or value < 0:
            abort(400, description=f"{label} cannot be negative.")
        values[key] = int(value) if value.is_integer() else value

    due_day = request.form.get("default_due_day", "").strip()
    if not re.fullmatch(r"\d{1,2}", due_day) or not 1 <= int(due_day) <= 31:
        abort(400, description="Due day must be a whole number from 1 to 31.")
    values["default_due_day"] = int(due_day)

    for key in ("auto_late_fee_enabled", "auto_backup_enabled", "dark_mode"):
        value = request.form.get(key, "")
        if value not in {"true", "false"}:
            abort(400, description=f"Choose a valid value for {key.replace('_', ' ')}.")
        values[key] = value == "true"

    for key, label, maximum in (
        ("landlord_name", "Landlord name", 160),
        ("landlord_role", "Landlord role", 100),
        ("landlord_contact", "Landlord contact", 254),
    ):
        value = request.form.get(key, "").strip()
        if len(value) > maximum:
            abort(400, description=f"{label} must be {maximum} characters or fewer.")
        values[key] = value or None
    return values


@app.route("/settings/<record_id>/edit", methods=["GET", "POST"])
def settings_form(record_id: str):
    record = _fetch_supabase_record(
        "settings", record_id, DETAIL_FIELDS["settings"]
    ) if getattr(g, "supabase_config", None) is not None else next(
        (row for row in rows_for("settings") if str(row.get("id")) == record_id),
        None,
    )
    if record is None:
        abort(404)
    if request.method == "GET":
        return render_template("settings_form.html", record=record, form_values={})
    try:
        values = _settings_form_values(record)
    except HTTPException as error:
        return render_template(
            "settings_form.html",
            record=record,
            form_values=dict(request.form),
            form_error=error.description,
        ), error.code or 400

    if getattr(g, "supabase_config", None) is None:
        with get_db() as db:
            updated = {**record, **values, "updated_at": datetime.now(timezone.utc).isoformat()}
            db.execute(
                "UPDATE records SET data = ? WHERE section = ? AND id = ?",
                (_json_dumps(updated), "settings", record_id),
            )
    else:
        query = {"id": f"eq.{record_id}", "select": "id"}
        if record.get("updated_at"):
            query["updated_at"] = f"eq.{record.get('updated_at')}"
        try:
            result = supabase_backend.api_request(
                g.supabase_config,
                g.authenticated["access_token"],
                "settings",
                method="PATCH",
                query=query,
                body=values,
                prefer="return=representation",
            )
        except supabase_backend.SupabaseRequestError as error:
            app.logger.warning(
                "Settings update failed with status %s and code %s.",
                error.status,
                error.code or "unknown",
            )
            return render_template(
                "settings_form.html",
                record=record,
                form_values=dict(request.form),
                form_error=error.user_message or "Settings could not be saved. Try again.",
            ), error.status if 400 <= error.status < 500 else 503
        if not result:
            return render_template(
                "settings_form.html",
                record=record,
                form_values=dict(request.form),
                form_error="Settings changed or could not be saved. Reload and try again.",
            ), 409
    flash("Settings saved.", "success")
    return redirect(url_for("record_detail", section="settings", record_id=record_id))


@app.post("/inquiries/<record_id>/review")
def review_inquiry(record_id: str):
    try:
        record_id = str(UUID(record_id))
    except ValueError:
        abort(404)
    if getattr(g, "supabase_config", None) is None:
        abort(503, description="Inquiry review requires a live Supabase connection.")
    inquiry = _fetch_supabase_record(
        "tenant_inquiries", record_id, DETAIL_FIELDS["inquiries"]
    )
    if inquiry is None:
        abort(404)
    if str(inquiry.get("status") or "").casefold() != "pending":
        abort(409, description="Only pending inquiries can be reviewed.")
    decision = request.form.get("decision", "").strip()
    if decision not in {"approve", "decline"}:
        flash("Choose Approve or Decline before submitting the review.", "error")
        return redirect(
            url_for("record_detail", section="inquiries", record_id=record_id)
        )
    assigned_unit_id = request.form.get("assigned_unit_id", "").strip() or None
    internal_note = request.form.get("internal_note", "").strip()
    if len(internal_note) > 1000:
        abort(400, description="The internal note must be 1,000 characters or fewer.")
    if assigned_unit_id:
        try:
            assigned_unit_id = str(UUID(assigned_unit_id))
        except ValueError:
            flash("Choose an available unit from the list.", "error")
            return redirect(
                url_for("record_detail", section="inquiries", record_id=record_id)
            )
        assigned_unit = _fetch_supabase_record(
            "units", assigned_unit_id,
            "id,is_archived,status,tenant_id,unit_number,name,title",
        )
        if assigned_unit is None or not _is_available_review_unit(assigned_unit):
            flash(
                "That unit is no longer available. Choose a vacant unit and try again.",
                "error",
            )
            return redirect(
                url_for("record_detail", section="inquiries", record_id=record_id)
            )
    supabase_backend.rpc_request(
        g.supabase_config,
        g.authenticated["access_token"],
        "review_tenant_inquiry",
        {
            "p_inquiry_id": record_id,
            "p_decision": decision,
            "p_assigned_unit_id": assigned_unit_id,
            "p_internal_note": internal_note,
        },
    )
    flash(
        "Inquiry approved through the existing review workflow."
        if decision == "approve"
        else "Inquiry declined through the existing review workflow.",
        "success",
    )
    return redirect(url_for("record_detail", section="inquiries", record_id=record_id))


@app.get("/favicon.ico")
def favicon():
    return redirect(url_for("static", filename="favicon.svg"))


@app.get("/<section>/export.csv")
def export_csv(section: str):
    if section not in SECTIONS:
        abort(404)
    rows, _, _ = filtered_rows(section)
    rows, _, _ = sorted_rows(section, rows)
    columns = SECTIONS[section]["columns"]
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow([label for _, label in columns])
    for row in rows:
        writer.writerow([_safe_csv_cell(row.get(key, "")) for key, _ in columns])
    response = make_response("\ufeff" + output.getvalue())
    response.headers["Content-Type"] = "text/csv; charset=utf-8"
    response.headers["Content-Disposition"] = f"attachment; filename={section}.csv"
    return response


@app.get("/<section>/export.xlsx")
def export_excel(section: str):
    if section not in SECTIONS:
        abort(404)
    rows, _, _ = filtered_rows(section)
    rows, _, _ = sorted_rows(section, rows)
    columns = SECTIONS[section]["columns"]
    workbook = Workbook()
    worksheet = workbook.active
    worksheet.title = re.sub(
        r"[\[\]:*?/\\]", " ", SECTIONS[section]["title"]
    ).strip()[:31] or "Records"
    worksheet.append([label for _, label in columns])
    for cell in worksheet[1]:
        cell.font = Font(bold=True)
    for row in rows:
        worksheet.append(
            [_safe_excel_cell(row.get(key, "")) for key, _ in columns]
        )
    worksheet.freeze_panes = "A2"
    worksheet.auto_filter.ref = worksheet.dimensions

    output = io.BytesIO()
    workbook.save(output)
    response = make_response(output.getvalue())
    response.headers["Content-Type"] = (
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )
    response.headers["Content-Disposition"] = f"attachment; filename={section}.xlsx"
    return response


def _safe_csv_cell(value: Any) -> Any:
    if isinstance(value, str) and value.lstrip(" \t\r\n").startswith(
        ("=", "+", "-", "@")
    ):
        return "'" + value
    return value


def _safe_excel_cell(value: Any) -> Any:
    if isinstance(value, (dict, list, tuple)):
        value = json.dumps(value, ensure_ascii=False, default=str)
    if isinstance(value, str):
        return _safe_csv_cell(value)
    if isinstance(value, Decimal):
        return float(value)
    return value


ENTITY_FORM_FIELDS = {
    "properties": [
        {"key": "unit_number", "label": "Unit number", "required": True, "min_length": 2, "max_length": 100},
        {"key": "name", "label": "Property name", "required": True, "min_length": 2, "max_length": 160},
        {"key": "location", "label": "Location", "max_length": 240},
        {"key": "landlord_id", "label": "Landlord", "kind": "select", "max_length": 80},
        {"key": "monthly_rent", "label": "Monthly rent", "kind": "number", "min": "0.01", "step": "0.01", "help": "Enter the monthly amount in PHP, up to two decimal places."},
        {"key": "status", "label": "Status", "required": True, "kind": "select", "options": ["Occupied", "Vacant", "Reserved", "Inactive"]},
    ],
    "tenants": [
        {"key": "name", "label": "Full name", "required": True, "min_length": 2, "max_length": 100},
        {"key": "email", "label": "Email", "kind": "email", "max_length": 254},
        {"key": "phone", "label": "Phone", "kind": "tel", "max_length": 40},
        {"key": "unit_id", "label": "Property", "kind": "select", "max_length": 80},
        {"key": "landlord_id", "label": "Landlord", "kind": "select", "max_length": 80},
        {"key": "status", "label": "Status", "required": True, "kind": "select", "options": ["Active", "Former"]},
        {"key": "monthly_rent", "label": "Monthly rent", "kind": "number", "min": "0.01", "step": "0.01", "help": "Enter the monthly amount in PHP, up to two decimal places."},
        {"key": "lease_start", "label": "Lease starts", "kind": "date", "min_date": "2025-01-01", "help": "Select a date on or after January 1, 2025."},
        {"key": "lease_end", "label": "Lease ends", "kind": "date", "min_date": "2025-01-01", "help": "Select a date on or after January 1, 2025."},
        {"key": "balance", "label": "Balance", "kind": "number", "min": "0", "step": "0.01", "help": "Enter the outstanding balance in PHP, up to two decimal places."},
    ],
    "expenses": [
        {"key": "title", "label": "Expense", "required": True, "min_length": 2, "max_length": 160},
        {"key": "category", "label": "Category", "required": True, "min_length": 2, "max_length": 80},
        {"key": "amount", "label": "Amount", "required": True, "kind": "number", "min": "0.01", "step": "0.01", "help": "Enter the expense amount in PHP, up to two decimal places."},
        {"key": "date", "label": "Date", "required": True, "kind": "date", "min_date": "2025-01-01", "help": "Select a date on or after January 1, 2025."},
        {"key": "unit_number", "label": "Unit number", "max_length": 100},
        {"key": "notes", "label": "Notes", "kind": "textarea", "max_length": 2000},
    ],
    "announcements": [
        {"key": "title", "label": "Title", "required": True, "min_length": 2, "max_length": 160},
        {"key": "message", "label": "Message", "required": True, "kind": "textarea", "max_length": 5000},
        {"key": "category", "label": "Category", "max_length": 80},
        {"key": "is_important", "label": "Mark as important", "kind": "boolean"},
    ],
}


def _find_entity(section: str, record_id: str) -> dict[str, Any] | None:
    if section not in ENTITY_TABLES:
        abort(404)
    if getattr(g, "supabase_config", None) is None:
        return next(
            (row for row in rows_for(section) if str(row.get("id")) == record_id),
            None,
        )
    result = supabase_backend.api_request(
        g.supabase_config,
        g.authenticated["access_token"],
        ENTITY_TABLES[section],
        query={"select": ENTITY_FIELDS[section], "id": f"eq.{record_id}", "limit": "1"},
    )
    return dict(result[0]) if result else None


def _unit_photo_object_path(record: dict[str, Any], reference: str) -> str:
    config = getattr(g, "supabase_config", None)
    try:
        if config is None:
            raise ValueError("Supabase is not configured.")
        path = supabase_backend.unit_media_object_path(config, reference)
    except ValueError:
        abort(409, description="This unit has an unsupported photo path. Contact support.")
    unit_id = str(record.get("id") or "")
    if path.split("/")[1] != unit_id:
        abort(409, description="This unit has a photo assigned to a different unit. Contact support.")
    return path


def _unit_photo_paths(record: dict[str, Any]) -> list[str]:
    raw_images = record.get("images")
    if raw_images is not None and not isinstance(raw_images, list):
        abort(409, description="This unit has an unsupported photo list. Contact support.")
    candidates = list(raw_images or [])
    if record.get("image_url"):
        candidates.append(record["image_url"])
    paths: list[str] = []
    for candidate in candidates:
        if not isinstance(candidate, str):
            abort(409, description="This unit has an unsupported photo path. Contact support.")
        path = _unit_photo_object_path(record, candidate)
        if path not in paths:
            paths.append(path)
    return paths


def _unit_photo_items(record: dict[str, Any]) -> list[dict[str, Any]]:
    config = getattr(g, "supabase_config", None)
    if config is None:
        return []
    cover_path = (
        _unit_photo_object_path(record, record["image_url"])
        if record.get("image_url")
        else None
    )
    return [
        {
            "path": path,
            "url": supabase_backend.public_unit_media_url(config, path),
            "is_cover": path == cover_path,
        }
        for path in _unit_photo_paths(record)
    ]


def _unit_photo_reference(object_path: str) -> str:
    config = getattr(g, "supabase_config", None)
    if config is None:
        return object_path
    return supabase_backend.public_unit_media_url(config, object_path)


def _read_unit_photo_uploads() -> list[tuple[bytes, str, str]]:
    uploads = [
        item
        for item in request.files.getlist("unit_images")
        if item and item.filename
    ]
    if len(uploads) > UNIT_PHOTO_MAX_FILES:
        abort(400, description=f"Choose no more than {UNIT_PHOTO_MAX_FILES} unit photos.")

    total_bytes = 0
    photos: list[tuple[bytes, str, str]] = []
    signatures = (
        (lambda data: data.startswith(b"\xff\xd8\xff"), "jpg", "image/jpeg"),
        (lambda data: data.startswith(b"\x89PNG\r\n\x1a\n"), "png", "image/png"),
        (
            lambda data: (
                len(data) >= 12
                and data[:4] == b"RIFF"
                and data[8:12] == b"WEBP"
            ),
            "webp",
            "image/webp",
        ),
    )
    for upload in uploads:
        content = upload.stream.read(UNIT_PHOTO_MAX_FILE_BYTES + 1)
        if not content:
            abort(400, description="Choose a non-empty unit photo.")
        if len(content) > UNIT_PHOTO_MAX_FILE_BYTES:
            abort(400, description="Each unit photo must be 5 MB or smaller.")
        total_bytes += len(content)
        if total_bytes > UNIT_PHOTO_MAX_TOTAL_BYTES:
            abort(400, description="Unit photos must total 20 MB or less.")
        detected = next(
            (
                (extension, content_type)
                for matches, extension, content_type in signatures
                if matches(content)
            ),
            None,
        )
        if detected is None:
            abort(400, description="Use a JPEG, PNG, or WebP image for unit photos.")
        extension, content_type = detected
        photos.append((content, extension, content_type))
    return photos


def _cleanup_uploaded_unit_photos(object_paths: list[str]) -> None:
    config = getattr(g, "supabase_config", None)
    auth = getattr(g, "authenticated", None)
    if config is None or auth is None:
        return
    for object_path in object_paths:
        try:
            supabase_backend.delete_unit_media(
                config, auth["access_token"], object_path
            )
        except supabase_backend.SupabaseRequestError as error:
            app.logger.warning(
                "Unit photo cleanup failed with status %s and code %s.",
                error.status,
                error.code or "unknown",
            )


def _entity_form_values(section: str, record: dict[str, Any] | None = None) -> dict[str, Any]:
    values: dict[str, Any] = {}
    for field in ENTITY_FORM_FIELDS[section]:
        key = field["key"]
        raw_value = request.form.get(key, "")
        value = raw_value.strip()
        if field.get("kind") == "textarea":
            value = value
        elif field.get("kind") not in {"number", "date", "email", "tel", "select", "boolean"}:
            value = _normalized_text(value)
        if field.get("required") and not value:
            abort(400, description=f"{field['label']} is required.")
        if len(value) > field.get("max_length", 500):
            abort(400, description=f"{field['label']} is too long.")
        if value and len(value) < field.get("min_length", 0):
            abort(400, description=f"{field['label']} is too short.")
        if (
            field.get("options")
            and value
            and value not in field["options"]
            and value != (record or {}).get(key)
        ):
            abort(400, description=f"Choose a valid {field['label'].lower()}.")
        if field.get("kind") == "boolean":
            if value not in {"true", "false", ""}:
                abort(400, description=f"Choose a valid {field['label'].lower()} value.")
            values[key] = value == "true"
            continue
        if key == "email":
            value = value.lower()
            if value and not _valid_contact_email(value):
                abort(400, description="Enter a valid, non-disposable email address.")
            values[key] = value or None
            continue
        if field.get("kind") == "tel":
            normalized_phone = _normalize_ph_mobile(value)
            if normalized_phone is None:
                abort(
                    400,
                    description="Enter a Philippine mobile number starting with 09 or +639.",
                )
            values[key] = normalized_phone or None
            continue
        if (
            value
            and field.get("kind") not in {"textarea", "select"}
            and re.fullmatch(r"(.)\1{3,}", value, re.IGNORECASE)
        ):
            abort(400, description=f"Enter a valid {field['label'].lower()}.")
        if section == "tenants" and key == "name" and value and not _valid_person_name(value):
            abort(
                400,
                description="Name may contain letters, spaces, periods, hyphens, and apostrophes only.",
            )
        if field.get("kind") == "number":
            if not value:
                values[key] = None
                continue
            try:
                number = Decimal(value)
            except InvalidOperation:
                abort(400, description=f"Enter a valid {field['label'].lower()}.")
            if not number.is_finite() or number < 0:
                abort(400, description=f"{field['label']} cannot be negative.")
            if number.as_tuple().exponent < -2:
                abort(400, description=f"{field['label']} may have at most two decimal places.")
            if number < Decimal(field.get("min", "0")):
                abort(400, description=f"{field['label']} must be at least {field['min']}.")
            values[key] = int(number) if number == number.to_integral_value() else float(number)
            continue
        if field.get("kind") == "date" and value:
            if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
                abort(400, description=f"Enter a valid {field['label'].lower()} date.")
            try:
                selected_date = date.fromisoformat(value)
            except ValueError:
                abort(400, description=f"Enter a valid {field['label'].lower()} date.")
            if selected_date < MIN_ENTRY_DATE and value != str(
                (record or {}).get(key) or ""
            ):
                abort(400, description=f"{field['label']} must be on or after 2025-01-01.")
        values[key] = value.lower() if key == "email" and value else value or None
    for key, section_name, label in (
        ("landlord_id", "landlords", "landlord"),
        ("unit_id", "properties", "property"),
    ):
        value = values.get(key)
        if not value:
            continue
        if record and str(record.get(key) or "") == str(value):
            continue
        allowed = rows_for(section_name)
        match = next(
            (
                row for row in allowed
                if str(row.get("uid") or row.get("id") or "") == str(value)
            ),
            None,
        )
        if match is None or match.get("is_archived") is True or str(
            match.get("status", "")
        ).casefold() == "archived":
            abort(400, description=f"Choose an active {label} from the list.")
    start = values.get("lease_start")
    end = values.get("lease_end")
    if start and end and end < start:
        abort(400, description="Lease end must be on or after the lease start.")
    return values


def _render_entity_form(
    section: str,
    record: dict[str, Any] | None,
    status: int = 200,
    form_values: dict[str, str] | None = None,
    form_error: str | None = None,
):
    submitted_values = form_values or {}
    landlords = rows_for("landlords") if section in {"properties", "tenants"} else []
    properties = rows_for("properties") if section == "tenants" else []
    return render_template(
        "entity_form.html",
        section=section,
        title={
            "properties": "property",
            "tenants": "tenant",
            "expenses": "expense",
            "announcements": "announcement",
        }[section],
        fields=ENTITY_FORM_FIELDS[section],
        record=record,
        landlords=landlords,
        properties=properties,
        unit_photos=_unit_photo_items(record) if section == "properties" and record else [],
        can_manage_unit_photos=getattr(g, "supabase_config", None) is not None,
        form_values=submitted_values,
        form_error=form_error,
        new_record_id=(
            submitted_values.get("record_id") or str(uuid4())
            if record is None
            else ""
        ),
    ), status


@app.route("/properties/new", methods=["GET", "POST"])
@app.route("/properties/<record_id>/edit", methods=["GET", "POST"])
def property_form(record_id: str | None = None):
    return entity_form("properties", record_id)


@app.route("/tenants/new", methods=["GET", "POST"])
@app.route("/tenants/<record_id>/edit", methods=["GET", "POST"])
def tenant_form(record_id: str | None = None):
    return entity_form("tenants", record_id)


@app.route("/expenses/new", methods=["GET", "POST"])
@app.route("/expenses/<record_id>/edit", methods=["GET", "POST"])
def expense_form(record_id: str | None = None):
    return entity_form("expenses", record_id)


@app.route("/announcements/new", methods=["GET", "POST"])
@app.route("/announcements/<record_id>/edit", methods=["GET", "POST"])
def announcement_form(record_id: str | None = None):
    return entity_form("announcements", record_id)


def entity_form(section: str, record_id: str | None = None):
    record = _find_entity(section, record_id) if record_id is not None else None
    if record_id is not None and record is None:
        abort(404)
    if record and record.get("is_archived") is True:
        abort(409, description="Archived records are read-only.")
    if request.method == "GET":
        return _render_entity_form(section, record)

    uploaded_photo_paths: list[str] = []
    removed_photo_paths: list[str] = []
    if record is not None and g.supabase_config is not None:
        version = request.form.get("updated_at", "")
        current_version = str(record.get("updated_at") or "")
        if current_version and version != current_version:
            abort(409, description="This record changed after you opened it. Reload before saving.")
    try:
        values = _entity_form_values(section, record)
        if record is None:
            record_id = request.form.get("record_id", "").strip() or str(uuid4())
            try:
                UUID(record_id)
            except ValueError:
                abort(400, description="The record identifier is invalid.")
            values["id"] = record_id
        if section == "properties":
            photo_uploads = _read_unit_photo_uploads()
            requested_removals = request.form.getlist("remove_images")
            requested_cover = request.form.get("cover_image", "")
            if (photo_uploads or requested_removals) and g.supabase_config is None:
                abort(503, description="Unit photo management requires a live Supabase connection.")
            existing_photo_paths = _unit_photo_paths(record) if record else []
            if any(path not in existing_photo_paths for path in requested_removals):
                abort(400, description="Choose photos that belong to this unit.")
            if requested_cover and requested_cover not in existing_photo_paths:
                abort(400, description="Choose a cover photo that belongs to this unit.")
            current_cover_path = (
                _unit_photo_object_path(record, record["image_url"])
                if record and record.get("image_url")
                else None
            )
            removed_photo_paths = list(dict.fromkeys(requested_removals))
            remaining_photo_paths = [
                path for path in existing_photo_paths if path not in removed_photo_paths
            ]
            cover_changed = bool(
                requested_cover
                and requested_cover != current_cover_path
            )
            if record is None or photo_uploads or removed_photo_paths or cover_changed:
                photo_paths = list(remaining_photo_paths)
                if photo_uploads:
                    for content, extension, content_type in photo_uploads:
                        object_path = f"units/{record_id}/{uuid4().hex}.{extension}"
                        uploaded_photo_paths.append(object_path)
                        try:
                            supabase_backend.upload_unit_media(
                                g.supabase_config,
                                g.authenticated["access_token"],
                                object_path,
                                content,
                                content_type,
                            )
                        except supabase_backend.SupabaseRequestError:
                            _cleanup_uploaded_unit_photos(uploaded_photo_paths)
                            raise
                    photo_paths.extend(uploaded_photo_paths)
                values["images"] = [
                    _unit_photo_reference(path) for path in photo_paths
                ]
                if requested_cover in photo_paths:
                    cover_path = requested_cover
                elif current_cover_path in photo_paths:
                    cover_path = current_cover_path
                else:
                    cover_path = photo_paths[0] if photo_paths else None
                values["image_url"] = (
                    _unit_photo_reference(cover_path) if cover_path else None
                )
    except HTTPException as error:
        _cleanup_uploaded_unit_photos(uploaded_photo_paths)
        if request.headers.get("X-Ramp-Form-Request") == "1":
            return jsonify(error=error.description), error.code or 400
        return _render_entity_form(
            section,
            record,
            error.code or 400,
            dict(request.form),
            error.description,
        )
    is_preview = g.supabase_config is None
    if section == "properties":
        values.pop("monthly_rent", None) if values.get("monthly_rent") is None else None
        if values.get("monthly_rent") is not None:
            values["rent"] = values["monthly_rent"]
    elif section == "tenants":
        values.pop("monthly_rent", None) if values.get("monthly_rent") is None else None
    elif section == "expenses":
        if record is None:
            profile = getattr(g, "current_user", None) or {}
            values["recorded_by"] = (
                profile.get("display_name") or profile.get("email") or "Administrator"
            )
        else:
            values["recorded_by"] = record.get("recorded_by")
    elif section == "announcements":
        if record is None:
            profile = getattr(g, "current_user", None) or {}
            values["author"] = (
                profile.get("display_name") or profile.get("email") or "Administrator"
            )
            values["is_archived"] = False
        else:
            values["author"] = record.get("author")
            values["is_archived"] = record.get("is_archived") is True

    if is_preview:
        with get_db() as db:
            if record is None:
                db.execute(
                    "INSERT INTO records (section, id, data) VALUES (?, ?, ?)",
                    (section, record_id, _json_dumps(values)),
                )
            else:
                current = {**record, **values}
                db.execute(
                    "UPDATE records SET data = ? WHERE section = ? AND id = ?",
                    (_json_dumps(current), section, record_id),
                )
    else:
        if record is None and g.offline_replay:
            existing = _find_entity(section, record_id)
            if existing is not None:
                if all(existing.get(key) == value for key, value in values.items() if key != "id"):
                    flash("Record was already synchronized.", "success")
                    return redirect(url_for("records_page", section=section))
                abort(409, description="A record with this identifier already exists.")
        if (
            section == "announcements"
            and record is not None
            and record.get("is_archived") is True
        ):
            abort(409, description="Archived announcements are read-only.")
        try:
            result = supabase_backend.api_request(
                g.supabase_config,
                g.authenticated["access_token"],
                ENTITY_TABLES[section],
                method="POST" if record is None else "PATCH",
                query=(
                    {"select": "id"}
                    if record is None
                    else {
                        "id": f"eq.{record_id}",
                        **(
                            {"updated_at": f"eq.{record.get('updated_at')}"}
                            if record.get("updated_at")
                            else {}
                        ),
                        "select": "id",
                    }
                ),
                body=values,
                prefer="return=representation",
            )
        except supabase_backend.SupabaseRequestError:
            _cleanup_uploaded_unit_photos(uploaded_photo_paths)
            raise
        if not result:
            _cleanup_uploaded_unit_photos(uploaded_photo_paths)
            abort(409, description="The record changed or could not be saved. Refresh and try again.")
    photo_delete_failed = False
    if removed_photo_paths and not is_preview:
        for object_path in removed_photo_paths:
            try:
                supabase_backend.delete_unit_media(
                    g.supabase_config,
                    g.authenticated["access_token"],
                    object_path,
                )
            except supabase_backend.SupabaseRequestError as error:
                app.logger.warning(
                    "Removed unit photo could not be deleted from Storage "
                    "(status %s, code %s).",
                    error.status,
                    error.code or "unknown",
                )
                photo_delete_failed = True
    if photo_delete_failed:
        flash(
            "Unit changes were saved, but one or more removed photo files could not be deleted from Storage. Contact support.",
            "error",
        )
    else:
        flash(f"{SECTIONS[section]['title'].rstrip('s')} saved.", "success")
    return redirect(url_for("records_page", section=section))


@app.post("/properties/<record_id>/archive")
def archive_property(record_id: str):
    return archive_entity("properties", record_id)


@app.post("/tenants/<record_id>/archive")
def archive_tenant(record_id: str):
    return archive_entity("tenants", record_id)


@app.post("/announcements/<record_id>/archive")
def archive_announcement(record_id: str):
    if g.supabase_config is None:
        record = _find_entity("announcements", record_id)
        if record is None:
            abort(404)
        if record.get("is_archived") is True:
            abort(409, description="This announcement is already archived.")
        record["is_archived"] = True
        with get_db() as db:
            db.execute(
                "UPDATE records SET data = ? WHERE section = ? AND id = ?",
                (_json_dumps(record), "announcements", record_id),
            )
    else:
        record = _find_entity("announcements", record_id)
        if record is None:
            abort(404)
        if record.get("is_archived") is True:
            abort(409, description="This announcement is already archived.")
        result = supabase_backend.api_request(
            g.supabase_config,
            g.authenticated["access_token"],
            "announcements",
            method="PATCH",
            query={
                "id": f"eq.{record_id}",
                "is_archived": "eq.false",
                "select": "id",
            },
            body={"is_archived": True},
            prefer="return=representation",
        )
        if not result:
            abort(409, description="The announcement changed or could not be archived.")
    flash("Announcement archived. Its history remains available.", "success")
    return redirect(url_for("records_page", section="announcements"))


def archive_entity(section: str, record_id: str):
    record = _find_entity(section, record_id)
    if record is None:
        abort(404)
    if record.get("is_archived") is True:
        abort(409, description="This record is already archived.")
    expected_version = request.form.get("updated_at", "")
    current_version = str(record.get("updated_at") or "")
    if current_version and expected_version != current_version:
        abort(409, description="This record changed while it was offline. Reload before retrying.")
    if g.supabase_config is None:
        record["is_archived"] = True
        record["status"] = "Archived"
        with get_db() as db:
            db.execute(
                "UPDATE records SET data = ? WHERE section = ? AND id = ?",
                (_json_dumps(record), section, record_id),
            )
    else:
        query = {"id": f"eq.{record_id}", "is_archived": "eq.false", "select": "id"}
        if record.get("updated_at"):
            query["updated_at"] = f"eq.{record.get('updated_at')}"
        result = supabase_backend.api_request(
            g.supabase_config,
            g.authenticated["access_token"],
            ENTITY_TABLES[section],
            method="PATCH",
            query=query,
            body={"is_archived": True},
            prefer="return=representation",
        )
        if not result:
            abort(409, description="The record changed or could not be archived. Refresh and try again.")
    flash("Record archived. Its history remains unchanged.", "success")
    return redirect(url_for("records_page", section=section))


@app.route("/superadmins/new", methods=["GET", "POST"])
@app.route("/superadmins/<account_id>/edit", methods=["GET", "POST"])
def superadmin_form(account_id: str | None = None):
    if g.supabase_config is None:
        abort(503, description="Superadmin accounts require a live Supabase connection.")
    account = None
    if account_id:
        account = next(
            (row for row in rows_for("superadmins") if str(row.get("id")) == account_id),
            None,
        )
        if account is None:
            abort(404)
    if request.method == "POST":
        name = _normalized_text(
            request.form.get("display_name", ""),
        )
        if (
            len(name) < 2
            or len(name) > 100
            or not _valid_person_name(name)
        ):
            flash("Enter a valid display name (2 to 100 characters).", "error")
            return render_template(
                "superadmin_form.html",
                account=account,
                form_values=dict(request.form),
            ), 400
        if account is None:
            email = request.form.get("email", "").strip().lower()
            if not _valid_contact_email(email):
                flash(
                    "Enter a valid email address from a non-disposable domain.",
                    "error",
                )
                return render_template(
                    "superadmin_form.html",
                    account=None,
                    form_values=dict(request.form),
                ), 400
            try:
                supabase_backend.invoke_function(
                    g.supabase_config,
                    g.authenticated["access_token"],
                    "invite-admin-account",
                    {"email": email, "display_name": name, "role": "super_admin"},
                )
            except supabase_backend.SupabaseRequestError as error:
                app.logger.warning(
                    "Superadmin invitation failed with status %s and code %s.",
                    error.status,
                    error.code or "unknown",
                )
                flash(
                    error.user_message or "The superadmin invitation could not be sent.",
                    "error",
                )
                return render_template(
                    "superadmin_form.html",
                    account=None,
                    form_values=dict(request.form),
                ), error.status if 400 <= error.status < 500 else 503
            flash("Superadmin invitation sent. Access remains disabled until approved.", "success")
        else:
            version = request.form.get("updated_at", "")
            current_version = str(account.get("updated_at") or "")
            if current_version and version != current_version:
                abort(409, description="This superadmin profile changed while it was offline.")
            result = supabase_backend.api_request(
                g.supabase_config,
                g.authenticated["access_token"],
                "users",
                method="PATCH",
                query={
                    "id": f"eq.{account_id}",
                    "role": "eq.super_admin",
                    **({"updated_at": f"eq.{account.get('updated_at')}"} if account.get("updated_at") else {}),
                    "select": "id",
                },
                body={"display_name": name},
                prefer="return=representation",
            )
            if not result:
                abort(409, description="The superadmin profile could not be updated.")
            flash("Superadmin profile updated.", "success")
        return redirect(url_for("records_page", section="superadmins"))
    return render_template("superadmin_form.html", account=account, form_values={})


@app.post("/superadmins/<account_id>/approval")
def update_superadmin_approval(account_id: str):
    if g.supabase_config is None:
        abort(503, description="Superadmin accounts require a live Supabase connection.")
    account = next(
        (row for row in rows_for("superadmins") if str(row.get("id")) == account_id),
        None,
    )
    if account is None:
        abort(404)
    approved = request.form.get("approved") == "true"
    expected_version = request.form.get("updated_at", "")
    current_version = str(account.get("updated_at") or "")
    if current_version and expected_version != current_version:
        abort(409, description="This superadmin account changed while it was offline.")
    if not approved and account.get("uid") == g.current_user.get("uid"):
        abort(409, description="You cannot disable your own superadmin account.")
    if not approved:
        active = [
            row for row in rows_for("superadmins")
            if row.get("is_approved") is True
        ]
        if len(active) <= 1:
            abort(409, description="At least one approved superadmin must remain.")
    result = supabase_backend.api_request(
        g.supabase_config,
        g.authenticated["access_token"],
        "users",
        method="PATCH",
        query={
            "id": f"eq.{account_id}",
            "role": "eq.super_admin",
            **({"updated_at": f"eq.{account.get('updated_at')}"} if account.get("updated_at") else {}),
            "select": "id",
        },
        body={"is_approved": approved},
        prefer="return=representation",
    )
    if not result:
        abort(409, description="The account approval could not be updated.")
    flash("Superadmin access updated.", "success")
    return redirect(url_for("records_page", section="superadmins"))


@app.post("/tenants/<tenant_id>/invite")
def invite_tenant(tenant_id: str):
    if g.supabase_config is None:
        abort(503, description="Tenant invitations require a live Supabase connection.")
    tenant = _find_entity("tenants", tenant_id)
    if tenant is None:
        abort(404)
    if tenant.get("is_archived") is True:
        abort(409, description="Archived tenant records cannot receive invitations.")
    email = str(tenant.get("email") or "").strip().lower()
    if not email:
        abort(400, description="Add an email address before inviting this tenant.")
    try:
        supabase_backend.invoke_function(
            g.supabase_config,
            g.authenticated["access_token"],
            "invite-admin-account",
            {
                "email": email,
                "display_name": tenant.get("name") or email.split("@")[0],
                "role": "tenant",
                "tenant_id": tenant_id,
                "phone": tenant.get("phone") or "",
            },
        )
    except supabase_backend.SupabaseRequestError as error:
        app.logger.warning(
            "Tenant invitation failed with status %s and code %s.",
            error.status,
            error.code or "unknown",
        )
        flash(error.user_message or "The tenant invitation could not be sent.", "error")
        return redirect(url_for("records_page", section="tenants"))
    flash("Tenant invitation sent.", "success")
    return redirect(url_for("records_page", section="tenants"))


@app.route("/landlords/new", methods=["GET", "POST"])
@app.route("/landlords/<landlord_id>/edit", methods=["GET", "POST"])
def landlord_form(landlord_id: str | None = None):
    landlord = None
    if landlord_id is not None:
        landlord = _find_landlord(landlord_id)
        if landlord is None:
            abort(404)
        if str(landlord.get("status", "")).casefold() == "archived":
            abort(409, description="Archived landlord records are read-only.")
    if request.method == "POST":
        name = _normalized_text(request.form.get("name", ""))
        company = _normalized_text(request.form.get("company", ""))
        email = request.form.get("email", "").strip().lower()
        phone_input = request.form.get("phone", "").strip()
        phone = _normalize_ph_mobile(phone_input)
        if (
            len(name) < 2 or len(name) > 100 or not _valid_person_name(name)
            or len(company) < 2 or len(company) > 120
            or len(email) > 254 or len(phone_input) > 40 or phone is None
        ):
            flash(
                "Enter a valid name, company, email, and Philippine mobile number.",
                "error",
            )
            return render_template(
                "landlord_form.html",
                landlord=landlord,
                form_values=dict(request.form),
            ), 400
        if landlord is None and not _valid_contact_email(email):
            flash(
                "Enter a valid email address from a non-disposable domain.",
                "error",
            )
            return render_template(
                "landlord_form.html",
                landlord=landlord,
                form_values=dict(request.form),
            ), 400
        if g.supabase_config is not None:
            if landlord is None:
                try:
                    supabase_backend.invoke_function(
                        g.supabase_config,
                        g.authenticated["access_token"],
                        "invite-admin-account",
                        {
                            "email": email,
                            "display_name": name,
                            "role": "landlord",
                            "company_name": company,
                            "phone": phone,
                        },
                    )
                except supabase_backend.SupabaseRequestError as error:
                    app.logger.warning(
                        "Landlord invitation failed with status %s and code %s.",
                        error.status,
                        error.code or "unknown",
                    )
                    flash(
                        error.user_message
                        or "The invitation could not be sent. Check the Supabase invitation function.",
                        "error",
                    )
                    return render_template(
                        "landlord_form.html",
                        landlord=None,
                        form_values=dict(request.form),
                    ), error.status if 400 <= error.status < 500 else 503
                flash("Landlord invitation sent. They will receive an account activation email.", "success")
            else:
                version = request.form.get("updated_at", "")
                current_version = str(landlord.get("updated_at") or "")
                if current_version and version != current_version:
                    abort(409, description="This landlord profile changed while it was offline.")
                result = supabase_backend.api_request(
                    g.supabase_config,
                    g.authenticated["access_token"],
                    "landlords",
                    method="PATCH",
                    query={
                        "uid": f"eq.{landlord['uid']}",
                        **({"updated_at": f"eq.{landlord.get('updated_at')}"} if landlord.get("updated_at") else {}),
                        "select": "id",
                    },
                    body={"name": name, "company_name": company, "phone": phone or ""},
                    prefer="return=representation",
                )
                if not result:
                    abort(409, description="The landlord could not be updated. Check access policies and refresh.")
                flash("Landlord profile updated.", "success")
            return redirect(url_for("records_page", section="landlords"))
        try:
            with get_db() as db:
                if landlord is None:
                    db.execute(
                        """INSERT INTO landlords
                           (name, company, email, phone, status, created_at)
                           VALUES (?, ?, ?, ?, 'Invited', ?)""",
                        (name, company, email, phone or "", date.today().isoformat()),
                    )
                else:
                    db.execute(
                        """UPDATE landlords SET name = ?, company = ?, phone = ?
                           WHERE id = ?""",
                        (name, company, phone or "", landlord_id),
                    )
        except sqlite3.IntegrityError:
            flash("That email address is already assigned to a landlord.", "error")
            return render_template(
                "landlord_form.html",
                landlord=landlord,
                form_values=dict(request.form),
            ), 400
        flash("Landlord saved to the local preview.", "success")
        return redirect(url_for("records_page", section="landlords"))
    return render_template("landlord_form.html", landlord=landlord, form_values={})


def _find_landlord(landlord_id: str) -> dict[str, Any] | None:
    if g.supabase_config is not None:
        if not re.fullmatch(r"[A-Za-z0-9_-]+", landlord_id):
            return None
        matches = supabase_backend.api_request(
            g.supabase_config,
            g.authenticated["access_token"],
            "landlords",
            query={
                "select": "id,uid,name,company_name,email,phone,status,created_at,updated_at",
                "id": f"eq.{landlord_id}",
                "limit": "1",
            },
        )
        if not matches:
            matches = supabase_backend.api_request(
                g.supabase_config,
                g.authenticated["access_token"],
                "landlords",
                query={
                    "select": "id,uid,name,company_name,email,phone,status,created_at,updated_at",
                    "uid": f"eq.{landlord_id}",
                    "limit": "1",
                },
            )
        if not matches:
            return None
        record = dict(matches[0])
        record["company"] = record.get("company_name") or ""
        record["name"] = record.get("name") or ""
        record["status"] = _display_status(record.get("status"))
        return record
    if not landlord_id.isdecimal():
        return None
    with get_db() as db:
        record = db.execute("SELECT * FROM landlords WHERE id = ?", (landlord_id,)).fetchone()
    return dict(record) if record is not None else None


LANDLORD_TRANSITIONS = {
    "activate": ("invited", "active"),
    "suspend": ("active", "suspended"),
    "reactivate": ("suspended", "active"),
}


@app.post("/landlords/<landlord_id>/transition")
def transition_landlord(landlord_id: str):
    landlord = _find_landlord(landlord_id)
    if landlord is None:
        abort(404)
    action = request.form.get("action", "")
    current_status = str(landlord.get("status", "")).casefold()
    if action == "archive":
        if current_status == "archived":
            abort(409, description="This landlord is already archived.")
        transition = (current_status, "archived")
    else:
        transition = LANDLORD_TRANSITIONS.get(action)
    if transition is None or current_status != transition[0]:
        abort(409, description="That landlord status transition is not allowed.")
    if g.supabase_config is not None:
        expected_version = request.form.get("updated_at", "")
        current_version = str(landlord.get("updated_at") or "")
        if current_version and expected_version != current_version:
            abort(409, description="This landlord changed while it was offline.")
        result = supabase_backend.api_request(
            g.supabase_config,
            g.authenticated["access_token"],
            "landlords",
            method="PATCH",
            query={
                "uid": f"eq.{landlord['uid']}",
                "status": f"eq.{transition[0]}",
                **({"updated_at": f"eq.{landlord.get('updated_at')}"} if landlord.get("updated_at") else {}),
                "select": "id",
            },
            body={"status": transition[1]},
            prefer="return=representation",
        )
        if not result:
            abort(409, description="The landlord status changed or access was denied.")
    else:
        with get_db() as db:
            changed = db.execute(
                "UPDATE landlords SET status = ? WHERE id = ? AND lower(status) = ?",
                (transition[1].title(), landlord_id, transition[0]),
            ).rowcount
        if not changed:
            abort(409, description="The landlord status changed. Refresh and try again.")
    flash(f"Landlord account {transition[1]}.", "success")
    return redirect(url_for("records_page", section="landlords"))


@app.get("/login")
@app.post("/login")
def login():
    if g.supabase_config is None:
        return render_template("login.html", configuration_missing=True)
    if g.current_user is not None:
        return redirect(url_for("dashboard"))
    email = ""
    if request.method == "POST":
        supplied = request.form.get("csrf_token", "")
        expected = session.get("login_csrf_token", "")
        if not expected or not secrets.compare_digest(expected, supplied):
            abort(400, description="The form expired. Reload the page and try again.")
        email = request.form.get("email", "").strip().lower()
        password = request.form.get("password", "")
        if not _valid_email_address(email) or not password:
            flash("Enter a valid administrator email and password.", "error")
        else:
            retry_after = _auth_rate_limit("login", email)
            if retry_after:
                g.auth_rate_limit_retry_after = retry_after
                abort(
                    429,
                    description=f"Too many sign-in attempts. Try again in {retry_after} seconds.",
                )
            try:
                sid, csrf_token = supabase_backend.sign_in(
                    g.supabase_config, DATABASE, email, password
                )
            except supabase_backend.SupabaseRequestError as error:
                if error.status in (400, 401):
                    flash("Email or password is incorrect.", "error")
                elif error.status == 403:
                    flash("This account is not an approved RAMP super-admin.", "error")
                elif error.status == 503:
                    flash("Could not reach Supabase. Check your connection and try again.", "error")
                else:
                    app.logger.warning("Supabase sign-in failed with status %s.", error.status)
                    flash("Supabase sign-in failed. Check the project Auth configuration.", "error")
            else:
                _clear_auth_rate_limit("login", email)
                session.clear()
                session.permanent = True
                session["supabase_session_id"] = sid
                session["csrf_token"] = csrf_token
                next_path = request.form.get("next", "")
                if (
                    not next_path.startswith("/")
                    or next_path.startswith("//")
                    or "\\" in next_path
                ):
                    next_path = url_for("dashboard")
                return redirect(next_path)
    return render_template(
        "login.html",
        configuration_missing=False,
        next_path=request.args.get("next", ""),
        email=email,
    )


@app.get("/login/forgot-password")
@app.post("/login/forgot-password")
def forgot_password():
    if g.supabase_config is None:
        flash("Supabase credentials are required before resetting a password.", "error")
        return redirect(url_for("login"))
    if g.current_user is not None:
        return redirect(url_for("dashboard"))
    if request.method == "POST":
        supplied = request.form.get("csrf_token", "")
        expected = session.get("login_csrf_token", "")
        if not expected or not secrets.compare_digest(expected, supplied):
            abort(400, description="The form expired. Reload the page and try again.")
        email = request.form.get("email", "").strip().lower()
        if not _valid_email_address(email):
            flash("Enter a valid email address linked to your account.", "error")
        else:
            retry_after = _auth_rate_limit("forgot_password", email)
            if retry_after:
                g.auth_rate_limit_retry_after = retry_after
                abort(
                    429,
                    description=f"Too many reset requests. Try again in {retry_after} seconds.",
                )
            try:
                supabase_backend.request_password_reset(g.supabase_config, email)
            except supabase_backend.SupabaseRequestError as error:
                if error.status in (400, 404):
                    flash(
                        "If that email is linked to an approved RAMP account, a reset link has been sent.",
                        "success",
                    )
                elif error.status == 503:
                    flash("Could not reach Supabase. Check your connection and try again.", "error")
                else:
                    app.logger.warning("Password reset request failed with status %s.", error.status)
                    flash("Password reset could not be started. Check the Auth configuration.", "error")
            else:
                flash(
                    "If that email matches an approved RAMP account, a password reset link has been sent.",
                    "success",
                )
        return redirect(url_for("login"))
    return render_template("forgot_password.html")


@app.post("/logout")
def logout():
    sid = session.get("supabase_session_id")
    session.clear()
    if sid and g.supabase_config is not None:
        try:
            supabase_backend.sign_out(g.supabase_config, DATABASE, sid)
        except supabase_backend.SupabaseRequestError:
            app.logger.exception("Supabase could not revoke the signed-in session.")
            flash("Signed out locally; Supabase could not confirm session revocation.", "error")
    return redirect(url_for("login"))


@app.errorhandler(supabase_backend.SupabaseRequestError)
def handle_supabase_error(error: supabase_backend.SupabaseRequestError):
    app.logger.warning(
        "Supabase request failed with status %s and code %s.",
        error.status,
        error.code or "unknown",
    )
    if error.status == 400:
        message = "Supabase rejected the submitted values. Check the fields and database constraints."
    elif error.status == 401:
        message = "Your Supabase session is no longer valid. Sign in again, then retry the change."
    elif error.status == 403:
        message = "Supabase denied this action. Check the superadmin's access and the table's Row Level Security policies."
    elif error.status == 404:
        message = "The Supabase record or endpoint was not found. Check the configured schema."
    elif error.status == 409:
        message = "This record changed elsewhere. Reload it and try again."
    elif error.status == 429:
        message = "Supabase is rate-limiting requests. Wait briefly and try again."
    else:
        message = "Supabase could not complete the request. Check the connection and try again."
    if request.headers.get("X-Ramp-Form-Request") == "1":
        status = error.status if 400 <= error.status < 600 else 502
        return jsonify({"error": message}), status
    title = (
        "Connection problem"
        if error.status >= 500 or error.status == 429
        else "Request could not be completed"
    )
    return (
        render_template(
            "backend_error.html",
            title=title,
            eyebrow="SUPABASE RESPONSE",
            message=message,
            back_url=url_for("dashboard"),
            back_label="Back to dashboard",
        ),
        error.status if 400 <= error.status < 600 else 502,
    )


@app.errorhandler(HTTPException)
def handle_form_http_error(error: HTTPException):
    if request.headers.get("X-Ramp-Form-Request") == "1":
        response = jsonify({"error": error.description})
        response.status_code = error.code or 400
    else:
        status = error.code or 400
        titles = {
            400: "Request needs attention",
            403: "Access denied",
            404: "Page not found",
            409: "Record changed",
            429: "Please wait before retrying",
        }
        message = error.description
        if status == 404 and message == "Not Found":
            message = "The page or record may have moved or no longer exists."
        back_url = url_for("dashboard")
        back_label = "Back to dashboard"
        if request.endpoint == "review_inquiry":
            record_id = (request.view_args or {}).get("record_id", "")
            try:
                record_id = str(UUID(record_id))
            except ValueError:
                pass
            else:
                back_url = url_for(
                    "record_detail", section="inquiries", record_id=record_id
                )
                back_label = "Back to inquiry"
        response = error.get_response()
        response.set_data(
            render_template(
                "backend_error.html",
                title=titles.get(status, "Request could not be completed"),
                eyebrow="REQUEST ERROR",
                message=message,
                back_url=back_url,
                back_label=back_label,
            )
        )
    retry_after = getattr(g, "auth_rate_limit_retry_after", None)
    if retry_after:
        response.headers["Retry-After"] = str(retry_after)
    return response


def _number(value: Any) -> float:
    try:
        number = float(value or 0)
    except (TypeError, ValueError):
        return 0
    return number if number >= 0 else 0


def _as_datetime(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value.strip():
        return None
    normalized = value.strip().replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        for format_string in ("%b %d, %Y", "%B %d, %Y"):
            try:
                return datetime.strptime(normalized, format_string)
            except ValueError:
                continue
        return None
    return parsed.replace(tzinfo=None) if parsed.tzinfo else parsed


@app.get("/health")
def health():
    if g.supabase_config is None:
        return {"mode": "preview", "supabase_configured": False}
    return {"mode": "connected", "supabase_configured": True, "authenticated": bool(g.current_user)}


@app.get("/service-worker.js")
def service_worker():
    response = app.send_static_file("sw.js")
    response.headers["Service-Worker-Allowed"] = "/"
    response.headers["Cache-Control"] = "no-cache"
    return response


@app.errorhandler(supabase_backend.SupabaseConfigurationError)
def handle_supabase_config_error(error: supabase_backend.SupabaseConfigurationError):
    app.logger.error("Supabase configuration error: %s", error)
    return (
        render_template(
            "backend_error.html",
            title="Connection problem",
            eyebrow="BACKEND CONNECTION",
            message=str(error),
            back_url=url_for("dashboard"),
            back_label="Back to dashboard",
        ),
        503,
    )


@app.errorhandler(503)
def handle_service_unavailable(error):
    message = getattr(
        error,
        "description",
        "The connected service is temporarily unavailable.",
    )
    if request.headers.get("X-Ramp-Form-Request") == "1":
        return jsonify({"error": message}), 503
    return (
        render_template(
            "backend_error.html",
            title="Service unavailable",
            eyebrow="BACKEND CONNECTION",
            message=message,
            back_url=url_for("dashboard"),
            back_label="Back to dashboard",
        ),
        503,
    )


if __name__ == "__main__":
    init_db()
    app.run(
        host="127.0.0.1",
        debug=os.environ.get("FLASK_DEBUG") == "1",
        ssl_context="adhoc" if os.environ.get("RAMP_USE_LOCAL_HTTPS") == "1" else None,
    )
