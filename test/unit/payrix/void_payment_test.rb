require 'test_helper'
require 'payrix/void_payment'
require 'payrix/create_transaction'

class PayrixVoidPaymentTest < Test::Unit::TestCase
  def api_key
    ENV.fetch('PAYRIX_API_KEY_TEST')
  end

  def test_integration_test_no_stubs
    service = Payrix::VoidPayment.new

    result = service.call(
      params: { transactionId: 'txn123' },
      api_key: api_key
    )

    assert_equal false, result.success?
    #<struct Payrix::VoidPayment::Result :success?=false, error_message="Field: fortxn, Code: 15, Severity: 2, Msg: This field is required to be set, ErrorCode: required_field, Field: origin, Code: 15, Severity: 2, Msg: This field is required to be set, ErrorCode: required_field, Field: merchant, Code: 15, Severity: 2, Msg: The referenced resource does not exist, ErrorCode: no_such_record, Field: total, Code: 15, Severity: 2, Msg: This field is required to be set, ErrorCode: required_field", data=nil>
    assert result.error_message.include?('This field is required to be set')
  end

  def test_voids_a_payment
    service = Payrix::VoidPayment.new(
      create_void_transaction: lambda { |*|
        Payrix::CreateTransaction::Result.new(
          success?: true,
          data: {
            id: 'void123',
            transactionStatus: '4'
          }
        )
      }
    )

    result = service.call(
      params: { transactionId: 'txn123' },
      api_key: api_key
    )

    assert_equal true, result.success?
    assert_equal 'void123', result.data[:id]
    assert_equal '4', result.data[:transactionStatus]
  end

  def test_errors_on_invalid_transaction_id
    service = Payrix::VoidPayment.new(
      create_void_transaction: lambda { |*|
        Payrix::CreateTransaction::Result.new(
          success?: false,
          error_message: 'Invalid transaction ID'
        )
      }
    )

    result = service.call(
      params: { transactionId: 'invalid123' },
      api_key: api_key
    )

    refute result.success?
    assert result.error_message.include?('Invalid transaction ID')
  end
end
