Rails.application.configure do
  config.content_security_policy do |policy|
    remote_sources = [ ENV["STORAGE_ENDPOINT"], ENV["STORAGE_BROWSER_ORIGIN"] ].compact_blank
    google_drive_enabled = %w[GOOGLE_DRIVE_CLIENT_ID GOOGLE_DRIVE_API_KEY GOOGLE_DRIVE_APP_ID].all? { |name| ENV[name].present? }
    google_scripts = google_drive_enabled ? %w[https://apis.google.com https://accounts.google.com] : []
    google_connections = google_drive_enabled ? %w[https://accounts.google.com https://oauth2.googleapis.com https://picker.googleapis.com https://www.googleapis.com] : []
    google_frames = google_drive_enabled ? %w[https://accounts.google.com https://docs.google.com https://drive.google.com] : []

    policy.default_src :self
    policy.base_uri :self
    policy.connect_src :self, *remote_sources, *google_connections
    policy.font_src :self
    policy.form_action :self
    policy.frame_ancestors :none
    policy.img_src :self, :data, :blob, *remote_sources
    policy.object_src :none
    policy.frame_src :self, *google_frames
    policy.script_src :self, *google_scripts
    policy.style_src :self
  end

  config.content_security_policy_nonce_generator = ->(*) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
  config.content_security_policy_nonce_auto = true
end
