require 'excon'

module DiscourseNarrativeBot
  class QuoteGenerator
    API_ENDPOINT = 'http://api.forismatic.com/api/1.0/'.freeze

    def self.generate
      connection = Excon.new("#{API_ENDPOINT}?lang=en&format=json&method=getQuote")
      response = connection.request(expects: [200, 201], method: :Get)

      response_body = JSON.parse(response.body)
      { quote: response_body["quoteText"].strip, author: response_body["quoteAuthor"].strip }
    end
  end
end
