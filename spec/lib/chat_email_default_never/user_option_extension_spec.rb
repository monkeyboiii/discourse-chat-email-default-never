# frozen_string_literal: true

describe ChatEmailDefaultNever::UserOptionExtension do
  let(:never) { UserOption.chat_email_frequencies[:never] }
  let(:when_away) { UserOption.chat_email_frequencies[:when_away] }

  def raw_frequency(user)
    DB.query_single("SELECT chat_email_frequency FROM user_options WHERE user_id = ?", user.id).first
  end

  it "is inert when disabled, preserving the core default" do
    SiteSetting.chat_email_default_never_enabled = false

    expect(raw_frequency(Fabricate(:user))).to eq(when_away)
  end

  context "when enabled" do
    before { SiteSetting.chat_email_default_never_enabled = true }

    it "assigns never to a newly created user" do
      user = Fabricate(:user)

      expect(raw_frequency(user)).to eq(never)
      expect(user.user_option.chat_email_frequency).to eq("never")
    end

    it "covers rows created by ensure_consistency!, which fires no :user_created event" do
      user = Fabricate(:user)
      user.user_option.destroy!

      UserOption.ensure_consistency!

      expect(UserOption.find_by(user_id: user.id).chat_email_frequency).to eq("never")
    end

    it "leaves existing users alone" do
      SiteSetting.chat_email_default_never_enabled = false
      existing = Fabricate(:user)
      SiteSetting.chat_email_default_never_enabled = true

      Fabricate(:user)

      expect(raw_frequency(existing)).to eq(when_away)
    end
  end
end
