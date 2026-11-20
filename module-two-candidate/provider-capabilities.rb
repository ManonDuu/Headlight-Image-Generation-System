# Current provider boundary only; no discovery, fallback, or additional provider.
require_relative 'generate-content-adapter'
require_relative 'rules-compiler'
module ProviderCapabilities
  CURRENT={provider:'google',model:GenerateContentAdapter::MODEL,adapter:'GenerateContentAdapter',
    imageSize:'2K',ratios:RulesCompiler::SIZES.keys.freeze,maxInputImages:2,
    textInstructions:true,responseParser:'GenerateContentAdapter.parse',
    budgetsMicroUSD:{1=>260000,2=>270000}.freeze}.freeze
  def self.validate(output,image_count,budget)
    raise 'unsupported image count' unless (1..CURRENT[:maxInputImages]).include?(image_count)
    raise 'unsupported native output' unless output['imageSize']==CURRENT[:imageSize]&&CURRENT[:ratios].include?(output['aspectRatio'])
    raise 'provider budget mismatch' unless CURRENT[:budgetsMicroUSD][image_count]==budget
    true
  end
end
