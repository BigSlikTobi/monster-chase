# Card Scout: Mac-backend removal chats

Created: 7 November 2026. One local project chat per task.

All 16 chats acknowledged their briefs and are waiting for the user to start.
Chat creation has not completed any implementation task.

Each chat contains the shared product decisions, its own scope, prerequisites,
starting files, completion checks, data-preservation rules, and a link to the
[master task list](mac-independent-backend-task-list.md).

Start with task 01. Open a chat below and say `Start this task` when ready.
The prerequisites name the earlier tasks whose evidence must be checked first.
All chats share the local checkout, so avoid starting overlapping edits together.

| Task | Chat | Prerequisites |
| --- | --- | --- |
| 01 | [Card Scout 01 — Audit backend dependencies](codex://threads/01a1b530-09ab-7d00-bba2-26405e7cbefb) | None |
| 02 | [Card Scout 02 — Prepare server migration](codex://threads/01a1b530-40a6-7432-8c1d-e683bea8bc80) | 01 |
| 03 | [Card Scout 03 — Prove Mac-off operation](codex://threads/01a1b530-4e18-7482-9931-6abdfabc4c47) | 02 |
| 04 | [Card Scout 04 — OCR front and back](codex://threads/01a1b530-5b99-7df3-8a64-fc2be35950e5) | 01 |
| 05 | [Card Scout 05 — Identity and catalog](codex://threads/01a1b530-6a3c-73a3-acf5-75f3a50a7ad6) | 01 |
| 06 | [Card Scout 06 — Matching without AI](codex://threads/01a1b530-7b2a-72d2-b4c9-528903d32bc3) | 04, 05 |
| 07 | [Card Scout 07 — Validate OCR-first recognition](codex://threads/01a1b530-a37d-7d83-a6e0-bc310329868a) | 06 |
| 08 | [Card Scout 08 — User access and ownership](codex://threads/01a1b530-ae8c-7e13-be77-21fce97b7030) | 01 |
| 09 | [Card Scout 09 — Add public HTTPS service](codex://threads/01a1b530-bdd3-7163-b8a4-57177afd20a6) | 06, 08 |
| 10 | [Card Scout 10 — Update iPhone onboarding](codex://threads/01a1b530-d124-7153-9d62-efafbf0dbede) | 08, 09 |
| 11 | [Card Scout 11 — Shared market cache](codex://threads/01a1b530-e74d-7861-aa78-77f4d535f323) | 05, 08 |
| 12 | [Card Scout 12 — Requests and spending](codex://threads/01a1b531-17af-79c0-abf0-307177f7deb6) | 08, 11 |
| 13 | [Card Scout 13 — Add operations and recovery](codex://threads/01a1b531-34bc-72c0-ba8b-0a1d361d1dae) | 02, 08, 09 |
| 14 | [Card Scout 14 — Privacy and store prep](codex://threads/01a1b531-5642-7b40-8d31-8103ee3b7266) | 08, 09, 10, 11, 12, 13 |
| 15 | [Card Scout 15 — External TestFlight beta](codex://threads/01a1b531-6d9e-7d23-ab7c-b44e2f0353bd) | 03, 07, 10, 11, 12, 13, 14 |
| 16 | [Card Scout 16 — Release and retire Mac](codex://threads/01a1b531-8292-7920-9855-4d04caa3565a) | 15 |

The shared brief keeps OCR and verified checklist matching as the first path.
Clear matches need no AI call; ambiguous cases go to review. Market evidence can
be cached across users while private photos and collection data stay separate.

Each task must record its completion evidence in the master plan before dependent
work relies on it. Do not treat historical deployment notes as current verification.
