// Read-only release check. Pass two CardScout app-data backups, never credentials.
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';

const [beforeRoot, afterRoot] = process.argv.slice(2);
if (!beforeRoot || !afterRoot) {
  throw new Error('Usage: node scripts/verify_collection_preservation.mjs <before> <after>');
}
const before = JSON.parse(readFileSync(join(beforeRoot, 'library.json'), 'utf8'));
const after = JSON.parse(readFileSync(join(afterRoot, 'library.json'), 'utf8'));
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]));
  }
  return value;
}
function same(a, b) { return JSON.stringify(canonical(a)) === JSON.stringify(canonical(b)); }
const hash = file => createHash('sha256').update(readFileSync(file)).digest('hex');
const beforeNames = readdirSync(join(beforeRoot, 'photos')).filter(name => !name.startsWith('.')).sort();
const afterNames = readdirSync(join(afterRoot, 'photos')).filter(name => !name.startsWith('.')).sort();
const changedPhotos = beforeNames.filter(name => !afterNames.includes(name) || hash(join(beforeRoot, 'photos', name)) !== hash(join(afterRoot, 'photos', name)));
const photoReferences = after.cards.flatMap(card => [card.frontFile, card.backFile].filter(Boolean));
const report = {
  cards: after.cards.length,
  collections: after.collections.length,
  hunts: after.hunts.length,
  ownedCardsAndAnalysesUnchanged: same(before.cards, after.cards),
  collectionsUnchanged: same(before.collections, after.collections),
  huntsUnchanged: same(before.hunts, after.hunts),
  filtersUnchanged: same(before.chaseFilters, after.chaseFilters),
  originalPhotos: beforeNames.length,
  changedOrMissingPhotos: changedPhotos.length,
  referencedPhotosPresent: photoReferences.every(name => afterNames.includes(name)),
};
console.log(JSON.stringify(report, null, 2));
if (!report.ownedCardsAndAnalysesUnchanged || !report.collectionsUnchanged || !report.huntsUnchanged || changedPhotos.length || !report.referencedPhotosPresent) process.exitCode = 1;
