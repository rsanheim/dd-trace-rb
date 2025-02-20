# typed: ignore
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/aws/ext'
require 'ddtrace/ext/http'
require 'ddtrace/ext/integration'

module Datadog
  module Contrib
    module Aws
      # A Seahorse::Client::Plugin that enables instrumentation for all AWS services
      class Instrumentation < Seahorse::Client::Plugin
        def add_handlers(handlers, _)
          handlers.add(Handler, step: :validate)
        end
      end

      # Generates Spans for all interactions with AWS
      class Handler < Seahorse::Client::Handler
        def call(context)
          tracer.trace(Ext::SPAN_COMMAND) do |span|
            @handler.call(context).tap do
              annotate!(span, ParsedContext.new(context))
            end
          end
        end

        private

        def annotate!(span, context)
          span.service = configuration[:service_name]
          span.span_type = Datadog::Ext::HTTP::TYPE_OUTBOUND
          span.name = Ext::SPAN_COMMAND
          span.resource = context.safely(:resource)

          # Tag as an external peer service
          span.set_tag(Datadog::Ext::Integration::TAG_PEER_SERVICE, span.service)

          # Set analytics sample rate
          if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
            Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
          end

          span.set_tag(Ext::TAG_AGENT, Ext::TAG_DEFAULT_AGENT)
          span.set_tag(Ext::TAG_OPERATION, context.safely(:operation))
          span.set_tag(Ext::TAG_REGION, context.safely(:region))
          span.set_tag(Ext::TAG_PATH, context.safely(:path))
          span.set_tag(Ext::TAG_HOST, context.safely(:host))
          span.set_tag(Datadog::Ext::HTTP::METHOD, context.safely(:http_method))
          span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, context.safely(:status_code))
        end

        def tracer
          configuration[:tracer]
        end

        def configuration
          Datadog.configuration[:aws]
        end
      end

      # Removes API request instrumentation from S3 Presign URL creation.
      #
      # This is necessary because the S3 SDK invokes the same handler
      # stack for presigning as it does for sending a real requests.
      # But presigning does not perform a network request.
      # There's not information available for our Handler plugin to differentiate
      # these two types of requests.
      #
      # DEV: Since aws-sdk-s3 1.94.1, we only need to check if
      # `context[:presigned_url] == true` in Datadog::Contrib::Aws::Handler#call
      # and skip the request if that condition is true. Since there's
      # no strong reason for us not to support older versions of `aws-sdk-s3`,
      # this {S3Presigner} monkey-patching is still required.
      module S3Presigner
        # Exclude our Handler from the current request's handler stack.
        #
        # This is the same approach that the AWS SDK takes to prevent
        # some of its plugins form interfering with the presigning process:
        # https://github.com/aws/aws-sdk-ruby/blob/a82c8981c95a8296ffb6269c3c06a4f551d87f7d/gems/aws-sdk-s3/lib/aws-sdk-s3/presigner.rb#L194-L196
        def sign_but_dont_send(*args, &block)
          if (request = args[0]).is_a?(::Seahorse::Client::Request)
            request.handlers.remove(Handler)
          end

          super(*args, &block)
        end
        ruby2_keywords :sign_but_dont_send if respond_to?(:ruby2_keywords, true)
      end
    end
  end
end
