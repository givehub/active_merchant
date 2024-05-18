module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class PayrixGateway < Gateway
      self.test_url = 'https://test-api.payrix.com'
      self.live_url = 'https://api.payrix.com'

      self.supported_countries = %w[AU GB NZ US]
      self.default_currency = 'USD'
      self.supported_cardtypes = %i[visa master american_express discover diners_club]

      self.homepage_url = 'https://www.payrix.com'
      self.display_name = 'Payrix REST'

      TXNS_TYPE = {
        cc_only_sale: '1',
        cc_only_auth: '2',
        cc_only_capture: '3',
        cc_only_reverse_auth: '4',
        cc_only_refund: '5',
        echeck_only_refund: '8'
      }

      TXNS_ORIGIN = {
        credit_card_terminal: '1',
        ecommerce_system: '2',
        mail_or_telephone_order: '3',
        successful_3dsecure: '5',
        attempted_3dsecure: '6',
        recurring: '7'
      }

      TXNS_ALLOW_PARTIAL = {
        partial_amount_authorizations_not_allowed: '0',
        partial_amount_authorizations_allowed: '1'
      }

      CREDIT_CARD_CODES = {
        american_express: '1',
        visa: '2',
        master: '3',
        diners_club: '4',
        discover: '5'
      }

      TXNS_UNAUTH_REASONS = {
        incomplete: 'incomplete',
        timeout: 'timeout',
        clerk_cancelled: 'clerkCancelled',
        customer_cancelled: 'customerCancelled',
        misdispense: 'misdispense',
        hardware_failure: 'hardwareFailure',
        suspected_fraud: 'suspectedFraud'
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
        invalid_card_number: 'invalid_card_number',
        invalid_refund: 'invalid_refund',
        invalid_reverse_auth: 'invalid_reverse_auth',
        invalid_capture: 'invalid_capture'
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
        true
      end

      def scrub(transcript)
        transcript.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?').
          gsub(/(\\?"number\\?":\\?")\d+/, '\1[FILTERED]').
          gsub(/(\\?"cvv\\?":\\?")\d+/, '\1[FILTERED]').
          gsub(/(\\?"method\\?":\\?")\d+/, '\1[FILTERED]').
          gsub(/(Apikey:)\s\w+/, '\1 [FILTERED]')
      end

      private

      def build_void_request(authorized_transaction_id, options)
        {}.tap do |post|
          post[:fortxn] = authorized_transaction_id
          post[:type] = TXNS_TYPE[:cc_only_reverse_auth]
        end.compact
      end

      def build_authorize_request(money, payment, options)
        {}.tap do |post|
          post.merge!(build_purchase_request(money, payment, options))
          post[:type] = TXNS_TYPE[:cc_only_auth]
        end.compact
      end

      def build_capture_request(money, authorized_transaction_id, options)
        {}.tap do |post|
          post.merge!(build_purchase_request(money, nil, options))
          post[:type] = TXNS_TYPE[:cc_only_capture]
          post[:fortxn] = authorized_transaction_id
        end.compact
      end

      def build_refund_request(money, authorized_transaction_id, options)
        {}.tap do |post|
          post[:fortxn] = authorized_transaction_id
          post[:total] = money if money
          post[:type] = TXNS_TYPE[:cc_only_refund]

          if options[:type] == TXNS_TYPE[:echeck_only_refund]
            post[:type] = TXNS_TYPE[:echeck_only_refund]
            post[:first] = options[:first_name]
          end
        end.compact
      end

      def build_purchase_request(money, payment, options)
        {}.tap do |post|
          add_merchant(post, options)
          add_payment(post, payment) if payment
          add_invoice(post, money, options)
          add_address(post, options)
          add_adjustments(post, options)
          add_customer_data(post, options)
          add_transaction_details(post, options)
        end.compact
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
        post[:clientIp] = options[:ip]
        post[:email] = scrub_email(options[:email])
        post[:first] = options[:first_name]
        post[:middle] = options[:middle_name]
        post[:last] = options[:last_name]
        post[:company] = options[:company]
      end

      def add_address(post, options)
        post[:address1] = truncate(options[:address1], ADDRESS_MAX_SIZE)
        post[:address2] = truncate(options[:address2], ADDRESS_MAX_SIZE)
        post[:city] = truncate(options[:city], ADDRESS_MAX_SIZE)
        post[:state] = truncate(options[:state], STATE_MAX_SIZE)
        post[:zip] = truncate(scrub_zip(options[:zip]), ZIP_MAX_SIZE)
        post[:country] = country_code(options[:country])
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
        post[:expiration] = expiration_date(payment)
      end

      def add_invoice(post, money, options)
        post[:total] = money
        post[:currency] = options[:currency] || default_currency
        post[:order] = truncate(options[:order_id], ORDER_MAX_SIZE)
      end

      def add_transaction_details(post, options)
        post[:type] = TXNS_TYPE[:cc_only_sale]
        post[:origin] = TXNS_ORIGIN[:ecommerce_system]
        post[:description] = truncate(options[:description], DESCRIPTION_MAX_SIZE)
        post[:fundingCurrency] = options[:fundingCurrency]
        post[:cofType] = options[:cofType]
        post[:allowPartial] = options[:allowPartial] || TXNS_ALLOW_PARTIAL[:partial_amount_authorizations_not_allowed]
      end

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
          test: test?,
          error_code: error_code_from(response)
        )
      rescue ActiveMerchant::ResponseError => e
        response = e.response.body.present? ? parse(e.response.body) : { 'response' => { 'data' => [], 'errors' => [{ 'msg' => e.response.msg }] } }
        message = e.response.msg
        Response.new(false, message, response, test: test?)
      end

      def auth_headers(options)
        {
          'Content-Type' => 'application/json',
          'APIKEY' => options[:api_key] || @options[:api_key]
        }
      end

      def success_from(response)
        response['response']['errors'].empty? ? true : false
      end

      def message_from(response)
        if success_from(response)
          response_status_code = response.try(:[], 'response').try(:[], 'data').first.try(:[], 'status')
          response_status_code.nil? ? 'Request Successful' : TXNS_RESPONSE_STATUS[:"#{response_status_code}"]
        else
          response.try(:[], 'response').try(:[], 'errors').first.try(:[], 'msg')
        end
      end

      def authorization_from(response)
        response.try(:[], 'response').try(:[], 'data').first.try(:[], 'id')
      end

      def error_code_from(response)
        response.try(:[], 'response').try(:[], 'errors').first.try(:[], 'errorCode') unless success_from(response)
      end

      def scrub_email(email)
        return nil unless email.present?
        return nil if email !~ /^.+@[^\.]+(\.[^\.]+)+[a-z]$/i || email =~ /\.(con|met)$/i

        email
      end

      def scrub_zip(zip)
        return nil unless zip.present?
        return nil if zip.gsub(/[^a-z0-9]/i, '').length > 9 || zip =~ /[^a-z0-9\- ]/i

        zip
      end

      def country_code(country)
        if country
          country = ActiveMerchant::Country.find(country)
          country.code(:alpha3).value
        end
      rescue InvalidCountryCodeError
        nil
      end

      def expiration_date(payment_method)
        yy = format(payment_method.year, :two_digits)
        mm = format(payment_method.month, :two_digits)
        mm + yy
      end
    end
  end
end
