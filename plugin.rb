# frozen_string_literal: true

# name: discourse-chat-email-default-never
# about: Newly created users default to "never" for Chat email notifications (UserOption#chat_email_frequency). Core ships no site setting for it.
# version: 0.2.0
# authors: DirtBikeX
# url: https://github.com/monkeyboiii/discourse-chat-email-default-never
# required_version: 2.7.0

enabled_site_setting :chat_email_default_never_enabled

module ::ChatEmailDefaultNever
  PLUGIN_NAME = "discourse-chat-email-default-never"
end

# Extension surface, load order and gating rationale: CLAUDE.md.
after_initialize do
  require_relative "lib/chat_email_default_never/user_option_extension"
  require_relative "lib/chat_email_default_never/user_notifications_extension"

  reloadable_patch do
    ::UserOption.prepend(::ChatEmailDefaultNever::UserOptionExtension)
    ::UserNotifications.prepend(::ChatEmailDefaultNever::UserNotificationsExtension)
  end

  register_modifier(:chat_mailer_send_summary_to_user) do |should_send, user|
    if SiteSetting.chat_email_never_suppresses_summary && user.user_option&.send_chat_email_never?
      false
    else
      should_send
    end
  end
end
