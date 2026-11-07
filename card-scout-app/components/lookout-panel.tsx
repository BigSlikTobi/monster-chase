'use client';

import { SubmitEvent, useState } from 'react';
import {
  Crosshair,
  ExternalLink,
  LoaderCircle,
  PackageSearch,
  Plus,
  Trophy,
} from 'lucide-react';

import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import type {
  HuntPriority,
  HuntProduct,
  HuntStatus,
  NewHuntTargetInput,
} from '@/lib/hunt-types';

const priorityLabel: Record<HuntPriority, string> = {
  grail: 'Grail',
  high: 'Hoch',
  medium: 'Mittel',
  low: 'Niedrig',
};

const priorityStyle: Record<HuntPriority, string> = {
  grail: 'border-fuchsia-400/25 bg-fuchsia-400/10 text-fuchsia-300',
  high: 'border-red-400/25 bg-red-400/10 text-red-300',
  medium: 'border-amber-400/25 bg-amber-400/10 text-amber-300',
  low: 'border-zinc-400/20 bg-zinc-400/10 text-zinc-400',
};

const statusLabel: Record<HuntStatus, string> = {
  hunting: 'Jagen',
  found: 'Gefunden',
  passed: 'Pausiert',
};

export function LookoutPanel({
  products,
  loading,
  saving,
  updatingId,
  onAdd,
  onUpdate,
}: {
  products: HuntProduct[];
  loading: boolean;
  saving: boolean;
  updatingId: string | null;
  onAdd: (input: NewHuntTargetInput) => Promise<boolean>;
  onUpdate: (
    id: string,
    patch: { status?: HuntStatus; priority?: HuntPriority },
  ) => Promise<void>;
}) {
  const [boxName, setBoxName] = useState('');
  const [format, setFormat] = useState('');
  const [label, setLabel] = useState('');
  const [parallel, setParallel] = useState('');
  const [priority, setPriority] = useState<HuntPriority>('high');

  async function submit(event: SubmitEvent<HTMLFormElement>) {
    event.preventDefault();
    const saved = await onAdd({
      boxName,
      format,
      label,
      parallel,
      whySpecial: '',
      priority,
    });
    if (!saved) return;
    setLabel('');
    setParallel('');
  }

  return (
    <div className="grid gap-6 xl:grid-cols-[350px_minmax(0,1fr)]">
      <Card className="h-fit border border-white/[0.08] bg-[#0d0f12] ring-0 xl:sticky xl:top-6">
        <CardHeader className="border-b border-white/[0.07]">
          <CardTitle className="flex items-center gap-2 text-white">
            <Crosshair className="size-4 text-red-400" />
            Chase Card hinzufügen
          </CardTitle>
        </CardHeader>
        <CardContent>
          <form className="space-y-4" onSubmit={submit}>
            <label
              htmlFor="hunt-box-name"
              className="block space-y-1.5 text-sm text-zinc-300"
            >
              <span>Box oder Produkt</span>
              <Input
                id="hunt-box-name"
                required
                value={boxName}
                onChange={(event) => setBoxName(event.target.value)}
                placeholder="z. B. 2024 Donruss Football"
                className="h-10 border-white/10 bg-white/[0.035]"
              />
            </label>

            <label
              htmlFor="hunt-box-format"
              className="block space-y-1.5 text-sm text-zinc-300"
            >
              <span>Format</span>
              <Input
                id="hunt-box-format"
                value={format}
                onChange={(event) => setFormat(event.target.value)}
                placeholder="Hobby, Mega, Blaster …"
                className="h-10 border-white/10 bg-white/[0.035]"
              />
            </label>

            <label
              htmlFor="hunt-card-label"
              className="block space-y-1.5 text-sm text-zinc-300"
            >
              <span>Karte oder Spieler</span>
              <Input
                id="hunt-card-label"
                required
                value={label}
                onChange={(event) => setLabel(event.target.value)}
                placeholder="Jayden Daniels Downtown!"
                className="h-10 border-white/10 bg-white/[0.035]"
              />
            </label>

            <label
              htmlFor="hunt-card-parallel"
              className="block space-y-1.5 text-sm text-zinc-300"
            >
              <span>Special / Parallel</span>
              <Input
                id="hunt-card-parallel"
                value={parallel}
                onChange={(event) => setParallel(event.target.value)}
                placeholder="SSP, Gold /10, Rookie Auto …"
                className="h-10 border-white/10 bg-white/[0.035]"
              />
            </label>

            <div className="space-y-1.5 text-sm text-zinc-300">
              <span>Priorität</span>
              <Select
                value={priority}
                onValueChange={(value) => setPriority(value as HuntPriority)}
              >
                <SelectTrigger className="h-10 w-full border-white/10 bg-white/[0.035]">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="grail">Grail</SelectItem>
                  <SelectItem value="high">Hoch</SelectItem>
                  <SelectItem value="medium">Mittel</SelectItem>
                  <SelectItem value="low">Niedrig</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <Button
              type="submit"
              size="lg"
              disabled={saving || !boxName.trim() || !label.trim()}
              className="h-11 w-full bg-red-600 text-white hover:bg-red-500"
            >
              {saving ? <LoaderCircle className="animate-spin" /> : <Plus />}
              {saving ? 'Wird gespeichert' : 'Zum Lookout'}
            </Button>
          </form>
        </CardContent>
      </Card>

      <div className="space-y-4">
        {loading ? (
          [0, 1].map((item) => (
            <div
              key={item}
              className="h-64 animate-pulse rounded-xl border border-white/[0.06] bg-white/[0.035]"
            />
          ))
        ) : products.length === 0 ? (
          <Card className="min-h-[420px] items-center justify-center border border-white/[0.08] bg-[#0d0f12] text-center ring-0">
            <CardContent className="max-w-md py-16">
              <span className="mx-auto mb-5 grid size-14 place-items-center rounded-2xl border border-white/10 bg-white/[0.04]">
                <PackageSearch className="size-6 text-zinc-500" />
              </span>
              <h2 className="text-lg font-semibold text-white">
                Keine Karten im Lookout
              </h2>
            </CardContent>
          </Card>
        ) : (
          products.map((product) => (
            <Card
              key={product.id}
              className="border border-white/[0.08] bg-[#0d0f12] ring-0"
            >
              <CardHeader className="border-b border-white/[0.07]">
                <div className="flex flex-wrap items-start justify-between gap-4">
                  <div>
                    <div className="flex flex-wrap items-center gap-2">
                      <CardTitle className="text-lg text-white">
                        {product.name}
                      </CardTitle>
                      {product.format && (
                        <Badge
                          variant="outline"
                          className="border-white/10 text-zinc-400"
                        >
                          {product.format}
                        </Badge>
                      )}
                    </div>
                    <p className="mt-1 text-sm text-zinc-500">
                      {product.counts.hunting} offen · {product.counts.found}{' '}
                      gefunden · {product.counts.total} gesamt
                    </p>
                  </div>
                  {product.checklistSourceUrl && (
                    <a
                      href={product.checklistSourceUrl}
                      target="_blank"
                      rel="noreferrer"
                      className="inline-flex items-center gap-1.5 text-xs text-zinc-400 hover:text-white"
                    >
                      Lizenz-/Produktquelle <ExternalLink className="size-3" />
                    </a>
                  )}
                </div>
              </CardHeader>
              <CardContent className="divide-y divide-white/[0.07] px-0">
                {product.targets.map((target) => (
                  <div
                    key={target.id}
                    className={`grid gap-4 px-4 py-4 sm:px-5 lg:grid-cols-[minmax(0,1fr)_130px_130px] lg:items-center ${
                      target.status === 'found' ? 'opacity-55' : ''
                    }`}
                  >
                    <div className="min-w-0">
                      <div className="flex flex-wrap items-center gap-2">
                        {target.status === 'found' && (
                          <Trophy className="size-4 text-amber-300" />
                        )}
                        <p
                          className={`font-medium text-white ${
                            target.status === 'found' ? 'line-through' : ''
                          }`}
                        >
                          {target.label}
                        </p>
                        <Badge
                          variant="outline"
                          className={priorityStyle[target.priority]}
                        >
                          {priorityLabel[target.priority]}
                        </Badge>
                      </div>
                      {(target.parallel || target.cardNumber) && (
                        <p className="mt-1 text-sm text-zinc-400">
                          {[
                            target.parallel,
                            target.cardNumber ? `#${target.cardNumber}` : null,
                          ]
                            .filter(Boolean)
                            .join(' · ')}
                        </p>
                      )}
                    </div>

                    <Select
                      value={target.priority}
                      disabled={updatingId === target.id}
                      onValueChange={(value) =>
                        void onUpdate(target.id, {
                          priority: value as HuntPriority,
                        })
                      }
                    >
                      <SelectTrigger className="h-9 w-full border-white/10 bg-white/[0.035]">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="grail">Grail</SelectItem>
                        <SelectItem value="high">Hoch</SelectItem>
                        <SelectItem value="medium">Mittel</SelectItem>
                        <SelectItem value="low">Niedrig</SelectItem>
                      </SelectContent>
                    </Select>

                    <Select
                      value={target.status}
                      disabled={updatingId === target.id}
                      onValueChange={(value) =>
                        void onUpdate(target.id, {
                          status: value as HuntStatus,
                        })
                      }
                    >
                      <SelectTrigger className="h-9 w-full border-white/10 bg-white/[0.035]">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="hunting">
                          {statusLabel.hunting}
                        </SelectItem>
                        <SelectItem value="found">
                          {statusLabel.found}
                        </SelectItem>
                        <SelectItem value="passed">
                          {statusLabel.passed}
                        </SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                ))}
              </CardContent>
            </Card>
          ))
        )}
      </div>
    </div>
  );
}
