# discourse-chat-email-default-never

Newly created users get `UserOption#chat_email_frequency = never` instead of the core database
default of `when_away`. Discourse ships no admin site setting for this preference.

Implemented as a `prepend` on `UserOption#set_defaults`, so the value lands in the same `INSERT`
as the other ~25 `default_*` preferences — no follow-up `UPDATE`, no committed window at the
wrong value, and it also covers `UserOption.ensure_consistency!`, which never fires
`DiscourseEvent :user_created`.

Enable with the `chat_email_default_never_enabled` site setting. Default off, so installing the
plugin is behaviourally a no-op until an admin flips it — and flipping it back is instant, with
no rebuild.

**Existing users are never touched.** Backfilling them is a deliberate operator action; see
[CLAUDE.md](CLAUDE.md) § Backfill.

## Making "never" actually mean never

Out of the box `chat_email_frequency` gates only *unread direct messages*. Category-channel
@mentions and watched threads are gated by `default email level` instead, so a user set to "never"
still receives chat summary email for those. Core treats that as intended.

`chat_email_never_suppresses_summary` (default off) closes it at both layers — the enqueue, via
chat's own `:chat_mailer_send_summary_to_user` modifier, and the render, via a prepend on
`UserNotifications#chat_summary` that also catches jobs already queued when you flip the setting.

**Scope:** this suppresses the chat *summary* email in full. Chat content that arrives as an
ordinary PM or topic — flag transcripts to moderators, channel-archive PMs, archived transcripts
copied into a topic — is governed by `email_messages_level` and category watching, not by this
plugin. See [CLAUDE.md](CLAUDE.md) § Scope.

Orientation for agents and maintainers: [CLAUDE.md](CLAUDE.md).
