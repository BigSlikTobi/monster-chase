import { getD1, getFiles } from '@/db';

const SAFE_IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);

type RouteContext = {
  params: Promise<{ id: string; side: string }>;
};

type ImageRow = {
  objectKey: string | null;
  contentType: string | null;
};

export async function GET(request: Request, context: RouteContext) {
  const db = getD1();
  const files = getFiles();
  const { id, side } = await context.params;
  if (side !== 'front' && side !== 'back') {
    return Response.json({ error: 'Unbekannte Bildseite.' }, { status: 400 });
  }

  const keyColumn = side === 'front' ? 'front_key' : 'back_key';
  const mimeColumn = side === 'front' ? 'front_mime' : 'back_mime';
  const row = await db.prepare(
    `SELECT ${keyColumn} AS objectKey, ${mimeColumn} AS contentType FROM cards WHERE id = ?`,
  )
    .bind(id)
    .first<ImageRow>();

  if (!row?.objectKey) {
    return Response.json({ error: 'Bild nicht gefunden.' }, { status: 404 });
  }

  const object = await files.get(row.objectKey);
  if (!object) {
    return Response.json({ error: 'Bild nicht gefunden.' }, { status: 404 });
  }

  const contentType = SAFE_IMAGE_TYPES.has(row.contentType ?? '')
    ? row.contentType!
    : 'application/octet-stream';
  const headers = new Headers({
    'Content-Type': contentType,
    'Content-Length': String(object.size),
    'Cache-Control': 'private, max-age=300',
    'X-Content-Type-Options': 'nosniff',
    'Cross-Origin-Resource-Policy': 'same-origin',
    ETag: object.httpEtag,
  });

  if (request.headers.get('if-none-match') === object.httpEtag) {
    return new Response(null, { status: 304, headers });
  }

  return new Response(object.body, { headers });
}
