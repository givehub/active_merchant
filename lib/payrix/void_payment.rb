require 'net/http'
require 'uri'
require 'json'

require_relative '../payrix'

module Payrix
  # Makes a FULL REFUND of a payment (NOT a partial, that would require a different service).
  #
  # A refund can be issued when the transaction status is "3" (captured) or "4" (settled),
  # but payments with these statuses cannot be voided or cancelled.
  # A payment can only be voided or cancelled if the transaction status is "1" (approved).
  # source: https://resource.payrix.com/resources/refund-or-void-a-transaction-in-the-api
  class VoidPayment
    private

    attr_reader :create_void_transaction

    # type 4 - void - Reverse Authorization. Reverses a prior Auth or Sale Transaction and releases the credit hold
    # type 5 - refund - Refund Transaction. Refunds a prior Capture or Sale Transaction (total may be specified for a partial refund)
    # see: https://resource.payrix.com/resources/refund-or-void-a-transaction-in-the-api#RefundorVoidaTransactionintheAPI-HowtoVoidaPaymentviatheAPI
    TYPE_VOID = '4'

    def initialize(
      create_void_transaction: lambda do |params:, api_key:, env:, timeout_ms:|
        Payrix::CreateTransaction.new.call(
          params: params.merge({ type: TYPE_VOID }),
          api_key: api_key,
          env: env,
          timeout_ms: timeout_ms
        )
      end
    )
      @create_void_transaction = create_void_transaction
    end

    public

    Result = Struct.new(:success?, :error_message, :data, keyword_init: true)

    def call(params:, api_key:, env: :test, timeout_ms: 5000)
      result = create_void_transaction.call(params: params, api_key: api_key, env: env, timeout_ms: timeout_ms)

      if result.success?
        Result.new(success?: true, data: result.data)
      else
        Result.new(success?: false, error_message: result.error_message)
      end
    end
  end
end
