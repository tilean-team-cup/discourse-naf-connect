# frozen_string_literal: true

# name: discourse-naf-connect
# about: Collega l'account NAF al profilo Discourse e sincronizza il nome coach
# version: 0.1.0
# authors: Tilea Forum
# url: https://forum.tilea.net

after_initialize do
  module ::NafConnect
    NAF_BASE = "https://member.thenaf.net"

    def self.exchange_code(code, redirect_uri)
      client_id     = SiteSetting.oauth2_client_id
      client_secret = SiteSetting.oauth2_client_secret

      uri  = URI("#{NAF_BASE}/index.php?module=NAF&type=token")
      http = build_http(uri)
      req  = Net::HTTP::Post.new(uri)
      req.basic_auth(client_id, client_secret)
      req.set_form_data(
        grant_type:    "authorization_code",
        code:          code,
        redirect_uri:  redirect_uri,
        client_id:     client_id,
        client_secret: client_secret
      )
      JSON.parse(http.request(req).body)
    end

    def self.get_user_info(access_token)
      uri  = URI("#{NAF_BASE}/index.php?module=NAF&type=oauthendpoint")
      http = build_http(uri)
      req  = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Bearer #{access_token}"
      JSON.parse(http.request(req).body)
    end

    def self.sanitize_username(name)
      max = [SiteSetting.max_username_length, 20].min
      name.strip
          .gsub(/[^a-zA-Z0-9_\-\.]/, "_")
          .gsub(/__+/, "_")
          .gsub(/\A[_\-\.]+|[_\-\.]+\z/, "")
          .slice(0, max)
    end

    def self.build_http(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = true
      http.open_timeout = 10
      http.read_timeout = 10
      http
    end
  end

  class ::NafConnectController < ::ApplicationController
    requires_login

    # Chiamato via AJAX: salva lo state in sessione e restituisce l'URL NAF
    # Il JS poi naviga direttamente verso il dominio esterno (Ember non intercetta)
    def auth_url
      state = SecureRandom.hex(24)
      session[:naf_state] = state

      query = {
        client_id:     SiteSetting.oauth2_client_id,
        redirect_uri:  callback_url,
        response_type: "code",
        state:         state
      }.map { |k, v| "#{k}=#{ERB::Util.url_encode(v)}" }.join("&")

      render json: { url: "#{NafConnect::NAF_BASE}/index.php?module=NAF&type=oauth&#{query}" }
    end

    def callback
      return redirect_with_error("Errore di sicurezza: state non valido.") \
        if params[:state].blank? || params[:state] != session.delete(:naf_state)

      return redirect_with_error("Nessun codice ricevuto da NAF.") \
        if params[:code].blank?

      token = NafConnect.exchange_code(params[:code], callback_url)
      return redirect_with_error("Impossibile ottenere il token da NAF.") \
        unless token["access_token"]

      naf_user = NafConnect.get_user_info(token["access_token"])
      return redirect_with_error("Impossibile recuperare i dati utente da NAF.") \
        unless naf_user["id"] && naf_user["name"]

      naf_id   = naf_user["id"].to_s
      naf_name = naf_user["name"].to_s.strip

      # Impedisce di collegare un account NAF già usato da un altro utente Discourse
      existing = UserAssociatedAccount.find_by(provider_name: "oauth2_basic", provider_uid: naf_id)
      return redirect_with_error("Questo account NAF è già collegato a un altro utente.") \
        if existing && existing.user_id != current_user.id

      UserAssociatedAccount.find_or_initialize_by(
        provider_name: "oauth2_basic",
        provider_uid:  naf_id
      ).tap do |a|
        a.user      = current_user
        a.last_used = Time.now
        a.info      = { "name" => naf_name, "nickname" => naf_name }
        a.save!
      end

      # Aggiorna il nome visualizzato
      current_user.update!(name: naf_name) if naf_name != current_user.name

      # Aggiorna l'username se possibile (il nome NAF fa fede)
      new_username = NafConnect.sanitize_username(naf_name)
      if new_username.length >= SiteSetting.min_username_length && new_username != current_user.username
        begin
          UsernameChanger.change(current_user, new_username, current_user)
          current_user.reload
        rescue => e
          Rails.logger.warn("NafConnect: impossibile cambiare username in '#{new_username}': #{e.message}")
        end
      end

      flash[:notice] = "Account NAF collegato! Benvenuto, #{naf_name}."
      redirect_to "/u/#{current_user.username}/preferences/account"
    end

    def status
      assoc = UserAssociatedAccount.find_by(provider_name: "oauth2_basic", user_id: current_user.id)
      if assoc
        render json: { connected: true, naf_id: assoc.provider_uid, naf_name: assoc.info&.dig("name") }
      else
        render json: { connected: false }
      end
    end

    def disconnect
      UserAssociatedAccount
        .find_by(provider_name: "oauth2_basic", user_id: current_user.id)
        &.destroy!
      render json: { success: true }
    end

    private

    def callback_url
      "#{Discourse.base_url}/naf/callback"
    end

    def redirect_with_error(msg)
      flash[:error] = msg
      redirect_to "/u/#{current_user.username}/preferences/account"
    end
  end

  # Espone naf_id e naf_name nel serializer utente (profilo pubblico)
  add_to_serializer(:user, :naf_id) do
    UserAssociatedAccount
      .find_by(provider_name: "oauth2_basic", user_id: object.id)
      &.provider_uid
  end

  add_to_serializer(:user, :naf_name) do
    UserAssociatedAccount
      .find_by(provider_name: "oauth2_basic", user_id: object.id)
      &.info&.dig("name")
  end

  Discourse::Application.routes.prepend do
    get    "/naf/auth_url"   => "naf_connect#auth_url"
    get    "/naf/callback"   => "naf_connect#callback"
    get    "/naf/status"     => "naf_connect#status"
    delete "/naf/disconnect" => "naf_connect#disconnect"
  end
end
