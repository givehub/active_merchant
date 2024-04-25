require_relative '../../../payrix/create_transaction'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class PayrixGateway < Gateway
      self.test_url = 'https://test-api.payrix.com'
      self.live_url = 'https://api.payrix.com'

      self.supported_countries = ['US']
      self.default_currency = 'USD'
      self.supported_cardtypes = %i[visa master american_express discover diners_club]

      self.homepage_url = 'https://www.payrix.com'
      self.display_name = 'Payrix REST'

      CREDIT_CARD_CODES = {
        american_express: '1',
        visa: '2',
        master: '3',
        diners_club: '4',
        discover: '5'
      }

      def self.success_message
        'Request Successful'
      end

      def self.api_key(options:, gateway:)
        options[:api_key] || gateway.options[:api_key]
      end

      def initialize(options = {})
        requires!(options, :merchant_id, :api_key)
        super
      end

      class MapPayrixErrorCodeToActiveMerchantErrorCode
        # NOTE: standardized error codes from ActiveMerchant
        # {
        #   incorrect_number: 'incorrect_number',
        #   invalid_number: 'invalid_number',
        #   invalid_expiry_date: 'invalid_expiry_date',
        #   invalid_cvc: 'invalid_cvc',
        #   expired_card: 'expired_card',
        #   incorrect_cvc: 'incorrect_cvc',
        #   incorrect_zip: 'incorrect_zip',
        #   incorrect_address: 'incorrect_address',
        #   incorrect_pin: 'incorrect_pin',
        #   card_declined: 'card_declined',
        #   processing_error: 'processing_error',
        #   call_issuer: 'call_issuer',
        #   pickup_card: 'pick_up_card',
        #   config_error: 'config_error',
        #   test_mode_live_card: 'test_mode_live_card',
        #   unsupported_feature: 'unsupported_feature',
        #   invalid_amount: 'invalid_amount'
        # }
        def call(payrix_error_code:)
          case payrix_error_code
          when 'invalid_auth'
            PayrixGateway::STANDARD_ERROR_CODE[:config_error]
          end
        end
      end

      def purchase(
        money,
        payment,
        options = {}
      )
        params = BuildPurchaseRequestParams.new.call(money: money, payment: payment, options: options, gateway: self)
        api_key = self.class.api_key(options: options, gateway: self)
        env = test? ? :test : :production
        # TODO: purchase timeout configurable by env var? or whatever is idiomatic in ActiveMerchant
        timeout_ms = 5000

        result = Payrix::CreateTransaction.new.call(params: params, api_key: api_key, env: env, timeout_ms: timeout_ms)
        # byebug
        if result.success?
          success = true
          error_message = nil
          params = {}
          authorization = GetAuthorizationFromPurchaseResponse.new.call(response: result.api_response)
          avs = GetAvsFromPurchaseResponse.new.call(response: result.api_response)
          cvv = GetCvvFromPurchaseResponse.new.call(response: result.api_response)
          options = {
            # TODO: extract this from the response
            authorization: authorization,
            # TODO: extract this from the response
            avs_result: avs,
            # TODO: extract this from the response
            cvv_result: cvv,
            test: test?,
            error_code: error_code
          }
        else
          success = false
          # ex: "Field: , Code: 4, Severity: 3, Msg: Invalid authentication, ErrorCode: invalid_auth"
          error_message = result.error_message
          # ex: [{:code=>4, :severity=>3, :msg=>"Invalid authentication", :errorCode=>"invalid_auth"}]
          errors = result.errors
          payrix_error_code = errors.first[:errorCode]
          error_code = MapPayrixErrorCodeToActiveMerchantErrorCode.new.call(payrix_error_code: payrix_error_code)
          params = {}
          options = {
            # TODO: extract this from the response
            authorization: nil,
            # TODO: extract this from the response
            avs_result: nil,
            # TODO: extract this from the response
            cvv_result: nil,
            test: test?,
            error_code: error_code
          }
        end

        # Response docs: https://www.rubydoc.info/github/Shopify/active_merchant/ActiveMerchant/Billing/Response
        Response.new(success, error_message, params, options)
      end

      class GetAuthorizationFromPurchaseResponse
        def call(response:)
          id = response.try(:[], 'response').try(:[], 'data').first.try(:[], 'id')
          total = response.try(:[], 'response').try(:[], 'data').first.try(:[], 'total')

          return '|' if id.blank? && total.blank?
          return "#{id}|" if total.blank?

          [id, total].join('|')
        end
      end

      class GetAvsFromPurchaseResponse
        def call(response:)
          code = response.try(:[], 'response').try(:[], 'data').first.try(:[], 'avsResponse')
          message = response.try(:[], 'response').try(:[], 'data').first.try(:[], 'avsResponseMessage')
          postal_match = response.try(:[], 'response').try(:[], 'data').first.try(:[], 'avsPostalMatch')
          street_match = response.try(:[], 'response').try(:[], 'data').first.try(:[], 'avsStreetMatch')

          AVSResult.new(code: code, message: message, postal_match: postal_match, street_match: street_match)
        end
      end

      class GetCvvFromPurchaseResponse
        def call(response:)
          code = response.try(:[], 'response').try(:[], 'data').first.try(:[], 'cvvResponse')
          message = response.try(:[], 'response').try(:[], 'data').first.try(:[], 'cvvResponseMessage')

          CVVResult.new(code: code, message: message)
        end
      end

      class BuildPurchaseRequestParams
        def call(gateway:, money:, payment:, options:)
          params = {}
          self.class.add_merchant!(params: params, options: options)
          self.class.add_payment!(params: params, payment: payment)
          self.class.add_invoice!(params: params, money: money, options: options, gateway: gateway)
          self.class.add_transaction_details!(params: params, options: options)
          params
        end

        def self.add_customer_data!(params:, options:); end

        def self.add_address!(params:, creditcard:, options:); end

        def self.add_merchant!(params:, options:)
          params[:merchant] = options[:merchant_id]
        end

        def self.add_payment!(params:, payment:)
          params[:payment] = {
            method: CREDIT_CARD_CODES[:"#{payment.brand}"],
            number: payment.number,
            cvv: payment.verification_value
          }
        end

        def self.add_invoice!(params:, money:, options:, gateway:)
          params[:total] = gateway.send(:amount, money)
          params[:currency] = (options[:currency] || gateway.send(:currency, money))
        end

        def self.add_transaction_details!(params:, options:)
          params[:type] = options[:type]
          params[:origin] = options[:origin]
          params[:expiration] = options[:expiration]
        end
      end

      def authorize(money, payment, options = {})
        commit('txns', post)
      end

      def capture(money, authorization, options = {})
        commit('txns', post)
      end

      def refund(money, authorization, options = {})
        commit('txns', post)
      end

      def void(authorization, options = {})
        commit('void', post)
      end

      def verify(credit_card, options = {})
        MultiResponse.run(:use_first_response) do |r|
          r.process { authorize(100, credit_card, options) }
          r.process(:ignore_result) { void(r.authorization, options) }
        end
      end

      def supports_scrubbing?
        # TODO: change this to true? We need to support scrubbing no matter what, right?
        false
      end

      def scrub(transcript)
        # transcript.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?').
        #  gsub(/(\\?"number\\?":\\?")\d+/, '\1[FILTERED]').
        #  gsub(/(\\?"cvv\\?":\\?")\d+/, '\1[FILTERED]').
        #  gsub(/(\\?"method\\?":\\?")\d+/, '\1[FILTERED]').
        #  gsub(/(\\?"Apikey\\?":\\?")\d+/, '\1[FILTERED]')
      end

      private

      def parse(body)
        JSON.parse(body)
      end

      def commit(action, parameters, options = {})
        url = (test? ? test_url : live_url)
        endpoint = url + '/' + action
        response = parse(ssl_post(endpoint, parameters.to_json, auth_headers(options)))

        Response.new(
          success_from(response),
          message_from(response),
          response,
          authorization: authorization_from(response),
          avs_result: GetAvsFromPurchaseResponse.new.call(response: response),
          cvv_result: GetCvvFromPurchaseResponse.new.call(response: response),
          test: test?,
          error_code: error_code_from(response)
        )
      end

      def auth_headers(options)
        {
          'Content-Type' => 'application/json',
          'APIKEY' => self.class.api_key(gateway: self, options: options)
        }
      end

      def success_from(response)
        response['response']['errors'].empty? ? true : false
      end

      def message_from(response)
        return self.success_message if success_from(response)
      end

      def error_code_from(response)
        response['response']['errors'].first['errorCode'] unless success_from(response)
      end
    end
  end
end
