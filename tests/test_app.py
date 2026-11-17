import io
import json
import os
import tempfile
import unittest
from pathlib import Path
from uuid import uuid4
from unittest.mock import patch

from openpyxl import load_workbook

import app as ramp_app


class RampAdminWebTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.original_database = ramp_app.DATABASE
        self.original_preview_setting = os.environ.get("RAMP_WEB_TEST_PREVIEW")
        os.environ["RAMP_WEB_TEST_PREVIEW"] = "1"
        ramp_app.DATABASE = Path(self.temp_dir.name) / "test.sqlite3"
        ramp_app.app.config.update(TESTING=True)
        ramp_app.init_db()
        self.client = ramp_app.app.test_client()

    def tearDown(self):
        ramp_app.DATABASE = self.original_database
        if self.original_preview_setting is None:
            os.environ.pop("RAMP_WEB_TEST_PREVIEW", None)
        else:
            os.environ["RAMP_WEB_TEST_PREVIEW"] = self.original_preview_setting
        self.temp_dir.cleanup()

    def csrf_token(self):
        self.client.get("/")
        with self.client.session_transaction() as browser_session:
            return browser_session["csrf_token"]

    def set_live_session(self):
        with self.client.session_transaction() as browser_session:
            browser_session["supabase_session_id"] = "mock-session"
        config = ramp_app.supabase_backend.SupabaseSettings(
            "https://example.supabase.co", "test-publishable-key"
        )
        auth = {
            "access_token": "admin-access-token",
            "profile": {
                "uid": "admin-uid",
                "email": "admin@example.com",
                "display_name": "Admin",
                "role": "super_admin",
                "is_approved": True,
            },
        }
        return config, auth

    def test_database_path_can_use_host_persistent_storage(self):
        configured_path = Path(self.temp_dir.name) / "persistent" / "ramp.sqlite3"
        with patch.dict(os.environ, {"RAMP_WEB_DATABASE": str(configured_path)}):
            self.assertEqual(ramp_app._database_path(), configured_path.resolve())

    def test_production_requires_supabase_environment_variables(self):
        with patch.dict(
            os.environ,
            {
                "RAMP_WEB_TEST_PREVIEW": "",
                "RAMP_ENV": "production",
                "RAMP_SUPABASE_URL": "",
                "RAMP_SUPABASE_PUBLISHABLE_KEY": "",
                "RAMP_SUPABASE_CONFIG": "",
            },
        ):
            with self.assertRaises(ramp_app.supabase_backend.SupabaseConfigurationError):
                ramp_app.supabase_backend.settings()

    def test_supabase_settings_accept_publishable_and_reject_secret_keys(self):
        variables = {
            "RAMP_WEB_TEST_PREVIEW": "",
            "RAMP_ENV": "production",
            "RAMP_SUPABASE_URL": "https://example.supabase.co",
            "RAMP_SUPABASE_CONFIG": "",
        }
        with patch.dict(
            os.environ,
            {**variables, "RAMP_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_test_key"},
        ):
            settings = ramp_app.supabase_backend.settings()
        self.assertEqual(settings.publishable_key, "sb_publishable_test_key")

        with patch.dict(
            os.environ,
            {**variables, "RAMP_SUPABASE_PUBLISHABLE_KEY": "sb_secret_do_not_use"},
        ):
            with self.assertRaises(ramp_app.supabase_backend.SupabaseConfigurationError):
                ramp_app.supabase_backend.settings()

    def test_email_and_ph_mobile_validation_normalize_and_reject_dummy_values(self):
        self.assertTrue(ramp_app._valid_contact_email("  Person+tag@Example.COM "))
        self.assertFalse(ramp_app._valid_contact_email("person@example"))
        self.assertFalse(ramp_app._valid_contact_email("person@mailinator.com"))
        self.assertEqual(
            ramp_app._normalize_ph_mobile(" 0917-123-4567 "),
            "09171234567",
        )
        self.assertEqual(
            ramp_app._normalize_ph_mobile("+63 (917) 123-4567"),
            "+639171234567",
        )
        self.assertIsNone(ramp_app._normalize_ph_mobile("09999999999"))
        self.assertIsNone(ramp_app._normalize_ph_mobile("09123456789"))
        self.assertIsNone(ramp_app._normalize_ph_mobile("0917ABC4567"))

    def test_supabase_config_file_must_contain_a_json_object(self):
        config_path = Path(self.temp_dir.name) / "supabase.json"
        config_path.write_text("[]", encoding="utf-8")
        with patch.dict(
            os.environ,
            {
                "RAMP_WEB_TEST_PREVIEW": "",
                "RAMP_ENV": "",
                "RAMP_SUPABASE_URL": "",
                "RAMP_SUPABASE_PUBLISHABLE_KEY": "",
                "RAMP_SUPABASE_CONFIG": str(config_path),
            },
        ):
            with self.assertRaisesRegex(
                ramp_app.supabase_backend.SupabaseConfigurationError,
                "JSON object",
            ):
                ramp_app.supabase_backend.settings()

    def test_supabase_configuration_is_not_rendered_into_html(self):
        config, _ = self.set_live_session()
        config = ramp_app.supabase_backend.SupabaseSettings(
            "https://private-project.supabase.co", "sb_publishable_do_not_render"
        )
        with patch.object(ramp_app.supabase_backend, "settings", return_value=config):
            response = self.client.get("/login")
        self.assertEqual(response.status_code, 200)
        self.assertNotIn(b"private-project.supabase.co", response.data)
        self.assertNotIn(b"sb_publishable_do_not_render", response.data)

    def test_sign_in_page_uses_aligned_local_icons(self):
        config = ramp_app.supabase_backend.SupabaseSettings(
            "https://example.supabase.co", "test-publishable-key"
        )
        with patch.object(ramp_app.supabase_backend, "settings", return_value=config):
            response = self.client.get("/login")

        self.assertEqual(response.status_code, 200)
        self.assertIn(b"/static/ramp_admin_logo.png", response.data)
        self.assertIn(b"#icon-building", response.data)
        self.assertIn(b"#icon-eye-off", response.data)
        self.assertIn(b"Rental Administration Maintenance Platform", response.data)
        self.assertIn(b"<h1>RAMP</h1>", response.data)
        self.assertIn(b'class="login-brand-footer">RAMP</span>', response.data)
        self.assertNotIn(b"Properties, tenants, payments, and maintenance", response.data)
        self.assertNotIn(b"Supabase project configuration detected", response.data)
        self.assertNotIn(b"Only approved super-admin accounts can access", response.data)
        self.assertNotIn(b"Secure administrator access", response.data)
        self.assertIn(b"Authenticated by Supabase", response.data)
        self.assertIn(b'class="button button-primary login-submit"', response.data)

    def test_rpc_helper_uses_authenticated_supabase_rest_endpoint(self):
        config = ramp_app.supabase_backend.SupabaseSettings(
            "https://example.supabase.co", "test-publishable-key"
        )
        with patch.object(
            ramp_app.supabase_backend, "_request", return_value="queued-command"
        ) as request:
            result = ramp_app.supabase_backend.rpc_request(
                config,
                "admin-access-token",
                "review_tenant_inquiry",
                {
                    "p_inquiry_id": "inquiry-12",
                    "p_decision": "approve",
                    "p_assigned_unit_id": "unit-12",
                    "p_internal_note": "",
                },
            )
        self.assertEqual(result, "queued-command")
        request.assert_called_once_with(
            config,
            "/rest/v1/rpc/review_tenant_inquiry",
            method="POST",
            token="admin-access-token",
            body={
                "p_inquiry_id": "inquiry-12",
                "p_decision": "approve",
                "p_assigned_unit_id": "unit-12",
                "p_internal_note": "",
            },
        )

    def test_dashboard_renders_preview_and_summary(self):
        response = self.client.get("/")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b">Local preview</strong>", response.data)
        self.assertIn(b">Dashboard</h1>", response.data)
        self.assertIn(b"Follow up", response.data)
        self.assertIn(b"Recent activity", response.data)
        self.assertIn(b"Active units", response.data)
        self.assertIn(b"Unit occupancy", response.data)
        self.assertIn(b"Active leases", response.data)
        self.assertIn(b"Revenue &amp; expenses", response.data)
        self.assertIn(b"Unit status", response.data)
        self.assertIn(b"Rent collected", response.data)
        self.assertIn(b"All clear.", response.data)
        self.assertNotIn(b"Based on stored payment status", response.data)
        self.assertNotIn(b"No overdue status is inferred", response.data)
        self.assertNotIn(b"Paid rent transactions only", response.data)
        self.assertIn(b"Current account status", response.data)
        self.assertNotIn(b"Nothing needs follow-up right now.", response.data)
        self.assertNotIn(b"Registered tenant accounts", response.data)
        self.assertNotIn(b"vs. last month", response.data)
        self.assertNotIn(b"Amara Santos", response.data)
        self.assertIn(b'id="pageLoading"', response.data)
        self.assertIn(b"<h2>Help</h2>", response.data)
        self.assertNotIn(b"Quick guide", response.data)
        self.assertIn(b"<details class=\"nav-group\"", response.data)
        self.assertIn(b'min="2025-01"', response.data)
        self.assertEqual(self.client.get("/?period=2024-12").status_code, 400)

    def test_dashboard_charts_use_real_six_month_payment_expense_and_unit_data(self):
        lease_end = (ramp_app.datetime.now() + ramp_app.timedelta(days=14)).strftime(
            "%Y-%m-%d"
        )
        records = (
            ("properties", 1, {"status": "Occupied"}),
            ("properties", 2, {"status": "Occupied"}),
            ("properties", 3, {"status": "Vacant"}),
            ("properties", 4, {"status": "Maintenance"}),
            ("tenants", 1, {"status": "Active", "lease_end": lease_end}),
            (
                "payments",
                1,
                {
                    "status": "Paid",
                    "transaction_type": "rent",
                    "payment_date": "2026-10-12",
                    "amount": 1000,
                },
            ),
            (
                "payments",
                2,
                {
                    "status": "Paid",
                    "transaction_type": "rent",
                    "payment_date": "2026-11-12",
                    "amount": 2000,
                },
            ),
            (
                "payments",
                3,
                {
                    "status": "Pending",
                    "transaction_type": "rent",
                    "payment_date": "2026-11-12",
                    "amount": 9000,
                },
            ),
            ("expenses", 1, {"date": "2026-10-15", "amount": 250}),
            ("expenses", 2, {"date": "2026-11-15", "amount": 500}),
        )
        with ramp_app.get_db() as db:
            db.executemany(
                "INSERT INTO records (section, id, data) VALUES (?, ?, ?)",
                [
                    (section, record_id, ramp_app._json_dumps(data))
                    for section, record_id, data in records
                ],
            )

        response = self.client.get("/?period=2026-11")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b">50% occupied</span>", response.data)
        self.assertIn(b"100% vs last month", response.data)
        self.assertIn(b"November 2026: \xe2\x82\xb12,000 rent collected", response.data)
        self.assertIn(b"November 2026: \xe2\x82\xb1500 expenses", response.data)
        self.assertIn(b"chart-revenue-line", response.data)
        self.assertIn(b"chart-axis-label", response.data)
        self.assertIn(b"unit-status-mini-progress", response.data)
        self.assertIn(b" C ", response.data)
        self.assertIn(b"2 of 4 active units occupied", response.data)
        self.assertIn(b"1 ending within 30 days", response.data)

    def test_dashboard_attention_inquiry_count_uses_correct_plural(self):
        with ramp_app.get_db() as db:
            db.execute(
                "INSERT INTO records (section, id, data) VALUES (?, ?, ?)",
                ("inquiries", 1, ramp_app._json_dumps({"status": "Pending"})),
            )

        one = self.client.get("/")
        self.assertIn(b">1 inquiry needs review</small>", one.data)
        self.assertNotIn(b"inquirys", one.data)

        with ramp_app.get_db() as db:
            db.execute(
                "INSERT INTO records (section, id, data) VALUES (?, ?, ?)",
                ("inquiries", 2, ramp_app._json_dumps({"status": "Pending"})),
            )

        two = self.client.get("/")
        self.assertIn(b">2 inquiries need review</small>", two.data)

    def test_terms_draft_is_reachable_from_settings(self):
        settings = self.client.get("/settings")
        self.assertEqual(settings.status_code, 200)
        self.assertIn(b"Terms &amp; Conditions draft", settings.data)

        draft = self.client.get("/settings/terms")
        self.assertEqual(draft.status_code, 200)
        self.assertIn(b"Draft status:", draft.data)
        self.assertIn(b"not legal advice or a consent flow", draft.data)

    def test_records_search_and_csv_export(self):
        csrf = self.csrf_token()
        self.client.post(
            "/landlords/new",
            data={
                "csrf_token": csrf,
                "name": "Amara Santos",
                "company": "Santos Property Group and Residential Holdings",
                "email": "amara@example.com",
                "phone": "+63 917 123 4567",
            },
        )
        response = self.client.get("/landlords?q=Amara")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Amara Santos", response.data)
        self.assertIn(b'data-label="Landlord"', response.data)
        self.assertIn(b'class="table-value truncate-cell"', response.data)
        self.assertIn(
            b'title="Santos Property Group and Residential Holdings"', response.data
        )
        self.assertNotIn(b"Daniel Reyes", response.data)
        self.assertIn(b'data-loading-label="Filtering', response.data)
        self.assertIn(b"CSV (.csv)", response.data)
        self.assertIn(b"Excel (.xlsx)", response.data)
        export = self.client.get("/landlords/export.csv?q=Amara")
        self.assertEqual(export.status_code, 200)
        self.assertIn(b"Amara Santos", export.data)
        self.assertNotIn(b"Taylor Lee", export.data)
        excel = self.client.get("/landlords/export.xlsx?q=Amara")
        self.assertEqual(excel.status_code, 200)
        workbook = load_workbook(io.BytesIO(excel.data))
        self.assertEqual(workbook.active["A2"].value, "Amara Santos")
        self.assertEqual(workbook.active.freeze_panes, "A2")
        workbook.close()

    def test_display_value_formats_dates_timestamps_and_months(self):
        self.assertEqual(
            ramp_app.format_display_value("2026-02-03", "lease_start"),
            "Feb 3, 2026",
        )
        self.assertEqual(
            ramp_app.format_display_value(
                "2026-02-03T15:04:00+00:00", "created_at"
            ),
            "Feb 3, 2026 · 3:04 PM",
        )
        self.assertEqual(
            ramp_app.format_display_value("2026-02", "month"),
            "February 2026",
        )
        self.assertEqual(
            ramp_app.format_display_value("Reference 2026-02-03", "message"),
            "Reference 2026-02-03",
        )
        self.assertEqual(
            ramp_app.format_structured_value(
                {"created_at": "2026-02-03T15:04:00+00:00", "status": "active"}
            ),
            "Created at: Feb 3, 2026 · 3:04 PM · Status: active",
        )

    def test_records_page_renders_readable_payment_dates(self):
        record_id = str(uuid4())
        with ramp_app.get_db() as db:
            db.execute(
                "INSERT INTO records (section, id, data) VALUES (?, ?, ?)",
                (
                    "payments",
                    record_id,
                    ramp_app._json_dumps(
                        {
                            "id": record_id,
                            "reference": "PAY-2026-001",
                            "amount": 1250,
                            "paid_on": "2026-02-03T15:04:00+00:00",
                            "status": "Paid",
                        }
                    ),
                ),
            )

        response = self.client.get("/payments")

        self.assertEqual(response.status_code, 200)
        self.assertIn("Feb 3, 2026 · 3:04 PM".encode(), response.data)
        self.assertNotIn(b"UTC", response.data)
        self.assertIn(b'title="2026-02-03T15:04:00+00:00"', response.data)

    def test_rfid_history_filters_by_result_and_marks_local_time(self):
        with ramp_app.get_db() as db:
            for record_id, status in (
                ("rfid-granted", "Granted"),
                ("rfid-denied", "Denied"),
            ):
                db.execute(
                    "INSERT INTO records (section, id, data) VALUES (?, ?, ?)",
                    (
                        "rfid-access",
                        record_id,
                        ramp_app._json_dumps(
                            {
                                "id": record_id,
                                "device": "Main entry",
                                "unit": "402",
                                "tenant": "Jamie Doe",
                                "action": "Entry",
                                "access_status": status,
                                "created": "2026-02-03T15:04:00+00:00",
                            }
                        ),
                    ),
                )

        response = self.client.get("/rfid-access?status=Denied")

        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Filter by access result", response.data)
        self.assertIn(b"All results", response.data)
        self.assertIn(b'data-record-id="rfid-denied"', response.data)
        self.assertNotIn(b'data-record-id="rfid-granted"', response.data)
        self.assertIn(
            b'data-local-time datetime="2026-02-03T15:04:00+00:00"',
            response.data,
        )

    def test_utility_history_marks_latest_effective_rates_and_shows_units(self):
        today = ramp_app.date.today()
        yesterday = today - ramp_app.timedelta(days=1)
        tomorrow = today + ramp_app.timedelta(days=1)
        entries = (
            ("water-old", "Water", 12.5, yesterday.isoformat()),
            ("water-current", "Water", 13.75, today.isoformat()),
            ("water-future", "Water", 14.0, tomorrow.isoformat()),
            ("electric-current", "Electricity", 8.25, today.isoformat()),
        )
        with ramp_app.get_db() as db:
            for record_id, utility, rate, effective_at in entries:
                db.execute(
                    "INSERT INTO records (section, id, data) VALUES (?, ?, ?)",
                    (
                        "utility-history",
                        record_id,
                        ramp_app._json_dumps(
                            {
                                "id": record_id,
                                "utility": utility,
                                "previous_rate": rate - 1,
                                "new_rate": rate,
                                "effective_at": effective_at,
                            }
                        ),
                    ),
                )

        response = self.client.get("/utility-history")

        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Previous rate (\xe2\x82\xb1/unit)", response.data)
        self.assertIn(b"New rate (\xe2\x82\xb1/unit)", response.data)
        self.assertIn("₱13.75".encode(), response.data)
        self.assertIn("m³".encode(), response.data)
        self.assertIn(b"kWh", response.data)
        self.assertIn(b"Active", response.data)
        self.assertIn(b"Historical", response.data)
        self.assertIn(b"Scheduled", response.data)
        self.assertIn(b'data-local-time datetime="' + today.isoformat().encode() + b'"', response.data)

        active_response = self.client.get("/utility-history?status=Active")
        self.assertIn(b'data-record-id="water-current"', active_response.data)
        self.assertIn(b'data-record-id="electric-current"', active_response.data)
        self.assertNotIn(b'data-record-id="water-old"', active_response.data)
        self.assertNotIn(b'data-record-id="water-future"', active_response.data)

        detail = self.client.get("/utility-history/water-current")
        self.assertEqual(detail.status_code, 200)
        self.assertIn("₱12.75".encode(), detail.data)
        self.assertIn("m³".encode(), detail.data)

    def test_empty_unit_page_has_create_action_and_search_empty_state(self):
        empty_response = self.client.get("/properties")

        self.assertEqual(empty_response.status_code, 200)
        self.assertIn(b"No units yet", empty_response.data)
        self.assertIn(b'href="/properties/new">Add unit</a>', empty_response.data)

        record_id = str(uuid4())
        with ramp_app.get_db() as db:
            db.execute(
                "INSERT INTO records (section, id, data) VALUES (?, ?, ?)",
                (
                    "properties",
                    record_id,
                    ramp_app._json_dumps(
                        {"id": record_id, "unit_number": "402", "name": "Harbor View"}
                    ),
                ),
            )

        no_match_response = self.client.get("/properties?q=missing")

        self.assertEqual(no_match_response.status_code, 200)
        self.assertIn(b"No matching units", no_match_response.data)
        self.assertIn(b"Clear filters", no_match_response.data)
        self.assertNotIn(b"Add first unit", no_match_response.data)

    def test_tenant_actions_are_collapsed_and_email_stays_below_name(self):
        record_id = str(uuid4())
        with ramp_app.get_db() as db:
            db.execute(
                "INSERT INTO records (section, id, data) VALUES (?, ?, ?)",
                (
                    "tenants",
                    record_id,
                    ramp_app._json_dumps(
                        {
                            "id": record_id,
                            "name": "Jamie Doe",
                            "email": "jamie@example.com",
                            "phone": "+63 912 345 6789",
                            "property": "Unit 4",
                            "lease_start": "2025-01-01",
                            "lease_end": "2026-01-01",
                            "lease_status": "Active",
                            "monthly_rent": 3000,
                            "balance": 0,
                            "status": "Active",
                            "is_archived": False,
                        }
                    ),
                ),
            )

        response = self.client.get("/tenants")

        self.assertEqual(response.status_code, 200)
        self.assertIn(b'<small>jamie@example.com</small>', response.data)
        self.assertIn(b'data-label="Email"', response.data)
        self.assertIn(b"> View</a>", response.data)
        self.assertNotIn(b'aria-label="View record"', response.data)
        self.assertIn(b'class="row-action-menu"', response.data)
        self.assertIn(b'data-offline-edit="tenants"', response.data)
        self.assertIn(b'action="/tenants/' + record_id.encode() + b'/archive"', response.data)
        self.assertIn(b"Archive Jamie Doe? Its history will remain available.", response.data)
        self.assertIn(b'href="/static/icons.svg#icon-sort"></use>', response.data)

        ascending = self.client.get("/tenants?sort=name&direction=asc")
        descending = self.client.get("/tenants?sort=name&direction=desc")
        self.assertIn(b'href="/static/icons.svg#icon-sort-up"></use>', ascending.data)
        self.assertIn(b'href="/static/icons.svg#icon-sort-down"></use>', descending.data)

    def test_records_pagination_shows_current_and_neighboring_pages(self):
        with ramp_app.get_db() as db:
            for index in range(120):
                record_id = str(uuid4())
                db.execute(
                    "INSERT INTO records (section, id, data) VALUES (?, ?, ?)",
                    (
                        "properties",
                        record_id,
                        ramp_app._json_dumps(
                            {
                                "id": record_id,
                                "unit_number": f"Unit {index + 1}",
                                "name": f"Unit {index + 1}",
                                "rent": 1,
                                "status": "Vacant",
                            }
                        ),
                    ),
                )

        response = self.client.get("/properties?page=2")

        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Page 2", response.data)
        self.assertIn(b"aria-current=\"page\">2</span>", response.data)
        self.assertIn(b"page=1", response.data)
        self.assertIn(b"page=3", response.data)
        self.assertIn(b"Showing 51\xe2\x80\x93100 of 120", response.data)

    def test_inquiry_application_is_summarized_as_a_chip(self):
        record_id = str(uuid4())
        with ramp_app.get_db() as db:
            db.execute(
                "INSERT INTO records (section, id, data) VALUES (?, ?, ?)",
                (
                    "inquiries",
                    record_id,
                    ramp_app._json_dumps(
                        {
                            "id": record_id,
                            "sender": "Pat Example",
                            "email": "pat@example.com",
                            "property": "W101",
                            "message": "[RENTAL APPLICATION] Preferred Unit: W101. Additional details.",
                            "status": "Pending",
                        }
                    ),
                ),
            )

        response = self.client.get("/inquiries")

        self.assertEqual(response.status_code, 200)
        self.assertIn(b'class="inquiry-kind">Rental app</span>', response.data)
        self.assertIn(b'class="inquiry-unit">W101</span>', response.data)
        self.assertNotIn(b"Additional details.", response.data)

    def test_notification_timestamp_stays_in_monospace_log_format(self):
        timestamp = "2026-11-16T10:11:42+00:00"
        with ramp_app.get_db() as db:
            db.execute(
                "INSERT INTO records (section, id, data) VALUES (?, ?, ?)",
                (
                    "notifications",
                    "notification-preview",
                    ramp_app._json_dumps(
                        {
                            "id": "notification-preview",
                            "title": "Payment received",
                            "type": "Payment",
                            "status": "Unread",
                            "timestamp": timestamp,
                            "entity_type": "Payment",
                            "action": "Review",
                        }
                    ),
                ),
            )

        response = self.client.get("/notifications")

        self.assertEqual(response.status_code, 200)
        self.assertIn(
            f'<time class="notification-time" datetime="{timestamp}" title="{timestamp}">{timestamp}</time>'.encode(),
            response.data,
        )
        self.assertNotIn(b'class="notification-time" data-local-time', response.data)

    def test_public_and_document_pages_use_compact_access_badges(self):
        listings = self.client.get("/public-listings")
        documents = self.client.get("/documents")

        self.assertEqual(listings.status_code, 200)
        self.assertEqual(documents.status_code, 200)
        self.assertIn(b'class="page-state-pill">Read-only</span>', listings.data)
        self.assertIn(b'class="page-state-pill restricted"', documents.data)
        self.assertNotIn(b"File opening is disabled", documents.data)

    def test_audit_rows_show_safe_business_summaries(self):
        row = ramp_app._normalize_audit_row(
            {
                "id": "audit-1",
                "action": "UPDATE",
                "details": ramp_app._json_dumps(
                    {
                        "actor_email": "maria@example.com",
                        "description": "Unit #104 (Beachfront Villa)",
                        "query": "UPDATE units SET rent = 5200",
                    }
                ),
                "timestamp": "2026-02-03T15:04:00+00:00",
            }
        )
        self.assertEqual(row["actor"], "maria@example.com")
        self.assertEqual(row["action"], "Updated")
        self.assertEqual(row["action_kind"], "updated")
        self.assertEqual(row["summary"], "maria@example.com updated Unit #104 (Beachfront Villa).")
        self.assertNotIn("UPDATE units SET", row["details"])

        raw_query = ramp_app._normalize_audit_row(
            {
                "id": "audit-2",
                "action": "UPDATE units SET rent = 5200",
                "details": ramp_app._json_dumps(
                    {"description": "SELECT * FROM units"}
                ),
                "timestamp": "2026-02-03T15:04:00+00:00",
            }
        )
        self.assertEqual(raw_query["action"], "Activity recorded")
        self.assertNotIn("SELECT * FROM", str(raw_query))
        self.assertNotIn("UPDATE units SET", str(raw_query))

    def test_audit_summary_understands_verb_resource_actions_and_metadata_aliases(self):
        named_tenant = ramp_app._normalize_audit_row(
            {
                "action": "add tenant",
                "details": ramp_app._json_dumps(
                    {
                        "user_name": "Alex Admin",
                        "tenant_name": "Jamie Doe",
                        "tenant_id": "tenant-42",
                    }
                ),
            }
        )
        self.assertEqual(named_tenant["actor"], "Alex Admin")
        self.assertEqual(named_tenant["action"], "Added")
        self.assertEqual(
            named_tenant["summary"], "Alex Admin added Jamie Doe."
        )

        generic_tenant = ramp_app._normalize_audit_row(
            {
                "action": "update tenant",
                "details": ramp_app._json_dumps({"user_email": "admin@example.com"}),
            }
        )
        self.assertEqual(
            generic_tenant["summary"],
            "admin@example.com updated a tenant record.",
        )

    def test_audit_pages_never_render_raw_query_details(self):
        record_id = str(uuid4())
        raw_query = "UPDATE units SET rent = 5200"
        with ramp_app.get_db() as db:
            db.execute(
                "INSERT INTO records (section, id, data) VALUES (?, ?, ?)",
                (
                    "activity",
                    record_id,
                    ramp_app._json_dumps(
                        {
                            "id": record_id,
                            "action": "UPDATE",
                            "details": ramp_app._json_dumps(
                                {
                                    "actor_email": "admin@example.com",
                                    "description": "SELECT * FROM units",
                                    "query": raw_query,
                                }
                            ),
                            "timestamp": "2026-02-03T15:04:00+00:00",
                        }
                    ),
                ),
            )

        listing = self.client.get("/activity")
        detail = self.client.get(f"/activity/{record_id}")
        dashboard = self.client.get("/")

        self.assertEqual(listing.status_code, 200)
        self.assertEqual(detail.status_code, 200)
        self.assertEqual(dashboard.status_code, 200)
        self.assertIn(b"admin@example.com updated a record.", listing.data)
        self.assertIn(
            b'<th scope="col" class="actions-heading"><span class="visually-hidden">Record actions</span></th>',
            listing.data,
        )
        self.assertIn(b'aria-sort="descending"', listing.data)
        self.assertIn(b"#icon-sort-down", listing.data)
        self.assertIn(b'name="q"', listing.data)
        self.assertIn(b"<strong>1</strong> audit history found", listing.data)
        self.assertIn(b"admin@example.com updated a record.", detail.data)
        self.assertIn(b"admin@example.com updated a record.", dashboard.data)
        self.assertIn(
            b'data-local-time datetime="2026-02-03T15:04:00+00:00"',
            dashboard.data,
        )
        self.assertNotIn(raw_query.encode(), listing.data)
        self.assertNotIn(raw_query.encode(), detail.data)
        self.assertNotIn(b"SELECT * FROM units", detail.data)

    def test_audit_history_defaults_to_newest_timestamp_first(self):
        with ramp_app.get_db() as db:
            for record_id, target, timestamp in (
                ("z-older", "Older record", "2026-02-01T10:00:00+00:00"),
                ("a-newer", "Newer record", "2026-02-03T10:00:00+00:00"),
            ):
                db.execute(
                    "INSERT INTO records (section, id, data) VALUES (?, ?, ?)",
                    (
                        "activity",
                        record_id,
                        ramp_app._json_dumps(
                            {
                                "id": record_id,
                                "action": "UPDATE",
                                "details": ramp_app._json_dumps(
                                    {
                                        "actor_name": "Admin",
                                        "target_name": target,
                                    }
                                ),
                                "timestamp": timestamp,
                            }
                        ),
                    ),
                )

        response = self.client.get("/activity")

        self.assertEqual(response.status_code, 200)
        self.assertLess(
            response.data.index(b"Newer record"),
            response.data.index(b"Older record"),
        )

    def test_csv_export_escapes_spreadsheet_formulas(self):
        with ramp_app.get_db() as db:
            db.execute(
                """INSERT INTO landlords
                   (name, company, email, phone, units, status, created_at)
                   VALUES (?, ?, ?, '', 0, 'Active', ?)""",
                ('=HYPERLINK("https://example.com","Open")', "Example", "safe@example.com", "2026-01-01"),
            )

        response = self.client.get("/landlords/export.csv")

        self.assertEqual(response.status_code, 200)
        self.assertIn(
            b'"\'' + b'=HYPERLINK(""https://example.com"",""Open"")"',
            response.data,
        )

        excel = self.client.get("/landlords/export.xlsx")
        self.assertEqual(excel.status_code, 200)
        workbook = load_workbook(io.BytesIO(excel.data), read_only=True)
        formula_cell = workbook.active["A2"]
        self.assertTrue(formula_cell.value.startswith("'="))
        self.assertNotEqual(formula_cell.data_type, "f")
        workbook.close()

    def test_records_page_paginates_filtered_rows(self):
        created_at = "2026-01-01T00:00:00+00:00"
        with ramp_app.get_db() as db:
            db.executemany(
                """INSERT INTO landlords (id, name, company, email, phone, units, status, created_at)
                   VALUES (?, ?, ?, ?, '', 0, 'Active', ?)""",
                [
                    (
                        index,
                        f"Test landlord {index}",
                        "Test company",
                        f"landlord{index}@example.com",
                        created_at,
                    )
                    for index in range(1, 53)
                ],
            )
        response = self.client.get("/landlords?page=2&status=Active")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Page 2 of 2", response.data)
        self.assertIn(b"Test landlord 52", response.data)
        self.assertNotIn(b"Test landlord 1", response.data)
        sorted_response = self.client.get("/landlords?sort=name&direction=desc")
        self.assertEqual(sorted_response.status_code, 200)
        self.assertLess(
            sorted_response.data.index(b"Test landlord 9"),
            sorted_response.data.index(b"Test landlord 8"),
        )

    def test_expenses_can_be_created_and_filtered_by_month_with_totals(self):
        csrf = self.csrf_token()
        response = self.client.post(
            "/expenses/new",
            data={
                "csrf_token": csrf,
                "record_id": str(uuid4()),
                "title": "Water pump repair",
                "category": "Maintenance",
                "amount": "1250.50",
                "date": "2026-03-12",
                "unit_number": "A-12",
                "notes": "Replaced the pump",
            },
        )
        self.assertEqual(response.status_code, 302)
        march = self.client.get("/expenses?period=2026-03")
        self.assertEqual(march.status_code, 200)
        self.assertIn(b"Water pump repair", march.data)
        self.assertIn(b"\xe2\x82\xb11,250.50", march.data)
        april = self.client.get("/expenses?period=2026-04")
        self.assertEqual(april.status_code, 200)
        self.assertNotIn(b"Water pump repair", april.data)

    def test_expense_category_filter_applies_to_list_and_csv(self):
        csrf = self.csrf_token()
        for title, category in (
            ("Water pump repair", "Maintenance"),
            ("Internet bill", "Utilities"),
        ):
            response = self.client.post(
                "/expenses/new",
                data={
                    "csrf_token": csrf,
                    "record_id": str(uuid4()),
                    "title": title,
                    "category": category,
                    "amount": "1250.50",
                    "date": "2026-03-12",
                },
            )
            self.assertEqual(response.status_code, 302)
        filtered = self.client.get("/expenses?category=maintenance")
        self.assertEqual(filtered.status_code, 200)
        self.assertIn(b"Water pump repair", filtered.data)
        self.assertNotIn(b"Internet bill", filtered.data)
        exported = self.client.get("/expenses/export.csv?category=maintenance")
        self.assertEqual(exported.status_code, 200)
        self.assertIn(b"Water pump repair", exported.data)
        self.assertNotIn(b"Internet bill", exported.data)

    def test_entity_form_normalizes_text_and_validates_phone_and_money_precision(self):
        csrf = self.csrf_token()
        response = self.client.post(
            "/tenants/new",
            data={
                "csrf_token": csrf,
                "name": "  Maria   Dela Cruz ",
                "email": " MARIA@Example.COM ",
                "phone": "0917-123-4567",
                "status": "Active",
                "monthly_rent": "12000.00",
            },
        )
        self.assertEqual(response.status_code, 302)
        tenant = ramp_app.rows_for("tenants")[0]
        self.assertEqual(tenant["name"], "Maria Dela Cruz")
        self.assertEqual(tenant["email"], "maria@example.com")
        self.assertEqual(tenant["phone"], "09171234567")

        invalid_phone = self.client.post(
            "/tenants/new",
            data={
                "csrf_token": csrf,
                "name": "Valid Tenant",
                "status": "Active",
                "phone": "09123456789",
            },
        )
        self.assertEqual(invalid_phone.status_code, 400)
        invalid_amount = self.client.post(
            "/expenses/new",
            data={
                "csrf_token": csrf,
                "record_id": str(uuid4()),
                "title": "Water pump repair",
                "category": "Maintenance",
                "amount": "10.001",
                "date": "2026-03-12",
            },
        )
        self.assertEqual(invalid_amount.status_code, 400)
        self.assertEqual(self.client.get("/expenses?period=2026-13").status_code, 400)
        self.assertEqual(self.client.get("/expenses?period=2024-12").status_code, 400)

    def test_live_expense_creator_is_attributed_to_signed_in_admin(self):
        config, auth = self.set_live_session()
        expense_id = str(uuid4())
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app.supabase_backend, "api_request", return_value=[{"id": expense_id}]
            ) as request_api,
        ):
            response = self.client.post(
                "/expenses/new",
                data={
                    "csrf_token": "live-csrf",
                    "record_id": expense_id,
                    "title": "Pump repair",
                    "category": "Maintenance",
                    "amount": "500",
                    "date": "2026-03-12",
                    "recorded_by": "Forged name",
                },
            )
        self.assertEqual(response.status_code, 302)
        self.assertEqual(request_api.call_args.kwargs["body"]["recorded_by"], "Admin")

    def test_announcements_can_be_archived_but_not_edited_afterward(self):
        csrf = self.csrf_token()
        record_id = str(uuid4())
        response = self.client.post(
            "/announcements/new",
            data={
                "csrf_token": csrf,
                "record_id": record_id,
                "title": "Water service update",
                "message": "Service resumes this afternoon.",
                "category": "Building",
                "is_important": "true",
            },
        )
        self.assertEqual(response.status_code, 302)
        announcement = next(
            row for row in ramp_app.rows_for("announcements")
            if str(row["id"]) == record_id
        )
        self.assertEqual(announcement["author"], "Administrator")
        self.assertTrue(announcement["is_important"])
        archived = self.client.post(
            f"/announcements/{record_id}/archive",
            data={"csrf_token": csrf},
        )
        self.assertEqual(archived.status_code, 302)
        self.assertEqual(
            self.client.get(f"/announcements/{record_id}/edit").status_code,
            409,
        )
        listing = self.client.get("/announcements?status=Archived")
        self.assertEqual(listing.status_code, 200)
        self.assertIn(b"Water service update", listing.data)
        self.assertNotIn(b">Edit</a>", listing.data)

    def test_settings_update_only_changes_an_existing_record(self):
        record_id = str(uuid4())
        setting = {
            "id": record_id,
            "default_late_fee": 100,
            "default_due_day": 5,
            "auto_late_fee_enabled": False,
            "auto_backup_enabled": True,
            "dark_mode": False,
            "landlord_name": "RAMP",
            "landlord_role": "Admin",
            "landlord_contact": "admin@example.com",
            "water_rate": 10,
            "electricity_rate": 12,
            "updated_at": "2026-01-01T00:00:00+00:00",
        }
        with ramp_app.get_db() as db:
            db.execute(
                "INSERT INTO records (section, id, data) VALUES (?, ?, ?)",
                ("settings", record_id, ramp_app._json_dumps(setting)),
            )
        csrf = self.csrf_token()
        response = self.client.post(
            f"/settings/{record_id}/edit",
            data={
                "csrf_token": csrf,
                "updated_at": setting["updated_at"],
                "default_late_fee": "150",
                "default_due_day": "10",
                "auto_late_fee_enabled": "true",
                "auto_backup_enabled": "true",
                "dark_mode": "false",
                "landlord_name": "RAMP Homes",
                "landlord_role": "Superadmin",
                "landlord_contact": "support@example.com",
                "water_rate": "11.5",
                "electricity_rate": "13",
            },
        )
        self.assertEqual(response.status_code, 302)
        updated = next(
            row for row in ramp_app.rows_for("settings")
            if str(row["id"]) == record_id
        )
        self.assertEqual(updated["default_due_day"], 10)
        self.assertEqual(updated["water_rate"], 11.5)
        self.assertEqual(
            self.client.post(
                "/settings/missing/edit",
                data={"csrf_token": csrf},
            ).status_code,
            404,
        )

    def test_live_settings_changes_patch_only_the_existing_row(self):
        config, auth = self.set_live_session()
        setting = {
            "id": "settings-main",
            "default_late_fee": 100,
            "default_due_day": 5,
            "auto_late_fee_enabled": False,
            "auto_backup_enabled": True,
            "dark_mode": False,
            "landlord_name": "RAMP",
            "landlord_role": "Admin",
            "landlord_contact": "admin@example.com",
            "water_rate": 10,
            "electricity_rate": 12,
            "updated_at": "2026-01-01T00:00:00+00:00",
        }
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(ramp_app, "_fetch_supabase_record", return_value=setting),
            patch.object(
                ramp_app.supabase_backend, "api_request", return_value=[{"id": "settings-main"}]
            ) as request_api,
        ):
            response = self.client.post(
                "/settings/settings-main/edit",
                data={
                    "csrf_token": "live-csrf",
                    "updated_at": setting["updated_at"],
                    "default_late_fee": "150",
                    "default_due_day": "10",
                    "auto_late_fee_enabled": "true",
                    "auto_backup_enabled": "true",
                    "dark_mode": "false",
                    "landlord_name": "RAMP Homes",
                    "landlord_role": "Superadmin",
                    "landlord_contact": "support@example.com",
                    "water_rate": "11.5",
                    "electricity_rate": "13",
                },
            )
        self.assertEqual(response.status_code, 302)
        self.assertEqual(request_api.call_args.args[2], "settings")
        self.assertEqual(request_api.call_args.kwargs["method"], "PATCH")
        self.assertEqual(
            request_api.call_args.kwargs["query"]["updated_at"],
            f"eq.{setting['updated_at']}",
        )

    def test_settings_form_rejects_stale_version(self):
        config, auth = self.set_live_session()
        setting = {
            "id": "settings-main",
            "default_late_fee": 100,
            "default_due_day": 5,
            "auto_late_fee_enabled": False,
            "auto_backup_enabled": True,
            "dark_mode": False,
            "landlord_name": "RAMP",
            "landlord_role": "Admin",
            "landlord_contact": "admin@example.com",
            "water_rate": 10,
            "electricity_rate": 12,
            "updated_at": "2026-01-02T00:00:00+00:00",
        }
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(ramp_app, "_fetch_supabase_record", return_value=setting),
            patch.object(ramp_app.supabase_backend, "api_request") as request_api,
        ):
            response = self.client.post(
                "/settings/settings-main/edit",
                data={
                    "csrf_token": "live-csrf",
                    "updated_at": "2026-01-01T00:00:00+00:00",
                    "default_due_day": "99",
                },
            )
        self.assertEqual(response.status_code, 409)
        self.assertIn(b"Settings changed after you opened this page.", response.data)
        self.assertIn(b'value="99"', response.data)
        request_api.assert_not_called()

    def test_document_and_rfid_loaders_do_not_select_private_identifiers_or_urls(self):
        config, auth = self.set_live_session()
        calls = []

        def fake_api_request(*args, **kwargs):
            calls.append((args, kwargs))
            return []

        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app.supabase_backend, "api_request", side_effect=fake_api_request
            ),
        ):
            documents = self.client.get("/documents")
            access_logs = self.client.get("/rfid-access")
        self.assertEqual(documents.status_code, 200)
        self.assertEqual(access_logs.status_code, 200)
        selects = {
            args[2]: kwargs["query"]["select"]
            for args, kwargs in calls
        }
        self.assertNotIn("file_url", selects["tenant_documents"])
        self.assertNotIn("card_uid", selects["rfid_access_logs"])

    def test_global_search_returns_matches_from_safe_list_data(self):
        csrf = self.csrf_token()
        self.client.post(
            "/landlords/new",
            data={
                "csrf_token": csrf,
                "name": "Morgan Rivera",
                "company": "Rivera Homes",
                "email": "morgan@example.com",
                "phone": "",
            },
        )
        response = self.client.get("/search?q=Morgan")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Search results", response.data)
        self.assertIn(b"Morgan Rivera", response.data)
        self.assertIn(b"Landlords", response.data)
        self.assertIn(b"View all", response.data)

    def test_run_guide_contains_only_the_run_command(self):
        run_guide = (Path(ramp_app.__file__).parent / "RUN.md").read_text(
            encoding="utf-8"
        )
        self.assertEqual(run_guide.strip(), "```powershell\npython app.py\n```")

    def test_properties_and_tenants_pages_render_offline_data(self):
        properties = self.client.get("/properties")
        tenants = self.client.get("/tenants")
        self.assertEqual(properties.status_code, 200)
        self.assertEqual(tenants.status_code, 200)
        self.assertIn(b'id="offlinePageData"', properties.data)
        self.assertIn(b'id="offlinePageData"', tenants.data)
        self.assertIn(b'"landlords": []', properties.data)
        self.assertIn(b'"properties": []', tenants.data)

    def test_additional_admin_sections_render_empty_preview(self):
        for section in (
            "expenses",
            "public-listings",
            "documents",
            "announcements",
            "notifications",
            "events",
            "rfid-access",
            "utility-history",
            "settings",
        ):
            with self.subTest(section=section):
                response = self.client.get(f"/{section}")
                self.assertEqual(response.status_code, 200)

    def test_favicon_ico_redirects_to_svg_asset(self):
        response = self.client.get("/favicon.ico")
        self.assertEqual(response.status_code, 302)
        self.assertIn("/static/favicon.svg", response.headers["Location"])

    def test_create_edit_and_archive_landlord(self):
        csrf = self.csrf_token()
        response = self.client.post(
            "/landlords/new",
            data={
                "csrf_token": csrf,
                "name": "Jordan Lee",
                "company": "Lee Living",
                "email": "jordan@example.com",
                "phone": "+63 917 123 4567",
                "status": "Invited",
            },
        )
        self.assertEqual(response.status_code, 302)
        landlord = next(
            item for item in ramp_app.rows_for("landlords") if item["email"] == "jordan@example.com"
        )
        response = self.client.post(
            f"/landlords/{landlord['id']}/edit",
            data={
                "csrf_token": csrf,
                "name": "Jordan Lee",
                "company": "Lee & Co.",
                "email": "jordan@example.com",
                "phone": "",
            },
        )
        self.assertEqual(response.status_code, 302)
        for action in ("activate", "suspend", "archive"):
            response = self.client.post(
                f"/landlords/{landlord['id']}/transition",
                data={"csrf_token": csrf, "action": action},
            )
            self.assertEqual(response.status_code, 302)
        self.assertEqual(response.status_code, 302)
        changed = next(
            item for item in ramp_app.rows_for("landlords") if item["id"] == landlord["id"]
        )
        self.assertEqual(changed["company"], "Lee & Co.")
        self.assertEqual(changed["status"], "Archived")

    def test_active_landlord_can_be_archived_without_suspending_first(self):
        csrf = self.csrf_token()
        self.client.post(
            "/landlords/new",
            data={
                "csrf_token": csrf,
                "name": "Casey Lee",
                "company": "Casey Properties",
                "email": "casey@example.com",
                "phone": "",
            },
        )
        landlord = next(
            item for item in ramp_app.rows_for("landlords")
            if item["email"] == "casey@example.com"
        )
        self.assertEqual(
            self.client.post(
                f"/landlords/{landlord['id']}/transition",
                data={"csrf_token": csrf, "action": "activate"},
            ).status_code,
            302,
        )
        response = self.client.post(
            f"/landlords/{landlord['id']}/transition",
            data={"csrf_token": csrf, "action": "archive"},
        )
        self.assertEqual(response.status_code, 302)
        changed = next(
            item for item in ramp_app.rows_for("landlords")
            if item["id"] == landlord["id"]
        )
        self.assertEqual(changed["status"], "Archived")

    def test_create_edit_and_archive_properties_and_tenants(self):
        csrf = self.csrf_token()
        property_response = self.client.post(
            "/properties/new",
            data={
                "csrf_token": csrf,
                "unit_number": "A-12",
                "name": "Harbor House",
                "location": "Pasay",
                "landlord_id": "",
                "monthly_rent": "25000",
                "status": "Vacant",
            },
        )
        self.assertEqual(property_response.status_code, 302)
        property_row = next(
            row for row in ramp_app.rows_for("properties")
            if row.get("unit_number") == "A-12"
        )
        property_id = str(property_row["id"])
        edit_property = self.client.post(
            f"/properties/{property_id}/edit",
            data={
                "csrf_token": csrf,
                "unit_number": "A-12",
                "name": "Harbor House Updated",
                "location": "Pasay",
                "landlord_id": "",
                "monthly_rent": "26000",
                "status": "Occupied",
            },
        )
        self.assertEqual(edit_property.status_code, 302)
        archive_property = self.client.post(
            f"/properties/{property_id}/archive",
            data={"csrf_token": csrf},
        )
        self.assertEqual(archive_property.status_code, 302)
        self.assertEqual(self.client.get(f"/properties/{property_id}/edit").status_code, 409)

        tenant_response = self.client.post(
            "/tenants/new",
            data={
                "csrf_token": csrf,
                "name": "Taylor Lee",
                "email": "taylor@example.com",
                "phone": "+63 917 123 4567",
                "unit_id": "",
                "landlord_id": "",
                "status": "Active",
                "monthly_rent": "12000",
                "lease_start": "2026-01-01",
                "lease_end": "2026-12-31",
                "balance": "0",
            },
        )
        self.assertEqual(tenant_response.status_code, 302)
        tenant = next(
            row for row in ramp_app.rows_for("tenants")
            if row.get("email") == "taylor@example.com"
        )
        tenant_id = str(tenant["id"])
        self.assertEqual(
            self.client.post(
                f"/tenants/{tenant_id}/archive",
                data={"csrf_token": csrf},
            ).status_code,
            302,
        )
        self.assertEqual(self.client.get(f"/tenants/{tenant_id}/edit").status_code, 409)

    def test_entity_status_and_date_values_are_validated(self):
        csrf = self.csrf_token()
        missing_property_name = self.client.post(
            "/properties/new",
            data={
                "csrf_token": csrf,
                "unit_number": "A-12",
                "status": "Vacant",
            },
        )
        self.assertEqual(missing_property_name.status_code, 400)
        invalid_status = self.client.post(
            "/properties/new",
            data={
                "csrf_token": csrf,
                "unit_number": "A-12",
                "name": "Harbor House",
                "status": "Available",
            },
        )
        self.assertEqual(invalid_status.status_code, 400)
        invalid_date = self.client.post(
            "/tenants/new",
            data={
                "csrf_token": csrf,
                "name": "Taylor Lee",
                "status": "Active",
                "lease_start": "20260101",
            },
        )
        self.assertEqual(invalid_date.status_code, 400)
        earlier_than_allowed = self.client.post(
            "/tenants/new",
            data={
                "csrf_token": csrf,
                "name": "Taylor Lee",
                "status": "Active",
                "lease_start": "2024-12-31",
            },
        )
        self.assertEqual(earlier_than_allowed.status_code, 400)

    def test_entity_validation_renders_server_error_and_preserves_input(self):
        response = self.client.post(
            "/properties/new",
            data={
                "csrf_token": self.csrf_token(),
                "record_id": str(uuid4()),
                "unit_number": "A-12",
                "name": "Harbor House",
                "status": "Invalid",
            },
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn(b'class="form-error" role="alert"', response.data)
        self.assertIn(b'value="Harbor House"', response.data)
        self.assertIn(b'value="Invalid" selected', response.data)

    def test_date_inputs_enforce_2025_minimum(self):
        response = self.client.get("/tenants/new")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b'min="2025-01-01"', response.data)
        expense = self.client.get("/expenses/new")
        self.assertEqual(expense.status_code, 200)
        self.assertIn(b'min="2025-01-01"', expense.data)

    def test_edit_forms_require_confirmation(self):
        csrf = self.csrf_token()
        self.client.post(
            "/landlords/new",
            data={
                "csrf_token": csrf,
                "name": "Amara Santos",
                "company": "Santos Property Group",
                "email": "amara@example.com",
                "phone": "+63 917 123 4567",
            },
        )
        landlord = ramp_app.rows_for("landlords")[0]
        response = self.client.get(f"/landlords/{landlord['id']}/edit")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Save changes to this landlord?", response.data)

    def test_entity_validation_rejects_bad_relationship_and_lease_range(self):
        csrf = self.csrf_token()
        invalid_relationship = self.client.post(
            "/tenants/new",
            data={
                "csrf_token": csrf,
                "name": "Taylor Lee",
                "status": "Active",
                "unit_id": str(uuid4()),
            },
        )
        self.assertEqual(invalid_relationship.status_code, 400)
        invalid_lease = self.client.post(
            "/tenants/new",
            data={
                "csrf_token": csrf,
                "name": "Taylor Lee",
                "status": "Active",
                "lease_start": "2026-12-01",
                "lease_end": "2026-01-01",
            },
        )
        self.assertEqual(invalid_lease.status_code, 400)

    def test_form_validation_error_is_returned_as_readable_json(self):
        csrf = self.csrf_token()
        response = self.client.post(
            "/properties/new",
            data={
                "csrf_token": csrf,
                "unit_number": "A-12",
                "name": "Harbor House",
                "status": "Invalid",
            },
            headers={"X-Ramp-Form-Request": "1"},
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json["error"], "Choose a valid status.")

    def test_supabase_permission_error_explains_rls_denial(self):
        config, auth = self.set_live_session()
        failure = ramp_app.supabase_backend.SupabaseRequestError(403, "rls_denied")
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app.supabase_backend, "api_request", side_effect=failure
            ),
        ):
            response = self.client.post(
                "/properties/new",
                data={
                    "csrf_token": "live-csrf",
                    "record_id": str(uuid4()),
                    "unit_number": "B-14",
                    "name": "Harbor Homes",
                    "status": "Vacant",
                },
                headers={"X-Ramp-Form-Request": "1"},
            )
        self.assertEqual(response.status_code, 403)
        self.assertIn("Row Level Security", response.json["error"])

    def test_archived_property_cannot_be_edited(self):
        config, auth = self.set_live_session()
        record_id = str(uuid4())
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app.supabase_backend,
                "api_request",
                return_value=[{"id": record_id, "is_archived": True}],
            ) as request_api,
        ):
            response = self.client.post(
                f"/properties/{record_id}/edit",
                data={"csrf_token": "live-csrf", "updated_at": "old-version"},
            )
        self.assertEqual(response.status_code, 409)
        request_api.assert_called_once()

    def test_unit_door_lock_route_is_removed(self):
        response = self.client.get(f"/properties/{uuid4()}/door-lock")
        self.assertEqual(response.status_code, 404)

    def test_tenant_detail_excludes_credentials_and_marks_private_information(self):
        config, auth = self.set_live_session()
        tenant_id = str(uuid4())
        tenant_row = {
            "id": tenant_id,
            "name": "Taylor Lee",
            "email": "taylor@example.com",
            "address": "Private address",
            "health_status": "Needs follow-up",
            "password": "must-not-be-rendered",
        }
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app.supabase_backend,
                "api_request",
                side_effect=[[tenant_row], [], [], []],
            ) as request_api,
        ):
            response = self.client.get(f"/tenants/{tenant_id}")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Private details", response.data)
        self.assertIn(b"Needs follow-up", response.data)
        self.assertNotIn(b"must-not-be-rendered", response.data)
        self.assertNotIn("password", request_api.call_args_list[0].kwargs["query"]["select"])

    def test_inquiry_review_uses_existing_authenticated_rpc(self):
        config, auth = self.set_live_session()
        inquiry_id = str(uuid4())
        unit_id = str(uuid4())
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app,
                "_fetch_supabase_record",
                side_effect=[
                    {"id": inquiry_id, "status": "pending"},
                    {
                        "id": unit_id,
                        "is_archived": False,
                        "status": "Vacant",
                        "tenant_id": None,
                    },
                ],
            ),
            patch.object(ramp_app.supabase_backend, "rpc_request") as review_rpc,
        ):
            response = self.client.post(
                f"/inquiries/{inquiry_id}/review",
                data={
                    "csrf_token": "live-csrf",
                    "decision": "approve",
                    "assigned_unit_id": unit_id,
                    "internal_note": "  Reviewed by admin  ",
                },
            )
        self.assertEqual(response.status_code, 302)
        review_rpc.assert_called_once_with(
            config,
            "admin-access-token",
            "review_tenant_inquiry",
            {
                "p_inquiry_id": inquiry_id,
                "p_decision": "approve",
                "p_assigned_unit_id": unit_id,
                "p_internal_note": "Reviewed by admin",
            },
        )

    def test_payment_receipt_review_uses_authenticated_rpc_with_reason(self):
        config, auth = self.set_live_session()
        payment_id = "pay_123"
        payment = {
            "id": payment_id,
            "status": "Pending Review",
            "tenant_id": "tenant_123",
            "proof_image_url": "tenant_123/pay_123/receipt.webp",
        }
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(ramp_app, "_fetch_supabase_record", return_value=payment),
            patch.object(ramp_app.supabase_backend, "rpc_request") as review_rpc,
        ):
            response = self.client.post(
                f"/payments/{payment_id}/review",
                data={
                    "csrf_token": "live-csrf",
                    "decision": "decline",
                    "decline_reason": "  Reference does not match  ",
                },
            )
        self.assertEqual(response.status_code, 302)
        review_rpc.assert_called_once_with(
            config,
            "admin-access-token",
            "review_tenant_payment_receipt",
            {
                "p_payment_id": payment_id,
                "p_decision": "decline",
                "p_decline_reason": "Reference does not match",
            },
        )

    def test_payment_receipt_review_requires_reason_and_unreviewed_state(self):
        config, auth = self.set_live_session()
        pending = {
            "id": "pay_123",
            "status": "Pending",
            "tenant_id": "tenant_123",
            "proof_image_url": "tenant_123/pay_123/receipt.webp",
        }
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(ramp_app, "_fetch_supabase_record", return_value=pending),
            patch.object(ramp_app.supabase_backend, "rpc_request") as review_rpc,
        ):
            missing_reason = self.client.post(
                "/payments/pay_123/review",
                data={
                    "csrf_token": "live-csrf",
                    "decision": "decline",
                    "decline_reason": "  ",
                },
            )
        self.assertEqual(missing_reason.status_code, 400)
        review_rpc.assert_not_called()

        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app,
                "_fetch_supabase_record",
                return_value={**pending, "status": "Paid"},
            ),
            patch.object(ramp_app.supabase_backend, "rpc_request") as review_rpc,
        ):
            already_reviewed = self.client.post(
                "/payments/pay_123/review",
                data={"csrf_token": "live-csrf", "decision": "approve"},
            )
        self.assertEqual(already_reviewed.status_code, 409)
        review_rpc.assert_not_called()

    def test_payment_receipt_route_returns_short_lived_signed_redirect(self):
        config, auth = self.set_live_session()
        payment = {
            "id": "pay_123",
            "tenant_id": "tenant_123",
            "proof_image_url": "tenant_123/pay_123/receipt.webp",
        }
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(ramp_app, "_fetch_supabase_record", return_value=payment),
            patch.object(
                ramp_app.supabase_backend,
                "create_signed_storage_url",
                return_value="https://example.supabase.co/storage/v1/object/sign/receipt?token=x",
            ) as sign_url,
        ):
            response = self.client.get("/payments/pay_123/receipt")
        self.assertEqual(response.status_code, 302)
        self.assertEqual(
            response.headers["Location"],
            "https://example.supabase.co/storage/v1/object/sign/receipt?token=x",
        )
        sign_url.assert_called_once_with(
            config,
            "admin-access-token",
            "tenant-payment-receipts",
            "tenant_123/pay_123/receipt.webp",
            expires_in=300,
        )

    def test_signed_storage_url_rejects_unexpected_host_and_object_path(self):
        config = ramp_app.supabase_backend.SupabaseSettings(
            "https://example.supabase.co", "test-publishable-key"
        )
        with patch.object(
            ramp_app.supabase_backend,
            "_request",
            return_value={"signedURL": "https://attacker.example/file"},
        ):
            with self.assertRaises(
                ramp_app.supabase_backend.SupabaseRequestError
            ):
                ramp_app.supabase_backend.create_signed_storage_url(
                    config,
                    "admin-access-token",
                    "tenant-payment-receipts",
                    "tenant_123/pay_123/receipt.webp",
                )
        with self.assertRaises(ValueError):
            ramp_app.supabase_backend.create_signed_storage_url(
                config,
                "admin-access-token",
                "tenant-payment-receipts",
                "tenant_123/pay_123/../private.webp",
            )

    def test_unit_media_storage_is_scoped_to_the_public_bucket_and_unit_paths(self):
        config = ramp_app.supabase_backend.SupabaseSettings(
            "https://example.supabase.co", "test-publishable-key"
        )
        unit_id = str(uuid4())
        object_path = f"units/{unit_id}/photo.webp"
        with patch.object(ramp_app.supabase_backend, "_request") as storage_request:
            ramp_app.supabase_backend.upload_unit_media(
                config, "admin-access-token", object_path, b"image", "image/webp"
            )
        storage_request.assert_called_once()
        self.assertIn("/storage/v1/object/ramp_media/units/", storage_request.call_args.args[1])
        self.assertEqual(storage_request.call_args.kwargs["body"], b"image")
        self.assertEqual(storage_request.call_args.kwargs["content_type"], "image/webp")

        with self.assertRaises(ValueError):
            ramp_app.supabase_backend.delete_unit_media(
                config, "admin-access-token", "other-folder/private.webp"
            )

    def test_unit_media_public_urls_normalize_to_safe_object_paths(self):
        config = ramp_app.supabase_backend.SupabaseSettings(
            "https://example.supabase.co", "test-publishable-key"
        )
        unit_id = str(uuid4())
        path = f"units/{unit_id}/room photo (1).jpg"
        public_url = (
            f"{config.url}/storage/v1/object/public/ramp_media/"
            f"units/{unit_id}/room%20photo%20%281%29.jpg"
        )

        self.assertEqual(
            ramp_app.supabase_backend.unit_media_object_path(config, public_url),
            path,
        )
        self.assertEqual(
            ramp_app.supabase_backend.unit_media_object_path(config, path),
            path,
        )
        with self.assertRaises(ValueError):
            ramp_app.supabase_backend.unit_media_object_path(
                config, public_url.replace("example.supabase.co", "other.example.com")
            )
        with self.assertRaises(ValueError):
            ramp_app.supabase_backend.unit_media_object_path(
                config, public_url.replace("ramp_media", "private_bucket")
            )

    def test_unit_detail_renders_existing_public_storage_photo_urls(self):
        config, auth = self.set_live_session()
        unit_id = str(uuid4())
        photo_url = (
            f"{config.url}/storage/v1/object/public/ramp_media/"
            f"units/{unit_id}/existing%20photo.jpg"
        )
        unit = {
            "id": unit_id,
            "unit_number": "A-12",
            "name": "Harbor House",
            "images": [photo_url],
            "image_url": photo_url,
            "is_archived": False,
        }
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(ramp_app, "_fetch_supabase_record", return_value=unit),
            patch.object(ramp_app, "_fetch_supabase_related", return_value=[]),
        ):
            response = self.client.get(f"/properties/{unit_id}")

        self.assertEqual(response.status_code, 200)
        self.assertIn(photo_url.encode(), response.data)
        self.assertIn(b"Unit photos", response.data)

    def test_live_property_create_uploads_unit_photo_and_stores_its_public_url(self):
        config, auth = self.set_live_session()
        record_id = str(uuid4())
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app.supabase_backend, "upload_unit_media"
            ) as upload_photo,
            patch.object(
                ramp_app.supabase_backend, "api_request", return_value=[{"id": record_id}]
            ) as request_api,
        ):
            response = self.client.post(
                "/properties/new",
                data={
                    "csrf_token": "live-csrf",
                    "record_id": record_id,
                    "unit_number": "B-14",
                    "name": "Harbor Homes",
                    "location": "Pasay",
                    "landlord_id": "",
                    "monthly_rent": "25000",
                    "status": "Vacant",
                    "unit_images": (io.BytesIO(b"\xff\xd8\xffunit photo"), "unit.jpg"),
                },
            )
        self.assertEqual(response.status_code, 302)
        upload_photo.assert_called_once()
        self.assertEqual(upload_photo.call_args.args[1], "admin-access-token")
        object_path = upload_photo.call_args.args[2]
        self.assertTrue(object_path.startswith(f"units/{record_id}/"))
        public_url = ramp_app.supabase_backend.public_unit_media_url(config, object_path)
        self.assertEqual(request_api.call_args.kwargs["body"]["images"], [public_url])
        self.assertEqual(request_api.call_args.kwargs["body"]["image_url"], public_url)

    def test_unit_photo_removal_updates_unit_and_deletes_storage_object(self):
        config, auth = self.set_live_session()
        record_id = str(uuid4())
        object_path = f"units/{record_id}/existing.webp"
        public_url = ramp_app.supabase_backend.public_unit_media_url(config, object_path)
        unit = {
            "id": record_id,
            "unit_number": "B-14",
            "name": "Harbor Homes",
            "location": "Pasay",
            "landlord_id": None,
            "rent": 25000,
            "monthly_rent": 25000,
            "status": "Vacant",
            "images": [public_url],
            "image_url": public_url,
        }
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app.supabase_backend,
                "api_request",
                side_effect=[[unit], [{"id": record_id}]],
            ) as request_api,
            patch.object(
                ramp_app.supabase_backend, "delete_unit_media"
            ) as delete_photo,
        ):
            response = self.client.post(
                f"/properties/{record_id}/edit",
                data={
                    "csrf_token": "live-csrf",
                    "unit_number": "B-14",
                    "name": "Harbor Homes",
                    "location": "Pasay",
                    "landlord_id": "",
                    "monthly_rent": "25000",
                    "status": "Vacant",
                    "remove_images": object_path,
                },
            )
        self.assertEqual(response.status_code, 302)
        self.assertEqual(request_api.call_args.kwargs["body"]["images"], [])
        self.assertIsNone(request_api.call_args.kwargs["body"]["image_url"])
        delete_photo.assert_called_once_with(config, "admin-access-token", object_path)

    def test_unit_photo_cover_can_be_changed_without_reuploading(self):
        config, auth = self.set_live_session()
        record_id = str(uuid4())
        first_path = f"units/{record_id}/first.webp"
        second_path = f"units/{record_id}/second.webp"
        first_url = ramp_app.supabase_backend.public_unit_media_url(config, first_path)
        second_url = ramp_app.supabase_backend.public_unit_media_url(config, second_path)
        unit = {
            "id": record_id,
            "unit_number": "B-14",
            "name": "Harbor Homes",
            "location": "Pasay",
            "landlord_id": None,
            "rent": 25000,
            "monthly_rent": 25000,
            "status": "Vacant",
            "images": [first_url, second_url],
            "image_url": first_url,
        }
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app.supabase_backend,
                "api_request",
                side_effect=[[unit], [{"id": record_id}]],
            ) as request_api,
            patch.object(
                ramp_app.supabase_backend, "delete_unit_media"
            ) as delete_photo,
        ):
            response = self.client.post(
                f"/properties/{record_id}/edit",
                data={
                    "csrf_token": "live-csrf",
                    "unit_number": "B-14",
                    "name": "Harbor Homes",
                    "location": "Pasay",
                    "landlord_id": "",
                    "monthly_rent": "25000",
                    "status": "Vacant",
                    "cover_image": second_path,
                },
            )
        self.assertEqual(response.status_code, 302)
        self.assertEqual(request_api.call_args.kwargs["body"]["images"], [first_url, second_url])
        self.assertEqual(request_api.call_args.kwargs["body"]["image_url"], second_url)
        delete_photo.assert_not_called()

    def test_unit_photo_upload_rejects_unrecognized_content(self):
        config, auth = self.set_live_session()
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app.supabase_backend, "upload_unit_media"
            ) as upload_photo,
            patch.object(ramp_app.supabase_backend, "api_request") as request_api,
        ):
            response = self.client.post(
                "/properties/new",
                data={
                    "csrf_token": "live-csrf",
                    "record_id": str(uuid4()),
                    "unit_number": "B-14",
                    "name": "Harbor Homes",
                    "location": "Pasay",
                    "landlord_id": "",
                    "status": "Vacant",
                    "unit_images": (io.BytesIO(b"<svg onload=alert(1)>"), "unit.svg"),
                },
                headers={"X-Ramp-Form-Request": "1"},
            )
        self.assertEqual(response.status_code, 400)
        self.assertIn(b"Use a JPEG, PNG, or WebP image", response.data)
        upload_photo.assert_not_called()
        request_api.assert_not_called()

    def test_unit_photo_upload_enforces_file_size_and_count_limits(self):
        config, auth = self.set_live_session()
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app.supabase_backend, "upload_unit_media"
            ) as upload_photo,
            patch.object(ramp_app.supabase_backend, "api_request") as request_api,
        ):
            oversized = self.client.post(
                "/properties/new",
                data={
                    "csrf_token": "live-csrf",
                    "record_id": str(uuid4()),
                    "unit_number": "B-14",
                    "name": "Harbor Homes",
                    "location": "Pasay",
                    "landlord_id": "",
                    "status": "Vacant",
                    "unit_images": (
                        io.BytesIO(b"\xff\xd8\xff" + b"x" * ramp_app.UNIT_PHOTO_MAX_FILE_BYTES),
                        "large.jpg",
                    ),
                },
                headers={"X-Ramp-Form-Request": "1"},
            )
            too_many = self.client.post(
                "/properties/new",
                data={
                    "csrf_token": "live-csrf",
                    "record_id": str(uuid4()),
                    "unit_number": "B-14",
                    "name": "Harbor Homes",
                    "location": "Pasay",
                    "landlord_id": "",
                    "status": "Vacant",
                    "unit_images": [
                        (io.BytesIO(b"\xff\xd8\xffphoto"), f"photo-{index}.jpg")
                        for index in range(ramp_app.UNIT_PHOTO_MAX_FILES + 1)
                    ],
                },
                headers={"X-Ramp-Form-Request": "1"},
            )
        self.assertEqual(oversized.status_code, 400)
        self.assertIn(b"5 MB or smaller", oversized.data)
        self.assertEqual(too_many.status_code, 400)
        self.assertIn(b"no more than 5", too_many.data)
        upload_photo.assert_not_called()
        request_api.assert_not_called()

    def test_payment_receipt_route_rejects_unrelated_or_public_urls(self):
        config, auth = self.set_live_session()
        unsafe_paths = (
            "https://example.com/receipt.webp",
            "another_tenant/pay_123/receipt.webp",
            "tenant_123/another_payment/receipt.webp",
        )
        for path in unsafe_paths:
            with self.subTest(path=path):
                with (
                    patch.object(
                        ramp_app.supabase_backend, "settings", return_value=config
                    ),
                    patch.object(
                        ramp_app.supabase_backend,
                        "load_session",
                        return_value=(auth, "live-csrf"),
                    ),
                    patch.object(
                        ramp_app,
                        "_fetch_supabase_record",
                        return_value={
                            "id": "pay_123",
                            "tenant_id": "tenant_123",
                            "proof_image_url": path,
                        },
                    ),
                    patch.object(
                        ramp_app.supabase_backend, "create_signed_storage_url"
                    ) as sign_url,
                ):
                    response = self.client.get("/payments/pay_123/receipt")
                self.assertEqual(response.status_code, 404)
                sign_url.assert_not_called()

    def test_inquiry_review_allows_approval_without_an_assigned_unit(self):
        config, auth = self.set_live_session()
        inquiry_id = str(uuid4())
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app,
                "_fetch_supabase_record",
                return_value={"id": inquiry_id, "status": "pending"},
            ),
            patch.object(ramp_app.supabase_backend, "rpc_request") as review_rpc,
        ):
            response = self.client.post(
                f"/inquiries/{inquiry_id}/review",
                data={
                    "csrf_token": "live-csrf",
                    "decision": "approve",
                    "assigned_unit_id": "",
                    "internal_note": "",
                },
            )

        self.assertEqual(response.status_code, 302)
        review_rpc.assert_called_once_with(
            config,
            "admin-access-token",
            "review_tenant_inquiry",
            {
                "p_inquiry_id": inquiry_id,
                "p_decision": "approve",
                "p_assigned_unit_id": None,
                "p_internal_note": "",
            },
        )

    def test_inquiry_review_rejects_notes_over_database_limit(self):
        config, auth = self.set_live_session()
        inquiry_id = str(uuid4())
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app,
                "_fetch_supabase_record",
                return_value={"id": inquiry_id, "status": "pending"},
            ),
            patch.object(ramp_app.supabase_backend, "rpc_request") as review_rpc,
        ):
            response = self.client.post(
                f"/inquiries/{inquiry_id}/review",
                data={
                    "csrf_token": "live-csrf",
                    "decision": "decline",
                    "internal_note": "x" * 1001,
                },
            )

        self.assertEqual(response.status_code, 400)
        self.assertIn(b"1,000 characters or fewer", response.data)
        review_rpc.assert_not_called()

    def test_inquiry_review_requires_a_valid_uuid_and_renders_a_helpful_error(self):
        config, auth = self.set_live_session()
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(ramp_app, "_fetch_supabase_record") as fetch_record,
        ):
            response = self.client.post(
                "/inquiries/not-a-uuid/review",
                data={"csrf_token": "live-csrf", "decision": "approve"},
            )
        self.assertEqual(response.status_code, 404)
        self.assertIn(b'class="panel error-card"', response.data)
        self.assertIn(b"Page not found", response.data)
        fetch_record.assert_not_called()

    def test_inquiry_review_method_error_uses_styled_page_and_keeps_allow_header(self):
        config, auth = self.set_live_session()
        inquiry_id = str(uuid4())
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
        ):
            response = self.client.get(f"/inquiries/{inquiry_id}/review")
        self.assertEqual(response.status_code, 405)
        self.assertIn("POST", response.headers["Allow"])
        self.assertIn(b'class="panel error-card"', response.data)
        self.assertIn(b"Request could not be completed", response.data)

    def test_inquiry_review_missing_decision_returns_to_review_page(self):
        config, auth = self.set_live_session()
        inquiry_id = str(uuid4())
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app,
                "_fetch_supabase_record",
                return_value={"id": inquiry_id, "status": "pending"},
            ),
            patch.object(ramp_app, "fetch_supabase_table", return_value=[]),
            patch.object(ramp_app.supabase_backend, "rpc_request") as review_rpc,
        ):
            response = self.client.post(
                f"/inquiries/{inquiry_id}/review",
                data={"csrf_token": "live-csrf"},
                follow_redirects=True,
            )
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Choose Approve or Decline", response.data)
        self.assertIn(b"Review inquiry", response.data)
        review_rpc.assert_not_called()

    def test_inquiry_review_preserves_optional_unit_assignment(self):
        config, auth = self.set_live_session()
        inquiry_id = str(uuid4())
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app,
                "_fetch_supabase_record",
                return_value={"id": inquiry_id, "status": "pending"},
            ),
            patch.object(ramp_app.supabase_backend, "rpc_request") as review_rpc,
        ):
            response = self.client.post(
                f"/inquiries/{inquiry_id}/review",
                data={"csrf_token": "live-csrf", "decision": "approve"},
            )
        self.assertEqual(response.status_code, 302)
        self.assertEqual(
            review_rpc.call_args.args[3]["p_assigned_unit_id"],
            None,
        )

    def test_inquiry_review_only_lists_vacant_unassigned_units(self):
        config, auth = self.set_live_session()
        inquiry_id = str(uuid4())
        units = [
            {
                "id": str(uuid4()),
                "unit_number": "A-101",
                "status": "Vacant",
                "is_archived": False,
                "tenant_id": None,
            },
            {
                "id": str(uuid4()),
                "unit_number": "A-102",
                "status": "Occupied",
                "is_archived": False,
                "tenant_id": str(uuid4()),
            },
            {
                "id": str(uuid4()),
                "unit_number": "A-103",
                "status": "Vacant",
                "is_archived": True,
                "tenant_id": None,
            },
            {
                "id": str(uuid4()),
                "unit_number": "A-104",
                "status": "Vacant",
                "is_archived": False,
                "tenant_id": str(uuid4()),
            },
        ]
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app,
                "_fetch_supabase_record",
                return_value={"id": inquiry_id, "status": "pending"},
            ),
            patch.object(ramp_app, "fetch_supabase_table", return_value=units),
        ):
            response = self.client.get(f"/inquiries/{inquiry_id}")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"class=\"detail-layout inquiry-detail-layout\"", response.data)
        self.assertIn(b"class=\"detail-related inquiry-review-column\"", response.data)
        self.assertIn(b"A-101", response.data)
        self.assertNotIn(b"A-102", response.data)
        self.assertNotIn(b"A-103", response.data)
        self.assertNotIn(b"A-104", response.data)
        self.assertIn(b"Only vacant, non-archived units", response.data)

    def test_inquiry_review_rejects_a_unit_that_is_no_longer_available(self):
        config, auth = self.set_live_session()
        inquiry_id = str(uuid4())
        unit_id = str(uuid4())
        inquiry = {"id": inquiry_id, "status": "pending"}
        occupied_unit = {
            "id": unit_id,
            "is_archived": False,
            "status": "Occupied",
            "tenant_id": str(uuid4()),
        }
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app,
                "_fetch_supabase_record",
                side_effect=[inquiry, occupied_unit, inquiry],
            ),
            patch.object(ramp_app, "fetch_supabase_table", return_value=[]),
            patch.object(ramp_app.supabase_backend, "rpc_request") as review_rpc,
        ):
            response = self.client.post(
                f"/inquiries/{inquiry_id}/review",
                data={
                    "csrf_token": "live-csrf",
                    "decision": "approve",
                    "assigned_unit_id": unit_id,
                },
                follow_redirects=True,
            )
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"That unit is no longer available", response.data)
        review_rpc.assert_not_called()

    def test_inquiry_internal_note_is_rendered_as_text(self):
        config, auth = self.set_live_session()
        inquiry_id = str(uuid4())
        inquiry = {
            "id": inquiry_id,
            "status": "declined",
            "internal_note": "<script>alert(1)</script>",
        }
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(ramp_app, "_fetch_supabase_record", return_value=inquiry),
        ):
            response = self.client.get(f"/inquiries/{inquiry_id}")
        self.assertEqual(response.status_code, 200)
        self.assertNotIn(b"<script>alert(1)</script>", response.data)
        self.assertIn(b"&lt;script&gt;alert(1)&lt;/script&gt;", response.data)

    def test_stale_property_edit_is_rejected_without_writing(self):
        config, auth = self.set_live_session()
        record_id = str(uuid4())
        record = {
            "id": record_id,
            "unit_number": "A-12",
            "name": "Harbor House",
            "location": "Pasay",
            "landlord_id": None,
            "rent": 25000,
            "status": "Vacant",
            "is_archived": False,
            "updated_at": "2026-02-01T00:00:00Z",
        }
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app.supabase_backend, "api_request", return_value=[record]
            ) as request_api,
        ):
            response = self.client.post(
                f"/properties/{record_id}/edit",
                data={
                    "csrf_token": "live-csrf",
                    "updated_at": "2026-01-01T00:00:00Z",
                    "unit_number": "A-12",
                    "name": "New name",
                    "status": "Vacant",
                },
            )
        self.assertEqual(response.status_code, 409)
        request_api.assert_called_once()

    def test_live_superadmin_directory_normalizes_profiles(self):
        config, auth = self.set_live_session()
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app.supabase_backend,
                "api_request",
                return_value=[
                    {
                        "id": "profile-id",
                        "uid": "other-admin",
                        "email": "casey@example.com",
                        "display_name": "Casey Admin",
                        "role": "super_admin",
                        "is_approved": False,
                    }
                ],
            ),
        ):
            response = self.client.get("/superadmins")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Casey Admin", response.data)
        self.assertIn(b"Disabled", response.data)

    def test_superadmin_directory_is_not_fabricated_in_preview(self):
        response = self.client.get("/superadmins")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Superadmins", response.data)
        self.assertNotIn(b"Alex Morgan", response.data)
        self.assertNotIn(b"Invite superadmin", response.data)
        self.assertEqual(self.client.get("/superadmins/new").status_code, 503)

    def test_live_property_create_uses_authenticated_supabase_token(self):
        config, auth = self.set_live_session()
        record_id = str(uuid4())
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app.supabase_backend, "api_request", return_value=[{"id": record_id}]
            ) as request_api,
        ):
            response = self.client.post(
                "/properties/new",
                data={
                    "csrf_token": "live-csrf",
                    "record_id": record_id,
                    "unit_number": "B-14",
                    "name": "Harbor Homes",
                    "location": "Pasay",
                    "landlord_id": "",
                    "monthly_rent": "25000",
                    "status": "Vacant",
                },
            )
        self.assertEqual(response.status_code, 302)
        request_api.assert_called_once()
        self.assertEqual(request_api.call_args.args[0], config)
        self.assertEqual(request_api.call_args.args[1], "admin-access-token")
        self.assertEqual(request_api.call_args.args[2], "units")
        self.assertEqual(request_api.call_args.kwargs["method"], "POST")
        self.assertEqual(request_api.call_args.kwargs["body"]["id"], record_id)

    def test_live_landlord_edit_updates_profile_with_authenticated_token(self):
        config, auth = self.set_live_session()
        record_id = str(uuid4())
        landlord = {
            "id": record_id,
            "uid": "landlord-user-uid",
            "name": "Demo Landlord",
            "company_name": "Demo Properties",
            "email": "landlord@example.com",
            "phone": "09171234567",
            "status": "active",
            "updated_at": "2026-11-12T10:00:00Z",
        }
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app.supabase_backend,
                "api_request",
                side_effect=[[], [landlord], [{"id": record_id}]],
            ) as request_api,
        ):
            response = self.client.post(
                f"/landlords/{record_id}/edit",
                data={
                    "csrf_token": "live-csrf",
                    "updated_at": landlord["updated_at"],
                    "name": "Demo Landlord Updated",
                    "company": "Demo Properties",
                    "email": landlord["email"],
                    "phone": "0917-123-4567",
                },
                headers={"X-Ramp-Form-Request": "1"},
            )
        self.assertEqual(response.status_code, 302)
        patch_call = request_api.call_args
        self.assertEqual(patch_call.args[2], "landlords")
        self.assertEqual(patch_call.kwargs["method"], "PATCH")
        self.assertEqual(patch_call.kwargs["body"]["name"], "Demo Landlord Updated")
        self.assertEqual(patch_call.kwargs["body"]["phone"], "09171234567")

    def test_live_landlord_edit_accepts_numeric_record_id(self):
        config, auth = self.set_live_session()
        landlord = {
            "id": 12,
            "uid": "landlord-user-uid",
            "name": "Demo Landlord",
            "company_name": "Demo Properties",
            "email": "landlord@example.com",
            "phone": "",
            "status": "active",
        }
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app.supabase_backend, "api_request", return_value=[landlord]
            ),
        ):
            response = self.client.get("/landlords/12/edit")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Edit landlord", response.data)
        self.assertIn(b"Demo Landlord", response.data)

    def test_live_landlord_edit_reports_supabase_permission_denial(self):
        config, auth = self.set_live_session()
        record_id = str(uuid4())
        landlord = {
            "id": record_id,
            "uid": "landlord-user-uid",
            "name": "Demo Landlord",
            "company_name": "Demo Properties",
            "email": "landlord@example.com",
            "phone": "",
            "status": "active",
            "updated_at": "2026-11-12T10:00:00Z",
        }
        failure = ramp_app.supabase_backend.SupabaseRequestError(403, "rls_denied")
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app.supabase_backend,
                "api_request",
                side_effect=[[], [landlord], failure],
            ),
        ):
            response = self.client.post(
                f"/landlords/{record_id}/edit",
                data={
                    "csrf_token": "live-csrf",
                    "updated_at": landlord["updated_at"],
                    "name": "Demo Landlord Updated",
                    "company": "Demo Properties",
                    "email": landlord["email"],
                    "phone": "",
                },
                headers={"X-Ramp-Form-Request": "1"},
            )
        self.assertEqual(response.status_code, 403)
        self.assertIn("Row Level Security", response.json["error"])

    def test_offline_sync_replay_is_idempotent(self):
        config, auth = self.set_live_session()
        record_id = str(uuid4())
        change_id = str(uuid4())
        api_results = [[], [{"id": record_id}]]
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app.supabase_backend,
                "api_request",
                side_effect=api_results,
            ) as request_api,
        ):
            data = {
                "csrf_token": "live-csrf",
                "record_id": record_id,
                "unit_number": "C-02",
                "name": "Central Place",
                "location": "Makati",
                "landlord_id": "",
                "monthly_rent": "18000",
                "status": "Vacant",
            }
            headers = {
                "X-Ramp-Offline-Replay": "1",
                "X-Ramp-Offline-Change": change_id,
            }
            first = self.client.post("/properties/new", data=data, headers=headers)
            second = self.client.post("/properties/new", data=data, headers=headers)
        self.assertEqual(first.status_code, 200)
        self.assertEqual(first.json, {"synced": True})
        self.assertEqual(second.status_code, 200)
        self.assertTrue(second.json["duplicate"])
        self.assertEqual(request_api.call_count, 2)

    def test_superadmin_invitation_uses_existing_edge_function(self):
        config, auth = self.set_live_session()
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(ramp_app.supabase_backend, "invoke_function") as invite,
        ):
            response = self.client.post(
                "/superadmins/new",
                data={
                    "csrf_token": "live-csrf",
                    "display_name": "Jordan Lee",
                    "email": "jordan@example.com",
                },
            )
        self.assertEqual(response.status_code, 302)
        invite.assert_called_once_with(
            config,
            "admin-access-token",
            "invite-admin-account",
            {
                "email": "jordan@example.com",
                "display_name": "Jordan Lee",
                "role": "super_admin",
            },
        )

    def test_superadmin_invitation_failure_is_reported(self):
        config, auth = self.set_live_session()
        failure = ramp_app.supabase_backend.SupabaseRequestError(
            503, "function_unavailable", "Invitation service is unavailable."
        )
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app.supabase_backend, "invoke_function", side_effect=failure
            ),
        ):
            response = self.client.post(
                "/superadmins/new",
                data={
                    "csrf_token": "live-csrf",
                    "display_name": "Jordan Lee",
                    "email": "jordan@example.com",
                },
            )
        self.assertEqual(response.status_code, 503)
        self.assertIn(b"Invitation service is unavailable.", response.data)

    def test_service_worker_is_available_without_admin_authentication(self):
        response = self.client.get("/service-worker.js")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers["Service-Worker-Allowed"], "/")
        self.assertIn(b"ramp-admin-shell", response.data)
        self.assertIn(b"/static/icons.svg", response.data)
        self.assertIn(b"/static/site.webmanifest", response.data)
        response.close()

    def test_local_icon_assets_and_app_manifest_are_available(self):
        page = self.client.get("/")
        self.assertEqual(page.status_code, 200)
        self.assertIn(b"/static/icons.svg#icon-dashboard", page.data)
        self.assertIn(b"/static/site.webmanifest", page.data)

        icons = self.client.get("/static/icons.svg")
        self.assertEqual(icons.status_code, 200)
        self.assertIn(b'<symbol id="icon-dashboard"', icons.data)
        icons.close()

        manifest = self.client.get("/static/site.webmanifest")
        self.assertEqual(manifest.status_code, 200)
        manifest_data = json.loads(manifest.get_data(as_text=True))
        self.assertEqual(manifest_data["name"], "RAMP Admin")
        self.assertEqual(manifest_data["icons"][0]["src"], "/static/favicon.svg")
        manifest.close()

    def test_invalid_landlord_is_rejected(self):
        csrf = self.csrf_token()
        response = self.client.post(
            "/landlords/new",
            data={
                "csrf_token": csrf,
                "name": "Missing Email",
                "company": "Example",
                "email": "not-an-email",
            },
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn(b"valid email address", response.data)

    def test_posts_require_csrf_token(self):
        response = self.client.post("/landlords/new", data={"name": "No token"})
        self.assertEqual(response.status_code, 400)

    def test_connected_mode_requires_admin_sign_in(self):
        config = ramp_app.supabase_backend.SupabaseSettings(
            "https://example.supabase.co", "test-publishable-key"
        )
        with patch.object(ramp_app.supabase_backend, "settings", return_value=config):
            protected = self.client.get("/")
            self.assertEqual(protected.status_code, 302)
            self.assertIn("/login", protected.headers["Location"])
            login = self.client.get("/login")
        self.assertEqual(login.status_code, 200)
        self.assertNotIn(b"approved super-admin account", login.data)
        self.assertIn(b"Forgot password?", login.data)
        self.assertIn(b"password-icon-show", login.data)
        self.assertIn(b"password-icon-hide", login.data)
        self.assertNotIn(b"Preview mode", login.data)

    def test_forgot_password_route_requests_reset_email(self):
        config = ramp_app.supabase_backend.SupabaseSettings(
            "https://example.supabase.co", "test-publishable-key"
        )
        with patch.object(ramp_app.supabase_backend, "settings", return_value=config):
            forgot = self.client.get("/login/forgot-password")
            self.assertEqual(forgot.status_code, 200)
            self.assertIn(b"Forgot your password?", forgot.data)
            with self.client.session_transaction() as browser_session:
                csrf = browser_session["login_csrf_token"]
            with patch.object(ramp_app.supabase_backend, "request_password_reset") as mock_reset:
                response = self.client.post(
                    "/login/forgot-password",
                    data={"csrf_token": csrf, "email": "admin@example.com"},
                )
        self.assertEqual(response.status_code, 302)
        mock_reset.assert_called_once_with(config, "admin@example.com")

    def test_forgot_password_rejects_malformed_email_before_requesting_reset(self):
        config = ramp_app.supabase_backend.SupabaseSettings(
            "https://example.supabase.co", "test-publishable-key"
        )
        with patch.object(ramp_app.supabase_backend, "settings", return_value=config):
            self.client.get("/login/forgot-password")
            with self.client.session_transaction() as browser_session:
                csrf = browser_session["login_csrf_token"]
            with patch.object(
                ramp_app.supabase_backend, "request_password_reset"
            ) as mock_reset:
                response = self.client.post(
                    "/login/forgot-password",
                    data={"csrf_token": csrf, "email": "not-an-email"},
                    follow_redirects=True,
                )

        self.assertEqual(response.status_code, 200)
        self.assertIn(b"valid email address", response.data)
        mock_reset.assert_not_called()

    def test_sign_in_attempts_are_rate_limited_with_retry_after(self):
        config = ramp_app.supabase_backend.SupabaseSettings(
            "https://example.supabase.co", "test-publishable-key"
        )
        with patch.object(ramp_app.supabase_backend, "settings", return_value=config):
            self.client.get("/login")
            with self.client.session_transaction() as browser_session:
                csrf = browser_session["login_csrf_token"]
            with patch.object(
                ramp_app.supabase_backend,
                "sign_in",
                side_effect=ramp_app.supabase_backend.SupabaseRequestError(401),
            ) as mock_sign_in:
                for _ in range(ramp_app.AUTH_RATE_LIMIT_MAX_ATTEMPTS):
                    response = self.client.post(
                        "/login",
                        data={
                            "csrf_token": csrf,
                            "email": "admin@example.com",
                            "password": "incorrect",
                        },
                    )
                    self.assertEqual(response.status_code, 200)
                limited = self.client.post(
                    "/login",
                    data={
                        "csrf_token": csrf,
                        "email": "admin@example.com",
                        "password": "incorrect",
                    },
                )

        self.assertEqual(mock_sign_in.call_count, ramp_app.AUTH_RATE_LIMIT_MAX_ATTEMPTS)
        self.assertEqual(limited.status_code, 429)
        self.assertTrue(int(limited.headers["Retry-After"]) > 0)

    def test_sign_in_only_persists_approved_super_admin_sessions(self):
        config = ramp_app.supabase_backend.SupabaseSettings(
            "https://example.supabase.co", "test-publishable-key"
        )
        auth_result = {
            "access_token": "access",
            "refresh_token": "refresh",
            "expires_in": 3600,
            "user": {"id": "admin-uid"},
        }
        profile = [{"uid": "admin-uid", "role": "super_admin", "is_approved": True}]
        with patch.object(
            ramp_app.supabase_backend, "_request", side_effect=[auth_result, profile]
        ):
            sid, csrf = ramp_app.supabase_backend.sign_in(
                config, ramp_app.DATABASE, "admin@example.com", "password"
            )
        self.assertTrue(sid)
        self.assertTrue(csrf)
        with ramp_app.get_db() as db:
            row = db.execute(
                "SELECT access_token, refresh_token FROM web_sessions WHERE id = ?",
                (sid,),
            ).fetchone()
        self.assertEqual(row["access_token"], "access")
        self.assertEqual(row["refresh_token"], "refresh")

        rejected = [{"uid": "admin-uid", "role": "tenant", "is_approved": True}]
        with patch.object(
            ramp_app.supabase_backend,
            "_request",
            side_effect=[auth_result, rejected, None],
        ):
            with self.assertRaises(ramp_app.supabase_backend.SupabaseRequestError) as error:
                ramp_app.supabase_backend.sign_in(
                    config, ramp_app.DATABASE, "tenant@example.com", "password"
                )
        self.assertEqual(error.exception.status, 403)

    def test_unavailable_route_returns_404(self):
        self.assertEqual(self.client.get("/not-a-section").status_code, 404)


if __name__ == "__main__":
    unittest.main()
