# discourse-chat-email-default-never

Makes Chat email notifications default to `never` for newly created users. Discourse ships no admin
site setting for `UserOption#chat_email_frequency`; the bundled `chat` plugin only defines the enum
and a preferences-page control.

All core line references below were verified at the pinned core SHA
(`infra/pins.upstream.env` → `DISCOURSE_VERSION`, `06d03da3…` at time of writing). Re-verify after a
core bump — this plugin patches a core model.

## Extension surface (all of it)

One method, one prepend:

| What | Where | Why |
|---|---|---|
| `UserOption#set_defaults` | `lib/chat_email_default_never/user_option_extension.rb` | `before_create :set_defaults` (`app/models/user_option.rb:27`) is the single chokepoint every ActiveRecord-created `user_options` row passes through |

Core's `set_defaults` assigns ~25 preferences from `SiteSetting.default_*` and simply omits
`chat_email_frequency`. This plugin fills that omission and nothing else. No migrations — the column
is core (`db/structure.sql`: `chat_email_frequency integer DEFAULT 1 NOT NULL`, added by
`plugins/chat/db/migrate/20220328142120_create_user_chat_message_statuses.rb`).

## Why not `on(:user_created)`

The obvious implementation is an `after_initialize { on(:user_created) { … update_column … } }`.
It was rejected for four independently verified reasons:

1. **It writes after the row is already committed wrong.** `after_commit
   :trigger_user_created_event, on: :create` (`app/models/user.rb:207`) runs *after* `after_create
   :create_user_option` (`:179`) has already persisted the row at the DB default of `when_away`.
   That needs a second `UPDATE` in a second transaction. `user_options` has no `created_at` /
   `updated_at`, so a row missed in that window is indistinguishable from a deliberate user choice.
2. **It misses live paths.** `UserOption.ensure_consistency!` (`app/models/user_option.rb:35`, run
   by `Jobs::EnsureDbConsistency`) and discobot's `create_user_option!`
   (`plugins/discourse-narrative-bot/db/fixtures/001_discobot.rb`) both create `user_options` rows
   without ever firing `DiscourseEvent :user_created`. Both go through `set_defaults`.
3. **An unrelated handler can silently cancel it.** `DiscourseEvent.trigger` re-raises unless
   `continue_on_error:` is passed, and `user.rb:2342` passes none.
4. **`user.user_option&.` fails invisibly.** `create_user_option` (`user.rb:2045`) never populates
   the `has_one` at `:58`. It re-queries and is non-nil today — verified live — but the `&.` means
   any future change turns this into a permanent silent no-op rather than an error.

## Boot safety (load-bearing)

`set_defaults` executes during seed-fu inside `rake db:migrate`, and that pups hook carries no
`raise_on_fail: false` (`discourse_docker/templates/web.template.yml`). A raise there is a **failed
rebuild with the forum already stopped**, not a 500. So the override:

- resolves everything chat-owned at **call time**, never at load time;
- guards on `has_attribute?(:chat_email_frequency)` and
  `UserOption.respond_to?(:chat_email_frequencies)` — either being false degrades to a no-op instead
  of a `PG::NotNullViolation` or `NoMethodError` on every signup;
- assigns an **Integer** from `UserOption.chat_email_frequencies[:never]`, never a Symbol.

`chat` installs its own `UserOption` prepend inside an unconditional `after_initialize`
(`plugins/chat/plugin.rb:49,107`), so `chat_email_frequencies` is defined regardless of
`SiteSetting.chat_enabled`, and `chat` sorts before `discourse-*` in `Dir[…].sort`. Nothing here
depends on that ordering, because resolution is deferred to call time.

The override is **public** on purpose — core's `set_defaults` is public, and a private override
would change its visibility on `UserOption`.

## The enabled toggle

`Plugin::Instance#notify_after_initialize` runs every `after_initialize` block with **no `enabled?`
gate**, and `reloadable_patch` does not check it either. The prepend is therefore always installed;
the explicit `SiteSetting.chat_email_default_never_enabled` read *inside* `set_defaults` is what
makes the admin toggle actually work. Do not remove it and rely on `enabled_site_setting` alone.

Default is `false`, matching the other first-party plugins: installing this via a `launcher rebuild`
is behaviourally inert, and the behaviour change is a separate, instantly-revertible admin flip.

## The core asymmetry this plugin exists to fix

`chat_email_frequency` gates **only** unread direct messages, in two places that must both be
patched:

| Layer | File | Mentions / threads gated by | DMs gated by |
|---|---|---|---|
| Enqueue (SQL) | `plugins/chat/lib/chat/mailer.rb:85,100` vs `:62` | `email_level <> never` | `chat_email_frequency = when_away` |
| Render | `plugins/chat/lib/chat/user_notifications_extension.rb:14-15` | `email_level != never` | `... && !send_chat_email_never?` |

So out of the box a user set to "never" **still receives** chat summary email for category-channel
@mentions and watched threads. Core asserts this as intended behaviour
(`plugins/chat/spec/components/chat/mailer_spec.rb:81-84`), which is why our fix is default-off.

`chat_email_never_suppresses_summary` closes both layers:

1. **Enqueue** — `register_modifier(:chat_mailer_send_summary_to_user)`, chat's own extension point
   (`mailer.rb:15`), applied *after* the three CTEs are UNIONed, so one `false` suppresses the
   summary whichever CTE matched. No SQL duplication, so no drift on a core bump.
2. **Render** — a prepend on `UserNotifications#chat_summary`. Necessary, not belt-and-braces:
   `Jobs::UserEmail` renders via `UserNotifications.public_send(type, ...)`
   (`app/jobs/regular/user_email.rb:240`) **without consulting any modifier**. Jobs already queued
   or retrying when the operator flips the setting would otherwise still send. This layer is also
   the authoritative one if another plugin ever registers the same modifier and returns `true`
   (`apply_modifier` chains in registration order).

Ordering: Ruby `prepend` is LIFO and `chat` sorts before `discourse-*` in `Dir[…].sort`, so ours is
prepended last, lands outermost, and `super` reaches chat's. Asserted in E2E, not assumed.

## Scope (do not over-promise)

`chat_email_never_suppresses_summary` suppresses the **chat summary email** in full. It does not —
and cannot — touch chat-derived content that reaches email as an ordinary PM or topic:

- flag PMs carrying a `Chat::TranscriptService` transcript to moderators (`lib/chat/review_queue.rb`)
- channel-archive system PMs to the archiving staff member (`lib/chat/channel_archive_service.rb`)
- an archived channel's transcripts copied into a real Topic, which then follows normal
  watching/digest rules

Those are governed by `email_messages_level` and category watching. Verified clean: core digest and
all core mailer views contain no chat content, and per-notification chat emails never fire —
`NotificationEmailer::EmailUser` defines no `chat_*` method, so those notification types are
silently skipped.

## Backfill (existing users)

Deliberately not shipped as code — no callback, no migration, no rake task. The plugin's contract is
creation-time only. To backfill, snapshot first (there is no `updated_at` to recover from):

```ruby
never = UserOption.chat_email_frequencies[:never]
scope = UserOption.human_users.where.not(chat_email_frequency: never)
File.write("/shared/tmp/cef_backfill_#{Time.now.to_i}.txt", scope.pluck(:user_id).join("\n"))
scope.update_all(chat_email_frequency: never)
```

`human_users` (`user_id > 0`) excludes system and bot accounts.

## Dev / deploy

- Specs: `RAILS_ENV=test bundle exec rspec plugins/discourse-chat-email-default-never/spec` from a
  core checkout with a Discourse dev environment. **This cannot run on dbc** (no Rails dev env);
  verification there is via `rails runner` against the live container.
- Ships via `infra/pins.upstream.env` (D3.5 in `infra/guides/RELEASING.md`): push commit + tag to
  this repo's remote **first**, pin the deref'd commit SHA, regenerate `versions.*`, then `esa` +
  `launcher rebuild app`.
