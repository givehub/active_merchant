require 'test_helper'
require 'payrix/create_customer'

class PayrixCreateCustomerTest < Test::Unit::TestCase
  def api_key
    ENV.fetch('PAYRIX_API_KEY_TEST')
  end

  def test_integration_test_with_payrix_test_api_when_customer_creation_fails_from_errors_field
    service = Payrix::CreateCustomer.new(
      post_customer: lambda { |*|
        { errors: [{ field: 'email', msg: 'Invalid email format' }] }
      }
    )

    result = service.call(
      params: { firstName: 'John', lastName: 'Doe', email: 'invalid-email' },
      api_key: api_key
    )

    assert_equal false, result.success?
    assert result.error_message.include?('Invalid email format')
  end

  def test_integration_test_with_payrix_test_api_when_customer_creation_fails_from_response_errors_field
    service = Payrix::CreateCustomer.new(
      post_customer: lambda { |*|
        { response: { errors: [{ field: 'email', msg: 'Invalid email format' }] } }
      }
    )

    result = service.call(
      params: { firstName: 'John', lastName: 'Doe', email: 'invalid-email' },
      api_key: api_key
    )

    assert_equal false, result.success?
    assert result.error_message.include?('Invalid email format')
  end

  def test_works_with_success_response
    service = Payrix::CreateCustomer.new(
      post_customer: lambda { |*|
        {
          response: {
            success: true,
            data: {
              id: 'cust123',
              firstName: 'John',
              lastName: 'Doe',
              email: 'john.doe@example.com'
            }
          }
        }
      }
    )

    result = service.call(
      params: { firstName: 'John', lastName: 'Doe', email: 'john.doe@example.com' },
      api_key: api_key
    )

    assert result.error_message.blank?
    assert result.success?
    assert_equal 'cust123', result.data[:id]
    assert_equal 'John', result.data[:firstName]
    assert_equal 'Doe', result.data[:lastName]
    assert_equal 'john.doe@example.com', result.data[:email]
  end

  def test_returns_a_details_error_message_when_the_api_call_fails_due_to_an_error_response
    service = Payrix::CreateCustomer.new(
      post_customer: lambda { |*|
                       {
                         response: {
                           errors: [
                             { field: 'email', msg: 'Invalid email format' }
                           ]
                         }
                       }
                     }
    )

    result = service.call(
      params: { firstName: 'John', lastName: 'Doe', email: 'invalid-email' },
      api_key: api_key
    )

    assert result.error_message.include?('email: Invalid email format')
    assert_equal false, result.success?
  end

  def test_handles_timeouts_appropriately
    service = Payrix::CreateCustomer.new(post_customer: ->(*) { raise Net::ReadTimeout })

    result = service.call(
      params: { firstName: 'John', lastName: 'Doe', email: 'john.doe@example.com' },
      api_key: api_key
    )

    assert result.error_message.include?('Request timed out')
    assert_equal false, result.success?
  end
end
