require 'test_helper'

class RemotePayrixTest < Test::Unit::TestCase
  def setup
    @gateway = PayrixGateway.new(fixtures(:payrix))

    @amount = 10000
    @credit_card = credit_card('4000100011112224')
    @invalid_number_card = credit_card('400030001111222')
    @test_credit_card = credit_card('4242424242424242')

    @options = {
      order: generate_unique_id,
      billing_address: address,
      description: 'Active Merchant Remote Test - Store Purchase',
      type: PayrixGateway::TXNS_TYPE[:cc_only_sale],
      origin: PayrixGateway::TXNS_ORIGIN[:ecommerce_system],
      expiration: '0120'
    }
  end

  def test_successful_purchase
    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert response.test?
    assert_equal 'Approved', response.message
  end

  def test_successful_purchase_with_more_options
    options = {
      type: PayrixGateway::TXNS_TYPE[:cc_only_sale],
      origin: PayrixGateway::TXNS_ORIGIN[:ecommerce_system],
      expiration: '0120',
      order: generate_unique_id,
      clientIp: '165.50.159.143',
      email: 'joe@example.com',
      fee: 1,
      address1: '1234 My Street',
      address2: 'Apt 1',
      city: 'Los Angeles',
      state: 'CA',
      zip: '90010',
      country: 'USA',
      phone: '5555555555',
      company: 'Widgets Inc',
      cofType: 'single',
      fundingCurrency: 'USD',
      description: 'Store Purchase Description',
      discount: 1,
      first: 'Joe',
      middle: 'M',
      last: 'Smith',
      shipping: 1,
      tax: 1,
      surcharge: 1,
      duty: 1
    }

    response = @gateway.purchase(@amount, @credit_card, options)
    assert_success response
    assert_equal 1, response.params['response']['data'].first['fee']
    assert_equal 'Approved', response.message
  end

  def test_failed_purchase
    response = @gateway.purchase(@amount, @invalid_number_card, @options)
    assert_failure response
    assert_equal 'Invalid credit card/debit card number', response.message
  end

  def test_successful_authorize
    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
    assert response.test?
    assert_equal 'Approved', response.message
    refute_empty response.params['response']['data'].first['authorization']
  end

  def test_partial_authorized
    @test_partially_approved_amount = 1010
    response = @gateway.authorize(@test_partially_approved_amount, @test_credit_card, @options.merge(allowPartial: 1))
    assert_success response
    assert response.test?
    assert_equal 'Approved', response.message
    refute_empty response.params['response']['data'].first['authorization']
    assert_equal '1010', response.params['response']['data'].first['approved']
  end

  def test_successful_authorize_and_capture
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    assert capture = @gateway.capture(@amount, auth.authorization)
    assert_success capture
    assert_equal 'Pending', capture.message
    refute_empty capture.params['response']['data'].first['batch']
  end

  def test_failed_authorize
    @test_exceeds_approval_amount_limit_amount = 50001
    response = @gateway.authorize(@test_exceeds_approval_amount_limit_amount, @test_credit_card, @options)
    assert_failure response
    assert_nil response.params['response']['data'].first['authorization']
    assert_equal 'Transaction declined: Exceeds Approval Amount Limit', response.message
  end

  def test_partial_capture
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    assert capture = @gateway.capture(@amount - 1, auth.authorization)
    assert_success capture
    assert_equal 'Pending', capture.message
    refute_empty capture.params['response']['data'].first['batch']
  end

  def test_failed_capture
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth
    assert @gateway.void(auth.authorization)

    failed_capture_response = @gateway.capture(10000, auth.authorization)
    assert_failure failed_capture_response
    assert_equal 'Invalid capture transaction', failed_capture_response.message
    assert_equal 'invalid_capture', failed_capture_response.error_code
  end

  def test_failed_refund
    purchase_response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase_response
    assert purchase_response.test?
    assert_equal 'Approved', purchase_response.message

    refund_response = @gateway.refund(nil, purchase_response.authorization)
    assert_failure refund_response
    assert_equal 'Invalid refund transaction', refund_response.message
  end

  def test_successful_void
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    assert void = @gateway.void(auth.authorization)
    assert_success void
    assert_equal 'Approved', void.message
    assert_equal PayrixGateway::TXNS_UNAUTH_REASONS[:customer_cancelled], void.params['response']['data'].first['unauthReason']
  end

  def test_successful_verify
    response = @gateway.verify(@credit_card, @options)
    assert_success response
    assert_match %r{Approved}, response.message
  end

  def test_failed_verify
    response = @gateway.verify(@invalid_number_card, @options)
    assert_failure response
    assert_match %r{Invalid credit card/debit card number}, response.message
    assert_match 'invalid_card_number', response.error_code
  end

  def test_invalid_login
    gateway = PayrixGateway.new(merchant_id: 'invalid', api_key: 'invalid')

    response = gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_match %r{Unauthorized}, response.message
  end

  def test_transcript_scrubbing
    transcript = capture_transcript(@gateway) do
      @gateway.purchase(@amount, @credit_card, @options)
    end
    transcript = @gateway.scrub(transcript)

    assert_scrubbed(@credit_card.number, transcript)
    assert_scrubbed(@credit_card.verification_value, transcript)
    assert_scrubbed(@gateway.options[:api_key], transcript)
  end
end
