# frozen_string_literal: true

# name: discourse-chat-email-default-never
# about: Newly created users default to "never" for Chat email notifications (UserOption#chat_email_frequency). Core ships no site setting for it.
# version: 0.1.0
# authors: DirtBikeX
# url: https://github.com/monkeyboiii/discourse-chat-email-default-never
# required_version: 2.7.0

enabled_site_setting :chat_email_default_never_enabled

module ::ChatEmailDefaultNever
  PLUGIN_NAME = "discourse-chat-email-default-never"
end

after_initialize do
  # Prepend, not on(:user_created); set_defaults also runs under db:migrate. See CLAUDE.md.
  require_relative "lib/chat_email_default_never/user_option_extension"

  reloadable_patch { ::UserOption.prepend(::ChatEmailDefaultNever::UserOptionExtension) }
end
