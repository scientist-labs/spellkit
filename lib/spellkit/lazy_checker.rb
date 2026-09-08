# frozen_string_literal: true

module SpellKit
  # A checker that has not built its index yet.
  #
  # WHY. A Rails initializer runs in EVERY process that boots the app - web, db:migrate,
  # rake, console, sidecars - but usually only the web server ever spell-checks anything.
  # Loading eagerly makes all of them pay, and the cost is not small: a ~200k-term pack at
  # edit_distance 2 measures ~2.1 GB resident and several seconds to index. That is not
  # hypothetical - it OOM-killed a memory-constrained migrate init container in production.
  #
  # WHAT DOES NOT TRIGGER A LOAD. `stats` and `healthcheck` deliberately do not, and that
  # matters more than it first appears: a liveness probe hitting a health endpoint would
  # otherwise build the whole index in exactly the process this class exists to protect,
  # silently reintroducing the bug. They report the deferred state instead.
  #
  # THREAD SAFETY. A threaded server can take two concurrent first requests; without the
  # mutex both would build a multi-gigabyte index. The build happens at most once.
  class LazyChecker
    # Lookups need a real index. Introspection must not build one.
    FORCES_LOAD = %i[correct correct? suggestions correct_tokens].freeze

    attr_reader :pack_name

    def initialize(pack_name, options)
      @pack_name = pack_name
      @options = options
      @mutex = Mutex.new
      @checker = nil
    end

    def loaded?
      !@checker.nil?
    end

    # Build the index now. Idempotent and thread-safe.
    #
    # Lazy loading MOVES the cost rather than removing it, so for a web process you
    # usually want the server to pay it instead of the first user:
    #
    #   # config/puma.rb
    #   on_worker_boot { SpellKit.load_dictionary! }
    def load_now!
      return @checker if @checker

      @mutex.synchronize do
        # Re-check inside the lock; another thread may have loaded while we waited.
        @checker ||= Checker.new.load!(**resolved_options)
      end
    end

    FORCES_LOAD.each do |name|
      define_method(name) { |*args| load_now!.public_send(name, *args) }
    end

    def stats
      loaded? ? @checker.stats : deferred_report
    end

    def healthcheck
      loaded? ? @checker.healthcheck : deferred_report
    end

    def method_missing(name, *args, &block)
      if Checker.method_defined?(name)
        load_now!.public_send(name, *args, &block)
      else
        super
      end
    end

    def respond_to_missing?(name, include_private = false)
      Checker.method_defined?(name) || super
    end

    private

    # Resolved here rather than through a module-level helper so that helper can stay
    # private: 1.0.0 freezes the public surface, and an internal seam that only exists to
    # let one collaborator reach a private method should not be part of it.
    def resolved_options
      return @options if @pack_name.nil?

      Packs.fetch(@pack_name).load_options(**@options)
    end

    def deferred_report
      {"loaded" => false, "deferred" => true, "pack" => @pack_name&.to_s}
    end
  end
end
