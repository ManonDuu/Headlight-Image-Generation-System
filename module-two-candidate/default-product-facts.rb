# User-confirmed workspace product fact; explicit mentions override the default.
module DefaultProductFacts
 CANBUS=/\bCAN[ -]?BUS\b/i
 def self.apply(options)
  Marshal.load(Marshal.dump(options)) # No inferred fact is inserted into actual user input.
 end
 def self.canbus_ready?(options)
  value=options.fetch('productParameters','')
  value.match?(CANBUS)&&!value.match?(/(?:no|not|without|non|disable[ds]?|不|无|未|没有|禁用).{0,16}CAN[ -]?BUS|CAN[ -]?BUS.{0,16}(?:not|false|disabled|不支持|没有|无)/i)
 end
end
