require 'test_helper'
require 'payrix/create_refund'

class PayrixCreateRefundTest < Test::Unit::TestCase
  def api_key
    ENV.fetch("PAYRIX_API_KEY_TEST")
  end

  def test_integration_test_with_payrix_test_api_when_entry_doesnt_exist
    service = Payrix::CreateRefund.new

    result = service.call(entry_id: 'entry123', amount: 1000, description: 'Refund for overcharge', api_key: api_key)

    assert result.error_message.include?('entry: The referenced resource does not exist')
    assert_equal false, result.success?
  end

  def test_works_with_success_response
    response_body = {
      response: {
        success: true,
        data: {
          id: 'refund123',
          amount: 1000,
          entry: 'entry123',
          description: 'Refund for overcharge'
        }
      }
    }
    service = Payrix::CreateRefund.new(post_refund: ->(*) { response_body })

    result = service.call(entry_id: 'entry123',
                          amount: 1000,
                          description: 'Refund for overcharge',
                          api_key: api_key)

    assert result.error_message.blank?
    assert result.success?
    assert_equal 'refund123', response_body[:response][:data][:id]
    assert_equal 1000, response_body[:response][:data][:amount]
    assert_equal 'entry123', response_body[:response][:data][:entry]
    assert_equal 'Refund for overcharge', response_body[:response][:data][:description]
  end

  def test_returns_a_details_error_message_when_the_api_call_fails_due_to_an_error_response
    response_body = {
      response: {
        errors: [
          { field: 'amount', msg: 'Invalid amount' },
          { field: 'entry', msg: 'Entry not found' }
        ]
      }
    }
    service = Payrix::CreateRefund.new(post_refund: ->(*) { response_body })

    result = service.call(entry_id: 'entry123',
                          amount: 1000,
                          description: 'Refund for overcharge',
                          api_key: api_key)

    assert result.error_message.include?('amount: Invalid amount')
    assert result.error_message.include?('entry: Entry not found')
    assert_equal false, result.success?
  end

  def test_returns_an_error_message_when_the_api_call_fails_due_to_an_error_response
    service = Payrix::CreateRefund.new(post_refund: ->(*) { raise Net::ReadTimeout })

    result = service.call(entry_id: 'entry123',
                          amount: 1000,
                          description: 'Refund for overcharge',
                          api_key: api_key)

    assert result.error_message.include?('Request timed out')
    assert_equal false, result.success?
  end
end
