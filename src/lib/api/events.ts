// Couche données — Événements (v1.999.0, migration 28).
// Droits garantis par la base (RLS + triggers) : on ne voit que les événements de son
// foyer, ou ceux « famille » de sa famille élargie ; chacun ne s'inscrit / ne répond
// que pour lui-même.

import { supabase } from '../supabase'
import type { EventKind, EventScope, RsvpAnswer } from '../evenements'

function db() {
  if (!supabase) throw new Error('Supabase non configuré')
  return supabase
}

export interface FamilyEvent {
  id: string
  family_id: string
  created_by: string | null
  kind: EventKind
  scope: EventScope
  title: string
  starts_on: string
  start_time: string | null
  location: string | null
  theme: string | null
  playlist_url: string | null
  notes: string | null
}

export interface EventTask {
  id: string
  event_id: string
  label: string
  position: number
  volunteers: string[]
  created_by: string | null
}

export interface EventRsvp {
  id: string
  event_id: string
  profile_id: string
  answer: RsvpAnswer
}

export interface EventDetail {
  event: FamilyEvent
  tasks: EventTask[]
  rsvps: EventRsvp[]
  /** Prénoms des personnes de l'événement (fonction event_people) */
  names: Map<string, string>
}

const EVENT_COLS = 'id, family_id, created_by, kind, scope, title, starts_on, start_time, location, theme, playlist_url, notes'

/** Événements visibles (mon foyer + « famille »), du plus proche au plus lointain. */
export async function fetchEvents(): Promise<FamilyEvent[]> {
  const { data, error } = await db().from('events').select(EVENT_COLS).order('starts_on').order('created_at')
  if (error) throw error
  return (data ?? []) as FamilyEvent[]
}

export async function fetchEvent(id: string): Promise<EventDetail | null> {
  const [ev, tasks, rsvps, people] = await Promise.all([
    db().from('events').select(EVENT_COLS).eq('id', id).maybeSingle(),
    db().from('event_tasks').select('id, event_id, label, position, volunteers, created_by').eq('event_id', id).order('position').order('created_at'),
    db().from('event_rsvps').select('id, event_id, profile_id, answer').eq('event_id', id),
    db().rpc('event_people', { p_event: id }),
  ])
  for (const r of [ev, tasks, rsvps, people]) if (r.error) throw r.error
  if (!ev.data) return null
  const names = new Map<string, string>()
  for (const p of (people.data ?? []) as { id: string; display_name: string }[]) names.set(p.id, p.display_name)
  return {
    event: ev.data as FamilyEvent,
    tasks: (tasks.data ?? []) as EventTask[],
    rsvps: (rsvps.data ?? []) as EventRsvp[],
    names,
  }
}

export interface EventInput {
  kind: EventKind
  scope: EventScope
  title: string
  starts_on: string
  start_time: string | null
  location: string | null
  theme: string | null
  playlist_url: string | null
  notes: string | null
}

/** Crée l'événement puis ses pôles « qui fait quoi ». Renvoie l'id. */
export async function createEvent(familyId: string, input: EventInput, poles: string[]): Promise<string> {
  const { data, error } = await db().from('events').insert({ family_id: familyId, ...input }).select('id').single()
  if (error) throw error
  const id = (data as { id: string }).id
  if (poles.length) {
    const rows = poles.map((label, position) => ({ event_id: id, label, position }))
    const r = await db().from('event_tasks').insert(rows)
    if (r.error) throw r.error
  }
  return id
}

export async function updateEvent(id: string, input: EventInput): Promise<void> {
  const { data, error } = await db().from('events').update(input).eq('id', id).select('id')
  if (error) throw error
  if (!data?.length) throw new Error('Tu ne peux pas modifier cet événement.')
}

export async function deleteEvent(id: string): Promise<void> {
  const { data, error } = await db().from('events').delete().eq('id', id).select('id')
  if (error) throw error
  if (!data?.length) throw new Error('Tu ne peux pas supprimer cet événement.')
}

export async function setRsvp(eventId: string, userId: string, answer: RsvpAnswer): Promise<void> {
  const { error } = await db()
    .from('event_rsvps')
    .upsert({ event_id: eventId, profile_id: userId, answer }, { onConflict: 'event_id,profile_id' })
  if (error) throw error
}

export async function addTask(eventId: string, label: string, position: number): Promise<void> {
  const { error } = await db().from('event_tasks').insert({ event_id: eventId, label, position })
  if (error) throw error
}

export async function deleteTask(id: string): Promise<void> {
  const { data, error } = await db().from('event_tasks').delete().eq('id', id).select('id')
  if (error) throw error
  if (!data?.length) throw new Error('Seul l’auteur de la tâche ou de l’événement peut la supprimer.')
}

/** S'inscrire / se retirer d'une tâche, en une seule opération côté base. */
export async function setVolunteer(taskId: string, on: boolean): Promise<string[]> {
  const { data, error } = await db().rpc('toggle_event_volunteer', { p_task: taskId, p_on: on })
  if (error) throw error
  if (data == null) throw new Error('Tâche introuvable.')
  return data as string[]
}
