<script lang="ts">
  import {
    RECIPE_TITLE_MAX, INGREDIENT_NAME_MAX, INGREDIENT_UNIT_MAX, STEP_TEXT_MAX, INGREDIENTS_MAX, STEPS_MAX,
  } from '../lib/limits'
  import { onDestroy, tick } from 'svelte'
  import { flip } from 'svelte/animate'
  import Icon from '../components/Icon.svelte'
  import ConfirmDialog from '../components/ConfirmDialog.svelte'
  import { categoryColor } from '../lib/categoryColors'
  import { toast } from '../lib/toast.svelte'
  import { href, navigate } from '../lib/router.svelte'
  import { auth } from '../lib/auth.svelte'
  import { profileState } from '../lib/profile.svelte'
  import { normalizeText } from '../lib/quantities'
  import { BUDGETS, MAX_THEMES, ORIGINES, REGIMES, THEMES, cleanKeys } from '../lib/etiquettes'
  import {
    fetchRecipe,
    fetchRecipeCategories,
    fetchShoppingCategories,
    fetchKnownIngredients,
    createRecipe,
    updateRecipe,
    type KnownIngredient,
  } from '../lib/api/recipes'
  import {
    compressRecipeImage,
    PhotoError,
    PhotoUploadError,
    recipeImageSrc,
    type CompressedImage,
    type PhotoChange,
  } from '../lib/api/recipeImages'
  import type {
    RecipeCategory,
    ShoppingCategory,
    RecipeFormData,
    RecipeIngredientInput,
    RecipeStepInput,
  } from '../lib/types'

  // Props
  interface Props {
    editId?: string | null
  }
  let { editId = null }: Props = $props()

  const isEdit = $derived(Boolean(editId))

  // ── Lignes du formulaire ──
  // Chaque ligne a une clé stable (`key`) : indispensable pour réordonner
  // sans que Svelte mélange les champs (focus, autocomplétion, animation).
  // La quantité est gardée en texte pour accepter « 1,5 » (virgule française).
  interface IngRow {
    key: number
    id?: string
    qty: string
    unit: string
    name: string
    shopping_category_id: string
  }
  interface StepRow {
    key: number
    id?: string
    instruction: string
  }

  let nextKey = 1
  const newIng = (): IngRow => ({ key: nextKey++, qty: '', unit: '', name: '', shopping_category_id: '' })
  const newStep = (): StepRow => ({ key: nextKey++, instruction: '' })

  // État du formulaire
  let title = $state('')
  let categoryId = $state('')
  // Étiquettes (migration 25) : liste fixe
  let diets: string[] = $state([])
  let origin = $state('')
  let themes: string[] = $state([])
  let budget: number | null = $state(null)

  function toggleDiet(key: string) {
    if (diets.includes(key)) {
      diets = diets.filter((d) => d !== key && !(key === 'vegetarien' && d === 'vegan'))
    } else {
      // Vegan ⇒ végétarien
      diets = cleanKeys([...diets, key, ...(key === 'vegan' ? ['vegetarien'] : [])], REGIMES)
    }
  }
  function toggleTheme(key: string) {
    if (themes.includes(key)) themes = themes.filter((t) => t !== key)
    else if (themes.length < MAX_THEMES) themes = cleanKeys([...themes, key], THEMES)
  }
  let prepTimeMin = $state<number | null>(null)
  let defaultPortions = $state<number | null>(4)
  // Qui voit la recette : sa famille (défaut, le plus prudent) ou toute la super-famille
  let visibility = $state<'famille' | 'super_famille'>('famille')
  const superFamilyName = $derived(profileState.context?.superFamily?.name ?? null)
  let ingredients = $state<IngRow[]>([newIng()])
  let steps = $state<StepRow[]>([newStep()])

  // Photo
  let currentImageUrl = $state<string | null>(null) // photo déjà enregistrée (édition)
  let pendingImage = $state<CompressedImage | null>(null) // nouvelle photo compressée, pas encore envoyée
  let pendingPreviewUrl = $state<string | null>(null)
  let imageRemoved = $state(false)
  let processingPhoto = $state(false)
  let photoInput = $state<HTMLInputElement | null>(null)

  const previewUrl = $derived(pendingPreviewUrl ?? (imageRemoved ? null : currentImageUrl))

  // Données de référence
  let recipeCategories: RecipeCategory[] = $state([])
  let shoppingCategories: ShoppingCategory[] = $state([])
  let knownIngredients: KnownIngredient[] = $state([])

  // Autocomplétion
  let activeAutocomplete = $state<number | null>(null) // clé de la ligne
  let autocompleteResults = $state<KnownIngredient[]>([])
  let acIndex = $state(-1) // suggestion surlignée au clavier

  // UI
  let loading = $state(true)
  let loadError = $state<string | null>(null)
  let reloadKey = $state(0)
  let saving = $state(false)
  let error = $state<string | null>(null) // erreur serveur
  let errors = $state<Record<string, string>>({}) // erreurs par champ
  let announce = $state('') // annonces pour lecteurs d'écran (déplacements)
  let freshFrom = $state(Infinity) // les lignes de clé ≥ freshFrom apparaissent en fondu

  const errorCount = $derived(Object.keys(errors).length)
  const titleMissing = $derived(!title.trim())

  const reduceMotion =
    typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches
  const flipMs = reduceMotion ? 0 : 220

  // ── Chargement ──
  let loadedFor: string | null = null // évite de recharger (et d'écraser la saisie) si le profil se met à jour

  $effect(() => {
    void reloadKey
    if (profileState.loading) return
    const familyId = profileState.profile?.family_id
    const key = `${editId ?? 'new'}#${reloadKey}`
    if (loadedFor === key) return
    loadedFor = key

    loading = true
    loadError = null
    error = null

    // Requêtes essentielles (catégories + recette en édition)
    const essentialPromises: Promise<any>[] = [
      fetchRecipeCategories(),
      fetchShoppingCategories(),
    ]

    if (editId) {
      essentialPromises.push(fetchRecipe(editId))
    }

    // L'autocomplétion est chargée à part pour ne pas bloquer le formulaire
    if (familyId) {
      fetchKnownIngredients(familyId)
        .then((data) => { knownIngredients = data })
        .catch(() => { /* silencieux : l'autocomplétion sera juste vide */ })
    }

    Promise.all(essentialPromises)
      .then((results) => {
        recipeCategories = results[0]
        shoppingCategories = results[1]

        if (editId && results[2]) {
          const r = results[2]
          if (familyId && r.family_id !== familyId && !profileState.context?.isSuperAdmin) {
            throw new Error('Cette recette appartient à un autre foyer : seul ce foyer peut la modifier.')
          }
          if (r.visibility === 'catalogue' && !profileState.context?.isSuperAdmin) {
            throw new Error('Recette du catalogue commun : elle ne se modifie pas.')
          }
          visibility = r.visibility === 'super_famille' ? 'super_famille' : 'famille'
          title = r.title
          categoryId = r.category_id ?? ''
          diets = cleanKeys(r.diets ?? [], REGIMES)
          origin = ORIGINES.some((o) => o.key === r.origin) ? (r.origin as string) : ''
          themes = cleanKeys(r.themes ?? [], THEMES)
          budget = r.budget ?? null
          prepTimeMin = r.prep_time_min
          defaultPortions = r.default_portions
          currentImageUrl = recipeImageSrc(r.image_url)

          ingredients = r.recipe_ingredients.length > 0
            ? r.recipe_ingredients.map((ing: any) => ({
                key: nextKey++,
                id: ing.id,
                name: ing.name,
                qty: formatQty(ing.quantity),
                unit: ing.unit ?? '',
                shopping_category_id: ing.shopping_category_id ?? '',
              }))
            : [newIng()]

          steps = r.recipe_steps.length > 0
            ? r.recipe_steps.map((s: any) => ({
                key: nextKey++,
                id: s.id,
                instruction: s.instruction,
              }))
            : [newStep()]
        } else if (editId) {
          throw new Error('Recette introuvable.')
        }
        baseline = serialize()
        freshFrom = nextKey
      })
      .catch((e) => {
        loadError = e?.message ?? 'Chargement impossible.'
        loadedFor = null
      })
      .finally(() => {
        loading = false
      })
  })

  // ── Quantités (texte ↔ nombre) ──
  function formatQty(q: number | null | undefined): string {
    return q == null ? '' : String(q).replace('.', ',')
  }

  /** null = vide ; NaN = invalide. Accepte « 1,5 », « 1.5 », « 1/2 ». */
  function parseQty(s: string): number | null {
    const t = s.trim().replace(/\s+/g, '')
    if (!t) return null
    const frac = t.match(/^(\d+)\/(\d+)$/)
    if (frac) {
      const d = Number(frac[2])
      return d > 0 ? Number(frac[1]) / d : NaN
    }
    if (!/^\d*[.,]?\d+$|^\d+[.,]$/.test(t)) return NaN
    return Number(t.replace(',', '.'))
  }

  // ── Modifications non enregistrées ──
  let baseline = $state<string | null>(null)

  function serialize(): string {
    return JSON.stringify({
      t: title.trim(),
      c: categoryId,
      g: [diets, origin, themes, budget],
      p: prepTimeMin ?? null,
      d: defaultPortions ?? null,
      v: visibility,
      i: ingredients
        .filter((i) => i.name.trim() || i.qty.trim() || i.unit.trim())
        .map((i) => [i.qty.trim(), i.unit.trim(), i.name.trim(), i.shopping_category_id]),
      s: steps.map((s) => s.instruction.trim()).filter(Boolean),
    })
  }

  const dirty = $derived(
    baseline !== null &&
      (serialize() !== baseline || pendingImage !== null || (imageRemoved && currentImageUrl !== null)),
  )

  // ── Autocomplétion ──
  function findKnown(name: string): KnownIngredient | undefined {
    const n = normalizeText(name)
    return n ? knownIngredients.find((ki) => normalizeText(ki.name) === n) : undefined
  }

  function onIngredientInput(row: IngRow) {
    clearErr(`ing-name-${row.key}`)
    const query = normalizeText(row.name)
    acIndex = -1
    if (query.length < 1) {
      closeAutocomplete()
      return
    }

    const starts: KnownIngredient[] = []
    const contains: KnownIngredient[] = []
    for (const ki of knownIngredients) {
      const n = normalizeText(ki.name)
      if (n.startsWith(query)) starts.push(ki)
      else if (n.includes(query)) contains.push(ki)
    }
    const results = [...starts, ...contains].slice(0, 6)

    if (results.length > 0) {
      activeAutocomplete = row.key
      autocompleteResults = results
    } else {
      closeAutocomplete()
    }
  }

  function applyKnown(row: IngRow, ki: KnownIngredient) {
    if (ki.unit && !row.unit) row.unit = ki.unit
    if (ki.shopping_category_id && !row.shopping_category_id) {
      row.shopping_category_id = ki.shopping_category_id
    }
  }

  function selectSuggestion(row: IngRow, suggestion: KnownIngredient) {
    row.name = suggestion.name
    applyKnown(row, suggestion)
    closeAutocomplete()
  }

  function closeAutocomplete() {
    activeAutocomplete = null
    autocompleteResults = []
    acIndex = -1
  }

  function onNameBlur(row: IngRow) {
    // Nom tapé en entier sans passer par la liste : on propose quand même le rayon
    const ki = findKnown(row.name)
    if (ki) applyKnown(row, ki)
    if (activeAutocomplete === row.key) closeAutocomplete()
  }

  // ── Focus ──
  async function focusField(selector: string) {
    await tick()
    const el = document.querySelector<HTMLElement>(selector)
    el?.focus()
  }

  // ── Ingrédients ──
  function addIngredient(focus = true) {
    if (ingredients.length >= INGREDIENTS_MAX) {
      announce = `${INGREDIENTS_MAX} ingrédients au maximum.`
      return
    }
    const row = newIng()
    ingredients.push(row)
    if (focus) focusField(`[data-ing="${row.key}"][data-f="qty"]`)
  }

  function removeIngredient(index: number) {
    const hadFocus = document.activeElement instanceof HTMLButtonElement
    const removed = ingredients[index]
    ingredients.splice(index, 1)
    for (const k of ['qty', 'name']) clearErr(`ing-${k}-${removed.key}`)
    if (ingredients.length === 0) ingredients.push(newIng())
    announce = `Ingrédient ${removed.name.trim() || index + 1} retiré.`
    if (hadFocus) {
      const next = ingredients[Math.min(index, ingredients.length - 1)]
      focusField(`[data-ing="${next.key}"][data-f="del"]`)
    }
  }

  function moveIngredient(index: number, dir: -1 | 1) {
    const to = index + dir
    if (to < 0 || to >= ingredients.length) return
    const [row] = ingredients.splice(index, 1)
    ingredients.splice(to, 0, row)
    announce = `${row.name.trim() || 'Ingrédient'} : position ${to + 1} sur ${ingredients.length}.`
    keepMoveFocus('ing', row.key, to, ingredients.length, dir)
  }

  /** Après un déplacement, garde le focus sur le bouton (ou l'autre s'il devient inactif). */
  function keepMoveFocus(kind: 'ing' | 'step', key: number, to: number, len: number, dir: -1 | 1) {
    if (!(document.activeElement instanceof HTMLButtonElement)) return
    let f = dir === -1 ? 'up' : 'down'
    if (dir === -1 && to === 0) f = 'down'
    if (dir === 1 && to === len - 1) f = 'up'
    focusField(`[data-${kind}="${key}"][data-f="${f}"]`)
  }

  function onIngKeydown(e: KeyboardEvent, row: IngRow, index: number, field: 'qty' | 'unit' | 'name') {
    // Navigation dans les suggestions
    if (field === 'name' && activeAutocomplete === row.key && autocompleteResults.length > 0) {
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault()
        const n = autocompleteResults.length
        acIndex = e.key === 'ArrowDown' ? (acIndex + 1) % n : (acIndex - 1 + n) % n
        return
      }
      if (e.key === 'Escape') {
        e.preventDefault()
        e.stopPropagation()
        closeAutocomplete()
        return
      }
      if (e.key === 'Enter' && acIndex >= 0) {
        e.preventDefault()
        selectSuggestion(row, autocompleteResults[acIndex])
        return
      }
    }

    if (e.key !== 'Enter' || e.isComposing) return
    e.preventDefault()

    if (field === 'qty') return void focusField(`[data-ing="${row.key}"][data-f="unit"]`)
    if (field === 'unit') return void focusField(`[data-ing="${row.key}"][data-f="name"]`)

    // Entrée dans le nom : ligne suivante, ou nouvel ingrédient si c'était la dernière
    const ki = findKnown(row.name)
    if (ki) applyKnown(row, ki)
    closeAutocomplete()
    const next = ingredients[index + 1]
    if (next) {
      focusField(`[data-ing="${next.key}"][data-f="qty"]`)
    } else if (row.name.trim() || row.qty.trim() || row.unit.trim()) {
      addIngredient()
    } else {
      // Dernière ligne vide : on passe aux étapes plutôt que d'empiler des lignes vides
      focusField(`[data-step="${steps[0].key}"][data-f="text"]`)
    }
  }

  // ── Étapes ──
  function addStep() {
    if (steps.length >= STEPS_MAX) {
      announce = `${STEPS_MAX} étapes au maximum.`
      return
    }
    const row = newStep()
    steps.push(row)
    focusField(`[data-step="${row.key}"][data-f="text"]`)
  }

  function removeStep(index: number) {
    const hadFocus = document.activeElement instanceof HTMLButtonElement
    steps.splice(index, 1)
    if (steps.length === 0) steps.push(newStep())
    announce = `Étape ${index + 1} retirée.`
    if (hadFocus) {
      const next = steps[Math.min(index, steps.length - 1)]
      focusField(`[data-step="${next.key}"][data-f="del"]`)
    }
  }

  function moveStep(index: number, dir: -1 | 1) {
    const to = index + dir
    if (to < 0 || to >= steps.length) return
    const [row] = steps.splice(index, 1)
    steps.splice(to, 0, row)
    announce = `Étape déplacée en position ${to + 1} sur ${steps.length}.`
    keepMoveFocus('step', row.key, to, steps.length, dir)
  }

  /** Zone de texte qui suit la hauteur de son contenu. */
  function autogrow(node: HTMLTextAreaElement, _value: string) {
    const fit = () => {
      const cs = getComputedStyle(node)
      const borders = parseFloat(cs.borderTopWidth) + parseFloat(cs.borderBottomWidth)
      node.style.height = 'auto'
      node.style.height = `${node.scrollHeight + borders}px`
    }
    fit()
    node.addEventListener('input', fit)
    window.addEventListener('resize', fit)
    return {
      update: fit,
      destroy() {
        node.removeEventListener('input', fit)
        window.removeEventListener('resize', fit)
      },
    }
  }

  // ── Portions ──
  function stepPortions(d: number) {
    const v = Math.round(Number(defaultPortions) || 0) + d
    defaultPortions = Math.min(50, Math.max(1, v))
    clearErr('portions')
  }

  // ── Photo ──
  function setPendingPreview(url: string | null) {
    if (pendingPreviewUrl) URL.revokeObjectURL(pendingPreviewUrl)
    pendingPreviewUrl = url
  }

  // Si on quitte la page pendant la compression, l'aperçu ne doit pas être créé
  // après coup (sinon son URL ne serait jamais libérée)
  let destroyed = false
  onDestroy(() => {
    destroyed = true
    setPendingPreview(null)
  })

  function pickPhoto() {
    if (processingPhoto || saving) return
    photoInput?.click()
  }

  async function onPhotoSelected(e: Event) {
    const input = e.currentTarget as HTMLInputElement
    const file = input.files?.[0]
    input.value = '' // permet de re-choisir la même photo
    if (!file) return

    processingPhoto = true
    try {
      const img = await compressRecipeImage(file)
      if (destroyed) return
      pendingImage = img
      setPendingPreview(URL.createObjectURL(img.blob))
      imageRemoved = false
    } catch (err) {
      toast.error(
        err instanceof PhotoError ? err.message : 'Impossible de préparer cette photo. Essaie avec une autre.',
      )
    } finally {
      processingPhoto = false
    }
  }

  function removePhoto() {
    pendingImage = null
    setPendingPreview(null)
    imageRemoved = true
  }

  function photoChange(): PhotoChange {
    if (pendingImage) return { kind: 'replace', image: pendingImage }
    if (imageRemoved && currentImageUrl) return { kind: 'remove' }
    return { kind: 'keep' }
  }

  // ── Validation ──
  function clearErr(key: string) {
    if (key in errors) delete errors[key]
  }

  function validate(): Record<string, string> {
    const errs: Record<string, string> = {}
    if (!title.trim()) errs.title = 'Donne un titre à la recette.'

    const p = Number(defaultPortions)
    if (defaultPortions == null || !Number.isInteger(p) || p < 1 || p > 50) {
      errs.portions = 'Entre 1 et 50.'
    }
    if (prepTimeMin != null && (!Number.isFinite(prepTimeMin) || prepTimeMin < 0 || prepTimeMin > 600)) {
      errs.prep = 'Entre 0 et 600 min.'
    }

    for (const ing of ingredients) {
      const q = parseQty(ing.qty)
      if (q !== null && Number.isNaN(q)) errs[`ing-qty-${ing.key}`] = 'Quantité invalide (ex : 1,5 ou 1/2).'
      if (!ing.name.trim() && (ing.qty.trim() || ing.unit.trim())) {
        errs[`ing-name-${ing.key}`] = 'Il manque le nom de cet ingrédient.'
      }
    }
    return errs
  }

  async function revealFirstError() {
    await tick()
    const el = document.querySelector<HTMLElement>('.page [aria-invalid="true"]')
    if (!el) return
    el.scrollIntoView({ block: 'center', behavior: reduceMotion ? 'auto' : 'smooth' })
    el.focus({ preventScroll: true })
  }

  // ── Soumission ──
  async function handleSubmit(e: SubmitEvent) {
    e.preventDefault()
    if (saving || processingPhoto) return

    errors = validate()
    if (errorCount > 0) {
      revealFirstError()
      return
    }

    const validIngredients: RecipeIngredientInput[] = ingredients
      .filter((i) => i.name.trim())
      .map((i) => ({
        id: i.id,
        name: i.name.trim(),
        quantity: parseQty(i.qty),
        unit: i.unit.trim(),
        shopping_category_id: i.shopping_category_id,
      }))
    const validSteps: RecipeStepInput[] = steps
      .filter((s) => s.instruction.trim())
      .map((s) => ({ id: s.id, instruction: s.instruction }))

    const formData: RecipeFormData = {
      title: title.trim(),
      category_id: categoryId,
      prep_time_min: prepTimeMin,
      default_portions: Number(defaultPortions),
      visibility,
      ingredients: validIngredients,
      steps: validSteps,
      tags: { diets, origin: origin || null, themes, budget },
    }

    saving = true
    error = null
    const photo = photoChange()

    try {
      if (isEdit && editId) {
        await updateRecipe(editId, formData, photo)
        leaveAllowed = true
        navigate('recette', editId)
      } else {
        const familyId = profileState.profile?.family_id
        const userId = auth.user?.id
        if (!familyId || !userId) {
          error = 'Profil non chargé.'
          saving = false
          return
        }
        const newId = await createRecipe(familyId, userId, formData, photo)
        leaveAllowed = true
        navigate('recette', newId)
      }
    } catch (e: any) {
      if (e instanceof PhotoUploadError) {
        // La recette existe : on y va quand même (pas de doublon en réessayant)
        toast.error(e.message)
        leaveAllowed = true
        navigate('recette', e.recipeId)
        return
      }
      error = e?.message ?? 'Enregistrement impossible.'
      if (e instanceof PhotoError) toast.error(e.message)
      saving = false
    }
  }

  // Entrée dans un champ simple : champ suivant (jamais d'envoi involontaire du formulaire)
  function nextOnEnter(selector: string) {
    return (e: KeyboardEvent) => {
      if (e.key !== 'Enter' || e.isComposing) return
      e.preventDefault()
      focusField(selector)
    }
  }

  function shoppingCat(id: string): ShoppingCategory | undefined {
    return shoppingCategories.find((s) => s.id === id)
  }

  // ── Protection contre la perte de saisie ──
  // Le routeur écoute `hashchange` sans offrir de garde (et un écouteur `hashchange`
  // ajouté ici passerait APRÈS le sien). On intercepte donc plus tôt, sans le modifier :
  //  1. clics sur les liens « #/… » (onglets, avatar, retour) en phase de capture,
  //     avant que le navigateur ne change l'adresse ;
  //  2. bouton retour du téléphone / navigateur (et changements d'adresse par code) :
  //     `popstate` est émis AVANT `hashchange`. On y remet aussitôt l'adresse du
  //     formulaire : quand le routeur lit l'adresse au `hashchange`, il voit la page
  //     actuelle et ne fait rien. Puis on demande confirmation.
  //  3. rechargement / fermeture de l'onglet : `beforeunload`.
  let leaveAllowed = false
  let leaveAction = $state<(() => void) | null>(null)

  const guardActive = () => dirty && !leaveAllowed
  const routeOf = (h: string) => h.replace(/^#\/?/, '')

  function askLeave(action: () => void) {
    closeAutocomplete()
    ;(document.activeElement as HTMLElement | null)?.blur?.()
    leaveAction = action
  }

  function confirmLeave() {
    const action = leaveAction
    leaveAction = null
    leaveAllowed = true
    action?.()
  }

  $effect(() => {
    const onClick = (e: MouseEvent) => {
      if (!guardActive() || e.defaultPrevented || e.button !== 0) return
      if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return
      const a = (e.target as Element | null)?.closest?.('a[href]')
      const h = a?.getAttribute('href')
      if (!h || !h.startsWith('#') || routeOf(h) === routeOf(location.hash)) return
      e.preventDefault()
      e.stopPropagation()
      askLeave(() => { location.hash = h })
    }

    const formUrl = location.href
    const onPop = () => {
      if (!guardActive() || routeOf(location.hash) === routeOf(new URL(formUrl).hash)) return
      history.pushState(null, '', formUrl)
      // Confirmé : un cran en arrière mène à la page demandée
      // (retour arrière comme changement d'adresse par code).
      askLeave(() => history.back())
    }

    const onBeforeUnload = (e: BeforeUnloadEvent) => {
      if (!guardActive()) return
      e.preventDefault()
      e.returnValue = ''
    }

    document.addEventListener('click', onClick, true)
    window.addEventListener('popstate', onPop)
    window.addEventListener('beforeunload', onBeforeUnload)
    return () => {
      document.removeEventListener('click', onClick, true)
      window.removeEventListener('popstate', onPop)
      window.removeEventListener('beforeunload', onBeforeUnload)
    }
  })

  // ── Clavier virtuel ──
  // Pendant la saisie, la barre d'enregistrement s'efface : elle flotterait sinon
  // au-dessus du clavier (ou derrière lui sur iOS) et mangerait la moitié de l'écran.
  let keyboardOpen = $state(false)

  $effect(() => {
    const vv = window.visualViewport
    let editing = false
    const isEditable = (el: Element | null) =>
      el instanceof HTMLTextAreaElement ||
      (el instanceof HTMLInputElement && !['checkbox', 'radio', 'file', 'button', 'submit'].includes(el.type))
    const update = () => {
      const gap = vv ? window.innerHeight - vv.height * vv.scale : 0
      keyboardOpen = editing && gap > 150
    }
    const onFocusIn = (e: FocusEvent) => { editing = isEditable(e.target as Element); update() }
    const onFocusOut = () => { editing = false; setTimeout(update, 50) }
    document.addEventListener('focusin', onFocusIn)
    document.addEventListener('focusout', onFocusOut)
    vv?.addEventListener('resize', update)
    return () => {
      document.removeEventListener('focusin', onFocusIn)
      document.removeEventListener('focusout', onFocusOut)
      vv?.removeEventListener('resize', update)
    }
  })

  const statusText = $derived.by(() => {
    if (saving) return pendingImage ? 'Envoi de la photo…' : 'Enregistrement…'
    if (errorCount > 0) return `${errorCount} champ${errorCount > 1 ? 's' : ''} à corriger`
    if (titleMissing) return 'Ajoute un titre pour enregistrer'
    if (processingPhoto) return 'Préparation de la photo…'
    if (dirty) return isEdit ? 'Modifications non enregistrées' : 'Brouillon non enregistré'
    return isEdit ? 'Aucune modification' : ''
  })
</script>

<div class="page">
  <a href={isEdit && editId ? href('recette', editId) : href('recettes')} class="back">
    <Icon name="arrow-left" size={20} />
    {isEdit ? 'Retour' : 'Recettes'}
  </a>

  <h1>{isEdit ? 'Modifier la recette' : 'Nouvelle recette'}</h1>

  {#if loading}
    <div class="center-msg"><div class="spinner"></div></div>
  {:else if loadError}
    <div class="card load-error" role="alert">
      <p>{loadError}</p>
      <button type="button" class="btn btn-outline" onclick={() => reloadKey++}>
        <Icon name="refresh" /> Réessayer
      </button>
    </div>
  {:else}
    <form onsubmit={handleSubmit} novalidate>

      <!-- ── Photo ── -->
      <section class="card" aria-labelledby="photo-label" style="--i: 0">
        <h2 class="section-title" id="photo-label"><Icon name="image" size={18} /> Photo</h2>
        <input
          bind:this={photoInput}
          type="file"
          accept="image/*"
          class="visually-hidden"
          tabindex="-1"
          aria-hidden="true"
          onchange={onPhotoSelected}
        />

        {#if previewUrl}
          <div class="photo-frame">
            <img src={previewUrl} alt={title.trim() || 'Aperçu'} class="photo-img" />
            {#if processingPhoto}
              <div class="photo-busy" role="status">
                <div class="spinner"></div>
                <span>Préparation de la photo…</span>
              </div>
            {/if}
          </div>
          <div class="photo-actions">
            <button
              type="button"
              class="btn btn-outline photo-btn"
              onclick={pickPhoto}
              disabled={processingPhoto || saving}
            >
              <Icon name="camera" size={18} /> Changer
            </button>
            <button
              type="button"
              class="btn btn-outline photo-btn photo-btn-danger"
              onclick={removePhoto}
              disabled={processingPhoto || saving}
            >
              <Icon name="trash" size={18} /> Retirer
            </button>
          </div>
        {:else}
          <button
            type="button"
            class="photo-frame photo-empty"
            onclick={pickPhoto}
            disabled={processingPhoto || saving}
            aria-describedby="photo-label"
          >
            {#if processingPhoto}
              <div class="spinner"></div>
              <span class="photo-empty-title" role="status">Préparation de la photo…</span>
            {:else}
              <span class="photo-empty-icon"><Icon name="camera" size={28} strokeWidth={1.8} /></span>
              <span class="photo-empty-title">Ajouter une photo</span>
              <span class="photo-empty-sub">Galerie ou appareil photo</span>
            {/if}
          </button>
        {/if}
        <p class="photo-hint">Visible par toute la famille. Évite les visages et les documents.</p>
      </section>

      <!-- ── Infos principales ── -->
      <section class="card" aria-label="Informations" style="--i: 1">
        <div class="field">
          <label class="label label-text" for="rf-title">Titre <span class="req" aria-hidden="true">*</span></label>
          <input
            id="rf-title"
            type="text"
            class="input"
            class:error={errors.title}
            placeholder="Ex : Poulet rôti aux herbes"
            autocapitalize="sentences"
            enterkeyhint="next"
            maxlength={RECIPE_TITLE_MAX}
            required
            aria-invalid={errors.title ? 'true' : undefined}
            aria-describedby={errors.title ? 'rf-title-err' : undefined}
            bind:value={title}
            oninput={() => clearErr('title')}
            onkeydown={nextOnEnter('#rf-portions')}
          />
          {#if errors.title}<p class="field-err" id="rf-title-err">{errors.title}</p>{/if}
        </div>

        <div class="field" role="group" aria-labelledby="rf-cat-label">
          <span class="label label-text" id="rf-cat-label">Catégorie</span>
          <div class="chip-select">
            <button
              type="button"
              class="chip chip-option"
              class:selected={categoryId === ''}
              aria-pressed={categoryId === ''}
              onclick={() => (categoryId = '')}
            >Aucune</button>
            {#each recipeCategories as cat (cat.id)}
              <button
                type="button"
                class="chip chip-option cat-option"
                class:selected={categoryId === cat.id}
                aria-pressed={categoryId === cat.id}
                onclick={() => (categoryId = cat.id)}
                style="--cat-color: {categoryColor(cat.name)}"
              >{cat.name}</button>
            {/each}
          </div>
        </div>

        <div class="row-2">
          <div class="field">
            <label class="label label-text" for="rf-portions"><Icon name="users" size={14} /> Portions</label>
            <div class="stepper" class:error={errors.portions}>
              <button
                type="button"
                class="stepper-btn"
                aria-label="Une portion de moins"
                disabled={(Number(defaultPortions) || 0) <= 1}
                onclick={() => stepPortions(-1)}
              ><Icon name="minus" /></button>
              <input
                id="rf-portions"
                type="number"
                class="stepper-input"
                inputmode="numeric"
                enterkeyhint="next"
                min="1"
                max="50"
                aria-invalid={errors.portions ? 'true' : undefined}
                aria-describedby={errors.portions ? 'rf-portions-err' : undefined}
                bind:value={defaultPortions}
                oninput={() => clearErr('portions')}
                onkeydown={nextOnEnter('#rf-prep')}
              />
              <button
                type="button"
                class="stepper-btn"
                aria-label="Une portion de plus"
                disabled={(Number(defaultPortions) || 0) >= 50}
                onclick={() => stepPortions(1)}
              ><Icon name="plus" /></button>
            </div>
            {#if errors.portions}<p class="field-err" id="rf-portions-err">{errors.portions}</p>{/if}
          </div>
          <div class="field">
            <label class="label label-text" for="rf-prep"><Icon name="clock" size={14} /> Temps (min)</label>
            <input
              id="rf-prep"
              type="number"
              class="input"
              class:error={errors.prep}
              inputmode="numeric"
              enterkeyhint="next"
              min="0"
              max="600"
              placeholder="Ex : 45"
              aria-invalid={errors.prep ? 'true' : undefined}
              aria-describedby={errors.prep ? 'rf-prep-err' : undefined}
              bind:value={prepTimeMin}
              oninput={() => clearErr('prep')}
              onkeydown={nextOnEnter(`[data-ing="${ingredients[0]?.key}"][data-f="qty"]`)}
            />
            {#if errors.prep}<p class="field-err" id="rf-prep-err">{errors.prep}</p>{/if}
          </div>
        </div>
      </section>

      <!-- ── Étiquettes (migration 25) ── -->
      <section class="card" aria-labelledby="rf-tags-title" style="--i: 2">
        <h2 class="section-title" id="rf-tags-title"><Icon name="tag" size={18} /> Étiquettes <span class="optional">facultatif</span></h2>

        <div class="field" role="group" aria-labelledby="rf-diet-label">
          <span class="label label-text" id="rf-diet-label">Régime</span>
          <div class="chip-select">
            {#each REGIMES as r (r.key)}
              <button
                type="button"
                class="chip chip-option"
                class:selected={diets.includes(r.key)}
                aria-pressed={diets.includes(r.key)}
                onclick={() => toggleDiet(r.key)}
              >{r.label}</button>
            {/each}
          </div>
          <p class="vis-hint">Indicatif : en cas d’allergie, vérifie toujours les emballages (bouillon, sauces…).</p>
        </div>

        <div class="field">
            <label class="label label-text" for="rf-origin">Origine</label>
            <select id="rf-origin" class="input" bind:value={origin}>
              <option value="">Aucune</option>
              {#each ['France', 'Monde'] as groupe (groupe)}
                <optgroup label={groupe}>
                  {#each ORIGINES.filter((o) => o.groupe === groupe) as o (o.key)}
                    <option value={o.key}>{o.label}</option>
                  {/each}
                </optgroup>
              {/each}
            </select>
        </div>
          <div class="field" role="group" aria-labelledby="rf-budget-label">
            <span class="label label-text" id="rf-budget-label">Budget</span>
            <div class="chip-select budget-select">
              {#each BUDGETS as b (b.value)}
                <button
                  type="button"
                  class="chip chip-option"
                  class:selected={budget === b.value}
                  aria-pressed={budget === b.value}
                  aria-label={b.long}
                  title={b.long}
                  onclick={() => (budget = budget === b.value ? null : b.value)}
                >{b.label}</button>
              {/each}
            </div>
          </div>

        <div class="field" role="group" aria-labelledby="rf-theme-label">
          <span class="label label-text" id="rf-theme-label">Thèmes <span class="optional">{themes.length}/{MAX_THEMES}</span></span>
          <div class="chip-select">
            {#each THEMES as t (t.key)}
              <button
                type="button"
                class="chip chip-option"
                class:selected={themes.includes(t.key)}
                aria-pressed={themes.includes(t.key)}
                disabled={!themes.includes(t.key) && themes.length >= MAX_THEMES}
                onclick={() => toggleTheme(t.key)}
              >{t.label}</button>
            {/each}
          </div>
        </div>
      </section>

      <!-- ── Qui peut voir la recette ── -->
      <section class="card" aria-labelledby="rf-vis-title" style="--i: 3">
        <h2 class="section-title" id="rf-vis-title"><Icon name="users" size={18} /> Qui peut la voir ?</h2>
        <div class="vis-options" role="radiogroup" aria-labelledby="rf-vis-title">
          <label class="vis-option" class:selected={visibility === 'famille'}>
            <input type="radio" class="check" name="rf-visibility" value="famille" bind:group={visibility} />
            <span class="vis-text">
              <span class="vis-name">Ma famille seulement</span>
              <span class="vis-hint">Visible par les membres de ta famille.</span>
            </span>
          </label>
          <label class="vis-option" class:selected={visibility === 'super_famille'}>
            <input type="radio" class="check" name="rf-visibility" value="super_famille" bind:group={visibility} />
            <span class="vis-text">
              <span class="vis-name">Toutes nos familles</span>
              <span class="vis-hint">
                {superFamilyName ? `Partagée avec toutes les familles de « ${superFamilyName} ».` : 'Partagée avec les autres familles de ton groupe.'}
              </span>
            </span>
          </label>
        </div>
      </section>

      <!-- ── Ingrédients ── -->
      <section class="card" aria-labelledby="rf-ing-title" style="--i: 4">
        <div class="section-head">
          <h2 class="section-title" id="rf-ing-title">🥕 Ingrédients</h2>
          <span class="count">{ingredients.filter((i) => i.name.trim()).length || ''}</span>
        </div>

        <div class="col-heads" aria-hidden="true">
          <span>Qté</span><span>Unité</span><span>Ingrédient</span>
        </div>

        <ul class="ing-list">
          {#each ingredients as ing, i (ing.key)}
            {@const cat = shoppingCat(ing.shopping_category_id)}
            {@const qtyErr = errors[`ing-qty-${ing.key}`]}
            {@const nameErr = errors[`ing-name-${ing.key}`]}
            <li class="ing" class:fresh={ing.key >= freshFrom} animate:flip={{ duration: flipMs }}>
              <div class="ing-line">
                <input
                  type="text"
                  class="input cell"
                  class:error={qtyErr}
                  placeholder="Qté"
                  inputmode="decimal"
                  enterkeyhint="next"
                  autocomplete="off"
                  aria-label="Quantité, ingrédient {i + 1}"
                  aria-invalid={qtyErr ? 'true' : undefined}
                  aria-describedby={qtyErr ? `rf-ingerr-${ing.key}` : undefined}
                  data-ing={ing.key}
                  data-f="qty"
                  bind:value={ing.qty}
                  oninput={() => clearErr(`ing-qty-${ing.key}`)}
                  onkeydown={(e) => onIngKeydown(e, ing, i, 'qty')}
                />
                <input
                  type="text"
                  class="input cell"
                  placeholder="g, cl…"
                  maxlength={INGREDIENT_UNIT_MAX}
                  enterkeyhint="next"
                  autocapitalize="none"
                  autocomplete="off"
                  spellcheck="false"
                  aria-label="Unité, ingrédient {i + 1}"
                  data-ing={ing.key}
                  data-f="unit"
                  bind:value={ing.unit}
                  onkeydown={(e) => onIngKeydown(e, ing, i, 'unit')}
                />
                <input
                  type="text"
                  class="input cell"
                  class:error={nameErr}
                  placeholder="Ex : beurre"
                  maxlength={INGREDIENT_NAME_MAX}
                  enterkeyhint="next"
                  autocapitalize="none"
                  autocomplete="off"
                  role="combobox"
                  aria-autocomplete="list"
                  aria-expanded={activeAutocomplete === ing.key}
                  aria-controls="rf-ac-{ing.key}"
                  aria-activedescendant={activeAutocomplete === ing.key && acIndex >= 0 ? `rf-ac-${ing.key}-${acIndex}` : undefined}
                  aria-label="Nom, ingrédient {i + 1}"
                  aria-invalid={nameErr ? 'true' : undefined}
                  aria-describedby={nameErr ? `rf-ingerr-${ing.key}` : undefined}
                  data-ing={ing.key}
                  data-f="name"
                  bind:value={ing.name}
                  oninput={() => onIngredientInput(ing)}
                  onblur={() => onNameBlur(ing)}
                  onkeydown={(e) => onIngKeydown(e, ing, i, 'name')}
                />
                {#if activeAutocomplete === ing.key && autocompleteResults.length > 0}
                  <ul class="autocomplete" id="rf-ac-{ing.key}" role="listbox" aria-label="Suggestions">
                    {#each autocompleteResults as suggestion, s (suggestion.name)}
                      {@const sc = suggestion.shopping_category_id ? shoppingCat(suggestion.shopping_category_id) : undefined}
                      <!-- Clavier géré par le champ (flèches + Entrée, aria-activedescendant) -->
                      <!-- svelte-ignore a11y_click_events_have_key_events -->
                      <li
                        id="rf-ac-{ing.key}-{s}"
                        role="option"
                        aria-selected={s === acIndex}
                        class="autocomplete-item"
                        class:active={s === acIndex}
                        onpointerdown={(e) => e.preventDefault()}
                        onclick={() => selectSuggestion(ing, suggestion)}
                      >
                        {#if sc}<span class="ac-emoji" aria-hidden="true">{sc.icon}</span>{/if}
                        <span class="ac-name">{suggestion.name}</span>
                        {#if suggestion.unit}<span class="ac-unit">{suggestion.unit}</span>{/if}
                      </li>
                    {/each}
                  </ul>
                {/if}
              </div>

              {#if qtyErr || nameErr}
                <p class="field-err" id="rf-ingerr-{ing.key}">{qtyErr ?? nameErr}</p>
              {/if}

              <div class="ing-tools">
                <label class="rayon" class:unset={!cat}>
                  <select
                    class="rayon-select"
                    aria-label="Rayon, ingrédient {i + 1}"
                    bind:value={ing.shopping_category_id}
                  >
                    <option value="">Choisir le rayon</option>
                    {#each shoppingCategories as sc (sc.id)}
                      <option value={sc.id}>{sc.icon} {sc.name}</option>
                    {/each}
                  </select>
                  <span class="rayon-chev" aria-hidden="true"><Icon name="chevron-down" size={16} /></span>
                </label>
                <button
                  type="button"
                  class="tool"
                  aria-label="Monter l'ingrédient {i + 1}"
                  disabled={i === 0}
                  data-ing={ing.key}
                  data-f="up"
                  onclick={() => moveIngredient(i, -1)}
                ><span class="up"><Icon name="chevron-down" size={20} /></span></button>
                <button
                  type="button"
                  class="tool"
                  aria-label="Descendre l'ingrédient {i + 1}"
                  disabled={i === ingredients.length - 1}
                  data-ing={ing.key}
                  data-f="down"
                  onclick={() => moveIngredient(i, 1)}
                ><Icon name="chevron-down" size={20} /></button>
                <button
                  type="button"
                  class="tool tool-del"
                  aria-label="Retirer l'ingrédient {i + 1}"
                  data-ing={ing.key}
                  data-f="del"
                  onclick={() => removeIngredient(i)}
                ><Icon name="trash" size={18} /></button>
              </div>
            </li>
          {/each}
        </ul>

        {#if ingredients.length < INGREDIENTS_MAX}
          <button type="button" class="btn btn-outline btn-add" onclick={() => addIngredient()}>
            <Icon name="plus" size={18} strokeWidth={2.5} /> Ajouter un ingrédient
          </button>
        {:else}
          <p class="limit-note">{INGREDIENTS_MAX} ingrédients au maximum.</p>
        {/if}
      </section>

      <!-- ── Étapes ── -->
      <section class="card" aria-labelledby="rf-steps-title" style="--i: 5">
        <div class="section-head">
          <h2 class="section-title" id="rf-steps-title"><Icon name="list" size={18} /> Étapes</h2>
        </div>

        <ol class="step-list">
          {#each steps as step, i (step.key)}
            <li class="step" class:fresh={step.key >= freshFrom} animate:flip={{ duration: flipMs }}>
              <div class="step-head">
                <span class="step-badge" aria-hidden="true">{i + 1}</span>
                <span class="step-label">Étape {i + 1}</span>
                <button
                  type="button"
                  class="tool"
                  aria-label="Monter l'étape {i + 1}"
                  disabled={i === 0}
                  data-step={step.key}
                  data-f="up"
                  onclick={() => moveStep(i, -1)}
                ><span class="up"><Icon name="chevron-down" size={20} /></span></button>
                <button
                  type="button"
                  class="tool"
                  aria-label="Descendre l'étape {i + 1}"
                  disabled={i === steps.length - 1}
                  data-step={step.key}
                  data-f="down"
                  onclick={() => moveStep(i, 1)}
                ><Icon name="chevron-down" size={20} /></button>
                <button
                  type="button"
                  class="tool tool-del"
                  aria-label="Retirer l'étape {i + 1}"
                  data-step={step.key}
                  data-f="del"
                  onclick={() => removeStep(i)}
                ><Icon name="trash" size={18} /></button>
              </div>
              <textarea
                class="input textarea"
                placeholder={i === 0 ? 'Ex : Préchauffer le four à 200 °C.' : 'Décris cette étape…'}
                rows="2"
                autocapitalize="sentences"
                enterkeyhint="enter"
                aria-label="Étape {i + 1}"
                data-step={step.key}
                data-f="text"
                maxlength={STEP_TEXT_MAX}
                bind:value={step.instruction}
                use:autogrow={step.instruction}
              ></textarea>
              {#if step.instruction.length > STEP_TEXT_MAX - 100}
                <p class="limit-note" aria-live="polite">{step.instruction.length} / {STEP_TEXT_MAX} caractères</p>
              {/if}
            </li>
          {/each}
        </ol>

        {#if steps.length < STEPS_MAX}
          <button type="button" class="btn btn-outline btn-add" onclick={addStep}>
            <Icon name="plus" size={18} strokeWidth={2.5} /> Ajouter une étape
          </button>
        {:else}
          <p class="limit-note">{STEPS_MAX} étapes au maximum.</p>
        {/if}
      </section>

      <!-- ── Barre d'enregistrement ── -->
      <div class="save-bar" class:hidden={keyboardOpen}>
        {#if error}
          <p class="form-error" role="alert">{error}</p>
        {/if}
        <div class="save-row">
          {#if errorCount > 0}
            <button type="button" class="status status-err" onclick={revealFirstError}>
              {statusText}
            </button>
          {:else}
            <p class="status" aria-live="polite">{statusText}</p>
          {/if}
          <button
            type="submit"
            class="btn btn-primary save-btn"
            class:inactive={titleMissing}
            aria-disabled={titleMissing ? 'true' : undefined}
            disabled={saving || processingPhoto}
          >
            {#if saving}
              <span class="spinner spinner-sm" aria-hidden="true"></span> {pendingImage ? 'Envoi…' : 'Enregistrement…'}
            {:else}
              <Icon name="check" /> {isEdit ? 'Enregistrer' : 'Créer la recette'}
            {/if}
          </button>
        </div>
      </div>
    </form>
  {/if}

  <p class="visually-hidden" aria-live="polite">{announce}</p>
</div>

{#if leaveAction}
  <ConfirmDialog
    title="Quitter sans enregistrer ?"
    confirmLabel="Quitter"
    cancelLabel="Rester"
    danger
    onconfirm={confirmLeave}
    oncancel={() => (leaveAction = null)}
  >
    Tes modifications {isEdit ? 'de cette recette' : 'sur cette nouvelle recette'} seront perdues.
  </ConfirmDialog>
{/if}

<style>
  .limit-note {
    margin: 6px 2px 0;
    font-size: 13px;
    color: var(--text-secondary);
  }

  .page {
    padding: var(--gutter);
    padding-top: calc(var(--gutter) + env(safe-area-inset-top, 0px));
    padding-bottom: calc(84px + env(safe-area-inset-bottom, 0px));
    max-width: 640px;
    margin: 0 auto;
  }

  .back {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    min-height: 44px;
    margin: -6px 0 var(--sp-1) -4px;
    padding: 0 8px 0 4px;
    color: var(--text);
    font-size: 15px;
    font-weight: var(--fw-bold);
    text-decoration: underline;
    text-decoration-thickness: 2px;
    text-underline-offset: 3px;
    touch-action: manipulation;
  }

  h1 {
    font-size: var(--fs-2xl);
    padding-right: 48px; /* place pour l'avatar */
    margin-bottom: var(--sp-4);
  }

  form {
    display: flex;
    flex-direction: column;
    gap: var(--sp-4);
  }

  /* ── Sections : carte (globale) + bandeau en tête ── */
  .card {
    --pad: 14px;
    padding: var(--sp-4) var(--pad);
    display: flex;
    flex-direction: column;
    gap: 14px;
    animation: fade-up var(--dur-sheet) var(--ease-out) calc(var(--i, 0) * 45ms) backwards;
  }

  .section-title,
  .section-head {
    margin: calc(var(--sp-4) * -1) calc(var(--pad) * -1) 0;
    padding: 6px var(--pad);
    background: var(--band);
    color: var(--text-on-band);
  }

  .section-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--sp-2);
  }

  .section-title {
    display: flex;
    align-items: center;
    gap: var(--sp-2);
    font-family: var(--font-display);
    font-size: var(--fs-base);
    font-weight: var(--fw-bold);
    text-transform: uppercase;
    letter-spacing: var(--tracking-caps);
  }

  .section-head .section-title {
    margin: 0;
    padding: 0;
  }

  .count {
    min-width: 28px;
    text-align: center;
    font-size: 13px;
    font-weight: var(--fw-bold);
    color: var(--text-on-band);
  }
  .count:empty { display: none; }

  /* ── Champs ── */
  .field {
    display: flex;
    flex-direction: column;
    gap: 6px;
    min-width: 0;
  }

  /* .label globale + icône en ligne */
  .label-text {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    margin: 0;
  }

  .req { color: var(--error); }

  /* Qui peut voir la recette */
  .vis-options {
    display: grid;
    gap: var(--sp-3);
    margin-top: var(--sp-3);
  }
  .vis-option {
    display: flex;
    align-items: flex-start;
    gap: var(--sp-3);
    min-height: 44px;
    padding: var(--sp-3);
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    cursor: pointer;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }
  .vis-option:active { transform: translate(2px, 2px); }
  .vis-option.selected {
    background: var(--highlight);
    box-shadow: var(--shadow-sm);
  }
  .vis-option.selected .vis-hint { color: var(--text); }
  .vis-option .check { margin-top: 2px; }
  .vis-text { display: grid; gap: 2px; }
  .vis-name { font-weight: var(--fw-bold); color: var(--text); }
  .vis-hint { font-size: 13px; color: var(--text-secondary); }

  /* Champs : la mise au point fait défiler en gardant de la place
     au-dessus de la barre d'enregistrement et de la barre d'onglets */
  .input,
  .stepper-input,
  .rayon-select {
    scroll-margin: 80px 0 150px;
  }

  .field-err {
    font-size: 13px;
    font-weight: var(--fw-bold);
    color: var(--error);
  }

  .row-2 {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: var(--sp-3);
  }

  /* Pas de flèches des champs nombre : on a le stepper */
  input[type='number'] { -moz-appearance: textfield; appearance: textfield; }
  input[type='number']::-webkit-inner-spin-button,
  input[type='number']::-webkit-outer-spin-button { -webkit-appearance: none; margin: 0; }

  /* ── Stepper portions ── */
  .stepper {
    display: flex;
    align-items: stretch;
    height: var(--tap);
    border: var(--line-w) solid var(--line);
    background: var(--bg);
  }

  .stepper:focus-within { box-shadow: var(--shadow-sm); }
  .stepper.error { border-color: var(--error); box-shadow: 3px 3px 0 var(--error); }

  .stepper-btn {
    flex: 0 0 44px;
    display: flex;
    align-items: center;
    justify-content: center;
    border: none;
    background: var(--surface);
    color: var(--text);
    cursor: pointer;
    touch-action: manipulation;
  }
  .stepper-btn:first-child { border-right: var(--line-w) solid var(--line); }
  .stepper-btn:last-child { border-left: var(--line-w) solid var(--line); }
  .stepper-btn:disabled { color: var(--text-placeholder); cursor: default; opacity: 0.6; }
  .stepper-btn:active:not(:disabled) { background: var(--accent); color: var(--on-accent); }
  .stepper-btn:focus-visible { outline-offset: -3px; }

  .stepper-input {
    flex: 1;
    min-width: 0;
    border: none;
    background: transparent;
    color: var(--text);
    font-family: var(--font-body);
    font-size: 17px;
    font-weight: var(--fw-bold);
    text-align: center;
    outline: none;
  }

  /* ── Puces (catégories, régime, thèmes) : .chip globale ── */
  .chip-select {
    display: flex;
    gap: var(--sp-2);
    flex-wrap: wrap;
  }

  .chip-option { min-height: 44px; padding: 0 14px; font-weight: var(--fw-bold); }
  .chip-option:disabled { opacity: 0.45; cursor: default; }
  .chip-option:focus-visible { outline-offset: 2px; }

  /* Catégorie : petit carré de sa couleur ; choisie = remplie, avec ombre */
  .cat-option::before {
    content: '';
    width: 12px;
    height: 12px;
    background: var(--cat-color);
    border: var(--line-thin) solid var(--ink);
  }
  .cat-option.selected::before { background: var(--ink); }
  .cat-option.selected {
    background: var(--cat-color);
    color: var(--ink);
    box-shadow: var(--shadow-sm);
  }

  .budget-select { flex-wrap: nowrap; gap: 6px; }
  .budget-select .chip-option { flex: 1; justify-content: center; padding: 0 8px; }
  .optional {
    font-family: var(--font-body);
    font-size: 12px;
    font-weight: var(--fw-medium);
    text-transform: none;
    letter-spacing: 0;
    margin-left: 4px;
  }
  .label .optional { color: var(--text-secondary); }
  .section-title .optional { color: var(--text-on-band); }
  select.input { padding: 12px 14px; min-height: var(--tap); }

  /* ── Ingrédients ── */
  .col-heads {
    display: grid;
    grid-template-columns: 56px 76px 1fr;
    gap: 6px;
    margin-bottom: -8px;
    padding: 0 2px;
    font-size: 11px;
    font-weight: var(--fw-bold);
    letter-spacing: var(--tracking-caps);
    text-transform: uppercase;
    color: var(--text-secondary);
  }

  .ing-list,
  .step-list {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
  }

  .ing {
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding: 10px 0;
    border-bottom: var(--line-thin) solid var(--line);
  }

  .ing:first-child { padding-top: 0; }

  .ing-line {
    position: relative;
    display: grid;
    grid-template-columns: 56px 76px 1fr;
    gap: 6px;
  }

  .cell {
    min-width: 0;
    height: 46px;
    min-height: 46px;
    padding: 0 9px;
    font-size: 16px; /* ≥ 16 px : pas de zoom automatique sur iOS */
  }

  .ing-tools {
    display: flex;
    align-items: center;
    gap: 6px;
  }

  .rayon {
    position: relative;
    flex: 1;
    min-width: 0;
    display: flex;
    align-items: center;
    height: 44px;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
  }

  .rayon:focus-within { box-shadow: var(--shadow-sm); }

  .rayon-select {
    width: 100%;
    height: 100%;
    min-width: 0;
    padding: 0 30px 0 10px;
    border: none;
    border-radius: 0;
    background: transparent;
    color: var(--text-secondary);
    font-family: var(--font-body);
    font-size: 14px;
    font-weight: var(--fw-medium);
    text-overflow: ellipsis;
    white-space: nowrap;
    appearance: none;
    -webkit-appearance: none;
    cursor: pointer;
    outline: none;
    touch-action: manipulation;
  }

  /* L'option choisie affiche l'émoji du rayon + son nom */
  .rayon:not(.unset) .rayon-select { color: var(--text); font-weight: var(--fw-bold); }
  .rayon.unset { border-style: dashed; }

  .rayon-select option { background: var(--bg); color: var(--text); }

  .rayon-chev {
    position: absolute;
    right: 8px;
    display: flex;
    color: var(--text);
    pointer-events: none;
  }

  /* Boutons d'outil : carrés, bordés */
  .tool {
    flex: 0 0 44px;
    width: 44px;
    height: 44px;
    display: flex;
    align-items: center;
    justify-content: center;
    border: var(--line-w) solid var(--line);
    background: var(--surface);
    color: var(--text);
    cursor: pointer;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }

  .step-head .tool { margin-left: 6px; }
  .step-head .tool:first-of-type { margin-left: 0; }

  .tool:disabled { opacity: 0.3; cursor: default; }
  .tool:active:not(:disabled) { transform: translate(2px, 2px); }
  .tool-del { color: var(--error); }
  .tool:focus-visible { outline-offset: 2px; }

  .up { display: flex; transform: rotate(180deg); }

  .fresh { animation: row-in var(--dur-base) var(--ease-out); }

  @keyframes row-in {
    from { opacity: 0; transform: translateY(-6px); }
  }

  /* ── Autocomplétion ── */
  .autocomplete {
    position: absolute;
    top: calc(100% + 4px);
    left: 0;
    right: 0;
    z-index: 30;
    list-style: none;
    margin: 0;
    padding: 0;
    max-height: 240px;
    overflow-y: auto;
    background: var(--bg);
    border: var(--line-w) solid var(--line);
    box-shadow: var(--shadow-md);
  }

  .autocomplete-item {
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 44px;
    padding: 0 12px;
    color: var(--text);
    font-size: 15px;
    cursor: pointer;
    touch-action: manipulation;
  }
  .autocomplete-item + .autocomplete-item { border-top: var(--line-thin) solid var(--line); }

  .autocomplete-item.active,
  .autocomplete-item:active {
    background: var(--highlight);
  }

  .ac-emoji { font-size: 16px; }
  .ac-name { font-weight: var(--fw-bold); flex: 1; min-width: 0; }
  .ac-unit { color: var(--text-secondary); font-size: 13px; }

  /* ── Étapes ── */
  .step-list { gap: var(--sp-4); }

  .step {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .step-head {
    display: flex;
    align-items: center;
  }

  /* Numéro dans un carré noir */
  .step-badge {
    flex: 0 0 auto;
    width: 32px;
    height: 32px;
    background: var(--band);
    color: var(--text-on-band);
    font-family: var(--font-display);
    font-size: 16px;
    font-weight: var(--fw-bold);
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .step-label {
    flex: 1;
    margin-left: var(--sp-2);
    font-size: 13px;
    font-weight: var(--fw-bold);
    letter-spacing: var(--tracking-caps);
    text-transform: uppercase;
    color: var(--text-secondary);
  }

  .textarea {
    display: block;
    resize: none;
    overflow: hidden;
    min-height: 76px;
    line-height: 1.45;
    font-family: var(--font-body);
  }

  /* ── Ajouter ── */
  .btn-add {
    width: 100%;
    border-style: dashed;
    box-shadow: none;
    color: var(--text);
  }
  .btn-add:focus-visible { outline-offset: 2px; }

  /* ── Barre d'enregistrement ── */
  .save-bar {
    position: sticky;
    /* juste au-dessus de la barre d'onglets (64 px + zone de sécurité) */
    bottom: calc(64px + env(safe-area-inset-bottom, 0px) + var(--sp-2));
    z-index: 20;
    display: flex;
    flex-direction: column;
    gap: var(--sp-2);
    margin-top: var(--sp-1);
    padding: var(--sp-2) var(--sp-2) var(--sp-2) 14px;
    background: var(--surface);
    border: var(--line-w) solid var(--line);
    box-shadow: var(--shadow-md);
    transition: transform var(--dur-base) var(--ease-out), opacity var(--dur-base) var(--ease-out);
  }

  .save-bar.hidden {
    transform: translateY(16px);
    opacity: 0;
    pointer-events: none;
  }

  .save-row {
    display: flex;
    align-items: center;
    gap: var(--sp-3);
  }

  .status {
    flex: 1;
    min-width: 0;
    font-size: 13px;
    line-height: 1.3;
    color: var(--text-secondary);
  }

  .status-err {
    min-height: 44px;
    padding: 0;
    border: none;
    background: none;
    text-align: left;
    font-family: var(--font-body);
    font-weight: var(--fw-bold);
    color: var(--error);
    text-decoration: underline;
    text-underline-offset: 3px;
    cursor: pointer;
    touch-action: manipulation;
  }

  .save-btn {
    flex: 0 0 auto;
    width: auto;
    padding: 0 18px;
    font-size: 15px;
    white-space: nowrap;
  }

  .save-btn.inactive,
  .save-btn:disabled {
    background: var(--surface-sunken);
    color: var(--text-secondary);
    box-shadow: none;
  }

  .save-btn:disabled { cursor: progress; opacity: 1; }

  .form-error {
    color: var(--text);
    background: var(--error-bg);
    border: var(--line-w) solid var(--error);
    padding: var(--sp-2) var(--sp-3);
    margin-right: 6px;
    font-size: 14px;
    font-weight: var(--fw-medium);
  }

  .load-error { align-items: flex-start; }
  .load-error p { color: var(--text); }

  /* ── Photo ── */
  .visually-hidden {
    position: absolute;
    width: 1px;
    height: 1px;
    margin: -1px;
    padding: 0;
    overflow: hidden;
    clip: rect(0 0 0 0);
    white-space: nowrap;
    border: 0;
  }

  .photo-frame {
    position: relative;
    width: 100%;
    aspect-ratio: 16 / 9;
    overflow: hidden;
    background: var(--surface-sunken);
    border: var(--line-w) solid var(--line);
  }

  .photo-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }

  .photo-busy {
    position: absolute;
    inset: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 10px;
    background: var(--surface);
    color: var(--text);
    font-size: 14px;
    font-weight: var(--fw-bold);
  }

  .photo-empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 6px;
    min-height: var(--tap);
    border-style: dashed;
    color: var(--text-secondary);
    font-family: var(--font-body);
    cursor: pointer;
    touch-action: manipulation;
    transition: transform var(--dur-fast) var(--ease-out);
  }

  /* Pas de photo : inutile d'occuper tout le 16/9 sur grand écran */
  .photo-empty { aspect-ratio: auto; height: clamp(150px, 42vw, 220px); }

  .photo-empty:active:not(:disabled) { transform: translate(2px, 2px); }
  .photo-empty:disabled { cursor: progress; }
  .photo-empty:focus-visible { outline-offset: 2px; }

  .photo-empty-icon {
    width: 56px;
    height: 56px;
    border: var(--line-w) solid var(--line);
    background: var(--accent);
    color: var(--on-accent);
    box-shadow: var(--shadow-sm);
    display: flex;
    align-items: center;
    justify-content: center;
    margin-bottom: var(--sp-1);
  }

  .photo-empty-title {
    font-size: 15px;
    font-weight: var(--fw-bold);
    color: var(--text);
  }

  .photo-empty-sub { font-size: 13px; }

  .photo-actions {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: var(--sp-3);
  }

  .photo-btn { gap: var(--sp-2); font-size: 15px; }
  .photo-btn-danger { color: var(--error); }

  .photo-hint {
    margin-top: -4px;
    font-size: 12px;
    color: var(--text-secondary);
  }

  /* ── Survol (souris uniquement) ── */
  @media (hover: hover) and (pointer: fine) {
    .photo-empty:hover:not(:disabled) { background: var(--surface-hover); }
    .chip-option:hover:not(:disabled):not([aria-pressed='true']) { background: var(--surface-hover); }
    .tool:hover:not(:disabled) { background: var(--surface-hover); }
    .stepper-btn:hover:not(:disabled) { background: var(--surface-hover); }
    .autocomplete-item:hover { background: var(--highlight); }
    .vis-option:not(.selected):hover { background: var(--surface-hover); }
  }

  /* ── Grand écran : un peu plus d'air ── */
  @media (min-width: 720px) {
    .card { --pad: 20px; padding-top: 20px; padding-bottom: 20px; }
    .section-title,
    .section-head { margin-top: -20px; }
    .col-heads,
    .ing-line { grid-template-columns: 90px 110px 1fr; }
  }

  /* ── Chargement ── */
  .center-msg {
    display: flex;
    justify-content: center;
    padding: 48px var(--sp-4);
  }

  .spinner {
    width: 28px;
    height: 28px;
    border: var(--line-w) solid var(--line);
    border-top-color: var(--accent);
    animation: spin 0.8s steps(4) infinite;
  }

  .spinner-sm {
    width: 16px;
    height: 16px;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }

  @media (prefers-reduced-motion: reduce) {
    .save-bar { transition: opacity 0.01s; }
    .save-bar.hidden { transform: none; }
  }
</style>
