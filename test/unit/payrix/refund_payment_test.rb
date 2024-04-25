require 'test_helper'
require 'payrix/refund_payment'
require 'payrix/create_transaction'

class PayrixRefundPaymentTest < Test::Unit::TestCase
  def api_key
    ENV.fetch('PAYRIX_API_KEY_TEST')
  end

  def test_full_refund_integration_test_no_stubs
    service = Payrix::RefundPayment.new

    result = service.call(
      params: { transactionId: 'txn123' },
      api_key: api_key,
      refund: Payrix::RefundPayment::Refund.new(type: :full)
    )

    # TODO: do whatever setup of resources is necessary to make this test pass in Payrix test 
    assert_equal false, result.success?
    #<struct Payrix::VoidPayment::Result :success?=false, error_message="Field: fortxn, Code: 15, Severity: 2, Msg: This field is required to be set, ErrorCode: required_field, Field: origin, Code: 15, Severity: 2, Msg: This field is required to be set, ErrorCode: required_field, Field: merchant, Code: 15, Severity: 2, Msg: The referenced resource does not exist, ErrorCode: no_such_record, Field: total, Code: 15, Severity: 2, Msg: This field is required to be set, ErrorCode: required_field", data=nil>
    assert result.error_message.include?('This field is required to be set')
  end

  def test_partial_refund_integration_test_no_stubs
    service = Payrix::RefundPayment.new

    result = service.call(
      params: { transactionId: 'txn123' },
      api_key: api_key,
      refund: Payrix::RefundPayment::Refund.new(type: :partial, amount: 1000)
    )

    # TODO: do whatever setup of resources is necessary to make this test pass in Payrix test env
    assert_equal false, result.success?
    #<struct Payrix::VoidPayment::Result :success?=false, error_message="Field: fortxn, Code: 15, Severity: 2, Msg: This field is required to be set, ErrorCode: required_field, Field: origin, Code: 15, Severity: 2, Msg: This field is required to be set, ErrorCode: required_field, Field: merchant, Code: 15, Severity: 2, Msg: The referenced resource does not exist, ErrorCode: no_such_record, Field: total, Code: 15, Severity: 2, Msg: This field is required to be set, ErrorCode: required_field", data=nil>
    assert result.error_message.include?('This field is required to be set')
  end

  def test_full_refund
    service = Payrix::RefundPayment.new(
      create_refund_transaction: lambda { |*|
        Payrix::CreateTransaction::Result.new(
          success?: true,
          data: {
            id: 'void123',
            transactionStatus: '5'
          }
        )
      }
    )

    result = service.call(
      params: { transactionId: 'txn123' },
      api_key: api_key,
      refund: Payrix::RefundPayment::Refund.new(type: :full)
    )

    assert_equal true, result.success?
    assert_equal 'void123', result.data[:id]
    assert_equal '5', result.data[:transactionStatus]
  end

  def test_partial_refund
    service = Payrix::RefundPayment.new(
      create_refund_transaction: lambda { |*|
        Payrix::CreateTransaction::Result.new(
          success?: true,
          data: {
            id: 'void123',
            transactionStatus: '5'
          }
        )
      }
    )
    amount = 1000

    result = service.call(
      params: { transactionId: 'txn123' },
      api_key: api_key,
      refund: Payrix::RefundPayment::Refund.new(type: :partial, amount: amount)
    )

    assert_equal true, result.success?
    assert_equal 'void123', result.data[:id]
    assert_equal '5', result.data[:transactionStatus]
  end

  def test_errors_when_amount_is_specified_for_full_refund
    assert_raises ArgumentError do
      Payrix::RefundPayment::Refund.new(type: :full, amount: 1000)
    end
  end

  def test_errors_when_amount_is_not_specified_for_partial_refund
    assert_raises ArgumentError do
      Payrix::RefundPayment::Refund.new(type: :partial)
    end
  end

  def test_errors_on_invalid_transaction_id
    service = Payrix::RefundPayment.new(
      create_refund_transaction: lambda { |*|
        Payrix::CreateTransaction::Result.new(
          success?: false,
          error_message: 'Invalid transaction ID'
        )
      }
    )

    result = service.call(
      params: { transactionId: 'invalid123' },
      api_key: api_key,
      refund: Payrix::RefundPayment::Refund.new(type: :full)
    )

    refute result.success?
    assert result.error_message.include?('Invalid transaction ID')
  end
end
