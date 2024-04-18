require 'net/http'
require 'uri'
require 'json'

require_relative '../payrix'

module Payrix
  class CreateTransaction
    private

    attr_reader :get_api_response

    def initialize(
      get_api_response: lambda do |endpoint:, api_key:, params:, timeout_ms:|
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
      @get_api_response = get_api_response
    end

    public

    Result = Struct.new(:success?, :error_message, :api_response, :data, keyword_init: true)

    def call(params:, api_key:, env: :test, timeout_ms: 5000)
      endpoint = self.class.endpoint(env: env)

      api_response = get_api_response.call(params: params, api_key: api_key, endpoint: endpoint, timeout_ms: timeout_ms)
      errors = api_response.dig(:response, :errors)

      if errors.blank?
        data = api_response.dig(:response, :data)

        Result.new(success?: true, api_response: api_response, data: data)
      else
        # Example error response:
        # {:response=>{:data=>[], :details=>{:requestId=>1}, :errors=>[{:field=>"token", :code=>15, :severity=>2, :msg=>"The referenced resource does not exist", :errorCode=>"no_such_record"}, {:field=>"merchant", :code=>15, :severity=>2, :msg=>"The referenced resource does not exist", :errorCode=>"no_such_record"}]}}
        message = errors.map do |error|
          "Field: #{error[:field]}, " \
          "Code: #{error[:code]}, " \
          "Severity: #{error[:severity]}, " \
          "Msg: #{error[:msg]}, " \
          "ErrorCode: #{error[:errorCode]}"
        end.uniq.join(', ')

        Result.new(success?: false, error_message: message || 'Error occurred')
      end
    rescue JSON::ParserError => e
      Result.new(success?: false, error_message: "Failed to parse JSON: #{e.message}")
    rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout => e
      Result.new(success?: false, error_message: "Request timed out: #{e.message}")
    end

    def self.endpoint(env:)
      if %i[production staging].include?(env)
        'https://api.payrix.com/txns'
      else
        'https://test-api.payrix.com/txns'
      end
    end
  end
end
