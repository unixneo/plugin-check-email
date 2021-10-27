# frozen_string_literal: true
# name: plugin-check-email
# about:  Check disposable emails on sign up against the free API provided by kickbox.com
# version: 0.0.28
# authors: Terrapop, Neo
# url: https://github.com/unixneo/plugin-check-email.git

require 'net/http'
require 'json'
require 'logger'

enabled_site_setting :plugin_check_email_enabled

after_initialize do
  module ::DiscoursePluginCheckEmail

    class EmailValidator < ActiveModel::EachValidator

        def validate_each(record, attribute, value)
            return unless value.present?
            return unless defined? record.id
            return unless record.password_validation_required?
            return unless record.should_validate_email_address?
            if email_checker(value)
                record.errors.add(attribute, I18n.t(:'user.email.not_allowed'))
            end
        end

        def valid_json?(json)
              result = JSON.parse(json)
              result.is_a?(Hash) || result.is_a?(Array)
            rescue JSON::ParserError, TypeError
              return false
        end

        def email_checker(email)
          if ENV["RAILS_ENV"] == "production"
            tmp_file = "/shared/log/plugin-check-email.log"
          else
            tmp_file = "#{Rails.root}/plugin-check-email.log"
          end

         

            uri = URI(SiteSetting.plugin_check_email_api_url+email)
            response = Net::HTTP.get(uri)
            if valid_json?(response)
                parsed_json = JSON.parse(response)
                if parsed_json['disposable'].nil?
                    @email_logger.warn("Check email plugin: Json response does not contain key 'disposable'")
                    return false
                else
                  if SiteSetting.plugin_check_email_debug_log
                    out_text = "A. plugin-check-email: #{email} disposable: #{parsed_json['disposable']} #{Time.now}\n"
                    IO.write(tmp_file, out_text, mode:"a")
                  end
                    @email_logger.info("Check email plugin: user email disposable: #{parsed_json['disposable']}.")
                    return parsed_json['disposable']
                end
            else
                @email_logger.warn("Check email plugin: No valid json response, check your API endpoint")
                return false
            end
        end
    end

    class ::User
      validate :plugin_check_email
      def plugin_check_email
        @email_logger = Logger.new('plugin-check-email-rails.log')
        DiscoursePluginCheckEmail::EmailValidator.new(attributes: :email).validate_each(self, :email, email)
      end
    end
  end
end
