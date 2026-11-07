'use client';

import { ChangeEvent, useCallback, useEffect, useMemo, useState } from 'react';
import {
  AlertCircle,
  Camera,
  Check,
  Clock3,
  Crosshair,
  Flame,
  Images,
  LoaderCircle,
  ShieldCheck,
  Upload,
} from 'lucide-react';

import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Hot10Panel } from '@/components/hot-10-panel';
import { LookoutPanel } from '@/components/lookout-panel';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { useCardScoutTools } from '@/hooks/use-card-scout-tools';
import type { CardRecord } from '@/lib/card-types';
import type { HotBoard, HotCard } from '@/lib/hot-10-types';
import type {
  HuntPriority,
  HuntProduct,
  HuntStatus,
  NewHuntTargetInput,
} from '@/lib/hunt-types';

type ImageSide = 'front' | 'back';

const recommendationStyle: Record<string, string> = {
  Keep: 'border-sky-400/20 bg-sky-400/10 text-sky-300',
  Sell: 'border-amber-400/20 bg-amber-400/10 text-amber-300',
  Grade: 'border-violet-400/20 bg-violet-400/10 text-violet-300',
  Bulk: 'border-zinc-400/20 bg-zinc-400/10 text-zinc-300',
};

function euro(cents: number) {
  return new Intl.NumberFormat('de-DE', {
    style: 'currency',
    currency: 'EUR',
    maximumFractionDigits: cents % 100 === 0 ? 0 : 2,
  }).format(cents / 100);
}

function marketRange(card: CardRecord) {
  if (card.marketLowCents === null && card.marketHighCents === null)
    return 'Noch offen';
  if (
    card.marketLowCents === card.marketHighCents &&
    card.marketLowCents !== null
  ) {
    return euro(card.marketLowCents);
  }
  return `${card.marketLowCents === null ? '–' : euro(card.marketLowCents)} – ${
    card.marketHighCents === null ? '–' : euro(card.marketHighCents)
  }`;
}

function UploadPanel({
  side,
  image,
  fileName,
  disabled,
  onFile,
}: {
  side: ImageSide;
  image: string | null;
  fileName: string | null;
  disabled: boolean;
  onFile: (side: ImageSide, event: ChangeEvent<HTMLInputElement>) => void;
}) {
  const isFront = side === 'front';
  const id = `${side}-upload`;

  return (
    <label
      htmlFor={id}
      className="group relative flex min-h-72 cursor-pointer flex-col overflow-hidden rounded-2xl border border-dashed border-white/14 bg-white/[0.025] transition hover:border-red-500/55 hover:bg-white/[0.045] focus-within:ring-2 focus-within:ring-red-500/70 has-[:disabled]:cursor-not-allowed has-[:disabled]:opacity-60"
    >
      <input
        id={id}
        className="sr-only"
        type="file"
        accept="image/jpeg,image/png,image/webp"
        disabled={disabled}
        onChange={(event) => onFile(side, event)}
      />

      {image ? (
        <>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={image}
            alt={`${isFront ? 'Vorderseite' : 'Rückseite'} der ausgewählten Karte`}
            className="absolute inset-0 h-full w-full object-contain p-5"
          />
          <div className="absolute inset-x-0 bottom-0 flex items-center justify-between gap-3 bg-gradient-to-t from-black via-black/80 to-transparent px-5 pb-4 pt-12">
            <span className="min-w-0 truncate text-xs text-zinc-300">
              {fileName}
            </span>
            <Badge className="bg-emerald-400 text-emerald-950">
              <Check /> bereit
            </Badge>
          </div>
        </>
      ) : (
        <div className="flex flex-1 flex-col items-center justify-center px-6 py-10 text-center">
          <span className="mb-5 grid size-13 place-items-center rounded-2xl border border-white/10 bg-white/[0.055] text-zinc-300 transition group-hover:scale-105 group-hover:text-white">
            {isFront ? <Camera /> : <Upload />}
          </span>
          <strong className="text-base font-semibold text-white">
            {isFront ? 'Vorderseite' : 'Rückseite'}
          </strong>
          <span className="mt-5 rounded-full border border-white/10 px-3 py-1 text-xs text-zinc-400">
            Foto wählen
          </span>
        </div>
      )}
    </label>
  );
}

export default function Home() {
  const [activeTab, setActiveTab] = useState('analysis');
  const [frontFile, setFrontFile] = useState<File | null>(null);
  const [backFile, setBackFile] = useState<File | null>(null);
  const [cards, setCards] = useState<CardRecord[]>([]);
  const [huntProducts, setHuntProducts] = useState<HuntProduct[]>([]);
  const [hotBoard, setHotBoard] = useState<HotBoard | null>(null);
  const [hotCards, setHotCards] = useState<HotCard[]>([]);
  const [collectionLoading, setCollectionLoading] = useState(true);
  const [lookoutLoading, setLookoutLoading] = useState(true);
  const [hot10Loading, setHot10Loading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [lookoutSaving, setLookoutSaving] = useState(false);
  const [updatingHuntId, setUpdatingHuntId] = useState<string | null>(null);
  const [hotAddingId, setHotAddingId] = useState<string | null>(null);
  const [notice, setNotice] = useState<{
    tone: 'success' | 'error';
    text: string;
  } | null>(null);

  const loadCards = useCallback(async () => {
    try {
      const response = await fetch('/api/cards?limit=100', {
        cache: 'no-store',
      });
      const payload = (await response.json()) as {
        cards?: CardRecord[];
        error?: string;
      };
      if (!response.ok)
        throw new Error(
          payload.error ?? 'Sammlung konnte nicht geladen werden.',
        );
      setCards(payload.cards ?? []);
    } catch (error) {
      setNotice({
        tone: 'error',
        text:
          error instanceof Error
            ? error.message
            : 'Sammlung konnte nicht geladen werden.',
      });
    } finally {
      setCollectionLoading(false);
    }
  }, []);

  const loadLookout = useCallback(async () => {
    try {
      const response = await fetch('/api/hunts', { cache: 'no-store' });
      const payload = (await response.json()) as {
        products?: HuntProduct[];
        error?: string;
      };
      if (!response.ok)
        throw new Error(
          payload.error ?? 'Lookout konnte nicht geladen werden.',
        );
      setHuntProducts(payload.products ?? []);
    } catch (error) {
      setNotice({
        tone: 'error',
        text:
          error instanceof Error
            ? error.message
            : 'Lookout konnte nicht geladen werden.',
      });
    } finally {
      setLookoutLoading(false);
    }
  }, []);

  const loadHot10 = useCallback(async () => {
    try {
      const response = await fetch('/api/hot-10', { cache: 'no-store' });
      const payload = (await response.json()) as {
        board?: HotBoard | null;
        cards?: HotCard[];
        error?: string;
      };
      if (!response.ok)
        throw new Error(payload.error ?? 'Hot 10 konnte nicht geladen werden.');
      setHotBoard(payload.board ?? null);
      setHotCards(payload.cards ?? []);
    } catch (error) {
      setNotice({
        tone: 'error',
        text:
          error instanceof Error
            ? error.message
            : 'Hot 10 konnte nicht geladen werden.',
      });
    } finally {
      setHot10Loading(false);
    }
  }, []);

  useCardScoutTools(loadCards, loadLookout, loadHot10);

  useEffect(() => {
    queueMicrotask(
      () => void Promise.all([loadCards(), loadLookout(), loadHot10()]),
    );
  }, [loadCards, loadHot10, loadLookout]);

  const frontPreview = useMemo(
    () => (frontFile ? URL.createObjectURL(frontFile) : null),
    [frontFile],
  );
  const backPreview = useMemo(
    () => (backFile ? URL.createObjectURL(backFile) : null),
    [backFile],
  );

  useEffect(() => {
    return () => {
      if (frontPreview) URL.revokeObjectURL(frontPreview);
    };
  }, [frontPreview]);

  useEffect(() => {
    return () => {
      if (backPreview) URL.revokeObjectURL(backPreview);
    };
  }, [backPreview]);

  const stats = useMemo(() => {
    const pending = cards.filter((card) => card.status === 'pending').length;
    const huntingTargets = huntProducts.reduce(
      (total, product) => total + product.counts.hunting,
      0,
    );
    const marketCents = cards.reduce((total, card) => {
      if (card.marketLowCents !== null && card.marketHighCents !== null) {
        return (
          total + Math.round((card.marketLowCents + card.marketHighCents) / 2)
        );
      }
      return total + (card.marketLowCents ?? card.marketHighCents ?? 0);
    }, 0);
    return { pending, marketCents, huntingTargets };
  }, [cards, huntProducts]);

  function handleFile(side: ImageSide, event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file) return;
    setNotice(null);
    if (side === 'front') setFrontFile(file);
    else setBackFile(file);
  }

  async function queueAnalysis() {
    if (!frontFile || submitting) return;
    setSubmitting(true);
    setNotice(null);

    try {
      const form = new FormData();
      form.set('front', frontFile);
      if (backFile) form.set('back', backFile);
      const response = await fetch('/api/cards', {
        method: 'POST',
        body: form,
      });
      const payload = (await response.json()) as { error?: string };
      if (!response.ok)
        throw new Error(payload.error ?? 'Upload fehlgeschlagen.');

      setFrontFile(null);
      setBackFile(null);
      await loadCards();
      setNotice({
        tone: 'success',
        text: 'Karte hochgeladen.',
      });
      setActiveTab('collection');
    } catch (error) {
      setNotice({
        tone: 'error',
        text: error instanceof Error ? error.message : 'Upload fehlgeschlagen.',
      });
    } finally {
      setSubmitting(false);
    }
  }

  async function addHuntTarget(input: NewHuntTargetInput) {
    if (lookoutSaving) return false;
    setLookoutSaving(true);
    setNotice(null);
    try {
      const response = await fetch('/api/hunts', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          product: {
            name: input.boxName,
            format: input.format || null,
          },
          targets: [
            {
              label: input.label,
              parallel: input.parallel || null,
              whySpecial: input.whySpecial || null,
              priority: input.priority,
            },
          ],
        }),
      });
      const payload = (await response.json()) as { error?: string };
      if (!response.ok)
        throw new Error(
          payload.error ?? 'Chase Card konnte nicht gespeichert werden.',
        );
      await loadLookout();
      setNotice({
        tone: 'success',
        text: `${input.label} ist jetzt auf deinem Lookout.`,
      });
      return true;
    } catch (error) {
      setNotice({
        tone: 'error',
        text:
          error instanceof Error
            ? error.message
            : 'Chase Card konnte nicht gespeichert werden.',
      });
      return false;
    } finally {
      setLookoutSaving(false);
    }
  }

  async function updateHuntTarget(
    id: string,
    patch: { status?: HuntStatus; priority?: HuntPriority },
  ) {
    if (updatingHuntId) return;
    setUpdatingHuntId(id);
    setNotice(null);
    try {
      const response = await fetch(`/api/hunts/${encodeURIComponent(id)}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(patch),
      });
      const payload = (await response.json()) as { error?: string };
      if (!response.ok)
        throw new Error(
          payload.error ?? 'Lookout konnte nicht aktualisiert werden.',
        );
      await loadLookout();
    } catch (error) {
      setNotice({
        tone: 'error',
        text:
          error instanceof Error
            ? error.message
            : 'Lookout konnte nicht aktualisiert werden.',
      });
    } finally {
      setUpdatingHuntId(null);
    }
  }

  async function addHotCardToLookout(card: HotCard) {
    if (hotAddingId) return;
    setHotAddingId(card.id);
    setNotice(null);
    try {
      const response = await fetch('/api/hunts', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          product: {
            name: card.productName,
            year: card.year,
            brand:
              card.brandFamily.charAt(0).toUpperCase() +
              card.brandFamily.slice(1),
            format: card.format ?? 'Alle Formate',
            checklistSourceUrl: card.licenseSourceUrl,
            sourceCheckedAt: card.licenseCheckedAt,
          },
          targets: [
            {
              label: card.label,
              player: card.player,
              cardNumber: card.cardNumber,
              parallel: card.parallel,
              whySpecial: card.whyHot,
              priority: card.rank <= 3 ? 'grail' : 'high',
              sourceUrl: card.evidence[0]?.url ?? card.imageSourceUrl,
              notes: `Hot 10 #${card.rank}, geprüft ${hotBoard?.researchedAt ?? 'aktuell'}`,
            },
          ],
        }),
      });
      const payload = (await response.json()) as { error?: string };
      if (!response.ok)
        throw new Error(
          payload.error ?? 'Karte konnte nicht zum Lookout hinzugefügt werden.',
        );
      await loadLookout();
      setNotice({
        tone: 'success',
        text: `${card.label} ist jetzt auf deinem Lookout.`,
      });
    } catch (error) {
      setNotice({
        tone: 'error',
        text:
          error instanceof Error
            ? error.message
            : 'Karte konnte nicht zum Lookout hinzugefügt werden.',
      });
    } finally {
      setHotAddingId(null);
    }
  }

  return (
    <main className="min-h-screen bg-[#08090b] text-zinc-100">
      <header className="border-b border-white/[0.08] bg-black/25">
        <div className="mx-auto flex max-w-7xl items-center px-5 py-4 sm:px-8">
          <div className="flex items-center gap-3">
            <span className="grid size-10 place-items-center rounded-xl bg-red-600 shadow-[0_0_28px_rgba(220,38,38,.22)]">
              <ShieldCheck className="size-5" />
            </span>
            <p className="font-semibold tracking-tight">NFL Card Scout</p>
          </div>
        </div>
      </header>

      <section className="mx-auto max-w-7xl px-5 py-6 sm:px-8 sm:py-8">
        <div className="mb-7 flex justify-end">
          <div className="grid w-full grid-cols-2 gap-px overflow-hidden rounded-xl border border-white/[0.08] bg-white/[0.08] sm:w-auto sm:grid-cols-4">
            {[
              [String(cards.length), 'Karten'],
              [euro(stats.marketCents), 'Marktwert'],
              [String(stats.pending), 'Offen'],
              [String(stats.huntingTargets), 'Lookout'],
            ].map(([value, label]) => (
              <div
                key={label}
                className="min-w-24 bg-[#0d0f12] px-4 py-3 text-center"
              >
                <p className="font-mono text-lg font-semibold text-white">
                  {value}
                </p>
                <p className="text-[11px] uppercase tracking-wider text-zinc-600">
                  {label}
                </p>
              </div>
            ))}
          </div>
        </div>

        {notice && (
          <div
            role={notice.tone === 'error' ? 'alert' : 'status'}
            className={`mb-6 flex items-start gap-3 rounded-xl border px-4 py-3 text-sm leading-6 ${
              notice.tone === 'error'
                ? 'border-red-400/20 bg-red-400/[0.07] text-red-200'
                : 'border-emerald-400/20 bg-emerald-400/[0.07] text-emerald-200'
            }`}
          >
            {notice.tone === 'error' ? (
              <AlertCircle className="mt-1 size-4 shrink-0" />
            ) : (
              <Check className="mt-1 size-4 shrink-0" />
            )}
            <span>{notice.text}</span>
          </div>
        )}

        <Tabs value={activeTab} onValueChange={setActiveTab} className="gap-7">
          <TabsList
            variant="line"
            className="max-w-full justify-start overflow-x-auto border-b border-white/[0.08]"
          >
            <TabsTrigger
              value="analysis"
              className="px-1 pb-3 data-active:after:bg-red-500"
            >
              Neue Analyse
            </TabsTrigger>
            <TabsTrigger
              value="collection"
              className="px-1 pb-3 data-active:after:bg-red-500"
            >
              Sammlung
              {stats.pending > 0 && (
                <span className="ml-1 rounded-full bg-red-500/15 px-1.5 py-0.5 text-[10px] text-red-300">
                  {stats.pending}
                </span>
              )}
            </TabsTrigger>
            <TabsTrigger
              value="hot-10"
              className="px-1 pb-3 data-active:after:bg-red-500"
            >
              <Flame className="size-3.5" />
              Hot 10
              {hotCards.length > 0 && (
                <span className="ml-1 rounded-full bg-red-500/15 px-1.5 py-0.5 text-[10px] text-red-300">
                  {hotCards.length}
                </span>
              )}
            </TabsTrigger>
            <TabsTrigger
              value="lookout"
              className="px-1 pb-3 data-active:after:bg-red-500"
            >
              <Crosshair className="size-3.5" />
              Lookout
              {stats.huntingTargets > 0 && (
                <span className="ml-1 rounded-full bg-fuchsia-500/15 px-1.5 py-0.5 text-[10px] text-fuchsia-300">
                  {stats.huntingTargets}
                </span>
              )}
            </TabsTrigger>
          </TabsList>

          <TabsContent value="analysis">
            <Card className="border border-white/[0.08] bg-[#0d0f12] py-0 ring-0">
              <CardHeader className="border-b border-white/[0.07] px-5 py-5 sm:px-7">
                <CardTitle className="text-lg text-white">Neue Karte</CardTitle>
              </CardHeader>
              <CardContent className="space-y-5 p-5 sm:p-7">
                <div className="grid gap-4 md:grid-cols-2">
                  <UploadPanel
                    side="front"
                    image={frontPreview}
                    fileName={frontFile?.name ?? null}
                    disabled={submitting}
                    onFile={handleFile}
                  />
                  <UploadPanel
                    side="back"
                    image={backPreview}
                    fileName={backFile?.name ?? null}
                    disabled={submitting}
                    onFile={handleFile}
                  />
                </div>
                <Button
                  size="lg"
                  disabled={!frontFile || submitting}
                  onClick={queueAnalysis}
                  className="h-12 w-full bg-red-600 text-white hover:bg-red-500"
                >
                  {submitting ? (
                    <>
                      <LoaderCircle className="animate-spin" /> Wird hochgeladen
                    </>
                  ) : (
                    'Analysieren'
                  )}
                </Button>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="collection">
            {collectionLoading ? (
              <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
                {[0, 1, 2].map((item) => (
                  <div
                    key={item}
                    className="h-96 animate-pulse rounded-xl border border-white/[0.06] bg-white/[0.035]"
                  />
                ))}
              </div>
            ) : cards.length === 0 ? (
              <Card className="min-h-[420px] items-center justify-center border border-white/[0.08] bg-[#0d0f12] text-center ring-0">
                <CardContent className="max-w-md py-16">
                  <span className="mx-auto mb-5 grid size-14 place-items-center rounded-2xl border border-white/10 bg-white/[0.04]">
                    <Images className="size-6 text-zinc-500" />
                  </span>
                  <h2 className="text-lg font-semibold text-white">
                    Keine Karten
                  </h2>
                </CardContent>
              </Card>
            ) : (
              <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
                {cards.map((card) => (
                  <Card
                    key={card.id}
                    className="border border-white/[0.08] bg-[#0d0f12] py-0 ring-0"
                  >
                    <div className="relative aspect-[4/3] overflow-hidden bg-black/30">
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img
                        src={card.frontImageUrl}
                        alt={
                          card.player
                            ? `${card.player} NFL-Karte`
                            : 'NFL-Karte wartet auf Analyse'
                        }
                        className="h-full w-full object-contain p-4"
                      />
                      <Badge
                        variant="outline"
                        className={`absolute left-3 top-3 backdrop-blur ${
                          card.status === 'pending'
                            ? 'border-amber-400/20 bg-black/65 text-amber-300'
                            : card.status === 'failed'
                              ? 'border-red-400/20 bg-black/65 text-red-300'
                              : 'border-emerald-400/20 bg-black/65 text-emerald-300'
                        }`}
                      >
                        {card.status === 'pending' && <Clock3 />}
                        {card.status === 'pending'
                          ? 'Offen'
                          : card.status === 'failed'
                            ? 'Fehler'
                            : 'Analysiert'}
                      </Badge>
                    </div>
                    <CardContent className="space-y-4 p-5">
                      <div>
                        <p className="text-xs uppercase tracking-wider text-zinc-600">
                          {[card.year, card.brand, card.setName]
                            .filter(Boolean)
                            .join(' · ') ||
                            (card.status === 'pending'
                              ? 'Analyse ausstehend'
                              : card.needsReview
                                ? 'Manuelle Prüfung nötig'
                                : 'Analyse abgeschlossen')}
                        </p>
                        <h2 className="mt-1 truncate text-lg font-semibold text-white">
                          {card.player ?? 'Unbekannte NFL-Karte'}
                        </h2>
                        {[
                          card.team,
                          card.parallel,
                          card.cardNumber ? `#${card.cardNumber}` : null,
                        ].some(Boolean) && (
                          <p className="mt-1 truncate text-sm text-zinc-500">
                            {[
                              card.team,
                              card.parallel,
                              card.cardNumber ? `#${card.cardNumber}` : null,
                            ]
                              .filter(Boolean)
                              .join(' · ')}
                          </p>
                        )}
                      </div>

                      <div className="flex items-end justify-between gap-4 border-t border-white/[0.07] pt-4">
                        <div>
                          <p className="text-[10px] uppercase tracking-wider text-zinc-600">
                            Markt
                          </p>
                          <p className="mt-1 font-mono text-sm text-zinc-200">
                            {marketRange(card)}
                          </p>
                        </div>
                        {card.recommendation && (
                          <Badge
                            variant="outline"
                            className={recommendationStyle[card.recommendation]}
                          >
                            {card.recommendation}
                          </Badge>
                        )}
                      </div>
                    </CardContent>
                  </Card>
                ))}
              </div>
            )}
          </TabsContent>

          <TabsContent value="hot-10">
            <Hot10Panel
              board={hotBoard}
              cards={hotCards}
              loading={hot10Loading}
              addingId={hotAddingId}
              onAddToLookout={addHotCardToLookout}
            />
          </TabsContent>

          <TabsContent value="lookout">
            <LookoutPanel
              products={huntProducts}
              loading={lookoutLoading}
              saving={lookoutSaving}
              updatingId={updatingHuntId}
              onAdd={addHuntTarget}
              onUpdate={updateHuntTarget}
            />
          </TabsContent>
        </Tabs>
      </section>
    </main>
  );
}
