BEGIN;

INSERT INTO storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
VALUES (
  'tenant-payment-receipts',
  'tenant-payment-receipts',
  false,
  8388608,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS ramp_web_superadmin_receipt_read ON storage.objects;
CREATE POLICY ramp_web_superadmin_receipt_read
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'tenant-payment-receipts'
    AND private.is_superadmin()
    AND EXISTS (
      SELECT 1
      FROM public.payments AS p
      WHERE p.id::text = (storage.foldername(name))[2]
        AND p.tenant_id::text = (storage.foldername(name))[1]
        AND p.proof_image_url = storage.objects.name
    )
  );

CREATE OR REPLACE FUNCTION private.review_tenant_payment_receipt(
  p_payment_id text,
  p_decision text,
  p_decline_reason text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_payment public.payments%ROWTYPE;
  v_reason text := NULLIF(btrim(COALESCE(p_decline_reason, '')), '');
  v_status text;
BEGIN
  IF (SELECT auth.uid()) IS NULL OR NOT private.is_superadmin() THEN
    RAISE EXCEPTION 'Approved super-admin access required'
      USING ERRCODE = '42501';
  END IF;

  IF p_payment_id IS NULL OR btrim(p_payment_id) = ''
     OR p_decision IS NULL OR p_decision NOT IN ('approve', 'decline') THEN
    RAISE EXCEPTION 'Payment and review decision are required'
      USING ERRCODE = '22023';
  END IF;
  IF v_reason IS NOT NULL AND char_length(v_reason) > 500 THEN
    RAISE EXCEPTION 'Decline reason is too long'
      USING ERRCODE = '22023';
  END IF;
  IF p_decision = 'decline' AND v_reason IS NULL THEN
    RAISE EXCEPTION 'A decline reason is required'
      USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_payment
  FROM public.payments AS p
  WHERE p.id::text = p_payment_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment not found' USING ERRCODE = 'P0002';
  END IF;
  IF lower(btrim(COALESCE(v_payment.status, ''))) NOT IN (
    'pending', 'overdue', 'pending review'
  ) THEN
    RAISE EXCEPTION 'Payment receipt has already been reviewed'
      USING ERRCODE = '22023';
  END IF;
  IF v_payment.tenant_id IS NULL
     OR NULLIF(btrim(COALESCE(v_payment.proof_image_url, '')), '') IS NULL
     OR split_part(v_payment.proof_image_url, '/', 1) <> v_payment.tenant_id::text
     OR split_part(v_payment.proof_image_url, '/', 2) <> v_payment.id::text
     OR NOT EXISTS (
       SELECT 1
       FROM storage.objects AS o
       WHERE o.bucket_id = 'tenant-payment-receipts'
         AND o.name = v_payment.proof_image_url
     ) THEN
    RAISE EXCEPTION 'A valid private receipt is required'
      USING ERRCODE = '22023';
  END IF;

  v_status := CASE WHEN p_decision = 'approve' THEN 'Paid' ELSE 'Declined' END;
  UPDATE public.payments
  SET status = v_status,
      decline_reason = CASE
        WHEN p_decision = 'decline' THEN v_reason
        ELSE NULL
      END
  WHERE id::text = p_payment_id;

  INSERT INTO public.audit_logs (id, landlord_id, action, details)
  VALUES (
    gen_random_uuid()::text,
    NULL,
    'tenant_payment_receipt_reviewed',
    pg_catalog.jsonb_build_object(
      'description', 'Tenant payment receipt reviewed.',
      'target_type', 'payment',
      'target_id', p_payment_id,
      'actor_id', (SELECT auth.uid())::text,
      'decision', p_decision
    )::text
  );

  RETURN pg_catalog.jsonb_build_object(
    'payment_id', p_payment_id,
    'status', v_status
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.review_tenant_payment_receipt(
  p_payment_id text,
  p_decision text,
  p_decline_reason text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path TO ''
AS $function$
  SELECT private.review_tenant_payment_receipt($1, $2, $3);
$function$;

REVOKE ALL ON FUNCTION public.review_tenant_payment_receipt(text, text, text)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.review_tenant_payment_receipt(text, text, text)
  TO authenticated;

REVOKE ALL ON FUNCTION private.review_tenant_payment_receipt(text, text, text)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION private.review_tenant_payment_receipt(text, text, text)
  TO authenticated;

COMMIT;
