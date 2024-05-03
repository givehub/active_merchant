require 'test_helper'

class PayrixTest < Test::Unit::TestCase
  def setup
    @gateway = PayrixGateway.new(merchant_id: 'SOMECREDENTIAL', api_key: 'ANOTHERCREDENTIAL')
    @credit_card = credit_card
    @amount = 100
    @refund_amount = 1

    @options = {
      order: 'order1',
      billing_address: address,
      description: 'Store Purchase',
      type: PayrixGateway::TXNS_TYPE[:cc_only_sale],
      origin: PayrixGateway::TXNS_ORIGIN[:ecommerce_system],
      expiration: '0120'
    }
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response

    assert_equal 't1_txn_66326c57442796049c22978|100', response.authorization
    assert response.test?
  end

  def test_failed_purchase
    @gateway.expects(:ssl_post).returns(failed_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal PayrixGateway::STANDARD_ERROR_CODE[:invalid_card_number], response.error_code
  end

  def test_successful_authorize; end

  def test_failed_authorize; end

  def test_successful_capture; end

  def test_failed_capture; end

  def test_successful_refund
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    @gateway.expects(:ssl_post).returns(successful_refund_response)
    response = @gateway.refund(@refund_amount, purchase.authorization, @options)

    assert_success response
    assert response.test?
    assert_equal 'Captured', response.message
    assert response.params['response']['data'].first['id'].present?
    assert response.params['response']['data'].first['fortxn'].present?
    assert_equal 100, response.params['response']['data'].first['total']
  end

  def test_failed_refund; end

  def test_successful_void; end

  def test_failed_void; end

  def test_successful_verify; end

  def test_successful_verify_with_failed_void; end

  def test_failed_verify; end

  def test_scrub
    assert @gateway.supports_scrubbing?
    assert_equal @gateway.scrub(pre_scrubbed), post_scrubbed
  end

  private

  def pre_scrubbed
    <<-PRE
    <- "POST /txns HTTP/1.1\r\nContent-Type: application/json\r\nApikey: 60fd52de55d3dede456116800ef6e293\r\nConnection: close\r\nAccept-Encoding: gzip;q=1.0,deflate;q=0.6,identity;q=0.3\r\nAccept: */*\r\nUser-Agent: Ruby\r\nHost: test-api.payrix.com\r\nContent-Length: 186\r\n\r\n"
    <- "{\"merchant\":\"t1_mer_661041feb6b9c04fb7a9ee5\",\"payment\":{\"method\":\"2\",\"number\":\"4000100011112224\",\"cvv\":\"123\"},\"total\":\"1.00\",\"currency\":\"USD\",\"type\":\"1\",\"origin\":\"2\",\"expiration\":\"0120\"}"
    -> "HTTP/1.1 200 OK\r\n"
    -> "Date: Mon, 22 Apr 2024 16:15:53 GMT\r\n"
    -> "Content-Type: application/json; charset=UTF-8\r\n"
    -> "Transfer-Encoding: chunked\r\n"
    -> "Connection: close\r\n"
    -> "Access-Control-Allow-Origin: *\r\n"
    -> "Access-Control-Max-Age: 1800\r\n"
    -> "Access-Control-Allow-Methods: GET,PUT,POST,DELETE,OPTIONS\r\n"
    -> "Access-Control-Allow-Headers: ACCEPT,APIKEY,CONTENT-TYPE,PASSWORD,REQUEST-TOKEN,REQUEST_TOKEN,RESETKEY,SEARCH,SESSIONKEY,TXNSESSIONKEY,TOKEN,TOTALS,USERNAME,X-FORWARDED-FOR\r\n"
    -> "CF-Cache-Status: DYNAMIC\r\n"
    -> "Server: cloudflare\r\n"
    -> "CF-RAY: 8786ea360b6bc409-EWR\r\n"
    -> "Content-Encoding: gzip\r\n"
    -> "\r\n"
    -> "ef\r\n"
    reading 239 bytes...
    -> "\x1F\x8B\b\x00\x00\x00\x00\x00\x00\x03\x1C\x8F\xC1j\xC30\x10D\xFFe\xCE:H\xAA\xE38{\xEE\xA5\xE7\xD2S\bF\xB6\xD6\x89 \x92\xDD\x95\xDC\xC6\x18\xFF{QO\x03\xC3{\x03\xB3C8/s\xCA\f\xDA\xE1]q\xA0\xEB\x8E\xC5m\x91S\xA9]\xE4\xF2\x98=\xC8*\xA45\x0E, Xk\e\x1C\n\xC1\x83PL_^\xA9o[\xDBv\xFE\xEDl\xDD\xC94Vs\xC7\xDCM\xD3\x00\x85\xC82>\\]\xABld\xE9\xDB\xD6\xE8\xC6L<\xB4\xC3e\xD4\xCD4\x9C\xDD\x85\xF9\x04\x85\xB2-\f\x82\x81\x02\xBF\x96 \xAE\x849\x81\xA0\x8D\xD5P\x18W\x11N\xE3\x06\xC2\xD7\xE7;\x14f\t\xF7P\x01[\xE5\xB9\xB8'\xC8(\xE4\xDF\xB0\xB0\ai\x05\x8E?\xFF\x99\xC3=\xB9\xB2\n\x83\xF4qS\xF0\\\\x\xE6zQ\xF8{\xE5\\><\xC8\x1C\n,2K\x06]o\xC7\xF1\a\x00\x00\xFF\xFF\x03\x00 \xCD\x03\x1E \x01\x00\x00"
    PRE
  end

  def post_scrubbed
    '
      Put the scrubbed contents of transcript.log here after implementing your scrubbing function.
      Things to scrub:
        - Credit card number
        - CVV
        - Sensitive authentication details
    '
  end

  def successful_purchase_response
    <<-RESPONSE
      {"response":{"data":[{"payment":{"id":"g158fe267496346","method":2,"number":"2224","routing":"0","bin":"400010","payment":null,"lastChecked":null,"last4":null,"mask":null},"id":"t1_txn_66326c57442796049c22978","created":"2024-05-01 14:11:33.6273","modified":"2024-05-01 14:11:35.1438","creator":"t1_log_660f182a09e2b0349924bd3","modifier":"t1_log_660f182a09e2b0349924bd3","ipCreated":"104.175.241.99","ipModified":"104.175.241.99","merchant":"t1_mer_661041feb6b9c04fb7a9ee5","token":null,"fortxn":null,"fromtxn":null,"batch":"t1_bth_66328504d42e3aa243fc6b2","subscription":null,"type":"1","expiration":"0120","currency":"USD","platform":"VANTIV","authDate":null,"authCode":null,"captured":null,"settled":null,"settledCurrency":null,"settledTotal":null,"allowPartial":0,"order":"order_id_123","description":"Store Purchase Description","descriptor":"Test Merchant","terminal":null,"terminalCapability":null,"entryMode":null,"origin":"2","tax":1,"total":100,"cashback":null,"authorization":"46096","approved":"100","cvv":1,"swiped":0,"emv":0,"signature":0,"unattended":null,"clientIp":"165.50.159.143","first":"Joe","middle":"M","last":"Smith","company":"Widgets Inc","email":"joe@example.com","address1":"1234 My Street","address2":"Apt 1","city":"Los Angeles","state":"CA","zip":"90010","country":"USA","phone":"5555555555","status":"1","refunded":0,"reserved":0,"misused":null,"imported":0,"inactive":0,"frozen":0,"discount":1,"shipping":1,"duty":1,"pin":0,"traceNumber":null,"cvvStatus":null,"unauthReason":null,"fee":1,"fundingCurrency":"USD","authentication":null,"authenticationId":null,"cofType":"single","copyReason":null,"originalApproved":"100","currencyConversion":null,"serviceCode":null,"authTokenCustomer":null,"debtRepayment":"0","statement":null,"convenienceFee":0,"surcharge":1,"channel":null,"funded":null,"fundingEnabled":"1","requestSequence":1,"processedSequence":0,"mobile":null,"pinEntryCapability":null,"returned":null,"txnsession":null}],"details":{"requestId":1},"errors":[]}}
    RESPONSE
  end

  def failed_purchase_response
    <<-RESPONSE
      {"response":{"data":[],"details":{"requestId":1},"errors":[{"field":"payment.number","code":15,"severity":2,"msg":"Invalid credit card/debit card number","errorCode":"invalid_card_number"}]}}
    RESPONSE
  end

  def successful_authorize_response; end

  def failed_authorize_response; end

  def successful_capture_response; end

  def failed_capture_response; end

  def successful_refund_response
    <<-RESPONSE
      {"response":{"data":[{"id":"t1_txn_6632a56685ff49459babb3a","created":"2024-05-01 16:26:14.5492","modified":"2024-05-01 16:26:16.4403","creator":"t1_log_660f182a09e2b0349924bd3","modifier":"t1_log_660f182a09e2b0349924bd3","ipCreated":"104.175.241.99","ipModified":"104.175.241.99","merchant":"t1_mer_661041feb6b9c04fb7a9ee5","token":null,"payment":"g157b215cd94669","fortxn":"t1_txn_66326c57442796049c22978","fromtxn":null,"batch":null,"subscription":null,"type":"5","expiration":"0125","currency":"USD","platform":"VANTIV","authDate":null,"authCode":null,"captured":"2024-05-01 16:26:16","settled":null,"settledCurrency":null,"settledTotal":null,"allowPartial":0,"order":"order123","description":null,"descriptor":"Test Merchant","terminal":null,"terminalCapability":null,"entryMode":null,"origin":"2","tax":1,"total":100,"cashback":null,"authorization":null,"approved":100,"cvv":0,"swiped":0,"emv":0,"signature":0,"unattended":null,"clientIp":null,"first":null,"middle":null,"last":null,"company":null,"email":null,"address1":null,"address2":null,"city":null,"state":null,"zip":null,"country":null,"phone":null,"status":"3","refunded":0,"reserved":0,"misused":null,"imported":0,"inactive":0,"frozen":0,"discount":null,"shipping":null,"duty":null,"pin":0,"traceNumber":null,"cvvStatus":"notProvided","unauthReason":"customerCancelled","fee":null,"fundingCurrency":"USD","authentication":null,"authenticationId":null,"cofType":null,"copyReason":null,"originalApproved":100,"currencyConversion":null,"serviceCode":null,"authTokenCustomer":null,"debtRepayment":"0","statement":null,"convenienceFee":0,"surcharge":1,"channel":null,"funded":null,"fundingEnabled":"1","requestSequence":1,"processedSequence":0,"mobile":null,"pinEntryCapability":null,"returned":null,"txnsession":null}],"details":{"requestId":1},"errors":[]}}
    RESPONSE
  end

  def failed_refund_response; end

  def successful_void_response; end

  def failed_void_response; end
end
