CREATE TABLE `hot_boards` (
	`id` text PRIMARY KEY NOT NULL,
	`window_start` text NOT NULL,
	`window_end` text NOT NULL,
	`methodology` text NOT NULL,
	`coverage_note` text,
	`researched_at` text NOT NULL,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `hot_cards` (
	`id` text PRIMARY KEY NOT NULL,
	`board_id` text NOT NULL,
	`rank` integer NOT NULL,
	`normalized_key` text NOT NULL,
	`brand_family` text NOT NULL,
	`product_name` text NOT NULL,
	`year` integer,
	`format` text,
	`license_scope` text NOT NULL,
	`license_source_url` text NOT NULL,
	`license_checked_at` text NOT NULL,
	`label` text NOT NULL,
	`player` text,
	`team` text,
	`card_number` text,
	`parallel` text,
	`image_url` text NOT NULL,
	`image_source_url` text NOT NULL,
	`why_hot` text NOT NULL,
	`sold_comp_count` integer NOT NULL,
	`market_low_cents` integer,
	`median_sold_cents` integer,
	`market_high_cents` integer,
	`currency` text NOT NULL,
	`momentum_bps` integer,
	`last_sale_at` text,
	`evidence_json` text NOT NULL,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL,
	FOREIGN KEY (`board_id`) REFERENCES `hot_boards`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `hot_cards_board_rank_unique` ON `hot_cards` (`board_id`,`rank`);--> statement-breakpoint
CREATE UNIQUE INDEX `hot_cards_board_key_unique` ON `hot_cards` (`board_id`,`normalized_key`);--> statement-breakpoint
CREATE INDEX `hot_cards_brand_rank_idx` ON `hot_cards` (`brand_family`,`rank`);