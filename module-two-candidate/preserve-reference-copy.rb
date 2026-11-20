require_relative 'copy-element-resolution'
module PreserveReferenceCopy
 def self.process(value,options,output_dimensions)
  CopyElementResolution.process(value,options,output_dimensions)
 end
end
