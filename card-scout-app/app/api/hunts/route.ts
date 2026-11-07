import { getD1 } from '@/db';
import type {
  HuntPriority,
  HuntProduct,
  HuntStatus,
  HuntTarget,
} from '@/lib/hunt-types';

const PRIORITIES = new Set<HuntPriority>(['grail', 'high', 'medium', 'low']);
const STATUSES = new Set<HuntStatus>(['hunting', 'found', 'passed']);

class ValidationError extends Error {}

type ProductRow = Omit<HuntProduct, 'counts' | 'targets'>;
type TargetRow = HuntTarget;

function objectValue(value: unknown, field: string) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new ValidationError(`${field} ist ungültig.`);
  }
  return value as Record<string, unknown>;
}

function optionalText(value: unknown, field: string, max = 500) {
  if (value === null || value === undefined || value === '') return null;
  if (typeof value !== 'string' || value.length > max) {
    throw new ValidationError(`${field} ist ungültig.`);
  }
  return value.trim().replace(/\s+/g, ' ') || null;
}

function requiredText(value: unknown, field: string, max = 500) {
  const parsed = optionalText(value, field, max);
  if (!parsed) throw new ValidationError(`${field} fehlt.`);
  return parsed;
}

function optionalUrl(value: unknown, field: string) {
  const text = optionalText(value, field, 2_000);
  if (!text) return null;
  try {
    const url = new URL(text);
    if (!['http:', 'https:'].includes(url.protocol)) throw new Error();
    return url.toString();
  } catch {
    throw new ValidationError(`${field} ist ungültig.`);
  }
}

function optionalYear(value: unknown) {
  if (value === null || value === undefined || value === '') return null;
  if (
    !Number.isInteger(value) ||
    (value as number) < 1900 ||
    (value as number) > 2100
  ) {
    throw new ValidationError('Jahr ist ungültig.');
  }
  return value as number;
}

function normalized(value: string) {
  return value.trim().toLocaleLowerCase('en-US').replace(/\s+/g, ' ');
}

async function stableId(prefix: string, value: string) {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(value),
  );
  const hex = Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, '0'),
  ).join('');
  return `${prefix}_${hex.slice(0, 32)}`;
}

function parseProduct(value: unknown) {
  const input = objectValue(value, 'Box');
  const name = requiredText(input.name, 'Box/Produkt');
  const year = optionalYear(input.year);
  const brand = optionalText(input.brand, 'Marke', 120);
  const format = optionalText(input.format, 'Format', 120);
  return {
    name,
    year,
    brand,
    format,
    checklistSourceUrl: optionalUrl(input.checklistSourceUrl, 'Checklist-URL'),
    sourceCheckedAt: optionalText(input.sourceCheckedAt, 'Prüfdatum', 40),
    normalizedKey: normalized(
      `${year ?? ''}|${brand ?? ''}|${name}|${format ?? ''}`,
    ),
  };
}

function parseTargets(value: unknown) {
  if (!Array.isArray(value) || value.length < 1 || value.length > 50) {
    throw new ValidationError('Es werden 1 bis 50 Chase Cards erwartet.');
  }

  return value.map((item, index) => {
    const input = objectValue(item, `Chase Card ${index + 1}`);
    const label = requiredText(input.label, `Name der Chase Card ${index + 1}`);
    const player = optionalText(input.player, `Spieler ${index + 1}`, 200);
    const cardNumber = optionalText(
      input.cardNumber,
      `Kartennummer ${index + 1}`,
      100,
    );
    const parallel = optionalText(input.parallel, `Parallel ${index + 1}`, 200);
    const priority = input.priority ?? 'medium';
    const status = input.status ?? 'hunting';
    if (
      typeof priority !== 'string' ||
      !PRIORITIES.has(priority as HuntPriority)
    ) {
      throw new ValidationError(
        `Priorität der Chase Card ${index + 1} ist ungültig.`,
      );
    }
    if (typeof status !== 'string' || !STATUSES.has(status as HuntStatus)) {
      throw new ValidationError(
        `Status der Chase Card ${index + 1} ist ungültig.`,
      );
    }

    return {
      label,
      player,
      cardNumber,
      parallel,
      whySpecial: optionalText(
        input.whySpecial,
        `Begründung ${index + 1}`,
        2_000,
      ),
      priority: priority as HuntPriority,
      status: status as HuntStatus,
      sourceUrl: optionalUrl(input.sourceUrl, `Quellen-URL ${index + 1}`),
      notes: optionalText(input.notes, `Notiz ${index + 1}`, 2_000),
      normalizedKey: normalized(
        `${label}|${player ?? ''}|${cardNumber ?? ''}|${parallel ?? ''}`,
      ),
    };
  });
}

export async function GET(request: Request) {
  const db = getD1();
  const url = new URL(request.url);
  const status = url.searchParams.get('status');
  const productId = url.searchParams.get('productId');
  if (status && !STATUSES.has(status as HuntStatus)) {
    return Response.json(
      { error: 'Ungültiger Lookout-Status.' },
      { status: 400 },
    );
  }

  const productsStatement = productId
    ? db
        .prepare(
          `SELECT id, name, year, brand, format,
            checklist_source_url AS checklistSourceUrl,
            source_checked_at AS sourceCheckedAt,
            created_at AS createdAt, updated_at AS updatedAt
          FROM hunt_products WHERE id = ? ORDER BY created_at DESC`,
        )
        .bind(productId)
    : db.prepare(
        `SELECT id, name, year, brand, format,
          checklist_source_url AS checklistSourceUrl,
          source_checked_at AS sourceCheckedAt,
          created_at AS createdAt, updated_at AS updatedAt
        FROM hunt_products ORDER BY created_at DESC`,
      );

  const targetConditions: string[] = [];
  const targetBindings: string[] = [];
  if (productId) {
    targetConditions.push('product_id = ?');
    targetBindings.push(productId);
  }
  const where = targetConditions.length
    ? `WHERE ${targetConditions.join(' AND ')}`
    : '';
  const targetsStatement = db
    .prepare(
      `SELECT id, product_id AS productId, label, player, card_number AS cardNumber,
        parallel, why_special AS whySpecial, priority, status, source_url AS sourceUrl,
        notes, found_at AS foundAt, created_at AS createdAt, updated_at AS updatedAt
      FROM hunt_targets ${where}
      ORDER BY product_id,
        CASE status WHEN 'hunting' THEN 0 WHEN 'found' THEN 1 ELSE 2 END,
        CASE priority WHEN 'grail' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END,
        created_at`,
    )
    .bind(...targetBindings);

  const [productsResult, targetsResult] = await Promise.all([
    productsStatement.all<ProductRow>(),
    targetsStatement.all<TargetRow>(),
  ]);
  const targetsByProduct = new Map<string, HuntTarget[]>();
  for (const target of targetsResult.results) {
    const list = targetsByProduct.get(target.productId) ?? [];
    list.push(target);
    targetsByProduct.set(target.productId, list);
  }

  const products = productsResult.results
    .map((product) => {
      const allTargets = targetsByProduct.get(product.id) ?? [];
      const targets = status
        ? allTargets.filter((target) => target.status === status)
        : allTargets;
      return {
        ...product,
        counts: {
          total: allTargets.length,
          hunting: allTargets.filter((target) => target.status === 'hunting')
            .length,
          found: allTargets.filter((target) => target.status === 'found')
            .length,
        },
        targets,
      } satisfies HuntProduct;
    })
    .filter((product) => !status || product.targets.length > 0);

  return Response.json(
    { products },
    { headers: { 'Cache-Control': 'no-store' } },
  );
}

export async function POST(request: Request) {
  try {
    const db = getD1();
    const body = objectValue(await request.json(), 'Payload');
    const product = parseProduct(body.product);
    const targets = parseTargets(body.targets);
    const now = new Date().toISOString();
    const productId = await stableId('hp', product.normalizedKey);
    const targetRows = await Promise.all(
      targets.map(async (target) => ({
        ...target,
        id: await stableId('ht', `${productId}|${target.normalizedKey}`),
      })),
    );

    const statements = [
      db
        .prepare(
          `INSERT INTO hunt_products (
            id, normalized_key, name, year, brand, format, checklist_source_url,
            source_checked_at, created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(normalized_key) DO UPDATE SET
            name = excluded.name,
            year = COALESCE(excluded.year, hunt_products.year),
            brand = COALESCE(excluded.brand, hunt_products.brand),
            format = COALESCE(excluded.format, hunt_products.format),
            checklist_source_url = COALESCE(
              excluded.checklist_source_url,
              hunt_products.checklist_source_url
            ),
            source_checked_at = COALESCE(excluded.source_checked_at, hunt_products.source_checked_at),
            updated_at = excluded.updated_at`,
        )
        .bind(
          productId,
          product.normalizedKey,
          product.name,
          product.year,
          product.brand,
          product.format,
          product.checklistSourceUrl,
          product.sourceCheckedAt,
          now,
          now,
        ),
      ...targetRows.map((target) =>
        db
          .prepare(
            `INSERT INTO hunt_targets (
              id, product_id, normalized_key, label, player, card_number, parallel,
              why_special, priority, status, source_url, notes, found_at, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(product_id, normalized_key) DO UPDATE SET
              label = excluded.label,
              player = COALESCE(excluded.player, hunt_targets.player),
              card_number = COALESCE(excluded.card_number, hunt_targets.card_number),
              parallel = COALESCE(excluded.parallel, hunt_targets.parallel),
              why_special = COALESCE(excluded.why_special, hunt_targets.why_special),
              priority = excluded.priority,
              source_url = COALESCE(excluded.source_url, hunt_targets.source_url),
              notes = COALESCE(excluded.notes, hunt_targets.notes),
              updated_at = excluded.updated_at`,
          )
          .bind(
            target.id,
            productId,
            target.normalizedKey,
            target.label,
            target.player,
            target.cardNumber,
            target.parallel,
            target.whySpecial,
            target.priority,
            target.status,
            target.sourceUrl,
            target.notes,
            target.status === 'found' ? now : null,
            now,
            now,
          ),
      ),
    ];
    await db.batch(statements);

    return Response.json(
      {
        productId,
        targetIds: targetRows.map((target) => target.id),
        saved: targetRows.length,
      },
      { status: 201, headers: { 'Cache-Control': 'no-store' } },
    );
  } catch (error) {
    if (error instanceof ValidationError || error instanceof SyntaxError) {
      return Response.json({ error: error.message }, { status: 400 });
    }
    console.error(error);
    return Response.json(
      { error: 'Lookout konnte nicht gespeichert werden.' },
      { status: 500 },
    );
  }
}
