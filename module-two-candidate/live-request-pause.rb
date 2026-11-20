module LiveRequestPause
 PATH=File.join(__dir__,'LIVE-REQUESTS-PAUSED')
 def self.active?;File.file?(PATH);end
 def self.check!
  raise '付费请求已暂停：先修复系统；既有额度已消费，不得复用。' if active?
 end
end
