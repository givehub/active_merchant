require 'net/http'
require 'uri'
require 'json'

require_relative '../payrix'

module Payrix
  class CreateCustomer
    private

    attr_reader :post_customer

    def initialize(
      post_customer: lambda do |endpoint:, api_key:, params:, timeout_ms:|
        body = URI.encode_www_form(params)
        headers = {
          'Content-Type' => 'application/x-www-form-urlencoded',
          'APIKEY' => api_key
        }
        uri = URI.parse(endpoint)
        request = Net::HTTP::Post.new(uri, headers)
        request.body = body
        timeout = timeout_ms / 1000

        response = Net::HTTP.start(uri.hostname, uri.port,
                                   use_ssl: uri.scheme == 'https',
                                   open_timeout: timeout,
                                   write_timeout: timeout,
                                   read_timeout: timeout) do |http|
          http.request(request)
        end
        body = response.body

        JSON.parse(body, symbolize_names: true)
      end
    )
      @post_customer = post_customer
    end

    public

    Result = Struct.new(:success?, :error_message, :response, :data, keyword_init: true)

    def call(api_key:, params:, env: :test, timeout_ms: 5000)
      endpoint = self.class.endpoint(env: env)

      api_response = post_customer.call(
        params: params,
        api_key: api_key,
        endpoint: endpoint,
        timeout_ms: timeout_ms
      )
      errors = api_response[:errors] || api_response.dig(:response, :errors)

      if errors.blank?
        data = api_response.dig(:response, :data)

        Result.new(success?: true, response: api_response, data: data)
      else
        error_message = errors.map do |error|
          "#{error[:field]}: #{error[:msg]}"
        end.join(', ')

        Result.new(success?: false, error_message: error_message)
      end
    rescue JSON::ParserError => e
      Result.new(success?: false, error_message: "Failed to parse JSON: #{e.message}")
    rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout => e
      Result.new(success?: false, error_message: "Request timed out: #{e.message}")
    end

    def self.endpoint(env:)
      if %i[production staging].include?(env)
        'https://api.payrix.com/customers'
      else
        'https://test-api.payrix.com/customers'
      end
    end
  end
end
