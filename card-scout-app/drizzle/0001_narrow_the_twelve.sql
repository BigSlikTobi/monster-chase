ALTER TABLE `cards` ADD `market_checked_at` text;--> statement-breakpoint
ALTER TABLE `cards` ADD `sold_comp_count` integer;--> statement-breakpoint
ALTER TABLE `cards` ADD `needs_review` integer DEFAULT true NOT NULL;