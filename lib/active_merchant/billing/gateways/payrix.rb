module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class PayrixGateway < Gateway
      self.test_url = 'https://test-api.payrix.com'
      self.live_url = 'https://api.payrix.com'

      self.supported_countries = ['AU', 'GB', 'NZ', 'US']
      self.default_currency = 'USD'
      self.supported_cardtypes = %i[visa master american_express discover diners_club]

      self.homepage_url = 'https://www.payrix.com'
      self.display_name = 'Payrix REST'

      TXNS_TYPE = {
        cc_only_sale: '1',
        cc_only_auth: '2',
        cc_only_capture: '3',
        cc_only_reverse_auth: '4',
        cc_only_refund: '5'
      }

      TXNS_ORIGIN = {
        credit_card_terminal: '1',
        ecommerce_system: '2',
        mail_or_telephone_order: '3',
        successful_3dsecure: '5',
        attempted_3dsecure: '6',
        recurring: '7'
      }

      CREDIT_CARD_CODES = {
        american_express: '1',
        visa: '2',
        master: '3',
        diners_club: '4',
        discover: '5'
      }

      STANDARD_ERROR_CODE = {
        invalid_card_number: 'invalid_card_number'
      }

      def initialize(options = {})
        requires!(options, :merchant_id, :api_key)
        super
      end

      def purchase(money, payment, options = {})
        post = build_purchase_request(money, payment, options)

        commit('txns', post, options)
      end

      def authorize(money, payment, options = {})
        commit('txns', post)
      end

      def capture(money, authorization, options = {})
        commit('txns', post)
      end

      def refund(money, authorization, options = {})
        post = build_refund_request(money, authorization, options)

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
        false
      end

      def scrub(transcript)
        #transcript.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?').
        #  gsub(/(\\?"number\\?":\\?")\d+/, '\1[FILTERED]').
        #  gsub(/(\\?"cvv\\?":\\?")\d+/, '\1[FILTERED]').
        #  gsub(/(\\?"method\\?":\\?")\d+/, '\1[FILTERED]').
        #  gsub(/(\\?"Apikey\\?":\\?")\d+/, '\1[FILTERED]')
      end

      private

      def build_refund_request(money, authorization, options)
        transaction_id = authorization.split('|').first
        post = {}
        post[:fortxn] = transaction_id
        post[:total] = amount(money)
        post[:type] = TXNS_TYPE[:cc_only_refund]
        post
      end

      def build_purchase_request(money, payment, options)
        post = {}
        add_merchant(post, options)
        add_payment(post, payment)
        add_invoice(post, money, options)
        add_address(post, options)
        add_adjustments(post, options)
        add_customer_data(post, options)
        add_transaction_details(post, options)
        post
      end

      def add_adjustments(post, options)
        post[:fee] = options[:fee]
        post[:discount] = options[:discount]
        post[:tax] = options[:tax]
        post[:surcharge] = options[:surcharge]
        post[:shipping] = options[:shipping]
        post[:duty] = options[:duty]
      end

      def add_customer_data(post, options)
        post[:phone] = options[:phone]
        post[:clientIp] = options[:clientIp]
        post[:email] = options[:email]
        post[:first] = options[:first]
        post[:middle] = options[:middle]
        post[:last] = options[:last]
        post[:company] = options[:company]
      end

      def add_address(post, options)
        post[:address1] = options[:address1]
        post[:address2] = options[:address2]
        post[:city] = options[:city]
        post[:state] = options[:state]
        post[:zip] = options[:zip]
        post[:country] = options[:country]
      end

      def add_merchant(post, options)
        post[:merchant] = options[:merchant_id] || @options[:merchant_id]
      end

      def add_payment(post, payment)
        post[:payment] = {
          method: CREDIT_CARD_CODES[:"#{payment.brand}"],
          number: payment.number,
          cvv: payment.verification_value
        }
      end

      def add_invoice(post, money, options)
        post[:total] = amount(money)
        post[:currency] = (options[:currency] || currency(money))
        post[:order] = options[:order]
      end

      def add_transaction_details(post, options)
        post[:type] = options[:type] || @options[:type]
        post[:origin] = options[:origin] || @options[:origin]
        post[:expiration] = options[:expiration] || @options[:expiration]
        post[:description] = options[:description]
        post[:fundingCurrency] = options[:fundingCurrency]
        post[:cofType] = options[:cofType]
      end

      def parse(body)
        JSON.parse(body)
      end

      def commit(action, parameters, options={})
        url = (test? ? test_url : live_url)
        endpoint = url + '/' + action
        response = parse(ssl_post(endpoint, parameters.to_json, auth_headers(options)))

        Response.new(
          success_from(response),
          message_from(response),
          response,
          authorization: authorization_from(response),
          avs_result: nil,
          cvv_result: CVVResult.new(response.try(:[], "response").try(:[], "data").first.try(:[], "cvvStatus")),
          test: test?,
          error_code: error_code_from(response)
        )
      end

      def auth_headers(options)
        {
          'Content-Type' => 'application/json',
          'APIKEY' => options[:api_key] || @options[:api_key]
        }
      end

      def success_from(response)
        response["response"]["errors"].empty? ? true : false
      end

      def message_from(response)
        return "Request Successful" if success_from(response)

        response.try(:[], "response").try(:[], "errors").first.try(:[], "msg")
      end

      def authorization_from(response)
        _id = response.try(:[], "response").try(:[], "data").first.try(:[], "id")
        _total = response.try(:[], "response").try(:[], "data").first.try(:[], "total")

        return '|' if _id.blank? && _total.blank?
        return "#{_id}|" if _total.blank?

        [_id, _total].join('|')
      end

      def error_code_from(response)
        unless success_from(response)
          response.try(:[], "response").try(:[], "errors").first.try(:[], "errorCode")
        end
      end
    end
  end
end
