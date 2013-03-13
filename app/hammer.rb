# Spins up a bunch of concurrent queues that write directly to the file
# system to demonstrate how Core Data and NSFileCoordinator handle the file
# system changing out from underneath it.

class Hammer

  def initialize path
    @path = path
  end

  def hammerFileSystem
    date_range = 10 * 25 * 60 * 60    # in seconds

    queue = Dispatch::Queue.concurrent
    30.times do |i|
      queue.after(rand * 5) do
        5.times do

          uuid = NSProcessInfo.processInfo.globallyUniqueString
          fullpath = "#{@path}/#{uuid}.txt"

          File.open(fullpath, "w") do |f|
            timestamp = NSDate.date - (rand * date_range)
            f.puts timestamp.strftime("%Y-%m-%d %H:%M:%S")
            f.puts "File #{uuid}"
          end

          queue.after(rand * 10) do
            NSFileManager.defaultManager.removeItemAtPath(fullpath, error:nil)
          end

        end
      end
    end
  end

  def emptyFileSystem
    Dispatch::Queue.concurrent.after(1) do
      Dir[@path + "/*.txt"].each do |file|
        NSFileManager.defaultManager.removeItemAtPath(file, error: nil)
      end
    end
  end

end

