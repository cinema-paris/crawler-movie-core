require 'active_support/core_ext/hash/keys'
require 'active_support/inflector'
require 'crawler/api'
require 'crawler/base'
require 'crawler/utils'

module Crawler
  module Movie
    include Base

    PROVIDERS = []
    SCORES = {}

    def self.add_provider(provider_name, options = {})
      options.assert_valid_keys :score, :insert_at

      PROVIDERS.insert(options[:insert_at] || -1, provider_name)

      if (score = options[:score])
        SCORES[provider_name] = score
      end
    end

    def self.search(query, year: nil)
      movies = PROVIDERS.flat_map do |provider_name|
        camelized = ActiveSupport::Inflector.camelize("crawler/movie/providers/#{provider_name.to_s}")
        klass = ActiveSupport::Inflector.constantize(camelized)
        movies = klass.search(Utils.transliterate(query))

        movies.map do |movie|
          provider_score = SCORES[provider_name] || 0.5
          title_score = Utils.levenshtein_score(query, movie[:title])
          year_score = 1.0 unless year
          year_score ||= movie[:release_date] && year.to_s == movie[:release_date].year.to_s ? 1.0 : 0.9

          {
            data: movie,
            score: provider_score * title_score * year_score
          }
        end
      end

      movies.group_by do |movie|
        [Utils.transliterate(movie[:data][:title]), movie[:data][:release_date] && movie[:data][:release_date].year]
      end
    end

    def self.best(query, year: nil)
      data = search(query, year: year).max_by do |_, movies|
        movie = movies.max_by do |movie|
          movie[:score]
        end

        movie[:score]
      end

      data&.last
    end
  end
end
