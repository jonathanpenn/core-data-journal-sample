class AppDelegate

  attr_accessor :window

  def application(application, didFinishLaunchingWithOptions: options)
    self.window = UIWindow.alloc.initWithFrame(UIScreen.mainScreen.bounds)
    controller = EntryTableViewController.alloc.initWithStyle(UITableViewStylePlain)
    navController = UINavigationController.alloc.initWithRootViewController(controller)
    window.rootViewController = navController
    window.makeKeyAndVisible
    true
  end

end
