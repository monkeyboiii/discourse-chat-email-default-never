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

## Scope (do not over-promise)

`chat_email_frequency` is referenced exactly once in `plugins/chat/lib/chat/mailer.rb`, inside the
`unread_dms` CTE. The sibling `unread_mentions` and `unread_threads` CTEs gate on
`eu.email_level <> never` instead, and all three are additionally gated by `uo.chat_enabled` and
`u.last_seen_at < now() - interval '15 minutes'`.

So this plugin suppresses **unread direct-message chat summary emails only**. Category-channel
@mentions and watched-thread messages still enqueue `Jobs::UserEmail type: "chat_summary"`. For "no
chat email at all", also set core's `default email level` to `never` — but note that suppresses
ordinary topic email too.

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
