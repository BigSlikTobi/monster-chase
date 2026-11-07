import { getD1, getFiles } from '@/db';

const MAX_IMAGE_BYTES = 12 * 1024 * 1024;
const ALLOWED_IMAGE_TYPES = new Map([
  ['image/jpeg', 'jpg'],
  ['image/png', 'png'],
  ['image/webp', 'webp'],
]);

type CardListRow = {
  id: string;
  status: 'pending' | 'analyzed' | 'failed';
  createdAt: string;
  updatedAt: string;
  analyzedAt: string | null;
  hasBack: number;
  player: string | null;
  year: number | null;
  brand: string | null;
  setName: string | null;
  cardNumber: string | null;
  parallel: string | null;
  team: string | null;
  rookie: number | null;
  serialNumber: string | null;
  recommendation: 'Keep' | 'Sell' | 'Grade' | 'Bulk' | null;
  marketLowCents: number | null;
  marketHighCents: number | null;
  marketCheckedAt: string | null;
  soldCompCount: number | null;
  confidence: 'low' | 'medium' | 'high' | null;
  conditionNotes: string | null;
  rationale: string | null;
  needsReview: number;
  errorMessage: string | null;
};

function asCard(row: CardListRow) {
  return {
    ...row,
    hasBack: Boolean(row.hasBack),
    rookie: row.rookie === null ? null : Boolean(row.rookie),
    needsReview: Boolean(row.needsReview),
    frontImageUrl: `/api/cards/${encodeURIComponent(row.id)}/images/front`,
    backImageUrl: row.hasBack
      ? `/api/cards/${encodeURIComponent(row.id)}/images/back`
      : null,
  };
}

function validateImage(value: FormDataEntryValue | null, required: boolean) {
  if (!(value instanceof File) || value.size === 0) {
    if (required) throw new Error('Vorderseite fehlt.');
    return null;
  }

  const extension = ALLOWED_IMAGE_TYPES.get(value.type);
  if (!extension) throw new Error('Nur JPG, PNG und WebP sind erlaubt.');
  if (value.size > MAX_IMAGE_BYTES) {
    throw new Error('Ein Bild darf höchstens 12 MB groß sein.');
  }

  return { file: value, extension };
}

export async function GET(request: Request) {
  const db = getD1();
  const url = new URL(request.url);
  const requestedStatus = url.searchParams.get('status');
  if (requestedStatus && !['pending', 'analyzed', 'failed'].includes(requestedStatus)) {
    return Response.json({ error: 'Ungültiger Status.' }, { status: 400 });
  }
  const status = ['pending', 'analyzed', 'failed'].includes(requestedStatus ?? '')
    ? requestedStatus
    : null;
  const parsedLimit = Number.parseInt(url.searchParams.get('limit') ?? '100', 10);
  const limit = Number.isFinite(parsedLimit)
    ? Math.min(Math.max(parsedLimit, 1), 100)
    : 100;

  const selection = `
    SELECT
      id,
      status,
      created_at AS createdAt,
      updated_at AS updatedAt,
      analyzed_at AS analyzedAt,
      CASE WHEN back_key IS NULL THEN 0 ELSE 1 END AS hasBack,
      player,
      year,
      brand,
      set_name AS setName,
      card_number AS cardNumber,
      parallel,
      team,
      rookie,
      serial_number AS serialNumber,
      recommendation,
      market_low_cents AS marketLowCents,
      market_high_cents AS marketHighCents,
      market_checked_at AS marketCheckedAt,
      sold_comp_count AS soldCompCount,
      confidence,
      condition_notes AS conditionNotes,
      rationale,
      needs_review AS needsReview,
      error_message AS errorMessage
    FROM cards
  `;

  const statement = status
    ? db.prepare(`${selection} WHERE status = ? ORDER BY created_at DESC LIMIT ?`).bind(
        status,
        limit,
      )
    : db.prepare(`${selection} ORDER BY created_at DESC LIMIT ?`).bind(limit);
  const result = await statement.all<CardListRow>();

  return Response.json(
    {
      cards: result.results.map((row) => {
        const card = asCard(row);
        return {
          ...card,
          frontImageUrl: new URL(card.frontImageUrl, url.origin).toString(),
          backImageUrl: card.backImageUrl
            ? new URL(card.backImageUrl, url.origin).toString()
            : null,
        };
      }),
    },
    { headers: { 'Cache-Control': 'no-store' } },
  );
}

export async function POST(request: Request) {
  const db = getD1();
  const files = getFiles();
  const uploadedKeys: string[] = [];

  try {
    const contentLength = Number(request.headers.get('content-length') ?? 0);
    if (contentLength > 26 * 1024 * 1024) {
      return Response.json({ error: 'Upload ist zu groß.' }, { status: 413 });
    }
    const form = await request.formData();
    const front = validateImage(form.get('front'), true)!;
    const back = validateImage(form.get('back'), false);
    const id = crypto.randomUUID();
    const now = new Date().toISOString();

    const frontKey = `cards/${id}/front.${front.extension}`;
    const backKey = back ? `cards/${id}/back.${back.extension}` : null;

    await files.put(frontKey, front.file.stream(), {
      httpMetadata: { contentType: front.file.type },
      customMetadata: { cardId: id, side: 'front', uploadedAt: now },
    });
    uploadedKeys.push(frontKey);
    if (back && backKey) {
      await files.put(backKey, back.file.stream(), {
        httpMetadata: { contentType: back.file.type },
        customMetadata: { cardId: id, side: 'back', uploadedAt: now },
      });
      uploadedKeys.push(backKey);
    }

    await db.prepare(
      `INSERT INTO cards (
        id, status, created_at, updated_at,
        front_key, front_mime, front_name,
        back_key, back_mime, back_name
      ) VALUES (?, 'pending', ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
      .bind(
        id,
        now,
        now,
        frontKey,
        front.file.type,
        (front.file.name || 'front').slice(0, 255),
        backKey,
        back?.file.type ?? null,
        back ? (back.file.name || 'back').slice(0, 255) : null,
      )
      .run();

    return Response.json(
      {
        card: {
          id,
          status: 'pending',
          createdAt: now,
          hasBack: Boolean(backKey),
          frontImageUrl: `/api/cards/${encodeURIComponent(id)}/images/front`,
          backImageUrl: backKey
            ? `/api/cards/${encodeURIComponent(id)}/images/back`
            : null,
        },
      },
      { status: 201 },
    );
  } catch (error) {
    if (uploadedKeys.length > 0) {
      await Promise.allSettled(uploadedKeys.map((key) => files.delete(key)));
    }

    const message = error instanceof Error ? error.message : 'Upload fehlgeschlagen.';
    const isClientError =
      message.includes('fehlt') || message.includes('erlaubt') || message.includes('12 MB');
    return Response.json({ error: message }, { status: isClientError ? 400 : 500 });
  }
}
