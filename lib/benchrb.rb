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

      console = Console.new

      loop do
        str = console.read_line.strip
        next  if str.empty?
        break if str == "exit"

        res = begin
          run(str, opts).inspect
        rescue Exception => err
          "#{err.class}: #{err.message}\n#{err.backtrace.map{|b| "\tfrom #{b}"}.join("\n")}"
        end

        puts res
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
    sci = !str.index("e").nil?

    rnd = len - str.index(".") - 1
    str = num.to_f.round(rnd).to_s.ljust(len, "0") if rnd > 0 && !sci

    return str if str.length == len

    str = str.split(".", 2)[0] if !sci
    str.rjust(len, " ")
  end


  class Console
    def initialize
      @history = []
      @prompt = ">> "
    end


    def read_line
      old_state = `stty -g`
      system "stty raw -echo"

      hindex = @history.length
      cpos   = write_line ""

      line = ""
      disp = line

      loop do
        ch = read_char

        case ch
        when "\e"
          # Got escape by itself. Do nothing.

        when "\u0001" # ctrl+A - BOL
          cpos = set_wpos(0)

        when "\u0005" # ctrl+E - EOL
          cpos = set_wpos(disp.length)

        when "\u0017" # ctrl+W - erase word
          i = disp.rstrip.rindex(" ")
          disp = i ? disp[0..i] : ""
          cpos = write_line disp

        when "\u0015" # ctrl+U - erase all
          disp.clear
          cpos = write_line disp

        when "\u0003" # ctrl+C - SIGINT
          set_cpos(0)
          Process.kill "INT", Process.pid
          break

        when "\e[A", "\u0010" # Up Arrow, Ctrl+P
          hindex = hindex - 1
          hindex = 0 if hindex < 0
          if @history[hindex]
            disp = @history[hindex].dup
            cpos = write_line disp
          end

        when "\e[B", "\u000E" # Down Arrow, Ctrl+N
          hindex = hindex + 1
          hindex = @history.length if hindex > @history.length
          disp = hindex == @history.length ? line : @history[hindex].dup
          cpos = write_line disp

        when "\e[C", "\u0006" # Right Arrow, Ctrl+F
          if cpos < (@prompt.length + disp.length + 1)
            cpos = cpos + 1
            $stdout.print "\e[#{cpos}G"
          end

        when "\e[D", "\u0002" # Left Arrow, Ctrl+B
          if cpos > @prompt.length + 1
            cpos = set_cpos(cpos - 1)
          end

        when "\r", "\n"
          line = disp
          $stdout.puts ch
          break

        when "\u007F", "\b" # Delete
          if cpos > @prompt.length + 1
            cpos = cpos - 1
            wpos = cpos - @prompt.length - 1
            disp[wpos,1] = ""
            write_line disp
            set_cpos cpos
          end

        else
          wpos = cpos - @prompt.length - 1
          disp[wpos,0] = ch
          write_line disp
          cpos = set_cpos(cpos + 1)
        end

        $stdout.flush
      end

      @history << line unless line.strip.empty? || @history[-1] == line
      line
    ensure
      # restore previous state of stty
      system "stty #{old_state}"
    end


    def write_line line
      text = "#{@prompt}#{line}"
      $stdout.print "\e[2K\e[0G#{text}"
      $stdout.flush
      text.length + 1
    end


    def set_wpos num
      pos = @prompt.length + num + 1
      $stdout.print "\e[#{pos}G"
      pos
    end


    def set_cpos num
      $stdout.print "\e[#{num}G"
      num
    end


    def read_char
      c = ""

      begin
        # save previous state of stty
        #old_state = `stty -g`
        # disable echoing and enable raw (not having to press enter)
        #system "stty raw -echo"
        c = $stdin.getc.chr
        # gather next two characters of special keys
        if(c=="\e")
          extra_thread = Thread.new{
            c = c + $stdin.getc.chr
            c = c + $stdin.getc.chr
          }
          # wait just long enough for special keys to get swallowed
          extra_thread.join(0.0001)
          # kill thread so not-so-long special keys don't wait on getc
          extra_thread.kill
        end

      rescue => ex
        puts "#{ex.class}: #{ex.message}"
      #ensure
        # restore previous state of stty
      #  system "stty #{old_state}"
      end

      return c
    end
  end
end


class Object
  ##
  # Convenience method for printing benchmarks inline with code.
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

    puts BenchRb.run(rb_str, :count => count, :binding => binding, &block).inspect
    puts "Caller: #{caller[0]}"
  end
end
