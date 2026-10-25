class Channels::Voip::RecordingDownloadJob < ApplicationJob
  queue_as :default

  def perform(message)
    client = Voip::Client.new
    file = Down.download(client.recording_url(message.source_id), headers: client.headers)
    message.attachments.create!(
      account_id: message.account_id,
      file_type: :audio,
      file: { io: file, filename: file.original_filename, content_type: file.content_type },
      meta: { 'transcribed_text' => message.call_data['transcript'] }.compact
    )
    message.reload.send_update_event
  end
end
