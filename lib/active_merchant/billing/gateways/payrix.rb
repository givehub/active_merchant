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

      TXNS_RESPONSE_STATUS = {
        '0': 'Pending',
        '1': 'Approved',
        '2': 'Failed',
        '3': 'Captured',
        '4': 'Settled',
        '5': 'Returned'
      }

      STANDARD_ERROR_CODE = {
        invalid_card_number: 'invalid_card_number'
      }

      ADDRESS_MAX_SIZE = 500
      STATE_MAX_SIZE = 100
      ZIP_MAX_SIZE = 20
      PHONE_MAX_SIZE = 15
      DESCRIPTION_MAX_SIZE = 1000
      ORDER_MAX_SIZE = 1000

      def initialize(options = {})
        requires!(options, :merchant_id, :api_key)
        super
      end

      def purchase(money, payment, options = {})
        post = build_purchase_request(money, payment, options)

        commit('txns', post, options)
      end

      def authorize(money, payment, options = {})
        post = build_authorize_request(money, payment, options)

        commit('txns', post, options)
      end

      def capture(money, authorization, options = {})
        post = build_capture_request(money, authorization, options)

        commit('txns', post, options)
      end

      def refund(money, authorization, options = {})
        post = build_refund_request(money, authorization, options)

        commit('txns', post, options)
      end

      def void(authorization, options = {})
        post = build_void_request(authorization, options)

        commit('txns', post, options)
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

      def build_void_request(authorization, options)
        transaction_id = authorization.split('|').first

        post = {
          fortxn: transaction_id,
          type: TXNS_TYPE[:cc_only_reverse_auth]
        }

        post
      end

      def build_authorize_request(money, payment, options)
        post = build_purchase_request(money, payment, options)
        post[:type] = TXNS_TYPE[:cc_only_auth]
        post
      end

      def build_capture_request(money, authorization, options)
        transaction_id = authorization.split('|').first
        post = {}
        post = build_purchase_request(money, nil, options)
        post[:type] = TXNS_TYPE[:cc_only_capture]
        post[:fortxn] = transaction_id
        post
      end

      def build_refund_request(money, authorization, options)
        transaction_id = authorization.split('|').first
        post = {}
        post[:fortxn] = transaction_id
        post[:total] = money
        post[:type] = options[:type] || TXNS_TYPE[:cc_only_refund]
        post
      end

      def build_purchase_request(money, payment, options)
        post = {}
        add_merchant(post, options)
        add_payment(post, payment) if payment
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
        post[:phone] = truncate(options[:phone], PHONE_MAX_SIZE)
        post[:clientIp] = options[:clientIp]
        post[:email] = options[:email]
        post[:first] = options[:first]
        post[:middle] = options[:middle]
        post[:last] = options[:last]
        post[:company] = options[:company]
      end

      def add_address(post, options)
        post[:address1] = truncate(options[:address1], ADDRESS_MAX_SIZE)
        post[:address2] = truncate(options[:address2], ADDRESS_MAX_SIZE)
        post[:city] = truncate(options[:city], ADDRESS_MAX_SIZE)
        post[:state] = truncate(options[:state], STATE_MAX_SIZE)
        post[:zip] = truncate(options[:zip], ZIP_MAX_SIZE)
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
        post[:total] = money
        post[:currency] = options[:currency] || default_currency
        post[:order] = truncate(options[:order], ORDER_MAX_SIZE)
      end

      def add_transaction_details(post, options)
        post[:type] = options[:type] || @options[:type]
        post[:origin] = options[:origin] || @options[:origin]
        post[:expiration] = options[:expiration] || @options[:expiration]
        post[:description] = truncate(options[:description], DESCRIPTION_MAX_SIZE)
        post[:fundingCurrency] = options[:fundingCurrency]
        post[:cofType] = options[:cofType]
        post[:allowPartial] = options[:allowPartial]
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
        if success_from(response)
          response_status_code = response.try(:[], "response").try(:[], "data").first.try(:[], "status")
          response_status_code.nil? ? 'Request Successful' : TXNS_RESPONSE_STATUS[:"#{response_status_code}"]
        else
          response.try(:[], "response").try(:[], "errors").first.try(:[], "msg")
        end
      end

      def authorization_from(response)
        _id = response.try(:[], "response").try(:[], "data").first.try(:[], "id")
        _authorized_amount = response.try(:[], "response").try(:[], "data").first.try(:[], "approved")

        return '|' if _id.blank? && _authorized_amount.blank?
        return "#{_id}|" if _authorized_amount.blank?

        [_id, _authorized_amount].join('|')
      end

      def error_code_from(response)
        unless success_from(response)
          response.try(:[], "response").try(:[], "errors").first.try(:[], "errorCode")
        end
      end
    end
  end
end
