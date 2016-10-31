require 'excon'

class QuoteGenerator
  API_ENDPOINT = 'http://api.forismatic.com/api/1.0/'.freeze

  def self.generate
    connection = Excon.new("#{API_ENDPOINT}?lang=en&format=json&method=getQuote")
    response = connection.request(expects: [200, 201], method: :Get)

    response_body = JSON.parse(response.body)
    { quote: response_body["quoteText"].chomp, author: response_body["quoteAuthor"].chomp }
  end
end
