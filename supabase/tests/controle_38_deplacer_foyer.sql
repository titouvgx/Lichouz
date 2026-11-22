SELECT
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='move_family') AS fonction_ok,
  has_function_privilege('authenticated','public.move_family(uuid,uuid)','EXECUTE')
    AND NOT has_function_privilege('anon','public.move_family(uuid,uuid)','EXECUTE') AS droits_ok;
