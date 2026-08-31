require "digest"
require "json"
require "net/http"
require "tempfile"
require "uri"

# Talks to the Drive API. Knows nothing about imports, blobs or users: it
# fetches metadata and streams bytes, and raises one of two errors so the job
# can decide whether to retry.
#
# Downloads follow at most one redirect, and only to a Google host, because a
# redirect is the one part of this exchange Campsend does not choose.
class GoogleDrive::Client
  class PermanentError < StandardError; end
  class TransientError < StandardError; end

  NETWORK_ERRORS = [ Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNRESET ].freeze
  API = "https://www.googleapis.com/drive/v3/files".freeze
  METADATA_FIELDS = "id,name,size,mimeType,md5Checksum,capabilities(canDownload)".freeze
  TRUSTED_DOWNLOAD_HOST = "content.googleapis.com".freeze
  TRUSTED_DOWNLOAD_SUFFIX = ".googleusercontent.com".freeze

  def metadata(file_id, token:, resource_key: nil)
    uri = URI("#{API}/#{file_id}")
    uri.query = URI.encode_www_form(fields: METADATA_FIELDS, supportsAllDrives: true)
    JSON.parse(request(uri, token:, resource_key:).body)
  rescue JSON::ParserError
    raise TransientError, "Google Drive returned an invalid response"
  end

  def download(file_id, token:, resource_key: nil, &block)
    uri = URI("#{API}/#{file_id}")
    uri.query = URI.encode_www_form(alt: "media", supportsAllDrives: true)
    stream(uri, token:, resource_key:, &block)
  end

  private
    def request(uri, token:, resource_key: nil)
      perform(uri, token:, resource_key:).tap { |response| raise_for_status!(response) }
    end

    def stream(uri, token:, resource_key:, redirects: 0, &block)
      perform(uri, token:, resource_key:, stream: true) do |response|
        if response.is_a?(Net::HTTPRedirection)
          return stream(*follow(uri, response, redirects), &block)
        end

        raise_for_status!(response)
        response.read_body(&block)
      end
    end

    # Returns the arguments for the next stream call. The token is dropped,
    # because a redirect target is not the host it was issued for.
    def follow(uri, response, redirects)
      raise PermanentError, "Google Drive returned too many redirects." if redirects >= 1

      location = response["location"]
      raise PermanentError, "Google Drive returned an invalid download location." if location.blank?

      redirected = URI.join(uri, location)
      unless redirected.scheme == "https" && trusted_download_host?(redirected.host)
        raise PermanentError, "Google Drive returned an unsafe download location."
      end

      [ redirected, { token: nil, resource_key: nil, redirects: redirects + 1 } ]
    end

    def perform(uri, token:, resource_key:, stream: false)
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{token}" if token
      request["X-Goog-Drive-Resource-Keys"] = resource_key_header(uri, resource_key) if resource_key

      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 60) do |http|
        stream ? http.request(request) { |response| yield response } : http.request(request)
      end
    end

    def raise_for_status!(response)
      case response
      when Net::HTTPSuccess
        nil
      when Net::HTTPTooManyRequests, Net::HTTPServerError
        raise TransientError, "Google Drive is temporarily unavailable"
      when Net::HTTPUnauthorized
        raise PermanentError, "Google access expired. Open Drive and try again."
      when Net::HTTPForbidden
        raise PermanentError, "Google Drive doesn't allow this file to be downloaded."
      when Net::HTTPNotFound
        raise PermanentError, "This Google Drive file is no longer available."
      else
        raise PermanentError, "Google Drive couldn't import this file."
      end
    end

    def resource_key_header(uri, resource_key)
      "#{uri.path.split("/").last}/#{resource_key}"
    end

    def trusted_download_host?(host)
      host == TRUSTED_DOWNLOAD_HOST || host&.end_with?(TRUSTED_DOWNLOAD_SUFFIX)
    end
end
