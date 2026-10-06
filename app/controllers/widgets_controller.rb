# TODO : Delete this and associated spec once 'api/widget/config' end point is merged
class WidgetsController < ActionController::Base
  include WidgetHelper

  before_action :set_global_config
  before_action :set_web_widget
  before_action :ensure_account_is_active
  before_action :skip_crawler_requests
  before_action :ensure_location_is_supported
  before_action :identify_contact_from_link, if: -> { permitted_params[:identifier].present? }
  before_action :set_token
  before_action :set_contact
  before_action :build_contact
  after_action :allow_iframe_requests

  private

  def set_global_config
    @global_config = GlobalConfig.get(
      'LOGO_THUMBNAIL',
      'BRAND_NAME',
      'WIDGET_BRAND_URL',
      'DIRECT_UPLOADS_ENABLED',
      'MAXIMUM_FILE_UPLOAD_SIZE',
      'INSTALLATION_NAME'
    )
  end

  def set_web_widget
    @web_widget = ::Channel::WebWidget.find_by!(website_token: permitted_params[:website_token])
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error('web widget does not exist')
    render json: { error: 'web widget does not exist' }, status: :not_found
  end

  # Redirect drops identifier params, which the widget would otherwise append to every API call
  def identify_contact_from_link
    identifier = permitted_params[:identifier]
    unless @web_widget.valid_identifier_hash?(identifier, permitted_params[:identifier_hash])
      return render json: { error: 'HMAC failed: Invalid Identifier Hash Provided' }, status: :unauthorized
    end

    contact_inbox = @web_widget.inbox.contact_inboxes.joins(:contact).find_by(hmac_verified: true, contacts: { identifier: identifier })
    contact_inbox ||= create_identified_contact_inbox(identifier)

    token = ::Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: @web_widget.inbox.id }).generate_token
    redirect_to widget_path(website_token: @web_widget.website_token, cw_conversation: token, locale: permitted_params[:locale].presence)
  end

  def create_identified_contact_inbox(identifier)
    contact_inbox, = build_contact_inbox_with_token(@web_widget, additional_attributes)
    contact_inbox.update!(hmac_verified: true)
    ContactIdentifyAction.new(
      contact: contact_inbox.contact,
      params: { identifier: identifier, phone_number: "+#{identifier}" },
      discard_invalid_attrs: true
    ).perform
    contact_inbox
  end

  def set_token
    @token = permitted_params[:cw_conversation]
    @auth_token_params = if @token.present?
                           ::Widget::TokenService.new(token: @token).decode_token
                         else
                           {}
                         end
  end

  def set_contact
    return if @auth_token_params[:source_id].nil?

    @contact_inbox = ::ContactInbox.find_by(
      inbox_id: @web_widget.inbox.id,
      source_id: @auth_token_params[:source_id]
    )

    @contact = @contact_inbox&.contact
  end

  def build_contact
    return if @contact.present?

    @contact_inbox, @token = build_contact_inbox_with_token(@web_widget, additional_attributes)
    @contact = @contact_inbox.contact
  end

  def ensure_account_is_active
    render json: { error: 'Account is suspended' }, status: :unauthorized unless @web_widget.inbox.account.active?
  end

  def skip_crawler_requests
    # A missing user agent alone does not identify a crawler.
    return unless request.user_agent.present? && browser.bot?

    response.headers['X-Robots-Tag'] = 'noindex'
    head :no_content
  end

  def ensure_location_is_supported; end

  def additional_attributes
    if @web_widget.inbox.account.feature_enabled?('ip_lookup')
      { created_at_ip: request.remote_ip }
    else
      {}
    end
  end

  def permitted_params
    params.permit(:website_token, :cw_conversation, :identifier, :identifier_hash, :locale)
  end

  def allow_iframe_requests
    if @web_widget.allowed_domains.blank? || embedded_from_non_web_origin?
      response.headers.delete('X-Frame-Options')
    else
      domains = @web_widget.allowed_domains.split(',').map(&:strip).join(' ')
      response.headers['Content-Security-Policy'] = "frame-ancestors #{domains}"
    end
  end

  # Mobile WebViews (iOS/Android) load content from file:// or null origins,
  # which cannot match any domain in frame-ancestors. When the per-inbox flag
  # is enabled, skip frame-ancestors for these requests.
  def embedded_from_non_web_origin?
    return false unless @web_widget.allow_mobile_webview?

    origin = request.headers['Origin']
    origin.blank? || origin == 'null' || origin&.start_with?('file://')
  end
end

WidgetsController.prepend_mod_with('WidgetsController')
