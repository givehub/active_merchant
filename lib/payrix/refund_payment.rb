require 'net/http'
require 'uri'
require 'json'

require_relative '../payrix'

module Payrix
  class RefundPayment
    private

    attr_reader :create_refund_transaction

    # type 5 - refund - Refund Transaction. Refunds a prior Capture or Sale Transaction (total may be specified for a partial refund)
    # see: https://resource.payrix.com/resources/refund-or-void-a-transaction-in-the-api#RefundorVoidaTransactionintheAPI-HowtoVoidaPaymentviatheAPI
    TYPE_REFUND = '5'

    def initialize(
      create_refund_transaction: lambda do |params:, refund:, api_key:, env:, timeout_ms:|
        Payrix::CreateTransaction.new.call(
          params: params.merge({ type: TYPE_REFUND, total: refund.amount }),
          api_key: api_key,
          env: env,
          timeout_ms: timeout_ms
        )
      end
    )
      @create_refund_transaction = create_refund_transaction
    end

    public

    Result = Struct.new(:success?, :error_message, :data, keyword_init: true)

    def call(params:, refund:, api_key:, env: :test, timeout_ms: 5000)
      result = create_refund_transaction.call(params: params, refund: refund, api_key: api_key, env: env, timeout_ms: timeout_ms)

      if result.success?
        Result.new(success?: true, data: result.data)
      else
        Result.new(success?: false, error_message: result.error_message)
      end
    end

    # value object for either a full or partial refund. if it's a partial refund, the amount must be specified
    class Refund
      REFUND_TYPE_FULL = :full
      REFUND_TYPE_PARTIAL = :partial

      attr_reader :type, :amount

      def initialize(type:, amount: nil)
        raise ArgumentError, 'amount must be specified for a partial refund' if type == REFUND_TYPE_PARTIAL && amount.nil?
        raise ArgumentError, 'amount must not be specified for a full refund' if type == REFUND_TYPE_FULL && amount.present?

        @type = type
        @amount = amount
      end
    end
  end
end
