-- ============================================================
-- Migration 26 : mieux planifier (v1.99.0, lot V1-4)
-- ============================================================
--  1. Entrée + plat + dessert sur un même repas : meal_slots.course
--     (unicité : un plat de chaque sorte par repas).
--  2. Restes planifiés (« batch cooking ») : meal_slots.leftover_of = le créneau
--     où la recette est cuisinée. Même recette, même foyer, repas STRICTEMENT
--     plus tard. Supprimer le créneau cuisiné supprime ses restes.
--     Courses : rien de spécial, chaque créneau compte pour ses portions
--     (cuisiné 4 + restes 4 = la recette pour 8).
--  3. Semaines types : tables week_templates + week_template_slots (privées au foyer).
--  4. Fonctions en UNE transaction, SECURITY INVOKER (les règles RLS s'appliquent) :
--     copy_week_slots (recopier une semaine), save_week_template,
--     apply_week_template.
--
-- Compatible avec l'ancien site : les créneaux existants deviennent des « plats »,
-- l'ancien code (un plat par repas) continue de marcher.
-- Contrôle : supabase/tests/controle_26_planning_plus.sql
-- ============================================================

-- ── 1. Entrée / plat / dessert ───────────────────────────────
ALTER TABLE public.meal_slots
  ADD COLUMN IF NOT EXISTS course text NOT NULL DEFAULT 'plat';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'meal_slots_course_check') THEN
    ALTER TABLE public.meal_slots
      ADD CONSTRAINT meal_slots_course_check CHECK (course IN ('entree', 'plat', 'dessert'));
  END IF;
END $$;

ALTER TABLE public.meal_slots DROP CONSTRAINT IF EXISTS uq_slot;
ALTER TABLE public.meal_slots
  ADD CONSTRAINT uq_slot UNIQUE (meal_plan_id, day_of_week, meal_type, course);

COMMENT ON COLUMN public.meal_slots.course IS 'entree | plat | dessert (v1.99.0) : jusqu''à 3 plats par repas';

-- ── 2. Restes planifiés ──────────────────────────────────────
ALTER TABLE public.meal_slots
  ADD COLUMN IF NOT EXISTS leftover_of uuid REFERENCES public.meal_slots(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_slots_leftover ON public.meal_slots(leftover_of);
COMMENT ON COLUMN public.meal_slots.leftover_of IS
  'Restes (v1.99.0) : créneau où la recette est cuisinée. Même recette, même foyer, repas plus tard.';

-- Rang d'un repas dans le temps : (date du lundi + jour) × 2 + (midi 0 / soir 1)
CREATE OR REPLACE FUNCTION public.slot_moment(p_week date, p_day smallint, p_meal text)
RETURNS integer
LANGUAGE sql IMMUTABLE
SET search_path = ''
AS $$
  SELECT ((p_week + p_day) - DATE '2000-01-03') * 2 + CASE WHEN p_meal = 'soir' THEN 1 ELSE 0 END
$$;

CREATE OR REPLACE FUNCTION public.guard_meal_slot_leftover()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  parent record;
  child_week date;
BEGIN
  -- Un créneau qui a des restes ne peut pas devenir lui-même des restes
  IF NEW.leftover_of IS NOT NULL AND TG_OP = 'UPDATE'
     AND EXISTS (SELECT 1 FROM public.meal_slots WHERE leftover_of = NEW.id) THEN
    RAISE EXCEPTION 'Ce repas a déjà des restes prévus' USING ERRCODE = '42501';
  END IF;

  -- Changer la recette d'un créneau cuisiné : ses restes ne correspondent plus
  IF TG_OP = 'UPDATE' AND NEW.recipe_id IS DISTINCT FROM OLD.recipe_id
     AND EXISTS (SELECT 1 FROM public.meal_slots WHERE leftover_of = NEW.id) THEN
    RAISE EXCEPTION 'Supprime d''abord les restes prévus de ce repas' USING ERRCODE = '42501';
  END IF;

  IF NEW.leftover_of IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.leftover_of = NEW.id THEN
    RAISE EXCEPTION 'Un repas ne peut pas être ses propres restes' USING ERRCODE = '42501';
  END IF;

  SELECT s.recipe_id, s.leftover_of, s.day_of_week, s.meal_type, mp.family_id, mp.week_start
    INTO parent
    FROM public.meal_slots s
    JOIN public.meal_plans mp ON mp.id = s.meal_plan_id
   WHERE s.id = NEW.leftover_of
     -- un repas d'un autre foyer est « introuvable » (pas d'indice sur son existence)
     AND (auth.uid() IS NULL OR public.is_family(mp.family_id));

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Repas cuisiné introuvable' USING ERRCODE = '42501';
  END IF;
  IF parent.leftover_of IS NOT NULL THEN
    RAISE EXCEPTION 'Des restes ne peuvent pas avoir leurs propres restes' USING ERRCODE = '42501';
  END IF;
  IF parent.recipe_id IS DISTINCT FROM NEW.recipe_id THEN
    RAISE EXCEPTION 'Les restes doivent être la même recette' USING ERRCODE = '42501';
  END IF;

  SELECT mp.week_start INTO child_week
    FROM public.meal_plans mp
   WHERE mp.id = NEW.meal_plan_id
     AND mp.family_id = parent.family_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Les restes doivent rester dans le même foyer' USING ERRCODE = '42501';
  END IF;

  IF public.slot_moment(child_week, NEW.day_of_week, NEW.meal_type)
     <= public.slot_moment(parent.week_start, parent.day_of_week, parent.meal_type) THEN
    RAISE EXCEPTION 'Les restes se mangent après le repas cuisiné' USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_meal_slot_leftover ON public.meal_slots;
CREATE TRIGGER trg_guard_meal_slot_leftover
  BEFORE INSERT OR UPDATE OF leftover_of, recipe_id, meal_plan_id, day_of_week, meal_type ON public.meal_slots
  FOR EACH ROW EXECUTE FUNCTION public.guard_meal_slot_leftover();

-- ── 3. Semaines types ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.week_templates (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id   uuid        NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
  name        text        NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 40),
  created_by  uuid                 REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_week_template_name UNIQUE (family_id, name)
);
CREATE INDEX IF NOT EXISTS idx_week_templates_family ON public.week_templates(family_id);
COMMENT ON TABLE public.week_templates IS 'Semaines types du foyer (v1.99.0), à appliquer sur une semaine.';

CREATE TABLE IF NOT EXISTS public.week_template_slots (
  id            uuid      PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id   uuid      NOT NULL REFERENCES public.week_templates(id) ON DELETE CASCADE,
  day_of_week   smallint  NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
  meal_type     text      NOT NULL CHECK (meal_type IN ('midi', 'soir')),
  course        text      NOT NULL DEFAULT 'plat' CHECK (course IN ('entree', 'plat', 'dessert')),
  recipe_id     uuid      NOT NULL REFERENCES public.recipes(id) ON DELETE CASCADE,
  portions      smallint  NOT NULL DEFAULT 4 CHECK (portions BETWEEN 1 AND 50),
  leftover_of   uuid               REFERENCES public.week_template_slots(id) ON DELETE CASCADE,
  CONSTRAINT uq_week_template_slot UNIQUE (template_id, day_of_week, meal_type, course)
);
CREATE INDEX IF NOT EXISTS idx_week_template_slots_template ON public.week_template_slots(template_id);
COMMENT ON TABLE public.week_template_slots IS 'Créneaux d''une semaine type (mêmes règles que meal_slots).';

ALTER TABLE public.week_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.week_template_slots ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "week_templates_select" ON public.week_templates;
DROP POLICY IF EXISTS "week_templates_insert" ON public.week_templates;
DROP POLICY IF EXISTS "week_templates_update" ON public.week_templates;
DROP POLICY IF EXISTS "week_templates_delete" ON public.week_templates;
CREATE POLICY "week_templates_select" ON public.week_templates FOR SELECT USING (public.is_family(family_id));
CREATE POLICY "week_templates_insert" ON public.week_templates FOR INSERT WITH CHECK (public.is_family(family_id));
CREATE POLICY "week_templates_update" ON public.week_templates FOR UPDATE
  USING (public.is_family(family_id)) WITH CHECK (public.is_family(family_id));
CREATE POLICY "week_templates_delete" ON public.week_templates FOR DELETE USING (public.is_family(family_id));

DROP POLICY IF EXISTS "week_template_slots_select" ON public.week_template_slots;
DROP POLICY IF EXISTS "week_template_slots_insert" ON public.week_template_slots;
DROP POLICY IF EXISTS "week_template_slots_update" ON public.week_template_slots;
DROP POLICY IF EXISTS "week_template_slots_delete" ON public.week_template_slots;
CREATE POLICY "week_template_slots_select" ON public.week_template_slots FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.week_templates t WHERE t.id = template_id AND public.is_family(t.family_id)));
CREATE POLICY "week_template_slots_insert" ON public.week_template_slots FOR INSERT
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.week_templates t WHERE t.id = template_id AND public.is_family(t.family_id))
    AND public.can_read_recipe(recipe_id)
  );
CREATE POLICY "week_template_slots_update" ON public.week_template_slots FOR UPDATE
  USING (EXISTS (SELECT 1 FROM public.week_templates t WHERE t.id = template_id AND public.is_family(t.family_id)))
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.week_templates t WHERE t.id = template_id AND public.is_family(t.family_id))
    AND public.can_read_recipe(recipe_id)
  );
CREATE POLICY "week_template_slots_delete" ON public.week_template_slots FOR DELETE
  USING (EXISTS (SELECT 1 FROM public.week_templates t WHERE t.id = template_id AND public.is_family(t.family_id)));

-- Auteur forcé (on ne se fait pas passer pour un autre), 20 semaines types par foyer
CREATE OR REPLACE FUNCTION public.guard_week_template()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NOT NULL THEN
    IF TG_OP = 'INSERT' THEN
      NEW.created_by := auth.uid();
    ELSE
      NEW.created_by := OLD.created_by;
    END IF;
  END IF;
  IF TG_OP = 'INSERT'
     AND (SELECT count(*) FROM public.week_templates WHERE family_id = NEW.family_id) >= 20 THEN
    RAISE EXCEPTION 'Pas plus de 20 semaines types par famille' USING ERRCODE = '54000';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_guard_week_template ON public.week_templates;
CREATE TRIGGER trg_guard_week_template
  BEFORE INSERT OR UPDATE ON public.week_templates
  FOR EACH ROW EXECUTE FUNCTION public.guard_week_template();

-- Restes d'une semaine type : même semaine type, même recette, plus tard, pas de chaîne
CREATE OR REPLACE FUNCTION public.guard_week_template_slot()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  parent record;
BEGIN
  IF NEW.leftover_of IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT template_id, recipe_id, leftover_of, day_of_week, meal_type INTO parent
    FROM public.week_template_slots WHERE id = NEW.leftover_of;
  IF NOT FOUND OR parent.template_id <> NEW.template_id THEN
    RAISE EXCEPTION 'Repas cuisiné introuvable dans cette semaine type' USING ERRCODE = '42501';
  END IF;
  IF parent.leftover_of IS NOT NULL OR parent.recipe_id <> NEW.recipe_id THEN
    RAISE EXCEPTION 'Restes : même recette, pas de restes de restes' USING ERRCODE = '42501';
  END IF;
  IF NEW.day_of_week * 2 + (CASE WHEN NEW.meal_type = 'soir' THEN 1 ELSE 0 END)
     <= parent.day_of_week * 2 + (CASE WHEN parent.meal_type = 'soir' THEN 1 ELSE 0 END) THEN
    RAISE EXCEPTION 'Les restes se mangent après le repas cuisiné' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_guard_week_template_slot ON public.week_template_slots;
CREATE TRIGGER trg_guard_week_template_slot
  BEFORE INSERT OR UPDATE ON public.week_template_slots
  FOR EACH ROW EXECUTE FUNCTION public.guard_week_template_slot();

-- ── 4. Fonctions (une transaction, droits de l'utilisateur) ──
-- Copie des créneaux d'une source (jsonb) vers un planning. Les restes sont
-- recréés en suivant leur repas cuisiné ; un reste dont le repas cuisiné n'est
-- pas recopié devient un repas normal. p_replace : on vide d'abord la semaine
-- cible ; sinon les cases déjà prises sont gardées (pas d'écrasement).
CREATE OR REPLACE FUNCTION public.fill_plan_slots(p_plan uuid, p_slots jsonb, p_replace boolean)
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  s jsonb;
  new_id uuid;
  parent_new uuid;
  mapping jsonb := '{}'::jsonb;
  inserted integer := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.meal_plans WHERE id = p_plan) THEN
    RAISE EXCEPTION 'Semaine introuvable' USING ERRCODE = '42501';
  END IF;
  IF jsonb_typeof(p_slots) <> 'array' OR jsonb_array_length(p_slots) > 42 THEN
    RAISE EXCEPTION 'Trop de repas à recopier' USING ERRCODE = '54000';
  END IF;

  IF p_replace THEN
    DELETE FROM public.meal_slots WHERE meal_plan_id = p_plan;
  END IF;

  -- 1er passage : repas cuisinés (et restes orphelins)
  FOR s IN SELECT * FROM jsonb_array_elements(p_slots) LOOP
    -- Une recette devenue illisible (plus partagée) est simplement sautée
    IF NOT public.can_read_recipe((s->>'recipe_id')::uuid) THEN
      CONTINUE;
    END IF;
    IF s->>'leftover_of' IS NULL
       OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(p_slots) x WHERE x->>'id' = s->>'leftover_of') THEN
      INSERT INTO public.meal_slots (meal_plan_id, day_of_week, meal_type, course, recipe_id, portions)
      VALUES (p_plan, (s->>'day_of_week')::smallint, s->>'meal_type', COALESCE(s->>'course', 'plat'),
              (s->>'recipe_id')::uuid, COALESCE((s->>'portions')::smallint, 4))
      ON CONFLICT (meal_plan_id, day_of_week, meal_type, course) DO NOTHING
      RETURNING id INTO new_id;
      IF new_id IS NOT NULL THEN
        inserted := inserted + 1;
        IF s->>'id' IS NOT NULL THEN
          mapping := mapping || jsonb_build_object(s->>'id', new_id);
        END IF;
      END IF;
      new_id := NULL;
    END IF;
  END LOOP;

  -- 2e passage : restes dont le repas cuisiné a bien été recopié
  FOR s IN SELECT * FROM jsonb_array_elements(p_slots) LOOP
    IF s->>'leftover_of' IS NOT NULL
       AND EXISTS (SELECT 1 FROM jsonb_array_elements(p_slots) x WHERE x->>'id' = s->>'leftover_of') THEN
      parent_new := (mapping->>(s->>'leftover_of'))::uuid;
      IF parent_new IS NOT NULL THEN
        INSERT INTO public.meal_slots (meal_plan_id, day_of_week, meal_type, course, recipe_id, portions, leftover_of)
        VALUES (p_plan, (s->>'day_of_week')::smallint, s->>'meal_type', COALESCE(s->>'course', 'plat'),
                (s->>'recipe_id')::uuid, COALESCE((s->>'portions')::smallint, 4), parent_new)
        ON CONFLICT (meal_plan_id, day_of_week, meal_type, course) DO NOTHING
        RETURNING id INTO new_id;
        IF new_id IS NOT NULL THEN inserted := inserted + 1; END IF;
        new_id := NULL;
      END IF;
    END IF;
  END LOOP;

  RETURN inserted;
END;
$$;

-- Recopier une semaine (ex. la semaine passée) dans une autre
CREATE OR REPLACE FUNCTION public.copy_week_slots(p_from_plan uuid, p_to_plan uuid, p_replace boolean DEFAULT false)
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  src jsonb;
BEGIN
  IF p_from_plan = p_to_plan THEN
    RAISE EXCEPTION 'Choisis une autre semaine' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.meal_plans WHERE id = p_from_plan) THEN
    RAISE EXCEPTION 'Semaine introuvable' USING ERRCODE = '42501';
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', id, 'day_of_week', day_of_week, 'meal_type', meal_type, 'course', course,
           'recipe_id', recipe_id, 'portions', portions, 'leftover_of', leftover_of)), '[]'::jsonb)
    INTO src
    FROM public.meal_slots WHERE meal_plan_id = p_from_plan;
  RETURN public.fill_plan_slots(p_to_plan, src, p_replace);
END;
$$;

-- Enregistrer une semaine comme semaine type (remplace celle du même nom)
CREATE OR REPLACE FUNCTION public.save_week_template(p_plan uuid, p_name text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  fam uuid;
  tpl uuid;
  s record;
  new_id uuid;
  mapping jsonb := '{}'::jsonb;
BEGIN
  SELECT family_id INTO fam FROM public.meal_plans WHERE id = p_plan;
  IF fam IS NULL THEN
    RAISE EXCEPTION 'Semaine introuvable' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.meal_slots WHERE meal_plan_id = p_plan) THEN
    RAISE EXCEPTION 'Cette semaine est vide' USING ERRCODE = '22023';
  END IF;

  DELETE FROM public.week_templates WHERE family_id = fam AND name = btrim(p_name);
  INSERT INTO public.week_templates (family_id, name) VALUES (fam, btrim(p_name)) RETURNING id INTO tpl;

  FOR s IN SELECT * FROM public.meal_slots WHERE meal_plan_id = p_plan ORDER BY (leftover_of IS NOT NULL) LOOP
    INSERT INTO public.week_template_slots (template_id, day_of_week, meal_type, course, recipe_id, portions, leftover_of)
    VALUES (tpl, s.day_of_week, s.meal_type, s.course, s.recipe_id, LEAST(s.portions, 50),
            CASE WHEN s.leftover_of IS NULL THEN NULL ELSE (mapping->>(s.leftover_of::text))::uuid END)
    RETURNING id INTO new_id;
    mapping := mapping || jsonb_build_object(s.id::text, new_id);
  END LOOP;
  RETURN tpl;
END;
$$;

-- Appliquer une semaine type sur une semaine
CREATE OR REPLACE FUNCTION public.apply_week_template(p_template uuid, p_plan uuid, p_replace boolean DEFAULT false)
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  src jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.week_templates WHERE id = p_template) THEN
    RAISE EXCEPTION 'Semaine type introuvable' USING ERRCODE = '42501';
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', id, 'day_of_week', day_of_week, 'meal_type', meal_type, 'course', course,
           'recipe_id', recipe_id, 'portions', portions, 'leftover_of', leftover_of)), '[]'::jsonb)
    INTO src
    FROM public.week_template_slots WHERE template_id = p_template;
  RETURN public.fill_plan_slots(p_plan, src, p_replace);
END;
$$;

REVOKE ALL ON FUNCTION public.fill_plan_slots(uuid, jsonb, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.copy_week_slots(uuid, uuid, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.save_week_template(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.apply_week_template(uuid, uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fill_plan_slots(uuid, jsonb, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.copy_week_slots(uuid, uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_week_template(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.apply_week_template(uuid, uuid, boolean) TO authenticated;

-- Gardes : appelées seulement par leurs triggers
REVOKE ALL ON FUNCTION public.guard_meal_slot_leftover() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_week_template() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_week_template_slot() FROM PUBLIC, anon, authenticated;
