BEGIN;

-- Retain elevated atomic writes; caller and resource authorization is enforced below.
CREATE OR REPLACE FUNCTION private.review_tenant_inquiry(
  p_inquiry_id uuid,
  p_decision text,
  p_assigned_unit_id text DEFAULT NULL::text,
  p_internal_note text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_inquiry public.tenant_inquiries%ROWTYPE;
  v_unit public.units%ROWTYPE;
  v_profile public.users%ROWTYPE;
  v_tenant_id text;
  v_auth_user_id uuid;
  v_is_superadmin boolean;
  v_profile_linked boolean := false;
  v_landlord_id text;
  v_context_unit_id text;
  v_unit_number text;
  v_monthly_rent numeric;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  IF p_decision IS NULL OR p_decision NOT IN ('approve', 'decline') THEN
    RAISE EXCEPTION 'Decision must be approve or decline' USING ERRCODE = '22023';
  END IF;

  IF p_internal_note IS NOT NULL AND char_length(p_internal_note) > 1000 THEN
    RAISE EXCEPTION 'Review note is too long' USING ERRCODE = '22023';
  END IF;

  SELECT true
  INTO v_is_superadmin
  FROM public.users AS u
  WHERE u.uid = (SELECT auth.uid())::text
    AND lower(COALESCE(u.role, '')) = 'super_admin'
    AND u.is_approved IS TRUE
  FOR SHARE;
  v_is_superadmin := COALESCE(v_is_superadmin, false);

  SELECT *
  INTO v_inquiry
  FROM public.tenant_inquiries
  WHERE id = p_inquiry_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Inquiry not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_inquiry.status IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'Only pending inquiries can be reviewed' USING ERRCODE = '22023';
  END IF;

  IF NOT v_is_superadmin
     AND NOT private.can_manage_tenant_inquiry(
       v_inquiry.preferred_unit_id,
       CASE
         WHEN p_decision = 'approve'
           THEN COALESCE(p_assigned_unit_id, v_inquiry.assigned_unit_id)
         ELSE v_inquiry.assigned_unit_id
       END
     ) THEN
    RAISE EXCEPTION 'Not authorized to review this inquiry' USING ERRCODE = '42501';
  END IF;

  IF p_decision = 'decline' THEN
    UPDATE public.tenant_inquiries
    SET status = 'declined',
        reviewed_by = (SELECT auth.uid()),
        reviewed_at = now(),
        internal_note = p_internal_note,
        updated_at = now()
    WHERE id = p_inquiry_id;

    INSERT INTO public.audit_logs (id, landlord_id, action, details)
    VALUES (
      gen_random_uuid()::text,
      NULL,
      'tenant_inquiry_reviewed',
      pg_catalog.jsonb_build_object(
        'description', 'Tenant inquiry reviewed.',
        'target_type', 'tenant_inquiry',
        'target_id', p_inquiry_id::text,
        'actor_id', (SELECT auth.uid())::text,
        'decision', p_decision
      )::text
    );

    RETURN jsonb_build_object(
      'inquiry_id', p_inquiry_id,
      'status', 'declined'
    );
  END IF;

  IF p_assigned_unit_id IS NOT NULL THEN
    IF NOT private.can_manage_tenant_unit(p_assigned_unit_id) THEN
      RAISE EXCEPTION 'Not authorized to assign this unit' USING ERRCODE = '42501';
    END IF;

    SELECT *
    INTO v_unit
    FROM public.units
    WHERE id = p_assigned_unit_id
    FOR UPDATE;

    IF NOT FOUND
       OR v_unit.is_archived IS TRUE
       OR v_unit.tenant_id IS NOT NULL
       OR v_unit.status IS NULL
       OR v_unit.status <> 'Vacant' THEN
      RAISE EXCEPTION 'The selected unit is not available' USING ERRCODE = '22023';
    END IF;

    IF NOT v_is_superadmin
       AND NOT private.can_manage_tenant_unit(p_assigned_unit_id) THEN
      RAISE EXCEPTION 'Not authorized to assign this unit' USING ERRCODE = '42501';
    END IF;

    IF EXISTS (
      SELECT 1
      FROM public.tenants t
      WHERE t.unit_id = p_assigned_unit_id
        AND t.is_archived IS NOT TRUE
        AND t.status IN ('Active', 'Pending')
    ) THEN
      RAISE EXCEPTION 'The selected unit already has an active or pending tenant'
        USING ERRCODE = '23505';
    END IF;

    v_landlord_id := v_unit.landlord_id;
    v_unit_number := COALESCE(
      NULLIF(v_unit.unit_number, ''),
      NULLIF(v_unit.name, ''),
      NULLIF(v_unit.title, ''),
      v_unit.id
    );
    v_monthly_rent := COALESCE(
      NULLIF(v_unit.monthly_rent, 0),
      NULLIF(v_unit.rent, 0),
      0
    );
  ELSE
    -- Preserve approval without assignment and retain landlord context when available.
    v_context_unit_id := COALESCE(
      v_inquiry.preferred_unit_id,
      v_inquiry.assigned_unit_id
    );
    IF v_context_unit_id IS NOT NULL THEN
      SELECT u.landlord_id
      INTO v_landlord_id
      FROM public.units u
      WHERE u.id = v_context_unit_id
      FOR SHARE;

      IF NOT v_is_superadmin
         AND NOT private.can_manage_tenant_unit(v_context_unit_id) THEN
        RAISE EXCEPTION 'Not authorized to review this inquiry' USING ERRCODE = '42501';
      END IF;
    END IF;
    v_unit_number := 'Unassigned';
    v_monthly_rent := 0;
  END IF;

  IF NOT v_is_superadmin
     AND v_inquiry.preferred_unit_id IS NOT NULL
     AND NOT private.can_manage_tenant_unit(v_inquiry.preferred_unit_id) THEN
    RAISE EXCEPTION 'Landlords may only review inquiries for their own units'
      USING ERRCODE = '42501';
  END IF;

  -- Prevent concurrent approvals for different inquiries from duplicating one email.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(lower(v_inquiry.email), 0)
  );

  IF EXISTS (
    SELECT 1
    FROM public.tenants t
    WHERE lower(t.email) = lower(v_inquiry.email)
      AND t.is_archived IS NOT TRUE
      AND t.status IN ('Active', 'Pending')
  ) THEN
    RAISE EXCEPTION 'This email already belongs to an active or pending tenant'
      USING ERRCODE = '23505';
  END IF;

  v_tenant_id := gen_random_uuid()::text;

  INSERT INTO public.tenants (
    id, landlord_id, name, email, phone, unit_id, unit_number,
    monthly_rent, status, lease_status
  ) VALUES (
    v_tenant_id,
    v_landlord_id,
    v_inquiry.full_name,
    v_inquiry.email,
    v_inquiry.phone,
    v_unit.id,
    v_unit_number,
    v_monthly_rent,
    'Pending',
    'Pending'
  );

  IF v_unit.id IS NOT NULL THEN
    UPDATE public.units
    SET status = 'Reserved',
        tenant_id = v_tenant_id,
        tenant_name = v_inquiry.full_name,
        current_tenancy_id = v_tenant_id,
        updated_at = now()
    WHERE id = v_unit.id;
  END IF;

  SELECT a.id
  INTO v_auth_user_id
  FROM auth.users a
  WHERE lower(a.email) = lower(v_inquiry.email)
  LIMIT 1;

  IF FOUND THEN
    SELECT *
    INTO v_profile
    FROM public.users u
    WHERE u.uid = v_auth_user_id::text
       OR u.id = v_tenant_id
       OR lower(u.email) = lower(v_inquiry.email)
    LIMIT 1
    FOR UPDATE;

    IF FOUND THEN
      IF v_profile.uid = v_auth_user_id::text
         AND v_profile.role = 'tenant'
         AND v_profile.tenant_id = v_tenant_id THEN
        v_profile_linked := true;
      ELSE
        RAISE EXCEPTION 'The applicant email is already linked to a different app profile'
          USING ERRCODE = '23505';
      END IF;
    ELSIF v_landlord_id IS NOT NULL THEN
      INSERT INTO public.users (
        id, uid, email, display_name, role, tenant_id, landlord_id, is_approved
      ) VALUES (
        v_tenant_id,
        v_auth_user_id::text,
        v_inquiry.email,
        v_inquiry.full_name,
        'tenant',
        v_tenant_id,
        v_landlord_id,
        true
      );
      v_profile_linked := true;
    END IF;
  END IF;

  UPDATE public.tenant_inquiries
  SET status = 'approved',
      assigned_unit_id = v_unit.id,
      tenant_id = v_tenant_id,
      reviewed_by = (SELECT auth.uid()),
      reviewed_at = now(),
      internal_note = p_internal_note,
      updated_at = now()
  WHERE id = p_inquiry_id;

  INSERT INTO public.audit_logs (id, landlord_id, action, details)
  VALUES (
    gen_random_uuid()::text,
    NULL,
    'tenant_inquiry_reviewed',
    pg_catalog.jsonb_build_object(
      'description', 'Tenant inquiry reviewed.',
      'target_type', 'tenant_inquiry',
      'target_id', p_inquiry_id::text,
      'actor_id', (SELECT auth.uid())::text,
      'decision', p_decision
    )::text
  );

  RETURN jsonb_build_object(
    'inquiry_id', p_inquiry_id,
    'status', 'approved',
    'tenant_id', v_tenant_id,
    'assigned_unit_id', v_unit.id,
    'auth_profile_linked', v_profile_linked
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.review_tenant_inquiry(
  p_inquiry_id uuid,
  p_decision text,
  p_assigned_unit_id text DEFAULT NULL::text,
  p_internal_note text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path TO ''
AS $function$
  SELECT private.review_tenant_inquiry($1, $2, $3, $4);
$function$;

REVOKE ALL ON FUNCTION public.review_tenant_inquiry(uuid, text, text, text)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.review_tenant_inquiry(uuid, text, text, text)
  TO authenticated;

REVOKE ALL ON FUNCTION private.review_tenant_inquiry(uuid, text, text, text)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION private.review_tenant_inquiry(uuid, text, text, text)
  TO authenticated;

REVOKE ALL ON FUNCTION private.is_superadmin()
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION private.is_superadmin() TO authenticated;

REVOKE ALL ON FUNCTION private.can_manage_tenant_unit(text)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION private.can_manage_tenant_unit(text)
  TO authenticated;

REVOKE ALL ON FUNCTION private.can_manage_tenant_inquiry(text, text)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION private.can_manage_tenant_inquiry(text, text)
  TO authenticated;

REVOKE UPDATE, DELETE ON TABLE public.audit_logs
  FROM PUBLIC, anon, authenticated;

DO $block$
DECLARE
  v_grant record;
  v_grantee text;
BEGIN
  FOR v_grant IN
    SELECT column_name, grantee
    FROM information_schema.column_privileges
    WHERE table_schema = 'public'
      AND table_name = 'audit_logs'
      AND privilege_type = 'UPDATE'
      AND grantee IN ('PUBLIC', 'anon', 'authenticated')
  LOOP
    v_grantee := CASE
      WHEN v_grant.grantee = 'PUBLIC' THEN 'PUBLIC'
      ELSE pg_catalog.quote_ident(v_grant.grantee)
    END;
    EXECUTE pg_catalog.format(
      'REVOKE UPDATE (%I) ON TABLE public.audit_logs FROM %s',
      v_grant.column_name,
      v_grantee
    );
  END LOOP;
END;
$block$;

COMMIT;
