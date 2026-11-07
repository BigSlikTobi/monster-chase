import { getD1 } from '@/db';

type RouteContext = { params: Promise<{ id: string }> };

const RECOMMENDATIONS = new Set(['Keep', 'Sell', 'Grade', 'Bulk']);
const CONFIDENCE_LEVELS = new Set(['low', 'medium', 'high']);
const SOURCE_STATUSES = new Set(['sold', 'ask']);
const MATCH_LEVELS = new Set(['exact', 'near', 'proxy']);

class ValidationError extends Error {}

type AnalysisInput = {
  player: string | null;
  year: number | null;
  brand: string | null;
  setName: string | null;
  cardNumber: string | null;
  parallel: string | null;
  team: string | null;
  rookie: boolean | null;
  serialNumber: string | null;
  recommendation: 'Keep' | 'Sell' | 'Grade' | 'Bulk';
  marketLowCents: number | null;
  marketHighCents: number | null;
  marketCheckedAt: string;
  marketSources: Array<Record<string, unknown>>;
  soldCompCount: number;
  confidence: 'low' | 'medium' | 'high';
  conditionNotes: string;
  rationale: string;
  needsReview: boolean;
  grading?: Record<string, unknown>;
  [key: string]: unknown;
};

function objectValue(value: unknown, field: string) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new ValidationError(`${field} ist ungültig.`);
  }
  return value as Record<string, unknown>;
}

function optionalString(value: unknown, field: string, max = 500) {
  if (value === null || value === undefined || value === '') return null;
  if (typeof value !== 'string' || value.length > max) {
    throw new ValidationError(`${field} ist ungültig.`);
  }
  return value.trim() || null;
}

function requiredString(value: unknown, field: string, max = 2_000) {
  const parsed = optionalString(value, field, max);
  if (!parsed) throw new ValidationError(`${field} fehlt.`);
  return parsed;
}

function integerValue(
  value: unknown,
  field: string,
  { nullable = true, min = 0, max = 100_000_000 } = {},
) {
  if ((value === null || value === undefined) && nullable) return null;
  if (!Number.isInteger(value) || (value as number) < min || (value as number) > max) {
    throw new ValidationError(`${field} ist ungültig.`);
  }
  return value as number;
}

function parseSources(value: unknown) {
  if (!Array.isArray(value) || value.length > 100) {
    throw new ValidationError('Marktquellen sind ungültig.');
  }

  return value.map((item, index) => {
    const source = objectValue(item, `Marktquelle ${index + 1}`);
    const url = requiredString(source.url, `URL der Marktquelle ${index + 1}`, 2_000);
    try {
      const parsedUrl = new URL(url);
      if (!['http:', 'https:'].includes(parsedUrl.protocol)) throw new Error();
    } catch {
      throw new ValidationError(`URL der Marktquelle ${index + 1} ist ungültig.`);
    }
    if (typeof source.status !== 'string' || !SOURCE_STATUSES.has(source.status)) {
      throw new ValidationError(`Status der Marktquelle ${index + 1} ist ungültig.`);
    }
    if (typeof source.matchQuality !== 'string' || !MATCH_LEVELS.has(source.matchQuality)) {
      throw new ValidationError(`Match der Marktquelle ${index + 1} ist ungültig.`);
    }

    return {
      ...source,
      url,
      title: requiredString(source.title, `Titel der Marktquelle ${index + 1}`),
      status: source.status,
      matchQuality: source.matchQuality,
      deliveredTotalCents: integerValue(
        source.deliveredTotalCents,
        `Preis der Marktquelle ${index + 1}`,
      ),
      currency: requiredString(source.currency, `Währung der Marktquelle ${index + 1}`, 8),
      saleDate: optionalString(source.saleDate, `Verkaufsdatum der Marktquelle ${index + 1}`, 30),
    };
  });
}

function parseGrading(value: unknown) {
  const grading = objectValue(value, 'Grading-Daten');
  const parsed = {
    ...grading,
    rawValueLowCents: integerValue(grading.rawValueLowCents, 'Raw Untergrenze', {
      nullable: false,
    })!,
    rawValueHighCents: integerValue(grading.rawValueHighCents, 'Raw Obergrenze', {
      nullable: false,
    })!,
    psa9ValueLowCents: integerValue(grading.psa9ValueLowCents, 'PSA 9 Untergrenze', {
      nullable: false,
    })!,
    psa9ValueHighCents: integerValue(grading.psa9ValueHighCents, 'PSA 9 Obergrenze', {
      nullable: false,
    })!,
    psa10ValueLowCents: integerValue(grading.psa10ValueLowCents, 'PSA 10 Untergrenze', {
      nullable: false,
    })!,
    psa10ValueHighCents: integerValue(grading.psa10ValueHighCents, 'PSA 10 Obergrenze', {
      nullable: false,
    })!,
    allInCostCents: integerValue(grading.allInCostCents, 'Grading-Kosten', {
      nullable: false,
    })!,
    psa10ChanceLow: integerValue(grading.psa10ChanceLow, 'PSA-10-Chance Untergrenze', {
      nullable: false,
      max: 100,
    })!,
    psa10ChanceHigh: integerValue(grading.psa10ChanceHigh, 'PSA-10-Chance Obergrenze', {
      nullable: false,
      max: 100,
    })!,
    expectedValueCents: integerValue(grading.expectedValueCents, 'Erwartungswert', {
      nullable: false,
      min: -100_000_000,
    })!,
    assessment: requiredString(grading.assessment, 'Grading-Einschätzung', 3_000),
  };

  const orderedRanges = [
    [parsed.rawValueLowCents, parsed.rawValueHighCents],
    [parsed.psa9ValueLowCents, parsed.psa9ValueHighCents],
    [parsed.psa10ValueLowCents, parsed.psa10ValueHighCents],
    [parsed.psa10ChanceLow, parsed.psa10ChanceHigh],
  ];
  if (orderedRanges.some(([low, high]) => low > high)) {
    throw new ValidationError('Eine Grading-Untergrenze liegt über ihrer Obergrenze.');
  }
  return parsed;
}

function parseAnalysis(value: unknown): AnalysisInput {
  const input = objectValue(value, 'Analyse');
  const recommendation = input.recommendation;
  const confidence = input.confidence;
  if (typeof recommendation !== 'string' || !RECOMMENDATIONS.has(recommendation)) {
    throw new ValidationError('Empfehlung ist ungültig.');
  }
  if (typeof confidence !== 'string' || !CONFIDENCE_LEVELS.has(confidence)) {
    throw new ValidationError('Confidence ist ungültig.');
  }
  if (input.rookie !== null && input.rookie !== undefined && typeof input.rookie !== 'boolean') {
    throw new ValidationError('Rookie-Wert ist ungültig.');
  }
  if (typeof input.needsReview !== 'boolean') {
    throw new ValidationError('needsReview fehlt oder ist ungültig.');
  }

  const marketSources = parseSources(input.marketSources);
  const parsed: AnalysisInput = {
    ...input,
    player: optionalString(input.player, 'Spieler'),
    year: integerValue(input.year, 'Jahr', { max: 2100 }),
    brand: optionalString(input.brand, 'Marke'),
    setName: optionalString(input.setName, 'Set'),
    cardNumber: optionalString(input.cardNumber, 'Kartennummer'),
    parallel: optionalString(input.parallel, 'Parallel'),
    team: optionalString(input.team, 'Team'),
    rookie: input.rookie === undefined ? null : (input.rookie as boolean | null),
    serialNumber: optionalString(input.serialNumber, 'Seriennummer'),
    recommendation: recommendation as AnalysisInput['recommendation'],
    marketLowCents: integerValue(input.marketLowCents, 'Unterer Marktwert'),
    marketHighCents: integerValue(input.marketHighCents, 'Oberer Marktwert'),
    marketCheckedAt: requiredString(input.marketCheckedAt, 'Markt-Prüfdatum', 40),
    marketSources,
    soldCompCount: marketSources.filter((source) => source.status === 'sold').length,
    confidence: confidence as AnalysisInput['confidence'],
    conditionNotes: requiredString(input.conditionNotes, 'Zustand', 4_000),
    rationale: requiredString(input.rationale, 'Begründung', 4_000),
    needsReview: input.needsReview,
  };

  if (!parsed.player && !parsed.needsReview) {
    throw new ValidationError('Unbekannte Spieler-Identität muss needsReview=true setzen.');
  }
  if (
    parsed.marketLowCents !== null &&
    parsed.marketHighCents !== null &&
    parsed.marketLowCents > parsed.marketHighCents
  ) {
    throw new ValidationError('Der untere Marktwert liegt über dem oberen.');
  }
  if (
    (parsed.marketLowCents !== null || parsed.marketHighCents !== null) &&
    parsed.soldCompCount === 0
  ) {
    throw new ValidationError('Marktwerte brauchen mindestens eine verkaufte Vergleichskarte.');
  }
  if (parsed.recommendation === 'Grade') parsed.grading = parseGrading(input.grading);
  if (JSON.stringify(parsed).length > 250_000) throw new ValidationError('Analyse ist zu groß.');
  return parsed;
}

export async function PUT(request: Request, context: RouteContext) {
  try {
    const db = getD1();
    const { id } = await context.params;
    const body = (await request.json()) as { analysis?: unknown };
    const analysis = parseAnalysis(body.analysis);
    const now = new Date().toISOString();

    const result = await db.prepare(
      `UPDATE cards SET
        status = 'analyzed', updated_at = ?, analyzed_at = ?, player = ?, year = ?,
        brand = ?, set_name = ?, card_number = ?, parallel = ?, team = ?, rookie = ?,
        serial_number = ?, recommendation = ?, market_low_cents = ?, market_high_cents = ?,
        market_checked_at = ?, sold_comp_count = ?, confidence = ?, condition_notes = ?,
        rationale = ?, needs_review = ?, analysis_json = ?, error_message = NULL
      WHERE id = ? AND status = 'pending'`,
    )
      .bind(
        now,
        now,
        analysis.player,
        analysis.year,
        analysis.brand,
        analysis.setName,
        analysis.cardNumber,
        analysis.parallel,
        analysis.team,
        analysis.rookie === null ? null : Number(analysis.rookie),
        analysis.serialNumber,
        analysis.recommendation,
        analysis.marketLowCents,
        analysis.marketHighCents,
        analysis.marketCheckedAt,
        analysis.soldCompCount,
        analysis.confidence,
        analysis.conditionNotes,
        analysis.rationale,
        Number(analysis.needsReview),
        JSON.stringify(analysis),
        id,
      )
      .run();

    if ((result.meta.changes ?? 0) === 0) {
      const existing = await db.prepare('SELECT status FROM cards WHERE id = ?')
        .bind(id)
        .first<{ status: string }>();
      if (!existing) return Response.json({ error: 'Karte nicht gefunden.' }, { status: 404 });
      return Response.json(
        { error: `Karte ist bereits im Status ${existing.status}.` },
        { status: 409 },
      );
    }

    return Response.json({ id, status: 'analyzed', updatedAt: now });
  } catch (error) {
    if (error instanceof ValidationError || error instanceof SyntaxError) {
      return Response.json({ error: error.message }, { status: 400 });
    }
    console.error(error);
    return Response.json({ error: 'Analyse konnte nicht gespeichert werden.' }, { status: 500 });
  }
}
