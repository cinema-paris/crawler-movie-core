require 'active_support/core_ext/hash/keys'
require 'active_support/inflector'
require 'levenshtein-ffi'

module Crawler
  module Movie
    PROVIDERS = []
    SCORES = {}

    def self.add_provider(provider_name, options = {})
      options.assert_valid_keys :score, :insert_at

      PROVIDERS.insert(options[:insert_at] || -1, provider_name)

      if (score = options[:score])
        SCORES[provider_name] = score
      end
    end

    def self.configure
      yield self
    end

    def self.transliterate(string)
      ActiveSupport::Inflector.transliterate(string.gsub(/[:\-.,!?]/, ' ').strip.gsub(/\s+/, ' ')).downcase
    end

    def self.search(query, year: nil)
      movies = PROVIDERS.flat_map do |provider_name|
        camelized = ActiveSupport::Inflector.camelize("crawler/movie/providers/#{provider_name.to_s}")
        klass = ActiveSupport::Inflector.constantize(camelized)
        movies = klass.search(transliterate(query))

        movies.map do |movie|
          provider_score = SCORES[provider_name] || 0.5
          query_transliterated = transliterate(query)
          title_transliterated = transliterate(movie[:title])
          levenshtein_distance = Levenshtein.distance(query_transliterated, title_transliterated)
          max_size = [query_transliterated.size, title_transliterated.size].max.to_f
          title_score = (max_size - levenshtein_distance) / max_size
          year_score = 1.0 unless year
          year_score ||= movie[:release_date] && year.to_s == movie[:release_date].year.to_s ? 1.0 : 0.9

          {
            data: movie,
            score: provider_score * title_score * year_score
          }
        end
      end

      movies.max_by { |movie| movie[:score] }
    end
  end
end
