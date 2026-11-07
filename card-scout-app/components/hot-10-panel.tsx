'use client';

import { useMemo, useState } from 'react';
import {
  ArrowUpRight,
  CalendarDays,
  Crosshair,
  Flame,
  ImageOff,
  LoaderCircle,
  ShieldCheck,
  TrendingUp,
} from 'lucide-react';

import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import type {
  HotBoard,
  HotBrandFamily,
  HotCard,
  LicenseScope,
} from '@/lib/hot-10-types';

const brandLabel: Record<HotBrandFamily, string> = {
  donruss: 'Donruss',
  select: 'Select',
  prizm: 'Prizm',
  topps: 'Topps',
};

const licenseLabel: Record<LicenseScope, string> = {
  nfl: 'NFL',
  nflpa: 'NFLPA',
  nfl_and_nflpa: 'NFL + NFLPA',
};

function money(cents: number | null, currency: string) {
  if (cents === null) return '–';
  try {
    return new Intl.NumberFormat('de-DE', {
      style: 'currency',
      currency,
      maximumFractionDigits: 0,
    }).format(cents / 100);
  } catch {
    return `${(cents / 100).toLocaleString('de-DE')} ${currency}`;
  }
}

function productKey(card: HotCard) {
  return `${card.year ?? '–'}|${card.productName}`;
}

function productLabel(card: HotCard) {
  const year = card.year?.toString();
  return year && !card.productName.startsWith(year)
    ? `${year} ${card.productName}`
    : card.productName;
}

function HotCardImage({ card }: { card: HotCard }) {
  const [failed, setFailed] = useState(false);

  if (failed) {
    return (
      <div className="grid h-full place-items-center bg-[radial-gradient(circle_at_center,rgba(239,68,68,.12),transparent_65%)] text-center text-zinc-600">
        <span>
          <ImageOff className="mx-auto mb-2 size-7" />
          Bildquelle öffnen
        </span>
      </div>
    );
  }

  return (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src={card.imageUrl}
      alt={`${card.label}${card.player ? ` von ${card.player}` : ''}`}
      loading="lazy"
      onError={() => setFailed(true)}
      className="h-full w-full object-contain p-5 transition duration-300 group-hover:scale-[1.025]"
    />
  );
}

export function Hot10Panel({
  board,
  cards,
  loading,
  addingId,
  onAddToLookout,
}: {
  board: HotBoard | null;
  cards: HotCard[];
  loading: boolean;
  addingId: string | null;
  onAddToLookout: (card: HotCard) => Promise<void>;
}) {
  const [brand, setBrand] = useState<'all' | HotBrandFamily>('all');
  const [product, setProduct] = useState('all');

  const products = useMemo(() => {
    const visible =
      brand === 'all'
        ? cards
        : cards.filter((card) => card.brandFamily === brand);
    return Array.from(
      new Map(visible.map((card) => [productKey(card), card])).entries(),
    ).map(([key, card]) => ({
      key,
      label: productLabel(card),
    }));
  }, [brand, cards]);

  const visibleCards = useMemo(
    () =>
      cards.filter(
        (card) =>
          (brand === 'all' || card.brandFamily === brand) &&
          (product === 'all' || productKey(card) === product),
      ),
    [brand, cards, product],
  );

  function chooseBrand(nextBrand: 'all' | HotBrandFamily) {
    setBrand(nextBrand);
    setProduct('all');
  }

  if (loading) {
    return (
      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        {[0, 1, 2, 3, 4, 5].map((item) => (
          <div
            key={item}
            className="h-[34rem] animate-pulse rounded-xl border border-white/[0.06] bg-white/[0.035]"
          />
        ))}
      </div>
    );
  }

  if (!board || cards.length === 0) {
    return (
      <Card className="min-h-[420px] items-center justify-center border border-white/[0.08] bg-[#0d0f12] text-center ring-0">
        <CardContent className="max-w-lg py-16">
          <span className="mx-auto mb-5 grid size-14 place-items-center rounded-2xl border border-red-400/15 bg-red-400/[0.06]">
            <Flame className="size-6 text-red-400" />
          </span>
          <h2 className="text-lg font-semibold text-white">Keine Hot 10</h2>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-6">
      <Card className="overflow-hidden border border-white/[0.08] bg-[linear-gradient(135deg,#151012,#0d0f12_46%,#101114)] ring-0">
        <CardContent className="space-y-5 p-5">
          <div className="flex flex-wrap items-center justify-between gap-4">
            <div className="flex flex-wrap items-center gap-2">
              <Badge className="border border-red-400/20 bg-red-400/10 text-red-300">
                <Flame /> Hot 10
              </Badge>
              <Badge
                variant="outline"
                className="border-emerald-400/20 text-emerald-300"
              >
                <ShieldCheck /> nur lizenziert
              </Badge>
            </div>
            <span className="flex items-center gap-2 text-sm text-zinc-300">
              <CalendarDays className="size-4 text-red-400" />
              {board.windowStart} – {board.windowEnd}
            </span>
          </div>
          <div className="grid gap-4 md:grid-cols-[minmax(0,1fr)_minmax(260px,.55fr)]">
            <div className="flex flex-wrap gap-2">
              {(['all', 'donruss', 'select', 'prizm', 'topps'] as const).map(
                (key) => (
                  <Button
                    key={key}
                    type="button"
                    size="sm"
                    variant="outline"
                    aria-pressed={brand === key}
                    onClick={() => chooseBrand(key)}
                    className={
                      brand === key
                        ? 'border-red-500/40 bg-red-500/12 text-white hover:bg-red-500/16'
                        : 'border-white/10 bg-white/[0.025] text-zinc-400 hover:text-white'
                    }
                  >
                    {key === 'all' ? 'Alle Marken' : brandLabel[key]}
                  </Button>
                ),
              )}
            </div>

            <Select
              value={product}
              onValueChange={(value) => setProduct(value ?? 'all')}
            >
              <SelectTrigger className="h-9 w-full border-white/10 bg-white/[0.035]">
                <SelectValue placeholder="Alle Produkte" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Alle Produkte</SelectItem>
                {products.map((entry) => (
                  <SelectItem key={entry.key} value={entry.key}>
                    {entry.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </CardContent>
      </Card>

      {visibleCards.length === 0 ? (
        <Card className="border border-white/[0.08] bg-[#0d0f12] ring-0">
          <CardContent className="py-16 text-center text-zinc-500">
            Keine Karten
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {visibleCards.map((card) => (
            <Card
              key={card.id}
              className={`group overflow-hidden border bg-[#0d0f12] py-0 ring-0 ${
                card.rank === 1
                  ? 'border-amber-300/30 shadow-[0_0_42px_rgba(251,191,36,.08)]'
                  : 'border-white/[0.08]'
              }`}
            >
              <div className="relative aspect-[5/5.9] overflow-hidden bg-[radial-gradient(circle_at_50%_20%,rgba(255,255,255,.08),transparent_58%),#08090b]">
                <HotCardImage key={card.imageUrl} card={card} />
                <span
                  className={`absolute left-3 top-3 grid size-10 place-items-center rounded-xl border font-mono text-lg font-bold backdrop-blur ${
                    card.rank === 1
                      ? 'border-amber-300/35 bg-amber-300 text-black'
                      : 'border-white/10 bg-black/70 text-white'
                  }`}
                >
                  {card.rank}
                </span>
                <Badge
                  variant="outline"
                  className="absolute right-3 top-3 border-emerald-300/20 bg-black/70 text-emerald-300 backdrop-blur"
                >
                  {licenseLabel[card.licenseScope]}
                </Badge>
              </div>

              <CardContent className="space-y-4 p-5">
                <div>
                  <p className="text-xs uppercase tracking-wider text-zinc-600">
                    {brandLabel[card.brandFamily]} · {productLabel(card)}
                  </p>
                  <h2 className="mt-1 text-lg font-semibold leading-6 text-white">
                    {card.label}
                  </h2>
                  {(card.parallel || card.cardNumber) && (
                    <p className="mt-1 text-sm text-zinc-400">
                      {[
                        card.parallel,
                        card.cardNumber ? `#${card.cardNumber}` : null,
                      ]
                        .filter(Boolean)
                        .join(' · ')}
                    </p>
                  )}
                </div>

                <div className="grid grid-cols-2 gap-3 border-y border-white/[0.07] py-4">
                  <div>
                    <p className="text-[11px] uppercase tracking-wider text-zinc-600">
                      Median
                    </p>
                    <p className="mt-1 font-mono text-base text-white">
                      {money(card.medianSoldCents, card.currency)}
                    </p>
                  </div>
                  <div>
                    <p className="text-[11px] uppercase tracking-wider text-zinc-600">
                      90-Tage-Spanne
                    </p>
                    <p className="mt-1 font-mono text-sm text-zinc-300">
                      {money(card.marketLowCents, card.currency)} –{' '}
                      {money(card.marketHighCents, card.currency)}
                    </p>
                  </div>
                  <div className="col-span-2 flex flex-wrap items-center gap-3 text-xs text-zinc-500">
                    <span className="inline-flex items-center gap-1.5">
                      <TrendingUp className="size-3.5" /> {card.soldCompCount}{' '}
                      Verkäufe
                    </span>
                    {card.lastSaleAt && <span>zuletzt {card.lastSaleAt}</span>}
                    {card.momentumBps !== null && (
                      <span
                        className={
                          card.momentumBps >= 0
                            ? 'text-emerald-300'
                            : 'text-red-300'
                        }
                      >
                        {card.momentumBps >= 0 ? '+' : ''}
                        {(card.momentumBps / 100).toFixed(1)}%
                      </span>
                    )}
                  </div>
                </div>

                <div className="flex flex-wrap items-center gap-x-4 gap-y-2 text-xs">
                  {card.evidence.slice(0, 2).map((sale, index) => (
                    <a
                      key={`${sale.url}-${index}`}
                      href={sale.url}
                      target="_blank"
                      rel="noreferrer"
                      className="inline-flex items-center gap-1 text-zinc-400 hover:text-white"
                    >
                      Verkauf {index + 1} <ArrowUpRight className="size-3" />
                    </a>
                  ))}
                  <a
                    href={card.imageSourceUrl}
                    target="_blank"
                    rel="noreferrer"
                    className="inline-flex items-center gap-1 text-zinc-500 hover:text-white"
                  >
                    Bildquelle <ArrowUpRight className="size-3" />
                  </a>
                  <a
                    href={card.licenseSourceUrl}
                    target="_blank"
                    rel="noreferrer"
                    className="inline-flex items-center gap-1 text-zinc-500 hover:text-white"
                  >
                    Lizenz <ArrowUpRight className="size-3" />
                  </a>
                </div>

                <Button
                  type="button"
                  variant="outline"
                  disabled={addingId !== null}
                  onClick={() => void onAddToLookout(card)}
                  className="w-full border-white/10 bg-white/[0.025] text-zinc-200 hover:bg-white/[0.06] hover:text-white"
                >
                  {addingId === card.id ? (
                    <LoaderCircle className="animate-spin" />
                  ) : (
                    <Crosshair />
                  )}
                  Zum Lookout
                </Button>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
