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

    assert_equal 't1_txn_66326c57442796049c22978', response.authorization
    assert response.test?
  end

  def test_failed_purchase
    @gateway.expects(:ssl_post).returns(failed_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal PayrixGateway::STANDARD_ERROR_CODE[:invalid_card_number], response.error_code
  end

  def test_successful_authorize
    @gateway.expects(:ssl_post).returns(successful_authorize_response)

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'Approved', response.message
    assert response.params['response']['data'].first['authorization'].present?
  end

  def test_failed_authorize
    @gateway.expects(:ssl_post).returns(failed_authorize_response)

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'Transaction declined: Exceeds Approval Amount Limit', response.message
    assert_equal 'Failed', PayrixGateway::TXNS_RESPONSE_STATUS[:"#{response.params['response']['data'].first['status']}"]
  end

  def test_successful_capture
    @gateway.expects(:ssl_post).returns(successful_authorize_response)
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    @gateway.expects(:ssl_post).returns(successful_capture_response)
    assert capture = @gateway.capture(@amount, auth.authorization)
    assert_success capture
    assert_equal 'Pending', capture.message
    refute_empty capture.params["response"]["data"].first["batch"]
  end

  def test_failed_capture; end

  def test_successful_refund
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    @gateway.expects(:ssl_post).returns(successful_refund_response)
    response = @gateway.refund(@refund_amount, purchase.authorization, @options)

    assert_success response
    assert response.test?
    assert_equal PayrixGateway::TXNS_RESPONSE_STATUS[:'3'], response.message
    assert response.params['response']['data'].first['id'].present?
    assert response.params['response']['data'].first['fortxn'].present?
    assert_equal 100, response.params['response']['data'].first['total']
    assert_equal PayrixGateway::TXNS_UNAUTH_REASONS[:customer_cancelled], response.params['response']['data'].first['unauthReason']
  end

  def test_partial_refund
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    @gateway.expects(:ssl_post).returns(successful_partial_refund_response)
    response = @gateway.refund(@refund_amount, purchase.authorization, @options)

    assert_success response
    assert response.test?
    assert response.params['response']['data'].first['id'].present?
    assert response.params['response']['data'].first['fortxn'].present?
    assert_equal PayrixGateway::TXNS_RESPONSE_STATUS[:'1'], response.message
    assert_equal @refund_amount, response.params["response"]["data"].first["approved"]
    assert_equal PayrixGateway::TXNS_UNAUTH_REASONS[:customer_cancelled], response.params["response"]["data"].first["unauthReason"]
    refute_empty response.params["response"]["data"].first["id"]
  end

  def test_failed_refund; end

  def test_successful_void
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    @gateway.expects(:ssl_post).returns(successful_void_response)
    response = @gateway.void(purchase.authorization, @options)

    assert_success response
    assert response.test?
    assert response.params['response']['data'].first['id'].present?
    assert response.params['response']['data'].first['fortxn'].present?
    assert_equal PayrixGateway::TXNS_RESPONSE_STATUS[:'1'], response.message
    assert_equal @amount, response.params["response"]["data"].first["approved"]
    assert_equal PayrixGateway::TXNS_UNAUTH_REASONS[:customer_cancelled], response.params["response"]["data"].first["unauthReason"]
  end

  def test_failed_void
    @gateway.expects(:ssl_post).returns(failed_void_response)
    @any_captured_transaction_id = 't1_txn_66326c57442796049c22978'

    failed_void_response = @gateway.void(@any_captured_transaction_id)

    assert_failure failed_void_response
    assert_equal 'Invalid unauth transaction', failed_void_response.message
    assert_equal 'invalid_reverse_auth', failed_void_response.error_code
  end

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
    PRE
  end

  def post_scrubbed
    <<-PRE
    <- "POST /txns HTTP/1.1\r\nContent-Type: application/json\r\nApikey: [FILTERED]\r\nConnection: close\r\nAccept-Encoding: gzip;q=1.0,deflate;q=0.6,identity;q=0.3\r\nAccept: */*\r\nUser-Agent: Ruby\r\nHost: test-api.payrix.com\r\nContent-Length: 186\r\n\r\n"
    <- "{\"merchant\":\"t1_mer_661041feb6b9c04fb7a9ee5\",\"payment\":{\"method\":\"[FILTERED]\",\"number\":\"[FILTERED]\",\"cvv\":\"[FILTERED]\"},\"total\":\"1.00\",\"currency\":\"USD\",\"type\":\"1\",\"origin\":\"2\",\"expiration\":\"0120\"}\"
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
    PRE
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

  def successful_authorize_response
    <<-RESPONSE
      {"response":{"data":[{"payment":{"id":"g158fe267496346","method":2,"number":"2224","routing":"0","bin":"400010","payment":null,"lastChecked":null,"last4":null,"mask":null},"id":"t1_txn_663523873402da4d3cef5bc","created":"2024-05-03 13:48:55.2134","modified":"2024-05-03 13:48:56.4753","creator":"t1_log_660f182a09e2b0349924bd3","modifier":"t1_log_660f182a09e2b0349924bd3","ipCreated":"104.175.241.99","ipModified":"104.175.241.99","merchant":"t1_mer_661041feb6b9c04fb7a9ee5","token":null,"fortxn":null,"fromtxn":null,"batch":null,"subscription":null,"type":"2","expiration":"0120","currency":"USD","platform":"VANTIV","authDate":null,"authCode":null,"captured":null,"settled":null,"settledCurrency":null,"settledTotal":null,"allowPartial":0,"order":"fda2f5647f9fbe5b4af8d3f925518705","description":"Active Merchant Remote Test - Store Purchase","descriptor":"Test Merchant","terminal":null,"terminalCapability":null,"entryMode":null,"origin":"2","tax":null,"total":10000,"cashback":null,"authorization":"92706","approved":"10000","cvv":1,"swiped":0,"emv":0,"signature":0,"unattended":null,"clientIp":null,"first":null,"middle":null,"last":null,"company":null,"email":null,"address1":null,"address2":null,"city":null,"state":null,"zip":null,"country":null,"phone":null,"status":"1","refunded":0,"reserved":0,"misused":null,"imported":0,"inactive":0,"frozen":0,"discount":null,"shipping":null,"duty":null,"pin":0,"traceNumber":null,"cvvStatus":null,"unauthReason":null,"fee":null,"fundingCurrency":"USD","authentication":null,"authenticationId":null,"cofType":null,"copyReason":null,"originalApproved":"10000","currencyConversion":null,"serviceCode":null,"authTokenCustomer":null,"debtRepayment":"0","statement":null,"convenienceFee":0,"surcharge":null,"channel":null,"funded":null,"fundingEnabled":"1","requestSequence":0,"processedSequence":0,"mobile":null,"pinEntryCapability":null,"returned":null,"txnsession":null}],"details":{"requestId":1},"errors":[]}}
    RESPONSE
  end

  def failed_authorize_response
    <<-RESPONSE
      {"response":{"data":[{"payment":{"id":"g157968b6df1534","method":2,"number":"4242","routing":"0","bin":"424242","payment":null,"lastChecked":null,"last4":null,"mask":null},"id":"t1_txn_6635541fe89ba95c25c5338","created":"2024-05-03 17:16:15.9531","modified":"2024-05-03 17:16:16.7347","creator":"t1_log_660f182a09e2b0349924bd3","modifier":"t1_log_660f182a09e2b0349924bd3","ipCreated":"104.175.241.99","ipModified":"104.175.241.99","merchant":"t1_mer_661041feb6b9c04fb7a9ee5","token":null,"fortxn":null,"fromtxn":null,"batch":null,"subscription":null,"type":"2","expiration":"0120","currency":"USD","platform":"VANTIV","authDate":null,"authCode":null,"captured":null,"settled":null,"settledCurrency":null,"settledTotal":null,"allowPartial":0,"order":"061ac90151f1e28210267df76aea88bb","description":"Active Merchant Remote Test - Store Purchase","descriptor":"Test Merchant","terminal":null,"terminalCapability":null,"entryMode":null,"origin":"2","tax":null,"total":50001,"cashback":null,"authorization":null,"approved":null,"cvv":1,"swiped":0,"emv":0,"signature":0,"unattended":null,"clientIp":null,"first":null,"middle":null,"last":null,"company":null,"email":null,"address1":null,"address2":null,"city":null,"state":null,"zip":null,"country":null,"phone":null,"status":2,"refunded":0,"reserved":0,"misused":null,"imported":0,"inactive":0,"frozen":0,"discount":null,"shipping":null,"duty":null,"pin":0,"traceNumber":null,"cvvStatus":null,"unauthReason":null,"fee":null,"fundingCurrency":"USD","authentication":null,"authenticationId":null,"cofType":null,"copyReason":null,"originalApproved":null,"currencyConversion":null,"serviceCode":null,"authTokenCustomer":null,"debtRepayment":"0","statement":null,"convenienceFee":0,"surcharge":null,"channel":null,"funded":null,"fundingEnabled":"1","requestSequence":0,"processedSequence":0,"mobile":null,"pinEntryCapability":null,"returned":null,"txnsession":null}],"details":{"requestId":1},"errors":[{"field":null,"code":15,"severity":2,"msg":"Transaction declined: Exceeds Approval Amount Limit","errorCode":"invalid_amount"}]}}
    RESPONSE
  end

  def successful_capture_response
    <<-RESPONSE
      {"response":{"data":[{"id":"t1_txn_663a990956aada37c9fd457","created":"2024-05-07 17:11:37.3555","modified":"2024-05-07 17:11:37.9397","creator":"t1_log_660f182a09e2b0349924bd3","modifier":"t1_log_660f182a09e2b0349924bd3","ipCreated":"104.175.241.99","ipModified":"104.175.241.99","merchant":"t1_mer_661041feb6b9c04fb7a9ee5","token":null,"payment":"g158fe267496346","fortxn":"t1_txn_663523873402da4d3cef5bc","fromtxn":null,"batch":"t1_bth_663a8f60472ab069ad8bd00","subscription":null,"type":"3","expiration":"0120","currency":"USD","platform":"VANTIV","authDate":null,"authCode":null,"captured":null,"settled":null,"settledCurrency":null,"settledTotal":null,"allowPartial":"0","order":"ec676602b37b33765196d0317ffdb894","description":null,"descriptor":"Test Merchant","terminal":null,"terminalCapability":null,"entryMode":null,"origin":2,"tax":null,"total":10000,"cashback":null,"authorization":"71145","approved":null,"cvv":0,"swiped":0,"emv":0,"signature":0,"unattended":null,"clientIp":null,"first":null,"middle":null,"last":null,"company":null,"email":null,"address1":null,"address2":null,"city":null,"state":null,"zip":null,"country":null,"phone":null,"status":0,"refunded":0,"reserved":0,"misused":null,"imported":0,"inactive":0,"frozen":0,"discount":null,"shipping":null,"duty":null,"pin":0,"traceNumber":null,"cvvStatus":"notProvided","unauthReason":null,"fee":null,"fundingCurrency":"USD","authentication":null,"authenticationId":null,"cofType":null,"copyReason":null,"originalApproved":null,"currencyConversion":null,"serviceCode":null,"authTokenCustomer":null,"debtRepayment":"0","statement":null,"convenienceFee":0,"surcharge":null,"channel":null,"funded":null,"fundingEnabled":"1","requestSequence":0,"processedSequence":0,"mobile":null,"pinEntryCapability":null,"returned":null,"txnsession":null}],"details":{"requestId":1},"errors":[]}}
    RESPONSE
  end

  def failed_capture_response; end

  def successful_refund_response
    <<-RESPONSE
      {"response":{"data":[{"id":"t1_txn_6632a56685ff49459babb3a","created":"2024-05-01 16:26:14.5492","modified":"2024-05-01 16:26:16.4403","creator":"t1_log_660f182a09e2b0349924bd3","modifier":"t1_log_660f182a09e2b0349924bd3","ipCreated":"104.175.241.99","ipModified":"104.175.241.99","merchant":"t1_mer_661041feb6b9c04fb7a9ee5","token":null,"payment":"g157b215cd94669","fortxn":"t1_txn_66326c57442796049c22978","fromtxn":null,"batch":null,"subscription":null,"type":"5","expiration":"0125","currency":"USD","platform":"VANTIV","authDate":null,"authCode":null,"captured":"2024-05-01 16:26:16","settled":null,"settledCurrency":null,"settledTotal":null,"allowPartial":0,"order":"order123","description":null,"descriptor":"Test Merchant","terminal":null,"terminalCapability":null,"entryMode":null,"origin":"2","tax":1,"total":100,"cashback":null,"authorization":null,"approved":100,"cvv":0,"swiped":0,"emv":0,"signature":0,"unattended":null,"clientIp":null,"first":null,"middle":null,"last":null,"company":null,"email":null,"address1":null,"address2":null,"city":null,"state":null,"zip":null,"country":null,"phone":null,"status":"3","refunded":0,"reserved":0,"misused":null,"imported":0,"inactive":0,"frozen":0,"discount":null,"shipping":null,"duty":null,"pin":0,"traceNumber":null,"cvvStatus":"notProvided","unauthReason":"customerCancelled","fee":null,"fundingCurrency":"USD","authentication":null,"authenticationId":null,"cofType":null,"copyReason":null,"originalApproved":100,"currencyConversion":null,"serviceCode":null,"authTokenCustomer":null,"debtRepayment":"0","statement":null,"convenienceFee":0,"surcharge":1,"channel":null,"funded":null,"fundingEnabled":"1","requestSequence":1,"processedSequence":0,"mobile":null,"pinEntryCapability":null,"returned":null,"txnsession":null}],"details":{"requestId":1},"errors":[]}}
    RESPONSE
  end

  def successful_partial_refund_response
    <<-RESPONSE
      {"response":{"data":[{"id":"t1_txn_66395fc6a8726f6803d6dfc","created":"2024-05-06 18:55:02.6905","modified":"2024-05-06 18:55:03.5942","creator":"t1_log_660f182a09e2b0349924bd3","modifier":"t1_log_660f182a09e2b0349924bd3","ipCreated":"104.175.241.99","ipModified":"104.175.241.99","merchant":"t1_mer_661041feb6b9c04fb7a9ee5","token":null,"payment":"g157b215cd94669","fortxn":"t1_txn_66326c57442796049c22978","fromtxn":null,"batch":"t1_bth_66395908c08f3bfdd8ed5cf","subscription":null,"type":"5","expiration":"0120","currency":"USD","platform":"VANTIV","authDate":null,"authCode":null,"captured":null,"settled":null,"settledCurrency":null,"settledTotal":null,"allowPartial":0,"order":"","description":null,"descriptor":"Test Merchant","terminal":null,"terminalCapability":null,"entryMode":null,"origin":2,"tax":null,"total":1,"cashback":null,"authorization":null,"approved":1,"cvv":0,"swiped":0,"emv":0,"signature":0,"unattended":null,"clientIp":null,"first":null,"middle":null,"last":null,"company":null,"email":null,"address1":null,"address2":null,"city":null,"state":null,"zip":null,"country":null,"phone":null,"status":"1","refunded":0,"reserved":0,"misused":null,"imported":0,"inactive":0,"frozen":0,"discount":null,"shipping":null,"duty":null,"pin":0,"traceNumber":null,"cvvStatus":"notProvided","unauthReason":"customerCancelled","fee":null,"fundingCurrency":"USD","authentication":null,"authenticationId":null,"cofType":null,"copyReason":null,"originalApproved":1,"currencyConversion":null,"serviceCode":null,"authTokenCustomer":null,"debtRepayment":"0","statement":null,"convenienceFee":0,"surcharge":null,"channel":null,"funded":null,"fundingEnabled":"1","requestSequence":2,"processedSequence":0,"mobile":null,"pinEntryCapability":null,"returned":null,"txnsession":null}],"details":{"requestId":1},"errors":[]}}
    RESPONSE
  end

  def failed_refund_response; end

  def successful_void_response
    <<-RESPONSE
      {"response":{"data":[{"id":"t1_txn_663a925c1ff80053d1f015a","created":"2024-05-07 16:43:08.1315","modified":"2024-05-07 16:43:08.509","creator":"t1_log_660f182a09e2b0349924bd3","modifier":"t1_log_660f182a09e2b0349924bd3","ipCreated":"104.175.241.99","ipModified":"104.175.241.99","merchant":"t1_mer_661041feb6b9c04fb7a9ee5","token":null,"payment":"g158fe267496346","fortxn":"t1_txn_663a92593be9ca96cc6ecdc","fromtxn":null,"batch":null,"subscription":null,"type":"4","expiration":"0120","currency":"USD","platform":"VANTIV","authDate":null,"authCode":null,"captured":null,"settled":null,"settledCurrency":null,"settledTotal":null,"allowPartial":0,"order":"0ed486a26ac21227064d2b6716187ccb","description":null,"descriptor":"Test Merchant","terminal":null,"terminalCapability":null,"entryMode":null,"origin":2,"tax":null,"total":10000,"cashback":null,"authorization":null,"approved":100,"cvv":0,"swiped":0,"emv":0,"signature":0,"unattended":null,"clientIp":null,"first":null,"middle":null,"last":null,"company":null,"email":null,"address1":null,"address2":null,"city":null,"state":null,"zip":null,"country":null,"phone":null,"status":"1","refunded":0,"reserved":0,"misused":null,"imported":0,"inactive":0,"frozen":0,"discount":null,"shipping":null,"duty":null,"pin":0,"traceNumber":null,"cvvStatus":"notProvided","unauthReason":"customerCancelled","fee":null,"fundingCurrency":"USD","authentication":null,"authenticationId":null,"cofType":null,"copyReason":null,"originalApproved":10000,"currencyConversion":null,"serviceCode":null,"authTokenCustomer":null,"debtRepayment":"0","statement":null,"convenienceFee":0,"surcharge":null,"channel":null,"funded":null,"fundingEnabled":"1","requestSequence":0,"processedSequence":0,"mobile":null,"pinEntryCapability":null,"returned":null,"txnsession":null}],"details":{"requestId":1},"errors":[]}}
    RESPONSE
  end

  def failed_void_response
    <<-RESPONSE
      {"response":{"data":[],"details":{"requestId":1},"errors":[{"field":null,"code":15,"severity":2,"msg":"Invalid unauth transaction","errorCode":"invalid_reverse_auth"}]}}
    RESPONSE
  end
end
