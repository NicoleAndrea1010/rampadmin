BEGIN;

CREATE OR REPLACE FUNCTION private.is_superadmin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.users AS u
    WHERE u.uid = (SELECT auth.uid())::text
      AND lower(coalesce(u.role, '')) = 'super_admin'
      AND u.is_approved IS TRUE
  );
$function$;

CREATE OR REPLACE FUNCTION private.guard_superadmin_approval()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF lower(coalesce(NEW.role, '')) = 'super_admin'
       AND NEW.is_approved IS TRUE
       AND (SELECT auth.uid()) IS NOT NULL
       AND NOT private.is_superadmin() THEN
      RAISE EXCEPTION 'Only an approved superadmin may approve superadmin accounts'
        USING ERRCODE = '42501';
    END IF;
  ELSIF (
        NEW.role IS DISTINCT FROM OLD.role
        OR NEW.is_approved IS DISTINCT FROM OLD.is_approved
      )
        AND (
          lower(coalesce(OLD.role, '')) = 'super_admin'
          OR lower(coalesce(NEW.role, '')) = 'super_admin'
        )
        AND (SELECT auth.uid()) IS NOT NULL
        AND NOT private.is_superadmin() THEN
    RAISE EXCEPTION 'Only an approved superadmin may change superadmin role or approval'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS users_guard_superadmin_approval ON public.users;
CREATE TRIGGER users_guard_superadmin_approval
BEFORE INSERT OR UPDATE OF role, is_approved ON public.users
FOR EACH ROW
EXECUTE FUNCTION private.guard_superadmin_approval();

REVOKE SELECT ON TABLE public.users FROM PUBLIC, anon, authenticated;
REVOKE SELECT ON TABLE public.tenants FROM PUBLIC, anon;
REVOKE SELECT ON TABLE public.units FROM PUBLIC, anon;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.units ENABLE ROW LEVEL SECURITY;

DO $block$
DECLARE
  v_grant record;
  v_grantee text;
BEGIN
  FOR v_grant IN
    SELECT table_name, column_name, grantee
    FROM information_schema.column_privileges
    WHERE table_schema = 'public'
      AND table_name IN ('users', 'tenants', 'units')
      AND privilege_type = 'SELECT'
      AND (
        grantee IN ('PUBLIC', 'anon')
        OR (table_name = 'users' AND grantee = 'authenticated')
      )
  LOOP
    v_grantee := CASE
      WHEN v_grant.grantee = 'PUBLIC' THEN 'PUBLIC'
      ELSE pg_catalog.quote_ident(v_grant.grantee)
    END;
    EXECUTE pg_catalog.format(
      'REVOKE SELECT (%I) ON TABLE public.%I FROM %s',
      v_grant.column_name,
      v_grant.table_name,
      v_grantee
    );
  END LOOP;
END;
$block$;

GRANT SELECT (
  id,
  uid,
  email,
  display_name,
  role,
  tenant_id,
  landlord_id,
  is_approved,
  must_change_password,
  created_at,
  last_login_at,
  updated_at,
  unit_id
) ON TABLE public.users TO authenticated;

GRANT SELECT ON TABLE public.tenants TO authenticated;
DROP POLICY IF EXISTS tenants_scoped_authenticated_select_guard
  ON public.tenants;
CREATE POLICY tenants_scoped_authenticated_select_guard
  ON public.tenants
  AS RESTRICTIVE
  FOR SELECT
  TO authenticated
  USING (
    private.is_superadmin()
    OR EXISTS (
      SELECT 1
      FROM public.users AS actor
      WHERE actor.uid = (SELECT auth.uid())::text
        AND actor.is_approved IS TRUE
        AND (
          (
            lower(coalesce(actor.role, '')) = 'tenant'
            AND actor.tenant_id = public.tenants.id::text
          )
          OR (
            lower(coalesce(actor.role, '')) = 'landlord'
            AND actor.landlord_id = public.tenants.landlord_id::text
          )
        )
    )
  );

GRANT SELECT ON TABLE public.units TO authenticated;

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
REVOKE INSERT ON TABLE public.audit_logs FROM PUBLIC, anon, authenticated;
GRANT INSERT ON TABLE public.audit_logs TO authenticated;
DROP POLICY IF EXISTS audit_logs_approved_superadmin_insert
  ON public.audit_logs;
CREATE POLICY audit_logs_approved_superadmin_insert
  ON public.audit_logs
  AS RESTRICTIVE
  FOR INSERT
  TO authenticated
  WITH CHECK (private.is_superadmin());

ALTER TABLE public.door_commands ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.door_commands FROM PUBLIC, anon, authenticated;

ALTER TABLE public.door_commands
  DROP CONSTRAINT IF EXISTS door_commands_actor_role_check;

ALTER TABLE public.door_commands
  ADD CONSTRAINT door_commands_actor_role_check
  CHECK (actor_role = ANY (ARRAY['landlord'::text, 'tenant'::text, 'super_admin'::text]));

CREATE OR REPLACE FUNCTION public.request_superadmin_unlock(p_unit_id text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user_id uuid;
  v_actor_email text;
  v_device_id text;
  v_active_device_count integer;
  v_command_id uuid;
BEGIN
  v_user_id := (SELECT auth.uid());

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required'
      USING ERRCODE = '42501';
  END IF;

  SELECT u.email
    INTO v_actor_email
  FROM public.users AS u
  WHERE u.uid = v_user_id::text
    AND lower(coalesce(u.role, '')) = 'super_admin'
    AND u.is_approved IS TRUE
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Approved superadmin access required'
      USING ERRCODE = '42501';
  END IF;

  IF p_unit_id IS NULL OR length(trim(p_unit_id)) = 0 THEN
    RAISE EXCEPTION 'Invalid unit';
  END IF;

  SELECT count(*), min(d.device_id)
    INTO v_active_device_count, v_device_id
  FROM private.rfid_devices AS d
  JOIN public.units AS u ON u.id::text = d.unit_id
  WHERE u.id::text = p_unit_id
    AND coalesce(u.is_archived, false) IS FALSE
    AND d.is_active IS TRUE;

  IF v_active_device_count = 0 THEN
    RAISE EXCEPTION 'No active door lock is assigned to this unit';
  END IF;

  IF v_active_device_count > 1 THEN
    RAISE EXCEPTION 'Multiple active door locks are assigned to this unit';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(v_device_id)::bigint
  );

  IF EXISTS (
    SELECT 1
    FROM public.door_commands AS dc
    WHERE dc.device_id = v_device_id
      AND dc.expires_at > pg_catalog.now()
      AND dc.status IN ('PENDING', 'CLAIMED')
  ) THEN
    RAISE EXCEPTION 'Door command already pending';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.door_commands AS dc
    WHERE dc.device_id = v_device_id
      AND dc.created_at > pg_catalog.now() - interval '5 seconds'
  ) THEN
    RAISE EXCEPTION 'Please wait before unlocking again';
  END IF;

  INSERT INTO public.door_commands (
    device_id,
    command,
    requested_by,
    actor_role,
    status
  )
  VALUES (
    v_device_id,
    'UNLOCK',
    v_user_id,
    'super_admin',
    'PENDING'
  )
  RETURNING id INTO v_command_id;

  INSERT INTO public.audit_logs (
    id,
    landlord_id,
    action,
    details
  )
  VALUES (
    v_command_id::text,
    NULL,
    'door_unlock_requested',
    pg_catalog.jsonb_build_object(
      'description', 'Unlock request queued for the lock controller.',
      'target_type', 'unit',
      'target_id', p_unit_id,
      'actor_id', v_user_id::text,
      'actor_email', v_actor_email,
      'device_id', v_device_id,
      'command_id', v_command_id::text,
      'command_status', 'PENDING'
    )::text
  );

  RETURN v_command_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.request_superadmin_unlock(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.request_superadmin_unlock(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.request_superadmin_unlock(text) TO authenticated;

COMMIT;
