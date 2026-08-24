require "test_helper"

class ApiTokenTest < ActiveSupport::TestCase
  setup { @user = User.create!(email_address: "sender@example.com") }

  test "issuing returns the raw token once and stores only its digest" do
    token, raw = ApiToken.issue_for(@user, name: "Laptop", scope: "read")

    assert token.persisted?
    assert raw.start_with?(ApiToken::PREFIX)
    assert_equal Digest::SHA256.hexdigest(raw), token.token_digest
    assert_not_equal raw, token.token_digest
    # Nothing on the record can reconstruct the secret.
    assert_no_match Regexp.new(Regexp.escape(raw)), token.attributes.to_s
  end

  test "authenticate matches a live token and records use" do
    token, raw = ApiToken.issue_for(@user, name: "Laptop", scope: "read")
    assert_nil token.last_used_at

    assert_equal token, ApiToken.authenticate(raw)
    assert_not_nil token.reload.last_used_at
  end

  test "authenticate rejects wrong, revoked and expired tokens alike" do
    token, raw = ApiToken.issue_for(@user, name: "Laptop", scope: "read")

    assert_nil ApiToken.authenticate("#{ApiToken::PREFIX}wrong")
    assert_nil ApiToken.authenticate(nil)
    # A secret without the prefix never reaches the database.
    assert_nil ApiToken.authenticate(raw.delete_prefix(ApiToken::PREFIX))

    token.revoke!
    assert_nil ApiToken.authenticate(raw)

    token.update_columns(revoked_at: nil, expires_at: 1.hour.ago)
    assert_nil ApiToken.authenticate(raw)
  end

  test "last_used_at is not rewritten on every call" do
    token, raw = ApiToken.issue_for(@user, name: "Laptop", scope: "read")
    ApiToken.authenticate(raw)
    first_use = token.reload.last_used_at

    ApiToken.authenticate(raw)

    assert_equal first_use, token.reload.last_used_at

    token.update_column(:last_used_at, (ApiToken::LAST_USED_RESOLUTION + 1.minute).ago)
    ApiToken.authenticate(raw)

    assert_operator token.reload.last_used_at, :>, first_use
  end

  test "scope must be read or write and write is the only one that writes" do
    token, raw = ApiToken.issue_for(@user, name: "Agent", scope: "admin")

    assert_nil raw
    assert_includes token.errors[:scope], "is not included in the list"

    read_token, = ApiToken.issue_for(@user, name: "Reader", scope: "read")
    write_token, = ApiToken.issue_for(@user, name: "Writer", scope: "write")

    assert_not read_token.writable?
    assert write_token.writable?
  end

  test "a name is reusable only after the token holding it is revoked" do
    first, = ApiToken.issue_for(@user, name: "Laptop", scope: "read")
    _, raw = ApiToken.issue_for(@user, name: "Laptop", scope: "read")

    assert_nil raw

    first.revoke!
    _, reissued = ApiToken.issue_for(@user, name: "Laptop", scope: "read")

    assert_not_nil reissued
  end

  test "expiry must be in the future" do
    token, raw = ApiToken.issue_for(@user, name: "Laptop", scope: "read", expires_at: 1.hour.ago)

    assert_nil raw
    assert_includes token.errors[:expires_at], "must be in the future"
  end

  test "tokens die with their user" do
    ApiToken.issue_for(@user, name: "Laptop", scope: "read")

    assert_difference "ApiToken.count", -1 do
      @user.destroy
    end
  end
end
