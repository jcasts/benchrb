raise LoadError, "Ruby version must be >= 1.9" if RUBY_VERSION < "1.9"

require 'benchmark'

$benchrb_binding = binding

##
# BenchRb is a simple wrapper around Ruby's Benchmark module which allows
# easily running a benchmark N times and getting averages, min, max, etc.

class BenchRb

  # Gem version
  VERSION = '1.0.0'


  ##
  # Parse command line arguments.

  def self.parse_args argv
    require 'optparse'

    options = {}

    opts = OptionParser.new do |opt|
        opt.program_name = File.basename $0
        opt.version = BenchRb::VERSION
        opt.release = nil

        opt.banner = <<-STR

#{opt.program_name} #{opt.version}

Quickly benchmark ruby code.

  Usage:
    #{opt.program_name} --help
    #{opt.program_name} --version
    #{opt.program_name} [options] [ruby code]

  Examples:
    #{opt.program_name} "[0, 1, 2, 3].inject(1){|last, num| last + num}"
    #{opt.program_name} -n 1000000 "2**10"
 

  Running without ruby code argument will open an interactive shell.

  Options:
      STR

      opt.on('-n', '--number INT', Integer,
      'Number of times to run the code (default 10000)') do |count|
        options[:count] = count
      end

      opt.on('-r MODULE', String, 'Same as `ruby -r\'') do |libs|
        libs.each{|lib| require lib }
      end

      opt.on('-I PATH', String, 'Specify $LOAD_PATH directory') do |path|
        $:.unshift path
      end

      opt.on('-h', '--help', 'Print this help screen') do
        puts opt
        exit
      end

      opt.on('-v', '--version', 'Output version and exit') do
        puts BenchRb::VERSION
        exit
      end
    end

    opts.parse! argv

    return [argv.last, options]
  end


  ##
  # Run from the command line.

  def self.run_cmd argv=ARGV
    res = run(*parse_args(argv))
    puts res.inspect if res
  end


  ##
  # Run and benchmark a Ruby String or block. Returns a BenchRb instance.
  # If no Ruby String or block is given, runs in a loop while expecting
  # input from $stdin.
  #
  # Supported options:
  #   :binding:: The binding to run the String as (not for blocks)
  #   :count:: The number of times to run the given code
  #
  # Examples:
  #   BenchRb.run "sleep 0.01", :count => 10
  #
  #   BenchRb.run :count => 10 do
  #     sleep 0.01
  #   end

  def self.run rb_str=nil, opts={}, &block
    rb_str, opts = nil, rb_str if Hash === rb_str

    if rb_str
      bind  = opts[:binding] || $benchrb_binding
      block = eval("lambda do\n#{rb_str}\nend", bind)
    end

    if block
      self.bench(opts[:count], &block)

    else
      # Interactive mode
      trap(:INT){ puts "\n"; exit 1 }

      loop do
        $stderr.print "\n>> "
        $stderr.flush
        str = gets.strip
        break if str == "break"
        puts( run(str, opts).inspect )
      end
    end
  end


  ##
  # Benchmark a block of code with a given count. Count defaults to 1.
  # Returns a BenchRb instance.

  def self.bench count=nil, &block
    count  = 1 if !count || count < 1
    result = new

    GC.start

    count.times do
      bm = Benchmark.measure(&block)
      result.add [bm.utime, bm.stime, bm.total, bm.real]
    end

    return result
  end


  ##
  # Create a new BenchRb instance for recording results.

  def initialize
    @map = %w{user system total real}
    @min = [0,0,0,0]
    @max = [0,0,0,0]
    @avg = [0,0,0,0]
    @tot = [0,0,0,0]
    @count = 0
  end


  ##
  # Append a result. Result should be an Array of the following form:
  #   [user_time, system_time, total_time, real_time]

  def add results
    if @count == 0
      @min = results.dup
      @max = results.dup
      @avg = results.dup
      @count += 1
      return self
    end

    results.each_with_index do |num, index|
      @avg[index] = ((@avg[index] * @count) + num) / (@count + 1.0)
      @min[index] = num if @min[index] > num
      @max[index] = num if @max[index] < num
      @tot[index] += num
    end

    @count += 1
    return self
  end


  ##
  # Inspect the instance. Renders the output grid as a String.

  def inspect
    grid = [
      ["   ", @map.dup],
      ["avg", @avg.map{|num| num_to_str(num)} ],
      ["min", @min.map{|num| num_to_str(num)} ],
      ["max", @max.map{|num| num_to_str(num)} ],
      ["tot", @tot.map{|num| num_to_str(num)} ]
    ]

    longest = 9
    grid.flatten.each{|item| longest = item.length if longest < item.length }

    out = ""

    grid.each do |(name, ary)|
      out << "#{name}  #{ary.map{|item| item.ljust(longest, " ")}.join(" ")}\n"
    end

    out
  end


  ##
  # Turn a number into a padded String with a target length.

  def num_to_str num, len=9
    str = num.to_f.round(len-2).to_s

    rnd = len - str.index(".") - 1
    str = num.to_f.round(rnd).to_s.ljust(len, "0") if rnd > 0

    return str if str.length == len

    str.split(".", 2)[0].rjust(len, " ")
  end
end


class Object
  ##
  # Convenience method for benchmarking inline.
  #   bench 100, "sleep 0.01"
  #   bench{ sleep 0.01 }
  #
  # Interactive mode with the current binding:
  #   bench binding

  def bench *args, &block
    count   = 1
    binding = nil
    rb_str  = nil

    args.each do |val|
      case val
      when String  then rb_str  = val
      when Integer then count   = val
      when Binding then binding = val
      end
    end

    BenchRb.run rb_str, :count => count, :binding => binding, &block
  end
end
