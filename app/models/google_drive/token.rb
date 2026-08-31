# The browser hands Campsend a short-lived Google access token. It travels to
# the import job through the queue, so it is encrypted on the way and carries
# its own expiry rather than relying on the queue to be quick.
module GoogleDrive::Token
  LIFETIME = 1.hour
  PURPOSE = :google_drive_import

  module_function

  def encrypt(token)
    encryptor.encrypt_and_sign({ token:, expires_at: LIFETIME.from_now.to_i }, purpose: PURPOSE)
  end

  def decrypt(encrypted)
    payload = encryptor.decrypt_and_verify(encrypted, purpose: PURPOSE)
    raise ActiveSupport::MessageEncryptor::InvalidMessage if payload.fetch("expires_at") < Time.current.to_i

    payload.fetch("token")
  end

  def encryptor
    key = Rails.application.key_generator.generate_key("google-drive-import", ActiveSupport::MessageEncryptor.key_len)
    ActiveSupport::MessageEncryptor.new(key)
  end
end
