# frozen_string_literal: true

module ChatEmailDefaultNever
  module UserOptionExtension
    # Public on purpose: core's UserOption#set_defaults is public, and a private
    # override would change its visibility on UserOption.
    def set_defaults
      super

      return true if !SiteSetting.chat_email_default_never_enabled
      return true if !has_attribute?(:chat_email_frequency) ||
        !UserOption.respond_to?(:chat_email_frequencies)

      self.chat_email_frequency = UserOption.chat_email_frequencies[:never]
      true
    end
  end
end
