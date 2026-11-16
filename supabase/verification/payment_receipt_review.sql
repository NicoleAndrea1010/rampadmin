DO $verification$
DECLARE
  v_public_function oid :=
    'public.review_tenant_payment_receipt(text,text,text)'::regprocedure::oid;
  v_private_function oid :=
    'private.review_tenant_payment_receipt(text,text,text)'::regprocedure::oid;
BEGIN
  IF NOT has_function_privilege(
    'authenticated', v_public_function, 'EXECUTE'
  ) OR NOT has_function_privilege(
    'authenticated', v_private_function, 'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'authenticated is missing payment-review function access';
  END IF;

  IF has_function_privilege('anon', v_public_function, 'EXECUTE')
     OR has_function_privilege('anon', v_private_function, 'EXECUTE')
     OR has_function_privilege('service_role', v_public_function, 'EXECUTE')
     OR has_function_privilege('service_role', v_private_function, 'EXECUTE') THEN
    RAISE EXCEPTION 'unexpected anon or service_role payment-review access';
  END IF;

  IF (SELECT p.prosecdef FROM pg_catalog.pg_proc AS p WHERE p.oid = v_public_function)
     OR NOT (
       SELECT p.prosecdef
       FROM pg_catalog.pg_proc AS p
       WHERE p.oid = v_private_function
     ) THEN
    RAISE EXCEPTION 'unexpected payment-review function security mode';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM storage.buckets
    WHERE id = 'tenant-payment-receipts'
      AND public IS FALSE
      AND file_size_limit = 8388608
  ) THEN
    RAISE EXCEPTION 'tenant payment receipt bucket is not private or configured';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'ramp_web_superadmin_receipt_read'
      AND cmd = 'SELECT'
      AND roles @> ARRAY['authenticated']::name[]
  ) THEN
    RAISE EXCEPTION 'superadmin receipt-read policy is missing';
  END IF;
END;
$verification$;

-- In a dedicated staging project, call the RPC as an approved super-admin
-- against a pending payment with an existing tenant-payment-receipts object.
-- Confirm approve/decline updates the payment and adds one audit event, while
-- anonymous, non-admin, stale-status, missing-proof, and empty-reason requests
-- fail without changing payment or audit rows. Do not use production fixtures.
