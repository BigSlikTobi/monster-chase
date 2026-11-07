import { getD1 } from '@/db';
import type { HuntPriority, HuntStatus } from '@/lib/hunt-types';

const PRIORITIES = new Set<HuntPriority>(['grail', 'high', 'medium', 'low']);
const STATUSES = new Set<HuntStatus>(['hunting', 'found', 'passed']);

type RouteContext = { params: Promise<{ id: string }> };
type CurrentTarget = {
  status: HuntStatus;
  priority: HuntPriority;
  foundAt: string | null;
};

export async function PATCH(request: Request, context: RouteContext) {
  try {
    const db = getD1();
    const { id } = await context.params;
    const body = (await request.json()) as {
      status?: unknown;
      priority?: unknown;
    };
    if (!body || typeof body !== 'object' || Array.isArray(body)) {
      return Response.json(
        { error: 'Änderung ist ungültig.' },
        { status: 400 },
      );
    }
    if (body.status === undefined && body.priority === undefined) {
      return Response.json(
        { error: 'Status oder Priorität fehlt.' },
        { status: 400 },
      );
    }
    if (body.status !== undefined && !STATUSES.has(body.status as HuntStatus)) {
      return Response.json({ error: 'Status ist ungültig.' }, { status: 400 });
    }
    if (
      body.priority !== undefined &&
      !PRIORITIES.has(body.priority as HuntPriority)
    ) {
      return Response.json(
        { error: 'Priorität ist ungültig.' },
        { status: 400 },
      );
    }

    const current = await db
      .prepare(
        `SELECT status, priority, found_at AS foundAt FROM hunt_targets WHERE id = ?`,
      )
      .bind(id)
      .first<CurrentTarget>();
    if (!current)
      return Response.json(
        { error: 'Chase Card nicht gefunden.' },
        { status: 404 },
      );

    const status = (body.status ?? current.status) as HuntStatus;
    const priority = (body.priority ?? current.priority) as HuntPriority;
    const now = new Date().toISOString();
    const foundAt = status === 'found' ? (current.foundAt ?? now) : null;
    await db
      .prepare(
        `UPDATE hunt_targets
        SET status = ?, priority = ?, found_at = ?, updated_at = ?
        WHERE id = ?`,
      )
      .bind(status, priority, foundAt, now, id)
      .run();

    return Response.json({ id, status, priority, foundAt, updatedAt: now });
  } catch (error) {
    if (error instanceof SyntaxError) {
      return Response.json({ error: 'Ungültiges JSON.' }, { status: 400 });
    }
    console.error(error);
    return Response.json(
      { error: 'Lookout konnte nicht aktualisiert werden.' },
      { status: 500 },
    );
  }
}
