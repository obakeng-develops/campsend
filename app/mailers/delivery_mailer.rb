class DeliveryMailer < ApplicationMailer
  def files_ready
    @send = params[:send]
    @access_token = params[:access_token]
    @file_count = @send.files.count
    @sender = @send.user.email_address

    mail to: @send.recipient_email,
      from: from_with_sender,
      reply_to: @sender,
      subject: @file_count == 1 ? "Your file is ready" : "Your #{@file_count} files are ready"
  end

  private
    # The sender's address belongs in the display name and Reply-To, never in the
    # subject. A gmail.com address in the subject of a message sent from
    # campsend.app is the shape of a compromised-account phish, and mailbox
    # providers score it that way, which is how these ended up in Spam.
    #
    # Reply-To earns its place twice: a client can answer the person who sent
    # them work, and a reply is one of the strongest signals that a message was
    # wanted.
    def from_with_sender
      address = Mail::Address.new(self.class.default[:from])
      address.display_name = "#{@sender} via #{address.display_name.presence || "Campsend"}"
      address.format
    end
end
