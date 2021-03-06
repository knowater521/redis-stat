require 'optparse'
require "uri"
require "cgi"

class RedisStat
module Option
  DEFAULT = {
    :hosts      => ['redis://127.0.0.1:6379'],
    :interval   => 2,
    :count      => nil,
    :csv_file   => nil,
    :csv_output => false,
    :style      => :unicode
  }
  class Host
    attr_reader :scheme, :host, :port, :password
    def initialize(scheme, host, port, password)
      @scheme, @host, @port, @password = scheme, host, port, password
    end
    def to_s
      "#{scheme}://#{host}:#{port}"
    end
    def to_str
      to_s
    end
  end

  def self.parse argv
    argv = argv.reject { |e| e == '-h' }

    options = DEFAULT.dup
    op = ::OptionParser.new { |opts|
      opts.banner = "usage: redis-stat [ [ <redis(s)://...> | HOST[:PORT[/PASSWORD]]] ...] [INTERVAL [COUNT]]"
      opts.separator ''

      opts.on('-a', '--auth=PASSWORD', 'Password') do |v|
        options[:auth] = v
      end

      opts.on('-k', '--key-file=path', 'Path to PEM encoded key file') do |v|
        options[:key_file] = v
      end

      opts.on('-c', '--cert-file=path', 'Path to PEM encoded cert file') do |v|
        options[:cert_file] = v
      end

      opts.on('--ca-file=path', 'Path to PEM encoded cert bundle file') do |v|
        options[:ca_file] = v
      end

      opts.on('-v', '--verbose', 'Show more info') do |v|
        options[:verbose] = v
      end

      opts.on('--style=STYLE', 'Output style: unicode|ascii') do |v|
        options[:style] = v.downcase.to_sym
      end

      opts.on('--no-color', 'Suppress ANSI color codes') do |v|
        options[:mono] = true
      end

      opts.on('--csv[=CSV_FILE]', 'Print or save the result in CSV') do |v|
        if v
          options[:csv_file] = v
        else
          options[:csv_output] = true
        end
      end

      opts.on('--es=ELASTICSEARCH_URL', 'Send results to ElasticSearch: [http://]HOST[:PORT][/INDEX]') do |v|
        options[:es] = RedisStat::ElasticsearchSink.parse_url v
      end

      opts.separator ''

      opts.on('--server[=PORT]', "Launch redis-stat web server (default port: #{RedisStat::DEFAULT_SERVER_PORT})") do |v|
        options[:server_port] = v || RedisStat::DEFAULT_SERVER_PORT
      end

      opts.on('--daemon', "Daemonize redis-stat. Must be used with --server option.") do |v|
        options[:daemon] = true
        if RUBY_PLATFORM == 'java'
          raise ArgumentError.new("Sorry. Daemonization is not supported in JRuby.")
        end
      end

      opts.separator ''

      opts.on('--version', 'Show version') do
        puts RedisStat::VERSION
        exit 0
      end

      opts.on_tail('--help', 'Show this message') do
        puts opts
        exit 0
      end
    }

    begin
      op.parse! argv

      is_number   = lambda { |str| str =~ /^([0-9]\.?[0-9]*)$|^([1-9][0-9]*)$/ }

      numbers, hosts = argv.partition { |e| is_number.call e }
      interval, count = numbers.map(&:to_f)

      options[:interval] = interval if interval
      options[:count]    = count if count
      options[:hosts]    = hosts unless hosts.empty?
      options[:hosts].map! { |h| to_host(h) }

      validate options

      return options
    rescue SystemExit => e
      exit e.status
    rescue Exception => e
      puts e.to_s
      puts op
      exit 1
    end
  end

  def self.validate options
    options[:interval].tap do |interval|
      unless interval.is_a?(Numeric) && interval > 0
        raise ArgumentError.new("Invalid interval: #{interval}")
      end
    end

    options[:count].tap do |count|
      unless count.nil? || (count.is_a?(Numeric) && count > 0)
        raise ArgumentError.new("Invalid count: #{count}")
      end
    end

    options[:hosts].tap do |hosts|
      if hosts.empty?
        raise ArgumentError.new("Redis host not given")
      end

      hosts.each do |h|
        unless ["redis", "rediss"].include?(h.scheme)
          raise ArgumentError.new("invalid scheme '#{h.scheme}'")
        end
        if h.port
          port = h.port.to_i
          unless port > 0 && port < 65536
            raise ArgumentError.new("Invalid port: #{port}")
          end
        end
      end
    end

    options[:style].tap do |style|
      unless [:unicode, :ascii].include?(style)
        raise ArgumentError.new("Invalid style")
      end
    end

    if options[:daemon] && options[:server_port].nil?
      raise ArgumentError.new("--daemon option must be used with --server option")
    end
  end


  def self.to_host host
    if host.index('redis') == 0
      uri = URI(host)
      password = CGI.unescape(uri.password) if uri.password
      Host.new(uri.scheme, uri.host, uri.port, password)
    else
      hostport, password = host.split('/')
      host, port = hostport.split(':')
      Host.new("redis", host, port, password)
    end
  end
end
end
