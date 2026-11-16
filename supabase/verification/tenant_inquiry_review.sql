-- Run only after review and application to a dedicated staging project.
-- The transaction is rolled back; function-triggered external side effects, if any,
-- are another reason not to run this against production.
BEGIN;

DO $verification$
DECLARE
  v_functions oid[] := ARRAY[
    'public.review_tenant_inquiry(uuid,text,text,text)'::regprocedure::oid,
    'private.review_tenant_inquiry(uuid,text,text,text)'::regprocedure::oid,
    'private.is_superadmin()'::regprocedure::oid,
    'private.can_manage_tenant_unit(text)'::regprocedure::oid,
    'private.can_manage_tenant_inquiry(text,text)'::regprocedure::oid
  ];
  v_function oid;
  v_public_wrapper oid := 'public.review_tenant_inquiry(uuid,text,text,text)'::regprocedure::oid;
  v_private_review oid := 'private.review_tenant_inquiry(uuid,text,text,text)'::regprocedure::oid;
  v_admin_uid text;
  v_pending_id uuid;
  v_stale_id uuid;
  v_unit_id text;
  v_result jsonb;
BEGIN
  FOREACH v_function IN ARRAY v_functions LOOP
    IF NOT has_function_privilege('authenticated', v_function, 'EXECUTE') THEN
      RAISE EXCEPTION 'authenticated is missing EXECUTE on function %',
        v_function::regprocedure;
    END IF;

    IF has_function_privilege('anon', v_function, 'EXECUTE')
       OR has_function_privilege('service_role', v_function, 'EXECUTE')
       OR EXISTS (
         SELECT 1
         FROM pg_catalog.pg_proc AS p
         CROSS JOIN LATERAL pg_catalog.aclexplode(
           COALESCE(
             p.proacl,
             pg_catalog.acldefault('f', p.proowner)
           )
         ) AS acl
         WHERE p.oid = v_function
           AND acl.grantee = 0
           AND acl.privilege_type = 'EXECUTE'
       ) THEN
      RAISE EXCEPTION 'unexpected anon, service_role, or PUBLIC EXECUTE on %',
        v_function::regprocedure;
    END IF;
  END LOOP;

  IF (SELECT p.prosecdef FROM pg_catalog.pg_proc AS p WHERE p.oid = v_public_wrapper)
     OR NOT (SELECT p.prosecdef FROM pg_catalog.pg_proc AS p WHERE p.oid = v_private_review) THEN
    RAISE EXCEPTION 'unexpected security mode on inquiry-review functions';
  END IF;

  IF has_table_privilege('authenticated', 'public.audit_logs', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.audit_logs', 'DELETE')
     OR has_table_privilege('anon', 'public.audit_logs', 'UPDATE')
     OR has_table_privilege('anon', 'public.audit_logs', 'DELETE')
     OR has_any_column_privilege('authenticated', 'public.audit_logs', 'UPDATE')
     OR has_any_column_privilege('anon', 'public.audit_logs', 'UPDATE') THEN
    RAISE EXCEPTION 'application roles must not update or delete audit_logs';
  END IF;

  SELECT u.uid
  INTO v_admin_uid
  FROM public.users AS u
  WHERE lower(COALESCE(u.role, '')) = 'super_admin'
    AND u.is_approved IS TRUE
  LIMIT 1;

  IF v_admin_uid IS NULL THEN
    RAISE EXCEPTION 'A staging approved super-admin fixture is required';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_admin_uid, true);

  BEGIN
    PERFORM public.review_tenant_inquiry(
      '00000000-0000-0000-0000-000000000000', NULL, NULL, NULL
    );
    RAISE EXCEPTION 'NULL decision was unexpectedly accepted';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  BEGIN
    PERFORM public.review_tenant_inquiry(
      '00000000-0000-0000-0000-000000000000', 'invalid', NULL, NULL
    );
    RAISE EXCEPTION 'Invalid decision was unexpectedly accepted';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  BEGIN
    PERFORM public.review_tenant_inquiry(
      '00000000-0000-0000-0000-000000000000', 'approve', NULL, repeat('x', 1001)
    );
    RAISE EXCEPTION 'Oversized review note was unexpectedly accepted';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  SELECT i.id
  INTO v_pending_id
  FROM public.tenant_inquiries AS i
  WHERE i.status = 'pending'
  LIMIT 1;

  IF v_pending_id IS NULL THEN
    RAISE EXCEPTION 'A staging pending inquiry fixture is required';
  END IF;

  PERFORM set_config(
    'request.jwt.claim.sub',
    '00000000-0000-0000-0000-000000000000',
    true
  );
  BEGIN
    PERFORM public.review_tenant_inquiry(v_pending_id, 'decline', NULL, NULL);
    RAISE EXCEPTION 'Unauthorized review was unexpectedly accepted';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;
  PERFORM set_config('request.jwt.claim.sub', v_admin_uid, true);

  SELECT i.id
  INTO v_stale_id
  FROM public.tenant_inquiries AS i
  WHERE i.status IS DISTINCT FROM 'pending'
  LIMIT 1;

  IF v_stale_id IS NOT NULL THEN
    BEGIN
      PERFORM public.review_tenant_inquiry(v_stale_id, 'decline', NULL, NULL);
      RAISE EXCEPTION 'Non-pending inquiry was unexpectedly reviewed';
    EXCEPTION WHEN SQLSTATE '22023' THEN
      NULL;
    END;
  ELSE
    RAISE NOTICE 'Skipped stale-inquiry runtime check: no non-pending fixture';
  END IF;

  BEGIN
    PERFORM public.review_tenant_inquiry(
      v_pending_id, 'approve', '__verification_missing_unit__', NULL
    );
    RAISE EXCEPTION 'Missing unit was unexpectedly accepted';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  SELECT u.id
  INTO v_unit_id
  FROM public.units AS u
  WHERE u.status = 'Occupied'
  LIMIT 1;
  IF v_unit_id IS NOT NULL THEN
    BEGIN
      PERFORM public.review_tenant_inquiry(v_pending_id, 'approve', v_unit_id, NULL);
      RAISE EXCEPTION 'Occupied unit was unexpectedly accepted';
    EXCEPTION WHEN SQLSTATE '22023' THEN
      NULL;
    END;
  ELSE
    RAISE NOTICE 'Skipped occupied-unit check: no fixture';
  END IF;

  SELECT u.id
  INTO v_unit_id
  FROM public.units AS u
  WHERE u.is_archived IS TRUE
  LIMIT 1;
  IF v_unit_id IS NOT NULL THEN
    BEGIN
      PERFORM public.review_tenant_inquiry(v_pending_id, 'approve', v_unit_id, NULL);
      RAISE EXCEPTION 'Archived unit was unexpectedly accepted';
    EXCEPTION WHEN SQLSTATE '22023' THEN
      NULL;
    END;
  ELSE
    RAISE NOTICE 'Skipped archived-unit check: no fixture';
  END IF;

  SELECT u.id
  INTO v_unit_id
  FROM public.units AS u
  WHERE u.status = 'Vacant'
    AND u.tenant_id IS NOT NULL
  LIMIT 1;
  IF v_unit_id IS NOT NULL THEN
    BEGIN
      PERFORM public.review_tenant_inquiry(v_pending_id, 'approve', v_unit_id, NULL);
      RAISE EXCEPTION 'Already-assigned unit was unexpectedly accepted';
    EXCEPTION WHEN SQLSTATE '22023' THEN
      NULL;
    END;
  ELSE
    RAISE NOTICE 'Skipped assigned-unit check: no fixture';
  END IF;

  SELECT u.id
  INTO v_unit_id
  FROM public.units AS u
  WHERE u.status = 'Vacant'
    AND u.tenant_id IS NULL
    AND EXISTS (
      SELECT 1
      FROM public.tenants AS t
      WHERE t.unit_id = u.id
        AND t.is_archived IS NOT TRUE
        AND t.status IN ('Active', 'Pending')
    )
  LIMIT 1;
  IF v_unit_id IS NOT NULL THEN
    BEGIN
      PERFORM public.review_tenant_inquiry(v_pending_id, 'approve', v_unit_id, NULL);
      RAISE EXCEPTION 'Unit with an active tenant was unexpectedly accepted';
    EXCEPTION WHEN SQLSTATE '23505' THEN
      NULL;
    END;
  ELSE
    RAISE NOTICE 'Skipped active-tenant unit check: no fixture';
  END IF;

  SELECT i.id
  INTO v_pending_id
  FROM public.tenant_inquiries AS i
  WHERE i.status = 'pending'
    AND NOT EXISTS (
      SELECT 1
      FROM public.tenants AS t
      WHERE lower(t.email) = lower(i.email)
        AND t.is_archived IS NOT TRUE
        AND t.status IN ('Active', 'Pending')
    )
    AND NOT EXISTS (
      SELECT 1
      FROM auth.users AS a
      JOIN public.users AS u
        ON u.uid = a.id::text OR lower(u.email) = lower(a.email)
      WHERE lower(a.email) = lower(i.email)
    )
  LIMIT 1;

  IF v_pending_id IS NULL THEN
    RAISE EXCEPTION 'A staging inquiry with a non-conflicting email is required';
  END IF;

  v_result := public.review_tenant_inquiry(v_pending_id, 'approve', NULL, NULL);
  IF v_result->>'status' IS DISTINCT FROM 'approved'
     OR v_result->>'assigned_unit_id' IS NOT NULL THEN
    RAISE EXCEPTION 'No-unit approval result did not match the application contract: %',
      v_result;
  END IF;
END;
$verification$;

ROLLBACK;

-- Anonymous function access is asserted above through the role ACL checks.
-- For rollback testing, use a staging applicant that causes profile linking to fail;
-- verify tenant, unit, inquiry, and audit-log rows remain unchanged after the error.
-- For the unit-claim race, submit different pending inquiries against one vacant unit
-- concurrently in two staging sessions. One may succeed; the other must fail after
-- the first commits, without partial writes. Never run these checks against production.
