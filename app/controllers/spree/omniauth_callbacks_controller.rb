class Spree::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  include Spree::Core::ControllerHelpers::Common
  include Spree::Core::ControllerHelpers::Order
  include Spree::Core::ControllerHelpers::Auth
  include Spree::Core::ControllerHelpers::SSL
  include Auth

  def self.provides_callback_for(*providers)
    providers.each do |provider|
      class_eval <<-FUNCTION_DEFS, __FILE__, __LINE__ + 1
        ssl_allowed :#{provider}
        def #{provider}
          if request.env["omniauth.error"].present?
            flash[:error] = I18n.t("devise.omniauth_callbacks.failure", :kind => auth_hash['provider'], :reason => Spree.t(:user_was_not_valid))
            redirect_back_or_default(root_url)
            return
          end

          authentication = Spree::UserAuthentication.find_by_provider_and_uid(auth_hash['provider'], auth_hash['uid'])

          if authentication.present?
            flash[:notice] = t("devise.omniauth_callbacks.success", :kind => auth_hash['provider'])
            sign_in_and_redirect :spree_user, authentication.user
          elsif spree_current_user
            spree_current_user.apply_omniauth(auth_hash)
            spree_current_user.save!
            flash[:notice] = t("devise.sessions.signed_in")
            redirect_back_or_default(account_url)
          else
            user = Spree::User.find_by_email(auth_hash['info']['email']) || Spree::User.new
            user.apply_omniauth(auth_hash)
            authentication = user.user_authentications.first
            user.email = "#{authentication.uid}@#{authentication.provider}.com" if user.email.blank?
            create_user_on_publisher(user) if user.new_record?
            if user.save
              user.add_tokens_from_omniauth
              flash[:notice] = I18n.t("devise.omniauth_callbacks.success", :kind => auth_hash['provider'])
              sign_in_and_redirect :spree_user, user
            else
              session[:omniauth] = auth_hash.except('extra')
              flash[:notice] = Spree.t(:one_more_step, :kind => auth_hash['provider'].capitalize)
              redirect_to new_spree_user_registration_url
              return
            end
          end

          if current_order
            user = spree_current_user || authentication.user
            current_order.associate_user!(user)
            session[:guest_token] = nil
          end
        end
      FUNCTION_DEFS
    end
  end

  SpreeSocial::OAUTH_PROVIDERS.each do |provider|
    provides_callback_for provider[1].to_sym
  end

  def failure
    set_flash_message :alert, :failure, :kind => failed_strategy.name.to_s.humanize, :reason => failure_message
    redirect_to spree.login_path
  end

  def passthru
    render :file => "#{Rails.root}/public/404", :formats => [:html], :status => 404, :layout => false
  end

  def auth_hash
    request.env["omniauth.auth"]
  end

  def current_store
    Spree::Store.first
  end

  def create_user_on_publisher(user)
    password = '12345678'
    password_confirmation = '12345678'
    url = publisher_url + "/signup"
    begin
      options = {full_name: user.full_name, email: user.email, subscribed_to_newsletter: 0, password:password, password_confirmation:password_confirmation, origin:"atbstore"}

      response =  RestClient.post(url, {account_type:"student", user:options})
      if response.code != 200
        flash[:error] = I18n.t("home.cannot_create_user")
        return
      end

      parsed_response = JSON.parse(response)
      if parsed_response["error"]
        flash[:error] = parsed_response["error"]
        return
      end

      access_token = omniauth_client.password.get_token(user.email, password)

      user[:authentication_token] = access_token.token
      user[:perishable_token] = access_token.refresh_token
    end

  end

end
