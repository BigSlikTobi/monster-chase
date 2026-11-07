export type HotBrandFamily = 'donruss' | 'select' | 'prizm' | 'topps';
export type LicenseScope = 'nfl' | 'nflpa' | 'nfl_and_nflpa';
export type MatchQuality = 'exact' | 'near' | 'proxy';

export type HotSaleEvidence = {
  url: string;
  title: string;
  saleDate: string;
  deliveredTotalCents: number;
  currency: string;
  matchQuality: MatchQuality;
};

export type HotBoard = {
  id: string;
  windowStart: string;
  windowEnd: string;
  methodology: string;
  coverageNote: string | null;
  researchedAt: string;
  createdAt: string;
  updatedAt: string;
};

export type HotCard = {
  id: string;
  boardId: string;
  rank: number;
  brandFamily: HotBrandFamily;
  productName: string;
  year: number | null;
  format: string | null;
  licenseScope: LicenseScope;
  licenseSourceUrl: string;
  licenseCheckedAt: string;
  label: string;
  player: string | null;
  team: string | null;
  cardNumber: string | null;
  parallel: string | null;
  imageUrl: string;
  imageSourceUrl: string;
  whyHot: string;
  soldCompCount: number;
  marketLowCents: number | null;
  medianSoldCents: number | null;
  marketHighCents: number | null;
  currency: string;
  momentumBps: number | null;
  lastSaleAt: string | null;
  evidence: HotSaleEvidence[];
  createdAt: string;
  updatedAt: string;
};

export type HotBoardResponse = {
  board: HotBoard | null;
  cards: HotCard[];
};
