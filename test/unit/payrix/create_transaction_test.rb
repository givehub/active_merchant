require 'test_helper'
require 'payrix/create_transaction'

class PayrixCreateTransactionTest < Test::Unit::TestCase
  def test_env_merchant_id
    't1_mer_661041feb6b9c04fb7a9ee5'
  end

  def api_key
    ENV.fetch('PAYRIX_API_KEY_TEST')
  end

  def test_integration_test_with_payrix_test_api
    service = Payrix::CreateTransaction.new

    result = service.call(
      api_key: api_key,
      params: {
        merchant: test_env_merchant_id,
        type: '1',
        origin: '2',
        total: 1000,
        expiration: '0120',
        payment: {
          method: 2,
          number: '4111111111111111',
          cvv: '111'
        }
      }
    )

    assert result.success?
    expected_response = { response: {
      data: [{
        payment: { method: 2, number: '1111' },
        id: 't1_txn_661eda69cf8834846219121', merchant: test_env_merchant_id,
        type: '1', expiration: '0120', origin: '2', total: 1000,
        swiped: 0, emv: 0, signature: 0
      }],
      details: { requestId: 1 },
      errors: []
    } }
    assert_equal expected_response[:response][:data][0][:merchant], result.api_response[:response][:data][0][:merchant]
    assert_match(/^t1_txn_/, result.data.first[:id])
  end

  def test_successfully_creates_a_transaction_and_checks_detailed_data
    params = {
      merchant: test_env_merchant_id,
      type: '1',
      origin: '2',
      token: 'e41272ec5464d9ec81cc85c854837472',
      total: 100
    }
    service = Payrix::CreateTransaction.new(
      get_api_response: lambda { |*|
                          {
                            response: {
                              data: [{
                                payment: { method: 2, number: '1111' },
                                id: 't1_txn_661eda69cf8834846219121', merchant: test_env_merchant_id,
                                type: '1', expiration: '0120', origin: '2', total: 1000,
                                swiped: 0, emv: 0, signature: 0
                              }],
                              details: { requestId: 1 },
                              errors: []
                            }
                          }
                        }
    )

    result = service.call(params: params, api_key: api_key)

    assert result.success?
    assert_equal(
      {
        response: {
          data: [
            { emv: 0, expiration: '0120', id: 't1_txn_661eda69cf8834846219121',
              merchant: 't1_mer_661041feb6b9c04fb7a9ee5', origin: '2',
              payment: { method: 2, number: '1111' }, signature: 0, swiped: 0, total: 1000, type: '1' }
          ], details: { requestId: 1 }, errors: []
        }
      }, result.api_response
    )
  end

  def test_returns_an_error_response_when_the_api_call_fails_due_to_an_error_response
    service = Payrix::CreateTransaction.new(
      get_api_response: lambda { |*|
                          { response: {
                            data: [],
                            details: { requestId: 1 },
                            errors: [
                              { field: 'token', code: 15, severity: 2, msg: 'The referenced resource does not exist',
                                errorCode: 'no_such_record' },
                              { field: 'merchant', code: 15, severity: 2,
                                msg: 'The referenced resource does not exist', errorCode: 'no_such_record' }
                            ]
                          } }
                        }
    )

    result = service.call(
      api_key: api_key,
      params: {
        merchant: test_env_merchant_id,
        type: '1',
        origin: '2',
        token: 'e41272ec5464d9ec81cc85c854837472',
        total: 100
      }
    )

    assert_false result.success?
    assert_equal 'Field: token, Code: 15, Severity: 2, Msg: The referenced resource does not exist, ErrorCode: no_such_record, Field: merchant, Code: 15, Severity: 2, Msg: The referenced resource does not exist, ErrorCode: no_such_record', result.error_message
  end

  def test_handles_timeouts_appropriately
    service = Payrix::CreateTransaction.new(
      get_api_response: ->(*) { raise Net::ReadTimeout }
    )

    result = service.call(
      api_key: api_key,
      params: {
        merchant: test_env_merchant_id,
        type: '1',
        origin: '2',
        token: 'e41272ec5464d9ec81cc85c854837472',
        total: 100
      }
    )

    assert_false result.success?
    assert_match(/Request timed out/, result.error_message)
  end

  def test_handles_json_parsing_errors_appropriately
    service = Payrix::CreateTransaction.new(
      get_api_response: ->(*) { raise JSON::ParserError, 'unexpected token' }
    )

    result = service.call(
      api_key: api_key,
      params: {
        merchant: test_env_merchant_id,
        type: '1',
        origin: '2',
        token: 'e41272ec5464d9ec81cc85c854837472',
        total: 100,
        api_key: api_key
      }
    )

    assert_false result.success?
    assert_match(/Failed to parse JSON/, result.error_message)
  end

  def test_params
    {
      merchant: test_env_merchant_id,
      type: '1',
      origin: '2',
      token: 'e41272ec5464d9ec81cc85c854837472',
      total: 100
    }
  end

  def test_uses_the_correct_endpoint_in_production
    result = Payrix::CreateTransaction.endpoint(env: :production)

    assert_equal 'https://api.payrix.com/txns', result
  end

  def test_uses_the_correct_endpoint_in_development
    result = Payrix::CreateTransaction.endpoint(env: :development)

    assert_equal 'https://test-api.payrix.com/txns', result
  end

  def test_uses_the_correct_endpoint_in_staging
    result = Payrix::CreateTransaction.endpoint(env: :staging)

    assert_equal 'https://api.payrix.com/txns', result
  end
end
