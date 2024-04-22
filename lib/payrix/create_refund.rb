require 'net/http'
require 'uri'
require 'json'

require_relative '../payrix'

module Payrix
  class CreateRefund
    private

    attr_reader :post_refund

    def initialize(
      post_refund: lambda do |endpoint:, api_key:, params:, timeout_ms:|
        body = params.to_json
        headers = {
          'Content-Type' => 'application/json',
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
      @post_refund = post_refund
    end

    public

    Result = Struct.new(:success?, :error_message, :response, :data, keyword_init: true)

    def call(entry_id:, amount:, description: nil, api_key:, env: :test, timeout_ms: 5000)
      params = {
        entry: entry_id,
        amount: amount
      }
      params[:description] = description if description
      endpoint = self.class.endpoint(env: env)

      api_response = post_refund.call(
        params: params,
        api_key: api_key,
        timeout_ms: timeout_ms,
        endpoint: endpoint
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

    def self.api_key(credentials: Rails.application.credentials)
      credentials.payrix[:api_key][:test]
    end

    def self.endpoint(env:)
      if %i[production staging].include?(env)
        'https://api.payrix.com/refunds'
      else
        'https://test-api.payrix.com/refunds'
      end
    end
  end
end
