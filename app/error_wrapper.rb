# ErrorWrapper lets you raise an NSError returned by the Core Data framework.
# This just takes the NSError object and makes a useful Ruby exception message
# out of it.
#
# It doesn't always work because raising exceptions while deep inside the
# Foundation and Core Data frameworks can cause memory leaks or random
# segfaults, but it works for our purposes here.
#
class ErrorWrapper < StandardError
  def initialize nserror
    @nserror = nserror
  end

  def message
    @nserror.localizedDescription + "\n" + @nserror.userInfo.description
  end
end

