require 'aws-sdk-bedrockruntime'

# The single seam to Amazon Bedrock. Everything model-facing lives behind this one
# class so the rest of the app never touches the AWS SDK directly and tests can stub
# one method. Uses the Converse API, which normalises the request/response shape
# across Bedrock models (Nova included).
#
# Config is env-only (no secrets in code): BEDROCK_REGION, BEDROCK_MODEL_ID, and the
# standard AWS credential chain (env / shared config / instance role). Set
# SUMMARY_LLM_DISABLED=1 to force the caller onto its template path — used in tests
# and on an offline box that should never dial out.
class Bedrock
  DEFAULT_REGION = 'eu-west-1'.freeze
  # The EU cross-region inference profile for Amazon Nova Lite. Confirm the exact id
  # against the account's enabled model access — it must match a profile you can call
  # from the configured region.
  DEFAULT_MODEL = 'eu.amazon.nova-lite-v1:0'.freeze
  MAX_TOKENS = 400
  TEMPERATURE = 0.4

  class << self
    def disabled?
      ENV['SUMMARY_LLM_DISABLED'].present?
    end

    # Send a system prompt + user message through Converse and return the model's
    # plain text. Raises on any transport/credential error — the caller decides how
    # to degrade (keep last-good cache, else template).
    def converse(system:, user:)
      raise 'Bedrock disabled (SUMMARY_LLM_DISABLED)' if disabled?

      response = client.converse(
        model_id:         model_id,
        system:           [{ text: system }],
        messages:         [{ role: 'user', content: [{ text: user }] }],
        inference_config: { max_tokens: MAX_TOKENS, temperature: TEMPERATURE }
      )
      response.output.message.content.map(&:text).join.strip
    end

    def model_id
      ENV.fetch('BEDROCK_MODEL_ID', DEFAULT_MODEL)
    end

    def region
      ENV.fetch('BEDROCK_REGION', DEFAULT_REGION)
    end

    private

    def client
      @client ||= Aws::BedrockRuntime::Client.new(region: region)
    end
  end
end
