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

**Scope caveat:** `chat_email_frequency` gates only the *unread direct-message* chat summary
email. Channel mentions and watched threads are gated by the core `default email level` setting
instead. See [CLAUDE.md](CLAUDE.md) § Scope.

Orientation for agents and maintainers: [CLAUDE.md](CLAUDE.md).
