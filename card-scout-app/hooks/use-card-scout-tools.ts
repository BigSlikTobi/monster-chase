'use client';

import { useEffect, useState } from 'react';

type ToolDefinition = {
  name: string;
  title: string;
  description: string;
  inputSchema: Record<string, unknown>;
  annotations: { readOnlyHint: boolean; untrustedContentHint: boolean };
  execute: (input: unknown) => unknown;
};

type ModelContext = {
  registerTool: (
    tool: ToolDefinition,
    options?: { signal?: AbortSignal },
  ) => void | Promise<void>;
};

function asObject(input: unknown) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    throw new Error('Input must be an object.');
  }
  return input as Record<string, unknown>;
}

async function readJson(response: Response) {
  const payload = (await response.json()) as Record<string, unknown>;
  if (!response.ok) {
    throw new Error(
      typeof payload.error === 'string' ? payload.error : 'Request failed.',
    );
  }
  return payload;
}

export function useCardScoutTools(
  onCollectionChanged: () => Promise<void>,
  onLookoutChanged: () => Promise<void>,
  onHotBoardChanged: () => Promise<void>,
) {
  const [available, setAvailable] = useState(false);

  useEffect(() => {
    const context = (document as Document & { modelContext?: ModelContext })
      .modelContext;
    if (!context?.registerTool) return;

    const lifecycle = new AbortController();
    const registrations = [
      context.registerTool(
        {
          name: 'read_pending_card_queue',
          title: 'Read pending NFL cards',
          description:
            'Return uploaded NFL cards that still need Codex vision identification, sold-market research, condition triage, and one Keep, Sell, Grade, or Bulk recommendation.',
          inputSchema: {
            type: 'object',
            properties: {
              limit: { type: 'integer', minimum: 1, maximum: 25, default: 10 },
            },
            additionalProperties: false,
          },
          annotations: { readOnlyHint: true, untrustedContentHint: true },
          async execute(input) {
            const data = asObject(input);
            const limit = data.limit === undefined ? 10 : data.limit;
            if (
              typeof limit !== 'number' ||
              !Number.isInteger(limit) ||
              limit < 1 ||
              limit > 25
            ) {
              throw new Error('limit must be an integer from 1 to 25.');
            }
            const response = await fetch(
              `/api/cards?status=pending&limit=${limit}`,
              {
                cache: 'no-store',
              },
            );
            return readJson(response);
          },
        },
        { signal: lifecycle.signal },
      ),
      context.registerTool(
        {
          name: 'complete_card_analysis',
          title: 'Complete NFL card analysis',
          description:
            'Save a completed NFL card analysis and move the uploaded card from pending to analyzed. Use the nfl-card-scout workflow, inspect both available images, and research current sold-market evidence before calling.',
          inputSchema: {
            type: 'object',
            properties: {
              cardId: { type: 'string', minLength: 1 },
              analysis: {
                type: 'object',
                properties: {
                  player: { type: ['string', 'null'], minLength: 1 },
                  year: {
                    type: ['integer', 'null'],
                    minimum: 0,
                    maximum: 2100,
                  },
                  brand: { type: ['string', 'null'] },
                  setName: { type: ['string', 'null'] },
                  cardNumber: { type: ['string', 'null'] },
                  parallel: { type: ['string', 'null'] },
                  team: { type: ['string', 'null'] },
                  rookie: { type: ['boolean', 'null'] },
                  serialNumber: { type: ['string', 'null'] },
                  recommendation: { enum: ['Keep', 'Sell', 'Grade', 'Bulk'] },
                  marketLowCents: { type: ['integer', 'null'], minimum: 0 },
                  marketHighCents: { type: ['integer', 'null'], minimum: 0 },
                  marketCheckedAt: { type: 'string', minLength: 1 },
                  marketSources: {
                    type: 'array',
                    maxItems: 100,
                    items: {
                      type: 'object',
                      properties: {
                        url: { type: 'string', minLength: 1 },
                        title: { type: 'string', minLength: 1 },
                        status: { enum: ['sold', 'ask'] },
                        matchQuality: { enum: ['exact', 'near', 'proxy'] },
                        deliveredTotalCents: {
                          type: ['integer', 'null'],
                          minimum: 0,
                        },
                        currency: {
                          type: 'string',
                          minLength: 3,
                          maxLength: 8,
                        },
                        saleDate: { type: ['string', 'null'] },
                      },
                      required: [
                        'url',
                        'title',
                        'status',
                        'matchQuality',
                        'deliveredTotalCents',
                        'currency',
                        'saleDate',
                      ],
                      additionalProperties: true,
                    },
                  },
                  confidence: { enum: ['low', 'medium', 'high'] },
                  conditionNotes: { type: 'string', minLength: 1 },
                  rationale: { type: 'string', minLength: 1 },
                  needsReview: { type: 'boolean' },
                  grading: {
                    type: 'object',
                    description: 'Required when recommendation is Grade.',
                    properties: {
                      rawValueLowCents: { type: 'integer', minimum: 0 },
                      rawValueHighCents: { type: 'integer', minimum: 0 },
                      psa9ValueLowCents: { type: 'integer', minimum: 0 },
                      psa9ValueHighCents: { type: 'integer', minimum: 0 },
                      psa10ValueLowCents: { type: 'integer', minimum: 0 },
                      psa10ValueHighCents: { type: 'integer', minimum: 0 },
                      allInCostCents: { type: 'integer', minimum: 0 },
                      psa10ChanceLow: {
                        type: 'integer',
                        minimum: 0,
                        maximum: 100,
                      },
                      psa10ChanceHigh: {
                        type: 'integer',
                        minimum: 0,
                        maximum: 100,
                      },
                      expectedValueCents: { type: 'integer' },
                      assessment: { type: 'string', minLength: 1 },
                    },
                    additionalProperties: true,
                  },
                },
                required: [
                  'player',
                  'recommendation',
                  'marketCheckedAt',
                  'marketSources',
                  'confidence',
                  'conditionNotes',
                  'rationale',
                  'needsReview',
                ],
                additionalProperties: true,
              },
            },
            required: ['cardId', 'analysis'],
            additionalProperties: false,
          },
          annotations: { readOnlyHint: false, untrustedContentHint: true },
          async execute(input) {
            const data = asObject(input);
            if (typeof data.cardId !== 'string' || !data.cardId.trim()) {
              throw new Error('cardId must be a non-empty string.');
            }
            asObject(data.analysis);
            const response = await fetch(
              `/api/cards/${encodeURIComponent(data.cardId)}/analysis`,
              {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ analysis: data.analysis }),
              },
            );
            const result = await readJson(response);
            await onCollectionChanged();
            return result;
          },
        },
        { signal: lifecycle.signal },
      ),
      context.registerTool(
        {
          name: 'read_card_lookout',
          title: 'Read NFL card lookout',
          description:
            'Return NFL chase cards grouped by exact box or product format. Use this before adding or changing hunt targets so existing entries are not duplicated.',
          inputSchema: {
            type: 'object',
            properties: {
              status: {
                enum: ['hunting', 'found', 'passed'],
                default: 'hunting',
              },
            },
            additionalProperties: false,
          },
          annotations: { readOnlyHint: true, untrustedContentHint: true },
          async execute(input) {
            const data = asObject(input);
            const status = data.status ?? 'hunting';
            if (
              typeof status !== 'string' ||
              !['hunting', 'found', 'passed'].includes(status)
            ) {
              throw new Error('status must be hunting, found, or passed.');
            }
            const response = await fetch(
              `/api/hunts?status=${encodeURIComponent(status)}`,
              {
                cache: 'no-store',
              },
            );
            return readJson(response);
          },
        },
        { signal: lifecycle.signal },
      ),
      context.registerTool(
        {
          name: 'add_card_hunts',
          title: 'Add NFL chase cards',
          description:
            'Create or extend one box-specific NFL chase list in a batch. Verify the exact year, brand, and box format against an authoritative checklist first; preserve the source URL and check date.',
          inputSchema: {
            type: 'object',
            properties: {
              product: {
                type: 'object',
                properties: {
                  name: { type: 'string', minLength: 1 },
                  year: {
                    type: ['integer', 'null'],
                    minimum: 1900,
                    maximum: 2100,
                  },
                  brand: { type: ['string', 'null'] },
                  format: { type: 'string', minLength: 1 },
                  checklistSourceUrl: { type: 'string', minLength: 1 },
                  sourceCheckedAt: { type: 'string', minLength: 1 },
                },
                required: [
                  'name',
                  'format',
                  'checklistSourceUrl',
                  'sourceCheckedAt',
                ],
                additionalProperties: false,
              },
              targets: {
                type: 'array',
                minItems: 1,
                maxItems: 50,
                items: {
                  type: 'object',
                  properties: {
                    label: { type: 'string', minLength: 1 },
                    player: { type: ['string', 'null'] },
                    cardNumber: { type: ['string', 'null'] },
                    parallel: { type: ['string', 'null'] },
                    whySpecial: { type: 'string', minLength: 1 },
                    priority: { enum: ['grail', 'high', 'medium', 'low'] },
                    sourceUrl: { type: 'string', minLength: 1 },
                    notes: { type: ['string', 'null'] },
                  },
                  required: ['label', 'whySpecial', 'priority', 'sourceUrl'],
                  additionalProperties: false,
                },
              },
            },
            required: ['product', 'targets'],
            additionalProperties: false,
          },
          annotations: { readOnlyHint: false, untrustedContentHint: true },
          async execute(input) {
            const data = asObject(input);
            asObject(data.product);
            if (!Array.isArray(data.targets) || data.targets.length < 1) {
              throw new Error('targets must contain at least one chase card.');
            }
            const response = await fetch('/api/hunts', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                product: data.product,
                targets: data.targets,
              }),
            });
            const result = await readJson(response);
            await onLookoutChanged();
            return result;
          },
        },
        { signal: lifecycle.signal },
      ),
      context.registerTool(
        {
          name: 'update_card_hunt',
          title: 'Update NFL chase card',
          description:
            'Update the priority and status of one existing NFL chase card. Use found only when the user confirms that exact card was pulled or acquired.',
          inputSchema: {
            type: 'object',
            properties: {
              targetId: { type: 'string', minLength: 1 },
              status: { enum: ['hunting', 'found', 'passed'] },
              priority: { enum: ['grail', 'high', 'medium', 'low'] },
            },
            required: ['targetId', 'status', 'priority'],
            additionalProperties: false,
          },
          annotations: { readOnlyHint: false, untrustedContentHint: true },
          async execute(input) {
            const data = asObject(input);
            if (typeof data.targetId !== 'string' || !data.targetId.trim()) {
              throw new Error('targetId must be a non-empty string.');
            }
            if (!['hunting', 'found', 'passed'].includes(String(data.status))) {
              throw new Error('status must be hunting, found, or passed.');
            }
            if (
              !['grail', 'high', 'medium', 'low'].includes(
                String(data.priority),
              )
            ) {
              throw new Error('priority must be grail, high, medium, or low.');
            }
            const response = await fetch(
              `/api/hunts/${encodeURIComponent(data.targetId)}`,
              {
                method: 'PATCH',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                  status: data.status,
                  priority: data.priority,
                }),
              },
            );
            const result = await readJson(response);
            await onLookoutChanged();
            return result;
          },
        },
        { signal: lifecycle.signal },
      ),
      context.registerTool(
        {
          name: 'read_hot_card_board',
          title: 'Read NFL Hot 10',
          description:
            'Return the current rolling NFL card Hot 10 with its market window, licensing evidence, exact card images, and sold-market evidence. Optionally filter to Donruss, Select, Prizm, or Topps.',
          inputSchema: {
            type: 'object',
            properties: {
              brand: {
                enum: ['donruss', 'select', 'prizm', 'topps'],
              },
            },
            additionalProperties: false,
          },
          annotations: { readOnlyHint: true, untrustedContentHint: true },
          async execute(input) {
            const data = asObject(input);
            const brand =
              typeof data.brand === 'string' ? data.brand : undefined;
            if (
              data.brand !== undefined &&
              (brand === undefined ||
                !['donruss', 'select', 'prizm', 'topps'].includes(brand))
            ) {
              throw new Error(
                'brand must be donruss, select, prizm, or topps.',
              );
            }
            const query = brand ? `?brand=${encodeURIComponent(brand)}` : '';
            const response = await fetch(`/api/hot-10${query}`, {
              cache: 'no-store',
            });
            return readJson(response);
          },
        },
        { signal: lifecycle.signal },
      ),
      context.registerTool(
        {
          name: 'publish_hot_card_board',
          title: 'Publish NFL Hot 10',
          description:
            'Replace the current NFL card Hot 10 with 1 to 10 researched cards. Use only products whose exact year and product have NFL or NFLPA licensing evidence. Rank from sold transactions inside the stated roughly 90-day window, never asking prices; keep grades and variants exact, preserve the latest sale as evidence, use real HTTPS card images with source pages, and explain partial coverage instead of inventing filler.',
          inputSchema: {
            type: 'object',
            properties: {
              board: {
                type: 'object',
                properties: {
                  windowStart: { type: 'string', minLength: 10 },
                  windowEnd: { type: 'string', minLength: 10 },
                  methodology: { type: 'string', minLength: 1 },
                  coverageNote: { type: ['string', 'null'] },
                  researchedAt: { type: 'string', minLength: 10 },
                },
                required: [
                  'windowStart',
                  'windowEnd',
                  'methodology',
                  'coverageNote',
                  'researchedAt',
                ],
                additionalProperties: false,
              },
              cards: {
                type: 'array',
                minItems: 1,
                maxItems: 10,
                items: {
                  type: 'object',
                  properties: {
                    rank: { type: 'integer', minimum: 1, maximum: 10 },
                    brandFamily: {
                      enum: ['donruss', 'select', 'prizm', 'topps'],
                    },
                    productName: { type: 'string', minLength: 1 },
                    year: {
                      type: ['integer', 'null'],
                      minimum: 1900,
                      maximum: 2100,
                    },
                    format: {
                      type: ['string', 'null'],
                      description:
                        'Optional box or product format such as Hobby; never use a grade or Raw here.',
                    },
                    licenseScope: {
                      enum: ['nfl', 'nflpa', 'nfl_and_nflpa'],
                    },
                    licenseSourceUrl: { type: 'string', minLength: 1 },
                    licenseCheckedAt: { type: 'string', minLength: 10 },
                    label: { type: 'string', minLength: 1 },
                    player: { type: ['string', 'null'] },
                    team: { type: ['string', 'null'] },
                    cardNumber: { type: ['string', 'null'] },
                    parallel: { type: ['string', 'null'] },
                    imageUrl: { type: 'string', minLength: 1 },
                    imageSourceUrl: { type: 'string', minLength: 1 },
                    whyHot: { type: 'string', minLength: 1 },
                    soldCompCount: { type: 'integer', minimum: 1 },
                    marketLowCents: {
                      type: ['integer', 'null'],
                      minimum: 0,
                    },
                    medianSoldCents: {
                      type: ['integer', 'null'],
                      minimum: 0,
                    },
                    marketHighCents: {
                      type: ['integer', 'null'],
                      minimum: 0,
                    },
                    currency: { type: 'string', minLength: 3, maxLength: 8 },
                    momentumBps: { type: ['integer', 'null'] },
                    lastSaleAt: { type: ['string', 'null'] },
                    evidence: {
                      type: 'array',
                      minItems: 1,
                      maxItems: 20,
                      items: {
                        type: 'object',
                        properties: {
                          url: { type: 'string', minLength: 1 },
                          title: { type: 'string', minLength: 1 },
                          saleDate: { type: 'string', minLength: 10 },
                          deliveredTotalCents: {
                            type: 'integer',
                            minimum: 0,
                          },
                          currency: {
                            type: 'string',
                            minLength: 3,
                            maxLength: 8,
                          },
                          matchQuality: {
                            enum: ['exact', 'near', 'proxy'],
                          },
                        },
                        required: [
                          'url',
                          'title',
                          'saleDate',
                          'deliveredTotalCents',
                          'currency',
                          'matchQuality',
                        ],
                        additionalProperties: false,
                      },
                    },
                  },
                  required: [
                    'rank',
                    'brandFamily',
                    'productName',
                    'year',
                    'format',
                    'licenseScope',
                    'licenseSourceUrl',
                    'licenseCheckedAt',
                    'label',
                    'player',
                    'team',
                    'cardNumber',
                    'parallel',
                    'imageUrl',
                    'imageSourceUrl',
                    'whyHot',
                    'soldCompCount',
                    'marketLowCents',
                    'medianSoldCents',
                    'marketHighCents',
                    'currency',
                    'momentumBps',
                    'lastSaleAt',
                    'evidence',
                  ],
                  additionalProperties: false,
                },
              },
            },
            required: ['board', 'cards'],
            additionalProperties: false,
          },
          annotations: { readOnlyHint: false, untrustedContentHint: true },
          async execute(input) {
            const data = asObject(input);
            asObject(data.board);
            if (
              !Array.isArray(data.cards) ||
              data.cards.length < 1 ||
              data.cards.length > 10
            ) {
              throw new Error('cards must contain 1 to 10 researched cards.');
            }
            const response = await fetch('/api/hot-10', {
              method: 'PUT',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ board: data.board, cards: data.cards }),
            });
            const result = await readJson(response);
            await onHotBoardChanged();
            return result;
          },
        },
        { signal: lifecycle.signal },
      ),
    ];

    Promise.all(
      registrations.map((registration) => Promise.resolve(registration)),
    )
      .then(() => setAvailable(true))
      .catch((error) => {
        setAvailable(false);
        console.error('WebMCP registration failed', error);
      });

    return () => {
      lifecycle.abort();
      setAvailable(false);
    };
  }, [onCollectionChanged, onHotBoardChanged, onLookoutChanged]);

  return available;
}
