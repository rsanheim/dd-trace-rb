# typed: true
require 'ddtrace/utils/time'

require 'ddtrace/worker'
require 'ddtrace/workers/polling'

module Datadog
  module Profiling
    # Periodically (every DEFAULT_INTERVAL_SECONDS) takes data from the `Recorder` and pushes them to all configured
    # `Exporter`s. Runs on its own background thread.
    class Scheduler < Worker
      include Workers::Polling

      DEFAULT_INTERVAL_SECONDS = 60
      MINIMUM_INTERVAL_SECONDS = 0

      # Profiles with duration less than this will not be reported
      PROFILE_DURATION_THRESHOLD_SECONDS = 1

      # We sleep for at most this duration seconds before reporting data to avoid multi-process applications all
      # reporting profiles at the exact same time
      DEFAULT_FLUSH_JITTER_MAXIMUM_SECONDS = 3

      private_constant :DEFAULT_INTERVAL_SECONDS, :MINIMUM_INTERVAL_SECONDS, :PROFILE_DURATION_THRESHOLD_SECONDS

      attr_reader \
        :exporters,
        :recorder

      def initialize(
        recorder,
        exporters,
        fork_policy: Workers::Async::Thread::FORK_POLICY_RESTART, # Restart in forks by default
        interval: DEFAULT_INTERVAL_SECONDS,
        enabled: true
      )
        @recorder = recorder
        @exporters = [exporters].flatten

        # Workers::Async::Thread settings
        self.fork_policy = fork_policy

        # Workers::IntervalLoop settings
        self.loop_base_interval = interval

        # Workers::Polling settings
        self.enabled = enabled
      end

      def start
        perform
      end

      def perform
        # A profiling flush may be called while the VM is shutting down, to report the last profile. When we do so,
        # we impose a strict timeout. This means this last profile may or may not be sent, depending on if the flush can
        # successfully finish in the strict timeout.
        # This can be somewhat confusing (why did it not get reported?), so let's at least log what happened.
        interrupted = true

        begin
          flush_and_wait
          interrupted = false
        ensure
          Datadog.logger.debug('#flush was interrupted or failed before it could complete') if interrupted
        end
      end

      def after_fork
        # Clear recorder's buffers by flushing events.
        # Objects from parent process will copy-on-write,
        # and we don't want to send events for the wrong process.
        recorder.flush
      end

      # Configure Workers::IntervalLoop to not report immediately when scheduler starts
      #
      # When a scheduler gets created (or reset), we don't want it to immediately try to flush; we want it to wait for
      # the loop wait time first. This avoids an issue where the scheduler reported a mostly-empty profile if the
      # application just started but this thread took a bit longer so there's already samples in the recorder.
      def loop_wait_before_first_iteration?
        true
      end

      def work_pending?
        !recorder.empty?
      end

      private

      def flush_and_wait
        run_time = Datadog::Utils::Time.measure do
          flush_events
        end

        # Update wait time to try to wake consistently on time.
        # Don't drop below the minimum interval.
        self.loop_wait_time = [loop_base_interval - run_time, MINIMUM_INTERVAL_SECONDS].max
      end

      def flush_events
        # Get events from recorder
        flush = recorder.flush

        if duration_below_threshold?(flush)
          Datadog.logger.debug do
            "Skipped exporting profiling events as profile duration is below minimum (#{flush.event_count} events skipped)"
          end

          return flush
        end

        # Sleep for a bit to cause misalignment between profilers in multi-process applications
        #
        # When not being run in a loop, it means the scheduler has not been started or was stopped, and thus
        # a) it's being shutting down (and is trying to report the last profile)
        # b) it's being run as a one-shot, usually in a test
        # ...so in those cases we don't sleep
        #
        # During PR review (https://github.com/DataDog/dd-trace-rb/pull/1807) we discussed the possible alternative of
        # just sleeping before starting the scheduler loop. We ended up not going with that option to avoid the first
        # profile containing up to DEFAULT_INTERVAL_SECONDS + DEFAULT_FLUSH_JITTER_MAXIMUM_SECONDS instead of the
        # usual DEFAULT_INTERVAL_SECONDS size.
        if run_loop?
          jitter_seconds = rand * DEFAULT_FLUSH_JITTER_MAXIMUM_SECONDS # floating point number between (0.0...maximum)
          sleep(jitter_seconds)
        end

        # Send events to each exporter
        if flush.event_count > 0
          exporters.each do |exporter|
            begin
              exporter.export(flush)
            rescue StandardError => e
              Datadog.logger.error(
                "Unable to export #{flush.event_count} profiling events. Cause: #{e} Location: #{Array(e.backtrace).first}"
              )
            end
          end
        end

        flush
      end

      def duration_below_threshold?(flush)
        (flush.finish - flush.start) < PROFILE_DURATION_THRESHOLD_SECONDS
      end
    end
  end
end
