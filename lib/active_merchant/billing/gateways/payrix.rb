module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class PayrixGateway < Gateway
      self.test_url = 'https://test-api.payrix.com/'
      self.live_url = 'https://api.payrix.com'

      self.supported_countries = ['US']
      self.default_currency = 'USD'
      self.supported_cardtypes = %i[visa master american_express discover]

      self.homepage_url = 'https://www.payrix.com/'
      self.display_name = 'Payrix REST'

      CREDIT_CARD_CODES = {
        american_express: '1',
        visa: '2',
        master: '3',
        diners_club: '4',
        discover: '5'
      }

      def initialize(options = {})
        requires!(options, :merchant_id, :api_key)
        super
      end

      def purchase(money, payment, options = {})
        post = build_purchase_request(money, payment, options)

        commit('txns', post)
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
        true
      end

      def scrub(transcript)
        transcript
      end

      private

      def build_purchase_request(money, payment, options)
        post = {}
        add_merchant(post, options)
        add_payment(post, payment)
        add_invoice(post, money, options)
        add_transaction_details(post, options)
        post
      end

      def add_customer_data(post, options); end

      def add_address(post, creditcard, options); end

      def add_merchant(post, options)
        post[:merchant] = options[:merchant_id]
      end

      def add_payment(post, payment)
        post[:payment] = {
          method: CREDIT_CARD_CODES[payment.brand],
          number: payment.number,
          cvv: payment.verification_value
        }
      end

      def add_invoice(post, money, options)
        post[:total] = amount(money)
        post[:currency] = (options[:currency] || currency(money))
      end

      def add_transaction_details(post, options)
        post[:type] = options[:type]
        post[:origin] = options[:origin]
        post[:expiration] = options[:expiration]
      end

      def parse(body)
        {}
      end

      def commit(action, parameters)
        url = (test? ? test_url : live_url)
        response = parse(ssl_post(url, post_data(action, parameters)))

        Response.new(
          success_from(response),
          message_from(response),
          response,
          authorization: authorization_from(response),
          avs_result: AVSResult.new(code: response['some_avs_response_key']),
          cvv_result: CVVResult.new(response['some_cvv_response_key']),
          test: test?,
          error_code: error_code_from(response)
        )
      end

      def success_from(response); end

      def message_from(response); end

      def authorization_from(response); end

      def post_data(action, parameters = {}); end

      def error_code_from(response)
        unless success_from(response)
          response['errors'].first['errorCode']
        end
      end
    end
  end
end
