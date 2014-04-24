require 'open3'

module PWKeep
  def self.run_editor(data, options)
    ret = [false, data] 
    Open3.pipeline_rw("vipe") do |din,dout,ts|
      din.write data
      din.close
      data2 = dout.read
      ret = [data != data2, data2]
    end
  end
end
