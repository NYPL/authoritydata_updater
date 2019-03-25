require 'nypl_log_formatter'

class VocabularyParser
  attr_reader :source, :vocabulary

  def initialize(vocabulary: nil, source: nil)
    @logger = NyplLogFormatter.new(STDOUT, level: 'debug')

    @source = source
    @vocabulary = vocabulary
  end

  def parse!
    @logger.info("Ho hum - I'll parse #{@vocabulary} from #{@source}")
  end
end
