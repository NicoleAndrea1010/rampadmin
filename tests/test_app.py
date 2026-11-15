import os
import tempfile
import unittest
from pathlib import Path
from uuid import uuid4
from unittest.mock import patch

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
        self.assertIn(b">Overview</h1>", response.data)
        self.assertIn(b"Follow up", response.data)
        self.assertIn(b"Recent activity", response.data)
        self.assertIn(b"Active units", response.data)
        self.assertNotIn(b"Registered tenant accounts", response.data)
        self.assertNotIn(b"vs. last month", response.data)
        self.assertNotIn(b"Amara Santos", response.data)
        self.assertIn(b'id="pageLoading"', response.data)
        self.assertIn(b"Quick guide", response.data)
        self.assertIn(b"<details class=\"nav-group\"", response.data)
        self.assertIn(b'min="2025-01"', response.data)
        self.assertEqual(self.client.get("/?period=2024-12").status_code, 400)

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
                "company": "Santos Property Group",
                "email": "amara@example.com",
                "phone": "+63 900 000 0000",
            },
        )
        response = self.client.get("/landlords?q=Amara")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Amara Santos", response.data)
        self.assertIn(b'data-label="Landlord"', response.data)
        self.assertNotIn(b"Daniel Reyes", response.data)
        self.assertIn(b'data-loading-label="Filtering', response.data)
        export = self.client.get("/landlords/export.csv?q=Amara")
        self.assertEqual(export.status_code, 200)
        self.assertIn(b"Amara Santos", export.data)
        self.assertNotIn(b"Taylor Lee", export.data)

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
                "phone": "+63 900 000 0000",
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
                "phone": "+63 900 000 0000",
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
                "phone": "+63 900 000 0000",
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

    def test_unit_door_lock_page_is_monitoring_only(self):
        config, auth = self.set_live_session()
        unit_id = str(uuid4())
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app,
                "_find_entity",
                return_value={
                    "id": unit_id,
                    "unit_number": "A-12",
                    "name": "Harbor House",
                    "is_archived": False,
                },
            ),
        ):
            response = self.client.get(f"/properties/{unit_id}/door-lock")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Controls unavailable", response.data)
        self.assertIn(b"No door command was sent.", response.data)
        self.assertNotIn(b"request_superadmin_unlock", response.data)
        self.assertNotIn(
            f'action="/properties/{unit_id}/door-lock"'.encode(), response.data
        )

    def test_unit_door_lock_page_does_not_send_commands(self):
        config, auth = self.set_live_session()
        unit_id = str(uuid4())
        with (
            patch.object(ramp_app.supabase_backend, "settings", return_value=config),
            patch.object(
                ramp_app.supabase_backend, "load_session", return_value=(auth, "live-csrf")
            ),
            patch.object(
                ramp_app,
                "_find_entity",
                return_value={
                    "id": unit_id,
                    "unit_number": "A-12",
                    "name": "Harbor House",
                    "is_archived": False,
                },
            ),
            patch.object(ramp_app.supabase_backend, "rpc_request") as request_rpc,
        ):
            response = self.client.post(
                f"/properties/{unit_id}/door-lock",
                data={"csrf_token": "live-csrf"},
            )
        self.assertEqual(response.status_code, 405)
        request_rpc.assert_not_called()

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
                    {"id": unit_id, "is_archived": False},
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
            "phone": "555-0100",
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
                    "phone": "555-0101",
                },
                headers={"X-Ramp-Form-Request": "1"},
            )
        self.assertEqual(response.status_code, 302)
        patch_call = request_api.call_args
        self.assertEqual(patch_call.args[2], "landlords")
        self.assertEqual(patch_call.kwargs["method"], "PATCH")
        self.assertEqual(patch_call.kwargs["body"]["name"], "Demo Landlord Updated")
        self.assertEqual(patch_call.kwargs["body"]["phone"], "555-0101")

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
        response.close()

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
        self.assertIn(b"approved super-admin account", login.data)
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
