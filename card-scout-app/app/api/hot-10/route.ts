import { getD1 } from '@/db';
import type {
  HotBoard,
  HotBrandFamily,
  HotCard,
  HotSaleEvidence,
  LicenseScope,
  MatchQuality,
} from '@/lib/hot-10-types';

const BOARD_ID = 'current';
const BRANDS = new Set<HotBrandFamily>(['donruss', 'select', 'prizm', 'topps']);
const LICENSES = new Set<LicenseScope>(['nfl', 'nflpa', 'nfl_and_nflpa']);
const MATCH_QUALITIES = new Set<MatchQuality>(['exact', 'near', 'proxy']);

class ValidationError extends Error {}

type HotCardRow = Omit<HotCard, 'evidence'> & { evidenceJson: string };

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

function httpsUrl(value: unknown, field: string) {
  const text = requiredText(value, field, 4_000);
  try {
    const url = new URL(text);
    if (url.protocol !== 'https:') throw new Error();
    return url.toString();
  } catch {
    throw new ValidationError(`${field} muss eine HTTPS-URL sein.`);
  }
}

function dateText(value: unknown, field: string) {
  const text = requiredText(value, field, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) {
    throw new ValidationError(`${field} muss YYYY-MM-DD sein.`);
  }
  const parsed = new Date(`${text}T00:00:00.000Z`);
  if (
    Number.isNaN(parsed.getTime()) ||
    parsed.toISOString().slice(0, 10) !== text
  ) {
    throw new ValidationError(`${field} ist kein gültiges Datum.`);
  }
  return text;
}

function integerValue(
  value: unknown,
  field: string,
  minimum: number,
  maximum: number,
) {
  if (
    !Number.isInteger(value) ||
    (value as number) < minimum ||
    (value as number) > maximum
  ) {
    throw new ValidationError(`${field} ist ungültig.`);
  }
  return value as number;
}

function optionalInteger(
  value: unknown,
  field: string,
  minimum: number,
  maximum: number,
) {
  if (value === null || value === undefined || value === '') return null;
  return integerValue(value, field, minimum, maximum);
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

function parseEvidence(value: unknown, cardIndex: number) {
  if (!Array.isArray(value) || value.length < 1 || value.length > 20) {
    throw new ValidationError(
      `Karte ${cardIndex + 1} braucht 1 bis 20 verkaufte Belege.`,
    );
  }

  return value.map((item, evidenceIndex) => {
    const input = objectValue(
      item,
      `Beleg ${evidenceIndex + 1} von Karte ${cardIndex + 1}`,
    );
    const matchQuality = requiredText(
      input.matchQuality,
      `Match-Qualität ${evidenceIndex + 1}`,
      20,
    );
    if (!MATCH_QUALITIES.has(matchQuality as MatchQuality)) {
      throw new ValidationError(
        `Match-Qualität ${evidenceIndex + 1} ist ungültig.`,
      );
    }
    const currency = requiredText(
      input.currency,
      `Währung ${evidenceIndex + 1}`,
      8,
    ).toUpperCase();
    if (!/^[A-Z]{3,8}$/.test(currency)) {
      throw new ValidationError(`Währung ${evidenceIndex + 1} ist ungültig.`);
    }
    return {
      url: httpsUrl(input.url, `Beleg-URL ${evidenceIndex + 1}`),
      title: requiredText(input.title, `Belegtitel ${evidenceIndex + 1}`, 300),
      saleDate: dateText(input.saleDate, `Verkaufsdatum ${evidenceIndex + 1}`),
      deliveredTotalCents: integerValue(
        input.deliveredTotalCents,
        `Verkaufspreis ${evidenceIndex + 1}`,
        0,
        1_000_000_000,
      ),
      currency,
      matchQuality: matchQuality as MatchQuality,
    } satisfies HotSaleEvidence;
  });
}

function parseBoard(value: unknown) {
  const input = objectValue(value, 'Hot-10-Board');
  const windowStart = dateText(input.windowStart, 'Start des Marktfensters');
  const windowEnd = dateText(input.windowEnd, 'Ende des Marktfensters');
  const start = new Date(`${windowStart}T00:00:00.000Z`).getTime();
  const end = new Date(`${windowEnd}T00:00:00.000Z`).getTime();
  const days = Math.round((end - start) / 86_400_000);
  if (days < 80 || days > 100) {
    throw new ValidationError(
      'Das Marktfenster muss ungefähr 90 Tage umfassen (80 bis 100 Tage).',
    );
  }
  const researchedAt = dateText(input.researchedAt, 'Recherche-Datum');
  if (windowEnd > researchedAt) {
    throw new ValidationError(
      'Das Ende des Marktfensters darf nicht nach dem Recherche-Datum liegen.',
    );
  }
  return {
    windowStart,
    windowEnd,
    methodology: requiredText(input.methodology, 'Methode', 1_500),
    coverageNote: optionalText(input.coverageNote, 'Abdeckung', 1_000),
    researchedAt,
  };
}

function parseCards(
  value: unknown,
  window: { windowStart: string; windowEnd: string },
) {
  if (!Array.isArray(value) || value.length < 1 || value.length > 10) {
    throw new ValidationError('Es werden 1 bis 10 belegte Hot Cards erwartet.');
  }

  const cards = value.map((item, index) => {
    const input = objectValue(item, `Hot Card ${index + 1}`);
    const rank = integerValue(input.rank, `Rang ${index + 1}`, 1, value.length);
    const brandFamily = requiredText(
      input.brandFamily,
      `Marke ${index + 1}`,
      20,
    );
    if (!BRANDS.has(brandFamily as HotBrandFamily)) {
      throw new ValidationError(`Marke ${index + 1} ist ungültig.`);
    }
    const licenseScope = requiredText(
      input.licenseScope,
      `Lizenz ${index + 1}`,
      30,
    );
    if (!LICENSES.has(licenseScope as LicenseScope)) {
      throw new ValidationError(`Lizenz ${index + 1} ist ungültig.`);
    }
    const year = optionalInteger(input.year, `Jahr ${index + 1}`, 1900, 2100);
    const productName = requiredText(
      input.productName,
      `Produkt ${index + 1}`,
      240,
    );
    const label = requiredText(input.label, `Kartenname ${index + 1}`, 300);
    const player = optionalText(input.player, `Spieler ${index + 1}`, 200);
    const cardNumber = optionalText(
      input.cardNumber,
      `Kartennummer ${index + 1}`,
      100,
    );
    const parallel = optionalText(input.parallel, `Parallel ${index + 1}`, 240);
    const currency = requiredText(
      input.currency,
      `Währung ${index + 1}`,
      8,
    ).toUpperCase();
    if (!/^[A-Z]{3,8}$/.test(currency)) {
      throw new ValidationError(`Währung ${index + 1} ist ungültig.`);
    }
    const evidence = parseEvidence(input.evidence, index);
    if (
      evidence.some(
        (sale) =>
          sale.saleDate < window.windowStart ||
          sale.saleDate > window.windowEnd,
      )
    ) {
      throw new ValidationError(
        `Mindestens ein Beleg von Karte ${index + 1} liegt außerhalb des Marktfensters.`,
      );
    }
    if (evidence.some((sale) => sale.currency !== currency)) {
      throw new ValidationError(
        `Die Währung der Belege von Karte ${index + 1} passt nicht.`,
      );
    }
    const marketLowCents = optionalInteger(
      input.marketLowCents,
      `Marktminimum ${index + 1}`,
      0,
      1_000_000_000,
    );
    const medianSoldCents = optionalInteger(
      input.medianSoldCents,
      `Marktmedian ${index + 1}`,
      0,
      1_000_000_000,
    );
    const marketHighCents = optionalInteger(
      input.marketHighCents,
      `Marktmaximum ${index + 1}`,
      0,
      1_000_000_000,
    );
    const marketValues = [marketLowCents, medianSoldCents, marketHighCents];
    if (
      marketValues.some((entry) => entry === null) &&
      marketValues.some((entry) => entry !== null)
    ) {
      throw new ValidationError(
        `Marktspanne ${index + 1} muss komplett oder leer sein.`,
      );
    }
    if (
      marketLowCents !== null &&
      medianSoldCents !== null &&
      marketHighCents !== null &&
      !(marketLowCents <= medianSoldCents && medianSoldCents <= marketHighCents)
    ) {
      throw new ValidationError(
        `Marktspanne ${index + 1} ist widersprüchlich.`,
      );
    }
    const soldCompCount = integerValue(
      input.soldCompCount,
      `Verkaufsanzahl ${index + 1}`,
      evidence.length,
      10_000,
    );
    const normalizedKey = normalized(
      `${brandFamily}|${year ?? ''}|${productName}|${label}|${player ?? ''}|${cardNumber ?? ''}|${parallel ?? ''}`,
    );
    const latestEvidenceSaleAt = evidence.reduce(
      (latest, sale) => (sale.saleDate > latest ? sale.saleDate : latest),
      evidence[0].saleDate,
    );
    const suppliedLastSaleAt = input.lastSaleAt
      ? dateText(input.lastSaleAt, `Letzter Verkauf ${index + 1}`)
      : null;
    if (suppliedLastSaleAt && suppliedLastSaleAt !== latestEvidenceSaleAt) {
      throw new ValidationError(
        `Der letzte Verkauf von Karte ${index + 1} muss dem neuesten Beleg entsprechen.`,
      );
    }
    return {
      rank,
      normalizedKey,
      brandFamily: brandFamily as HotBrandFamily,
      productName,
      year,
      format: optionalText(input.format, `Format ${index + 1}`, 120),
      licenseScope: licenseScope as LicenseScope,
      licenseSourceUrl: httpsUrl(
        input.licenseSourceUrl,
        `Lizenzquelle ${index + 1}`,
      ),
      licenseCheckedAt: dateText(
        input.licenseCheckedAt,
        `Lizenzprüfung ${index + 1}`,
      ),
      label,
      player,
      team: optionalText(input.team, `Team ${index + 1}`, 160),
      cardNumber,
      parallel,
      imageUrl: httpsUrl(input.imageUrl, `Bild-URL ${index + 1}`),
      imageSourceUrl: httpsUrl(input.imageSourceUrl, `Bildquelle ${index + 1}`),
      whyHot: requiredText(input.whyHot, `Hot-Begründung ${index + 1}`, 1_000),
      soldCompCount,
      marketLowCents,
      medianSoldCents,
      marketHighCents,
      currency,
      momentumBps: optionalInteger(
        input.momentumBps,
        `Momentum ${index + 1}`,
        -100_000,
        100_000,
      ),
      lastSaleAt: latestEvidenceSaleAt,
      evidence,
    };
  });

  const ranks = cards.map((card) => card.rank).sort((a, b) => a - b);
  if (ranks.some((rank, index) => rank !== index + 1)) {
    throw new ValidationError('Die Ränge müssen lückenlos bei 1 beginnen.');
  }
  if (new Set(cards.map((card) => card.normalizedKey)).size !== cards.length) {
    throw new ValidationError(
      'Doppelte Karten sind im Hot-10-Board nicht erlaubt.',
    );
  }
  return cards.sort((a, b) => a.rank - b.rank);
}

function safeEvidence(value: string) {
  try {
    const parsed = JSON.parse(value);
    return Array.isArray(parsed) ? (parsed as HotSaleEvidence[]) : [];
  } catch {
    return [];
  }
}

export async function GET(request: Request) {
  const db = getD1();
  const url = new URL(request.url);
  const brand = url.searchParams.get('brand');
  if (brand && !BRANDS.has(brand as HotBrandFamily)) {
    return Response.json({ error: 'Ungültige Marke.' }, { status: 400 });
  }

  const boardStatement = db
    .prepare(
      `SELECT id, window_start AS windowStart, window_end AS windowEnd,
        methodology, coverage_note AS coverageNote, researched_at AS researchedAt,
        created_at AS createdAt, updated_at AS updatedAt
      FROM hot_boards WHERE id = ?`,
    )
    .bind(BOARD_ID);

  const statement = brand
    ? db
        .prepare(
          `SELECT id, board_id AS boardId, rank, brand_family AS brandFamily,
            product_name AS productName, year, format, license_scope AS licenseScope,
            license_source_url AS licenseSourceUrl, license_checked_at AS licenseCheckedAt,
            label, player, team, card_number AS cardNumber, parallel, image_url AS imageUrl,
            image_source_url AS imageSourceUrl, why_hot AS whyHot,
            sold_comp_count AS soldCompCount, market_low_cents AS marketLowCents,
            median_sold_cents AS medianSoldCents, market_high_cents AS marketHighCents,
            currency, momentum_bps AS momentumBps, last_sale_at AS lastSaleAt,
            evidence_json AS evidenceJson, created_at AS createdAt, updated_at AS updatedAt
          FROM hot_cards WHERE board_id = ? AND brand_family = ? ORDER BY rank`,
        )
        .bind(BOARD_ID, brand)
    : db
        .prepare(
          `SELECT id, board_id AS boardId, rank, brand_family AS brandFamily,
            product_name AS productName, year, format, license_scope AS licenseScope,
            license_source_url AS licenseSourceUrl, license_checked_at AS licenseCheckedAt,
            label, player, team, card_number AS cardNumber, parallel, image_url AS imageUrl,
            image_source_url AS imageSourceUrl, why_hot AS whyHot,
            sold_comp_count AS soldCompCount, market_low_cents AS marketLowCents,
            median_sold_cents AS medianSoldCents, market_high_cents AS marketHighCents,
            currency, momentum_bps AS momentumBps, last_sale_at AS lastSaleAt,
            evidence_json AS evidenceJson, created_at AS createdAt, updated_at AS updatedAt
          FROM hot_cards WHERE board_id = ? ORDER BY rank`,
        )
        .bind(BOARD_ID);

  const [boardResult, cardsResult] = await db.batch([
    boardStatement,
    statement,
  ]);
  const board = boardResult.results[0] as unknown as HotBoard | undefined;
  const cards = (cardsResult.results as unknown as HotCardRow[]).map(
    ({ evidenceJson, ...card }) => ({
      ...card,
      evidence: safeEvidence(evidenceJson),
    }),
  ) satisfies HotCard[];

  return Response.json(
    { board: board ?? null, cards: board ? cards : [] },
    { headers: { 'Cache-Control': 'no-store' } },
  );
}

export async function PUT(request: Request) {
  try {
    const db = getD1();
    const body = objectValue(await request.json(), 'Payload');
    const board = parseBoard(body.board);
    const cards = parseCards(body.cards, board);
    const now = new Date().toISOString();
    const rows = await Promise.all(
      cards.map(async (card) => ({
        ...card,
        id: await stableId('hot', card.normalizedKey),
      })),
    );

    const statements = [
      db
        .prepare(
          `INSERT INTO hot_boards (
            id, window_start, window_end, methodology, coverage_note,
            researched_at, created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            window_start = excluded.window_start,
            window_end = excluded.window_end,
            methodology = excluded.methodology,
            coverage_note = excluded.coverage_note,
            researched_at = excluded.researched_at,
            updated_at = excluded.updated_at`,
        )
        .bind(
          BOARD_ID,
          board.windowStart,
          board.windowEnd,
          board.methodology,
          board.coverageNote,
          board.researchedAt,
          now,
          now,
        ),
      db.prepare('DELETE FROM hot_cards WHERE board_id = ?').bind(BOARD_ID),
      ...rows.map((card) =>
        db
          .prepare(
            `INSERT INTO hot_cards (
              id, board_id, rank, normalized_key, brand_family, product_name,
              year, format, license_scope, license_source_url, license_checked_at,
              label, player, team, card_number, parallel, image_url, image_source_url,
              why_hot, sold_comp_count, market_low_cents, median_sold_cents,
              market_high_cents, currency, momentum_bps, last_sale_at,
              evidence_json, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          )
          .bind(
            card.id,
            BOARD_ID,
            card.rank,
            card.normalizedKey,
            card.brandFamily,
            card.productName,
            card.year,
            card.format,
            card.licenseScope,
            card.licenseSourceUrl,
            card.licenseCheckedAt,
            card.label,
            card.player,
            card.team,
            card.cardNumber,
            card.parallel,
            card.imageUrl,
            card.imageSourceUrl,
            card.whyHot,
            card.soldCompCount,
            card.marketLowCents,
            card.medianSoldCents,
            card.marketHighCents,
            card.currency,
            card.momentumBps,
            card.lastSaleAt,
            JSON.stringify(card.evidence),
            now,
            now,
          ),
      ),
    ];
    await db.batch(statements);

    return Response.json({
      boardId: BOARD_ID,
      saved: rows.length,
      researchedAt: board.researchedAt,
    });
  } catch (error) {
    if (error instanceof ValidationError || error instanceof SyntaxError) {
      return Response.json({ error: error.message }, { status: 400 });
    }
    console.error(error);
    return Response.json(
      { error: 'Hot 10 konnte nicht gespeichert werden.' },
      { status: 500 },
    );
  }
}
