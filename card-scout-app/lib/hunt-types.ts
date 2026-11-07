export type HuntPriority = 'grail' | 'high' | 'medium' | 'low';
export type HuntStatus = 'hunting' | 'found' | 'passed';

export type HuntTarget = {
  id: string;
  productId: string;
  label: string;
  player: string | null;
  cardNumber: string | null;
  parallel: string | null;
  whySpecial: string | null;
  priority: HuntPriority;
  status: HuntStatus;
  sourceUrl: string | null;
  notes: string | null;
  foundAt: string | null;
  createdAt: string;
  updatedAt: string;
};

export type HuntProduct = {
  id: string;
  name: string;
  year: number | null;
  brand: string | null;
  format: string | null;
  checklistSourceUrl: string | null;
  sourceCheckedAt: string | null;
  createdAt: string;
  updatedAt: string;
  counts: { total: number; hunting: number; found: number };
  targets: HuntTarget[];
};

export type NewHuntTargetInput = {
  boxName: string;
  format: string;
  label: string;
  parallel: string;
  whySpecial: string;
  priority: HuntPriority;
};
