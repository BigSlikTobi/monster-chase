import {
  index,
  integer,
  sqliteTable,
  text,
  uniqueIndex,
} from 'drizzle-orm/sqlite-core';

export const cards = sqliteTable(
  'cards',
  {
    id: text('id').primaryKey(),
    status: text('status', { enum: ['pending', 'analyzed', 'failed'] })
      .notNull()
      .default('pending'),
    createdAt: text('created_at').notNull(),
    updatedAt: text('updated_at').notNull(),
    analyzedAt: text('analyzed_at'),

    frontKey: text('front_key').notNull(),
    frontMime: text('front_mime').notNull(),
    frontName: text('front_name').notNull(),
    backKey: text('back_key'),
    backMime: text('back_mime'),
    backName: text('back_name'),

    player: text('player'),
    year: integer('year'),
    brand: text('brand'),
    setName: text('set_name'),
    cardNumber: text('card_number'),
    parallel: text('parallel'),
    team: text('team'),
    rookie: integer('rookie', { mode: 'boolean' }),
    serialNumber: text('serial_number'),

    recommendation: text('recommendation', {
      enum: ['Keep', 'Sell', 'Grade', 'Bulk'],
    }),
    marketLowCents: integer('market_low_cents'),
    marketHighCents: integer('market_high_cents'),
    marketCheckedAt: text('market_checked_at'),
    soldCompCount: integer('sold_comp_count'),
    confidence: text('confidence', { enum: ['low', 'medium', 'high'] }),
    conditionNotes: text('condition_notes'),
    rationale: text('rationale'),
    needsReview: integer('needs_review', { mode: 'boolean' })
      .notNull()
      .default(true),
    analysisJson: text('analysis_json'),
    errorMessage: text('error_message'),
  },
  (table) => [
    index('cards_status_created_idx').on(table.status, table.createdAt),
  ],
);

export type Card = typeof cards.$inferSelect;
export type NewCard = typeof cards.$inferInsert;

export const huntProducts = sqliteTable(
  'hunt_products',
  {
    id: text('id').primaryKey(),
    normalizedKey: text('normalized_key').notNull(),
    name: text('name').notNull(),
    year: integer('year'),
    brand: text('brand'),
    format: text('format'),
    checklistSourceUrl: text('checklist_source_url'),
    sourceCheckedAt: text('source_checked_at'),
    createdAt: text('created_at').notNull(),
    updatedAt: text('updated_at').notNull(),
  },
  (table) => [
    uniqueIndex('hunt_products_normalized_key_unique').on(table.normalizedKey),
  ],
);

export const huntTargets = sqliteTable(
  'hunt_targets',
  {
    id: text('id').primaryKey(),
    productId: text('product_id')
      .notNull()
      .references(() => huntProducts.id, { onDelete: 'cascade' }),
    normalizedKey: text('normalized_key').notNull(),
    label: text('label').notNull(),
    player: text('player'),
    cardNumber: text('card_number'),
    parallel: text('parallel'),
    whySpecial: text('why_special'),
    priority: text('priority', { enum: ['grail', 'high', 'medium', 'low'] })
      .notNull()
      .default('medium'),
    status: text('status', { enum: ['hunting', 'found', 'passed'] })
      .notNull()
      .default('hunting'),
    sourceUrl: text('source_url'),
    notes: text('notes'),
    foundAt: text('found_at'),
    createdAt: text('created_at').notNull(),
    updatedAt: text('updated_at').notNull(),
  },
  (table) => [
    uniqueIndex('hunt_targets_product_key_unique').on(
      table.productId,
      table.normalizedKey,
    ),
    index('hunt_targets_product_status_priority_idx').on(
      table.productId,
      table.status,
      table.priority,
    ),
  ],
);

export type HuntProduct = typeof huntProducts.$inferSelect;
export type NewHuntProduct = typeof huntProducts.$inferInsert;
export type HuntTarget = typeof huntTargets.$inferSelect;
export type NewHuntTarget = typeof huntTargets.$inferInsert;

export const hotBoards = sqliteTable('hot_boards', {
  id: text('id').primaryKey(),
  windowStart: text('window_start').notNull(),
  windowEnd: text('window_end').notNull(),
  methodology: text('methodology').notNull(),
  coverageNote: text('coverage_note'),
  researchedAt: text('researched_at').notNull(),
  createdAt: text('created_at').notNull(),
  updatedAt: text('updated_at').notNull(),
});

export const hotCards = sqliteTable(
  'hot_cards',
  {
    id: text('id').primaryKey(),
    boardId: text('board_id')
      .notNull()
      .references(() => hotBoards.id, { onDelete: 'cascade' }),
    rank: integer('rank').notNull(),
    normalizedKey: text('normalized_key').notNull(),
    brandFamily: text('brand_family', {
      enum: ['donruss', 'select', 'prizm', 'topps'],
    }).notNull(),
    productName: text('product_name').notNull(),
    year: integer('year'),
    format: text('format'),
    licenseScope: text('license_scope', {
      enum: ['nfl', 'nflpa', 'nfl_and_nflpa'],
    }).notNull(),
    licenseSourceUrl: text('license_source_url').notNull(),
    licenseCheckedAt: text('license_checked_at').notNull(),
    label: text('label').notNull(),
    player: text('player'),
    team: text('team'),
    cardNumber: text('card_number'),
    parallel: text('parallel'),
    imageUrl: text('image_url').notNull(),
    imageSourceUrl: text('image_source_url').notNull(),
    whyHot: text('why_hot').notNull(),
    soldCompCount: integer('sold_comp_count').notNull(),
    marketLowCents: integer('market_low_cents'),
    medianSoldCents: integer('median_sold_cents'),
    marketHighCents: integer('market_high_cents'),
    currency: text('currency').notNull(),
    momentumBps: integer('momentum_bps'),
    lastSaleAt: text('last_sale_at'),
    evidenceJson: text('evidence_json').notNull(),
    createdAt: text('created_at').notNull(),
    updatedAt: text('updated_at').notNull(),
  },
  (table) => [
    uniqueIndex('hot_cards_board_rank_unique').on(table.boardId, table.rank),
    uniqueIndex('hot_cards_board_key_unique').on(
      table.boardId,
      table.normalizedKey,
    ),
    index('hot_cards_brand_rank_idx').on(table.brandFamily, table.rank),
  ],
);

export type HotBoard = typeof hotBoards.$inferSelect;
export type NewHotBoard = typeof hotBoards.$inferInsert;
export type HotCard = typeof hotCards.$inferSelect;
export type NewHotCard = typeof hotCards.$inferInsert;
