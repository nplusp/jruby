require 'pp'
require 'yaml'

stubs = {
    # TODO (pitr-ch 23-Jun-2016): remove? it's not used any more
    minitest: dedent(<<-RUBY),
      require 'minitest'
      # mock load_plugins as it loads rubygems
      def Minitest.load_plugins
      end
    RUBY

    activesupport_isolation: dedent(<<-RUBY),
      require 'active_support/testing/isolation'

      module ActiveSupport
        module Testing
          module Isolation

            def run
              with_info_handler do
                time_it do
                  capture_exceptions do
                    before_setup; setup; after_setup

                    skip 'isolation not supported'
                  end

                  %w{ before_teardown teardown after_teardown }.each do |hook|
                    capture_exceptions do
                      self.send hook
                    end
                  end
                end
              end

              return self # per contract
            end
          end
        end
      end
    RUBY

    bcrypt: dedent(<<-RUBY),
      require 'bcrypt'

      module BCrypt
        class Engine
          def self.hash_secret(secret, salt, _ = nil)
            if valid_secret?(secret)
              if valid_salt?(salt)
                Truffle::Gem::BCrypt.hashpw(secret.to_s, salt.to_s)
              else
                raise Errors::InvalidSalt.new("invalid salt")
              end
            else
              raise Errors::InvalidSecret.new("invalid secret")
            end
          end

          def self.generate_salt(cost = self.cost)
            cost = cost.to_i
            if cost > 0
              if cost < MIN_COST
                cost = MIN_COST
              end
              Truffle::Gem::BCrypt.gensalt(cost)
            else
              raise Errors::InvalidCost.new("cost must be numeric and > 0")
            end
          end
        end
      end
    RUBY

    html_sanitizer: dedent(<<-RUBY),
      require 'action_view'
      require 'action_view/helpers'
      require 'action_view/helpers/sanitize_helper'

      module ActionView
        module Helpers
          module SanitizeHelper
            def sanitize(html, options = {})
              html
            end

            def sanitize_css(style)
              style
            end

            def strip_tags(html)
              html
            end

            def strip_links(html)
              html
            end

            module ClassMethods #:nodoc:
              attr_writer :full_sanitizer, :link_sanitizer, :white_list_sanitizer

              def sanitized_allowed_tags
                []
              end

              def sanitized_allowed_attributes
                []
              end
            end

          end
        end
      end
    RUBY

}.reduce({}) do |h, (k, v)|
  file_name = "stub-#{k}"
  h.update k => { setup: { file: { "#{file_name}.rb" => v } },
                  run:   { require: [file_name] } }
end

replacements = {
    bundler: dedent(<<-RUBY),
      module Bundler
        BundlerError = Class.new(Exception)
        def self.setup
        end
      end
    RUBY
    :'bundler/gem_tasks'    => nil,
    java:                   nil,
    bcrypt_ext:             nil,
    method_source:          nil,
    :'rails-html-sanitizer' => nil,
    nokogiri:               nil
}.reduce({}) do |h, (k, v)|
  h.update k => { setup: { file: { "#{k}.rb" => v || %[puts "loaded '#{k}.rb' an empty replacement"] } } }
end

# add required replacements to stubs
deep_merge!(stubs.fetch(:bcrypt),
            replacements.fetch(:java),
            replacements.fetch(:bcrypt_ext))
deep_merge!(stubs.fetch(:html_sanitizer),
            replacements.fetch(:'rails-html-sanitizer'),
            replacements.fetch(:nokogiri))

def exclusion_file(gem_name)
  data = YAML.load_file(__dir__ + "/#{gem_name}_exclusions.yaml")
  data.pretty_inspect
end

rails_common =
    deep_merge replacements.fetch(:bundler),
               setup: { without: %w(db job) },
               run:   { environment: { 'N' => 1 },
                        require:     %w(rubygems date bigdecimal pathname openssl-stubs) }

config :activesupport,
       deep_merge(
           rails_common,
           stubs.fetch(:activesupport_isolation),
           replacements.fetch(:method_source))

config :activemodel,
       deep_merge(
           rails_common,
           stubs.fetch(:activesupport_isolation),
           stubs.fetch(:bcrypt))

# TODO (pitr-ch 23-Jun-2016): investigate, fails intermittently
config :actionpack,
       deep_merge(
           rails_common,
           stubs.fetch(:html_sanitizer),
           setup: { file: { 'excluded-tests.rb' => format(dedent(<<-RUBY), exclusion_file(:actionpack)),
                              failures = %s
                              require 'truffle/exclude_rspec_examples'
                              Truffle.exclude_rspec_examples failures
                            RUBY
           } })

config :'concurrent-ruby',
       setup: { file: { "stub-processor_number.rb" => dedent(<<-RUBY) } },
          # stub methods calling #system
          require 'concurrent'
          module Concurrent
            module Utility
              class ProcessorCounter
                def compute_processor_count
                  2
                end
                def compute_physical_processor_count
                  2
                end
              end
            end
          end
       RUBY
       run: { require: %w(stub-processor_number) }

config :monkey_patch,
       replacements.fetch(:bundler)

config :openweather,
       replacements.fetch(:'bundler/gem_tasks')

config :psd,
       replacements.fetch(:nokogiri)
