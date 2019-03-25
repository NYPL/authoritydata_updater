class VocabularyParser
  attr_reader :source, :vocabulary

  def initialize(vocabulary: nil, source: nil)
    @source = source
    @vocabulary = vocabulary
  end

  def parse!
    puts "Ho hum - I'll parse #{@vocabulary} from #{@source}"
  end
end
