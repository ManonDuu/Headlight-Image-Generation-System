# One proxy submission for a frozen Gemini-shaped plan. The key stays in the config file.
require 'digest'
require 'json'
require 'open3'
require 'fileutils'
require 'tmpdir'
module ImageProxyClient
  def self.generate(body_json, proxy, meter_module)
    Dir.mktmpdir('image-proxy-') do |dir|
      body = File.join(dir, 'body.json')
      out = File.join(dir, 'image.bin')
      meta = File.join(dir, 'result.json')
      File.binwrite(body, body_json)
      File.chmod(0600, body)
      script = File.expand_path('../deploy/image_proxy.py', __dir__)
      _stdout, stderr, status = Open3.capture3('python3', script, 'send', '--config', proxy.fetch('configPath'),
        '--body', body, '--out', out, '--meta', meta, '--module', meter_module,
        '--timeout', '180', '--connect-timeout', '15')
      raise(stderr.strip.empty? ? '生图失败，未自动重试' : stderr.strip) unless status.success?
      result = JSON.parse(File.read(meta))
      bytes = File.binread(out)
      raise '返回图片与摘要不一致，未自动重试' unless result['outputHash'] == Digest::SHA256.hexdigest(bytes)
      result['bytes'] = bytes
      result
    end
  end
end
