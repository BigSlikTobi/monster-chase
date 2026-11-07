CREATE TABLE `hunt_products` (
	`id` text PRIMARY KEY NOT NULL,
	`normalized_key` text NOT NULL,
	`name` text NOT NULL,
	`year` integer,
	`brand` text,
	`format` text,
	`checklist_source_url` text,
	`source_checked_at` text,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `hunt_products_normalized_key_unique` ON `hunt_products` (`normalized_key`);--> statement-breakpoint
CREATE TABLE `hunt_targets` (
	`id` text PRIMARY KEY NOT NULL,
	`product_id` text NOT NULL,
	`normalized_key` text NOT NULL,
	`label` text NOT NULL,
	`player` text,
	`card_number` text,
	`parallel` text,
	`why_special` text,
	`priority` text DEFAULT 'medium' NOT NULL,
	`status` text DEFAULT 'hunting' NOT NULL,
	`source_url` text,
	`notes` text,
	`found_at` text,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL,
	FOREIGN KEY (`product_id`) REFERENCES `hunt_products`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `hunt_targets_product_key_unique` ON `hunt_targets` (`product_id`,`normalized_key`);--> statement-breakpoint
CREATE INDEX `hunt_targets_product_status_priority_idx` ON `hunt_targets` (`product_id`,`status`,`priority`);