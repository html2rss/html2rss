# frozen_string_literal: true

##
# Deterministic helpers for specs that exercise concurrent callers.
module ThreadHelpers
  ##
  # @param total [Integer] number of threads to start
  # @yieldparam index [Integer] zero-based thread number
  # @return [Array<Thread>] the started threads
  def spawn_threads(total)
    Array.new(total) do |index|
      Thread.new(index) do |number| # rubocop:disable ThreadSafety/NewThread
        Thread.current.report_on_exception = false
        yield number
      end
    end
  end

  ##
  # @param threads [Array<Thread>] started threads
  # @return [Array<Object>] each thread's value, or the error it raised
  def settle(threads)
    threads.map do |thread|
      thread.value
    rescue StandardError => error
      error
    end
  end

  ##
  # Waits until the threads are parked, opens the gate, and collects their results.
  # @param gate [Queue] queue the threads block on
  # @param threads [Array<Thread>] started threads
  # @return [Array<Object>] see {#settle}
  def release_and_settle(gate, threads)
    wait_until_parked(threads)
    gate.close
    settle(threads)
  end

  ##
  # Blocks until every thread is asleep (waiting on a queue or condition variable) or finished.
  # @param threads [Array<Thread>] threads expected to park
  # @return [void]
  def wait_until_parked(threads)
    Thread.pass until threads.all? { |thread| thread.status != 'run' }
  end
end

RSpec.configure { |config| config.include ThreadHelpers }
