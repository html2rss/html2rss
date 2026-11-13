# frozen_string_literal: true

require 'optparse'
require 'time'

# Single owner of the perf budget rule shared by bin/heuristic-perf-baseline,
# bin/selectors-perf-baseline and bin/feed-perf-baseline.
#
# Rule: allocations (median of RUNS) are the hard gate, budgeted at ALLOC_TOLERANCE times the
# recorded baseline. Wall time (min of RUNS, the least noisy statistic) is advisory, budgeted at
# WALL_TOLERANCE times the recorded baseline; exceeding it warns but never fails.
module PerfBaseline
  WARMUP = 1
  RUNS = 5
  ALLOC_TOLERANCE = 1.15
  WALL_TOLERANCE = 1.1

  Sample = Data.define(:wall, :allocations, :result)

  module_function

  # @param title [String] report heading
  # @param subject [String] one line naming what is measured
  # @param summary [String] heading of the per-subject result lines
  # @param root [String] repo root; baseline paths resolve against it
  # @yieldreturn [Hash{String => String}] result per subject, from one workload pass
  def run(title:, subject:, summary:, root:, &workload)
    options = parse_options
    sample = measure(&workload)
    report = render(title:, subject:, summary:, sample:)
    puts report
    write(report, options[:write], root) if options[:write]
    check(sample, options[:check], root) if options[:check]
  end

  def parse_options
    options = {}
    OptionParser.new do |opts|
      opts.on('--write PATH', 'Write markdown baseline to PATH') { options[:write] = _1 }
      opts.on('--check PATH', 'Fail when allocations exceed the budget recorded in PATH') { options[:check] = _1 }
    end.parse!
    options
  end

  def measure(&workload)
    WARMUP.times { pass(&workload) }
    samples = Array.new(RUNS) { pass(&workload) }
    Sample.new(
      wall: samples.map(&:wall).min,
      allocations: samples.map(&:allocations).sort[RUNS / 2],
      result: samples.last.result
    )
  end

  def pass
    GC.start
    before = GC.stat[:total_allocated_objects]
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
    wall = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    Sample.new(wall:, allocations: GC.stat[:total_allocated_objects] - before, result:)
  end

  def render(title:, subject:, summary:, sample:)
    <<~MARKDOWN
      # #{title}

      Captured: #{Time.now.utc.iso8601}
      Ruby: #{RUBY_VERSION}
      #{subject}
      Warmup runs: #{WARMUP}; measured runs: #{RUNS}

      | Metric | Value |
      | --- | --- |
      | wall_time_s (min of #{RUNS}) | #{format('%.6f', sample.wall)} |
      | allocations (median of #{RUNS}) | #{sample.allocations} |
      | wall_budget_s (#{WALL_TOLERANCE}x min, advisory) | #{format('%.6f', sample.wall * WALL_TOLERANCE)} |
      | alloc_budget (#{ALLOC_TOLERANCE}x median, hard gate) | #{(sample.allocations * ALLOC_TOLERANCE).ceil} |

      #{summary}:
      #{sample.result.map { |name, value| "- #{name}: #{value}" }.join("\n")}
    MARKDOWN
  end

  def write(report, path, root)
    target = File.expand_path(path, root)
    File.write(target, report)
    warn "Wrote #{target}"
  end

  # Exits 1 when allocations exceed the recorded budget; warns when wall exceeds its budget.
  def check(sample, path, root)
    recorded = File.read(File.expand_path(path, root))
    alloc_budget = budget(recorded, 'alloc_budget').to_i
    wall_budget = budget(recorded, 'wall_budget_s').to_f

    warn "wall #{format('%.6f', sample.wall)}s exceeds advisory budget #{wall_budget}s" if sample.wall > wall_budget
    return if sample.allocations <= alloc_budget

    warn "allocations #{sample.allocations} exceed budget #{alloc_budget} (#{path})"
    exit 1
  end

  def budget(recorded, name) = recorded[/^\| #{name}[^|]*\| ([\d.]+) \|$/, 1] || abort("no #{name} row in baseline")
end
