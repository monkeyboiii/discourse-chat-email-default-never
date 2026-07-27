# frozen_string_literal: true

module ChatEmailDefaultNever
  module UserNotificationsExtension
    # Render-time gate; see CLAUDE.md § "The core asymmetry this plugin exists to fix".
    def chat_summary(user, opts = nil)
      return if SiteSetting.chat_email_never_suppresses_summary &&
        user.user_option&.send_chat_email_never?

      super
    end
  end
end
